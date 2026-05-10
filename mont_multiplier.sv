`timescale 1ns/1ps

module mont_multiplier (
    input  logic         clk,
    input  logic         reset,
    input  logic         start,
    input  logic [254:0] X,
    input  logic [254:0] Y,
    output logic [254:0] result,
    output logic         done
);

    // 파라미터 및 타입 정의 (Constants & Types)
    localparam W = 17;   // word 비트 수
    localparam K = 15;   // word 개수
    localparam SAVE_LAT = 3;    // DSP 파이프라인 레이턴시
    localparam [16:0] N_prime = 17'h35E5; 
    localparam [254:0] N = 254'h2523648240000001BA344D80000000086121000000000013A700000000000013;

    localparam D0_START = 0;
    localparam D1_START = 5;
    localparam D2_START = 15;
    localparam D3_START = 20;
    localparam j_max    = 29; 

    typedef enum logic [2:0] {
        S_IDLE, S_INIT, S_RUNNING, S_FINAL_SUB, S_DONE
    } state_e;

    // =========================================================================
    //  내부 신호 및 메모리 선언부 (Signal Declarations)
    //  제어 신호 (Control Signals)
    (* max_fanout = "20" *) state_e       state;
    (* max_fanout = "10" *) logic [8:0]   local_cnt;
    logic [5:0]   j_cnt      [3:0];
    logic [3:0]   i_cnt      [1:0];
    logic [2:0]   out_cnt;
    logic         dsp_active [3:0];
    wire          dsp_start  [3:0];

    // 데이터 패스 및 레지스터 (Datapath & Registers)
    logic [W-1:0] x_word [K-1:0];
    logic [W-1:0] y_word [K-1:0];
    logic [W-1:0] n_word [K-1:0];
    logic [W-1:0] m_val  [1:0];

    // DSP 입출력 포트
    logic [29:0]  dsp_a [3:0];
    logic [17:0]  dsp_b [3:0];
    logic [47:0]  dsp_c [3:0];
    logic [47:0]  dsp_p [3:0];

    // 메모리 뱅크 (T 배열 - 분산 램)
    (* ram_style = "distributed" *) logic [W-1:0] t_bank_0 [4:0];
    (* ram_style = "distributed" *) logic [W-1:0] t_bank_1 [3:0];
    (* ram_style = "distributed" *) logic [W-1:0] t_bank_2 [3:0];
    (* ram_style = "distributed" *) logic [W-1:0] t_bank_3 [3:0];

    // 메모리 라우팅 및 딜레이 라인 신호
    (* max_fanout = "10", srl_style = "srl" *) logic [5:0] write_delay_dsp_0 [2:0];
    (* max_fanout = "10", srl_style = "srl" *) logic [5:0] write_delay_dsp_1 [7:0];
    (* max_fanout = "10", srl_style = "srl" *) logic [5:0] write_delay_dsp_2 [2:0];
    (* max_fanout = "10", srl_style = "srl" *) logic [5:0] write_delay_dsp_3 [7:0];

    wire  [4:0]   w_addr        [3:0]; // T 쓰기 주소
    wire  [4:0]   r_addr        [3:0]; // T 읽기 주소
    wire          valid_write_0, valid_write_1, valid_write_2, valid_write_3;
    logic [W-1:0] raw_t_read    [3:0]; 
    logic [W-1:0] t_read   [3:0]; 
    
    // 2.6 Final Subtraction 결과 신호
    // logic [W*K-1:0] t_concat;   
    // logic [W*K-1:0] t_sub_val;  

    // =========================================================================
    // [Section 3] 모듈 인스턴스 및 와이어 할당 (Instantiations & Assigns)
    // =========================================================================
    // 3.1 워드 분할

    // X,Y wrod 단위로 분할
    generate
        for (genvar g = 0; g < K; g++) begin : gen_split
            assign x_word[g] = X[W*g +: W];
            assign y_word[g] = Y[W*g +: W];
            assign n_word[g] = N[W*g +: W];
        end
    endgenerate

    // 3.2 제어 와이어 매핑
    //dsp_start -> dsp_active을 위한 control signal
    assign dsp_start[0] = (state == S_RUNNING) && (local_cnt == D0_START);
    assign dsp_start[1] = (state == S_RUNNING) && (local_cnt == D1_START);
    assign dsp_start[2] = (state == S_RUNNING) && (local_cnt == D2_START);
    assign dsp_start[3] = (state == S_RUNNING) && (local_cnt == D3_START);
    
    // // read_address (T[0] ~ T[15], T[16] 읽기를 위한 RAM 접근 주소)
    // assign r_addr[0] = j_cnt[0];                                      // DSP_0은 T 읽기 주소가 j_cnt와 동일 (j_cnt : 0 ~ 15) 
    // assign r_addr[1] = j_cnt[1] == '0 ? '0 : write_delay_dsp_1[3];    // DSP_1은 T 읽기 주소가 j_cnt - 4 와 동일 (j_cnt : 4 ~ 15)
    // assign r_addr[2] = j_cnt[2];                                      // DSP_2은 T 읽기 주소가 j_cnt와 동일 (j_cnt : 0 ~ 15)
    // assign r_addr[3] = j_cnt[3] == '0 ? '0 : write_delay_dsp_3[3];    // DSP_0은 T 읽기 주소가 j_cnt - 4 와 동일 (j_cnt : 4 ~ 20)

    // (상태에 따른 읽기 주소 스위칭!)
    assign r_addr[0] = (state == S_FINAL_SUB) ? {out_cnt[2:0], 2'b00} : j_cnt[0];
    assign r_addr[1] = (state == S_FINAL_SUB) ? {out_cnt[2:0], 2'b01} : (j_cnt[1] == '0 ? '0 : write_delay_dsp_1[3]);
    assign r_addr[2] = (state == S_FINAL_SUB) ? {out_cnt[2:0], 2'b10} : j_cnt[2];
    assign r_addr[3] = (state == S_FINAL_SUB) ? {out_cnt[2:0], 2'b11} : (j_cnt[3] == '0 ? '0 : write_delay_dsp_3[3]);

    // write_address (T[0] ~ T[16] 쓰기를 위한 RAM 접근 주소)
    assign w_addr[0] = write_delay_dsp_0[2]; // DSP_0는 j_cnt - 3 clk 
    assign w_addr[1] = write_delay_dsp_1[7]; // DSP_1는 j_cnt - 8 clk
    assign w_addr[2] = write_delay_dsp_2[2]; // DSP_2는 j_cnt - 3 clk
    assign w_addr[3] = write_delay_dsp_3[7]; // DSP_3는 j_cnt - 8 clk


    wire val_range_0 = (w_addr[0] <= 6'd16);
    wire val_range_1 = (w_addr[1] <= 6'd16);
    wire val_range_2 = (w_addr[2] <= 6'd16);
    wire val_range_3 = (w_addr[3] <= 6'd16);

    // write_enable signal
    // DSP가 연산을 실행중이면서 쓰기 주소가 유효할 때 (0 ~ 16)
    assign valid_write_0 = dsp_active[0] && (val_range_0);
    assign valid_write_1 = dsp_active[1] && (val_range_1);
    assign valid_write_2 = dsp_active[2] && (val_range_2);
    assign valid_write_3 = dsp_active[3] && (val_range_3);

    //assign t_sub_val = t_concat - {1'b0, N}; 

    // 3.3 DSP 유닛 4개 생성
    generate
        for (genvar d = 0; d < 4; d++) begin : gen_dsp
            dsp_cios_3stage dsp_inst (
                .clk   (clk),
                .reset (reset),
                .x_in  (dsp_a[d]),
                .y_in  (dsp_b[d]),
                .t_in  (dsp_c[d]),
                .p_out (dsp_p[d])
            );
        end
    endgenerate

    // =========================================================================
    // [Section 4] 조합 논리 회로 (Combinational Logic - always_comb)
    // =========================================================================
    always_comb begin
        // 4.1 T 배열(4-Bank) 읽기
        // r_addr 하위 2 비트-> T bank 접근 주소
        // r_addr 상위 3 비트 -> T bank 내에서의 인덱스 주소
        for(int d=0; d<4; d++) begin
            case (r_addr[d][1:0]) // bank 선택
                2'b00: t_read[d] = t_bank_0[r_addr[d][4:2]]; // 뱅크 내에서 인덱스 접근
                2'b01: t_read[d] = t_bank_1[r_addr[d][4:2]];
                2'b10: t_read[d] = t_bank_2[r_addr[d][4:2]];
                2'b11: t_read[d] = t_bank_3[r_addr[d][4:2]];
            endcase
        end

        // 4.3 DSP 입력 데이터 선택 MUX
        for (int d = 0; d < 4; d++) begin
            dsp_a[d] = '0; dsp_b[d] = '0; dsp_c[d] = '0;
        end

        if (state == S_RUNNING) begin
            // DSP_0 입력
            if (dsp_active[0]) begin
                if ((j_cnt[0] < K) && (i_cnt[0] < K)) begin
                    dsp_a[0] = {{(30-W){1'b0}}, x_word[r_addr[0][3:0]]};
                    dsp_b[0] = {{(18-W){1'b0}}, y_word[i_cnt[0]]}; 
                    dsp_c[0] = {{(48-W){1'b0}}, t_read[0]}; // t_read 적용
                end else if (j_cnt[0] == K) begin
                    dsp_a[0] = 30'b1;
                    dsp_b[0] = {{(18-W){1'b0}}, t_read[0]}; // t_read 적용
                    dsp_c[0] = '0;
                end
            end

            // DSP_1 입력
            if (dsp_active[1]) begin
                if(j_cnt[1]==0) begin
                    dsp_a[1] = {{(30-W){1'b0}}, t_read[1]}; // T[0]는 항상 Bank 0의 0번방
                    dsp_b[1] = {{(18-W){1'b0}}, N_prime};
                end else if(4 <= j_cnt[1] && j_cnt[1] < K+4) begin
                    dsp_a[1] = {{(30-W){1'b0}}, n_word[r_addr[1][3:0]]};
                    dsp_b[1] = {{(18-W){1'b0}}, m_val[0]};
                    dsp_c[1] = {{(48-W){1'b0}}, t_read[1]}; // t_read 적용
                end else if ((K+4<=j_cnt[1]) && (j_cnt[1]< K+6)) begin
                    dsp_a[1] = {{(30-W){1'b0}}, t_read[1]}; // t_read 적용
                    dsp_b[1] = 18'b1;
                end
            end

            // DSP_2 입력
            if (dsp_active[2]) begin
                if ((j_cnt[2] < K) && (i_cnt[1] < (K-1))) begin
                    dsp_a[2] = {{(30-W){1'b0}}, x_word[r_addr[2][3:0]]}; 
                    dsp_b[2] = {{(18-W){1'b0}}, y_word[i_cnt[1]]}; 
                    dsp_c[2] = {{(48-W){1'b0}}, t_read[2]}; // t_read 적용
                end else if (j_cnt[2] == K) begin
                    dsp_a[2] = 30'b1;
                    dsp_b[2] = {{(18-W){1'b0}}, t_read[2]}; // t_read 적용
                end
            end

            // DSP_3 입력
            if (dsp_active[3]) begin
                if(j_cnt[3]==0) begin
                    dsp_a[3] = {{(30-W){1'b0}}, t_read[3]};; // T[0]
                    dsp_b[3] = {{(18-W){1'b0}}, N_prime}; 
                end else if(4 <= j_cnt[3] && j_cnt[3] < K+4) begin
                    dsp_a[3] = {{(30-W){1'b0}}, n_word[r_addr[3][3:0]]};
                    dsp_b[3] = {{(18-W){1'b0}}, m_val[1]}; 
                    dsp_c[3] = {{(48-W){1'b0}}, t_read[3]}; // t_read 적용
                end else if ((K+4<=j_cnt[3]) && (j_cnt[3]< K+6)) begin
                    dsp_a[3] = {{(30-W){1'b0}}, t_read[3]}; // t_read 적용
                    dsp_b[3] = 18'b1;
                end
            end
        end
    end

    // =========================================================================
    // [Section 5] 순차 논리 회로 (Sequential Logic - always_ff)
    // =========================================================================
    
    // 5.1 시프트 레지스터 (주소 지연선) & M-Value 캡처
    always_ff @(posedge clk) begin
        if (dsp_active[0]) begin 
            write_delay_dsp_0[0] <= j_cnt[0];      
            for (int i = 1; i < 3; i++) write_delay_dsp_0[i] <= write_delay_dsp_0[i-1];
        end
        if (dsp_active[1]) begin 
            write_delay_dsp_1[0] <= j_cnt[1];       
            for (int i = 1; i < 8; i++) write_delay_dsp_1[i] <= write_delay_dsp_1[i-1];
            if (j_cnt[1] == SAVE_LAT) m_val[0] <= dsp_p[1][W-1:0]; // M값 캡처
        end
        if (dsp_active[2]) begin 
            write_delay_dsp_2[0] <= j_cnt[2];       
            for (int i = 1; i < 3; i++) write_delay_dsp_2[i] <= write_delay_dsp_2[i-1]; // 수정 완료!
        end
        if (dsp_active[3]) begin
            write_delay_dsp_3[0] <= j_cnt[3];       
            for (int i = 1; i < 8; i++) write_delay_dsp_3[i] <= write_delay_dsp_3[i-1];
            if (j_cnt[3] == SAVE_LAT) m_val[1] <= dsp_p[3][W-1:0]; // M값 캡처
        end
    end

    // 5.2 메인 상태 머신 및 제어 루프 카운터
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE;
            local_cnt <= '0;
            done <= '0;
            i_cnt[0] <= '0; 
            i_cnt[1] <= 4'd1;
            result <= '0;
            for (int d = 0; d < 4; d++) begin
                j_cnt[d] <= '0; 
                dsp_active[d] <= 1'b0;
            end
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    local_cnt <=1'b0;
                    if (start) state <= S_INIT;
                end
                S_INIT: begin
                    // local_cnt를 0부터 4까지 증가시키며 청소 시간 5클럭 확보!
                    if (local_cnt < 5) begin
                        local_cnt <= local_cnt + 1;
                    end else begin
                        // 5클럭 청소가 끝나면, 원래 하려던 변수 초기화를 하고 RUNNING으로 넘어감
                        local_cnt <= '0;
                        i_cnt[0]  <= '0;
                        i_cnt[1] <= 4'd1;
                        out_cnt <='0;
                        //m_val[0] <= '0;
                        //m_val[1] <= '0;
                        for (int d = 0; d < 4; d++) begin
                            j_cnt[d] <= '0; dsp_active[d] <= 1'b0;
                        end
                        state <= S_RUNNING;
                    end
                end
                S_RUNNING: begin
                    local_cnt <= local_cnt + 1;
                    if(local_cnt > 18 && !dsp_active[0] && !dsp_active[1] && !dsp_active[2] && !dsp_active[3]) begin
                        state <= S_FINAL_SUB;
                    end

                    // (DSP_0 ~ DSP_3의 제어 루프 로직은 기존과 동일하게 완벽하므로 그대로 둡니다)
                    // DSP_0
                    if (dsp_start[0]) begin 
                        j_cnt[0] <= '0; dsp_active[0] <= 1'b1; 
                    end
                    else if (dsp_active[0]) begin
                        if(j_cnt[0] == j_max) begin 
                            j_cnt[0] <= '0;
                            if(i_cnt[0] == K-1) dsp_active[0] <= 1'b0;
                            else i_cnt[0] <= i_cnt[0] + 2;
                        end 
                        else j_cnt[0] <= j_cnt[0] + 1;
                    end
                    // DSP_1
                    if (dsp_start[1]) begin j_cnt[1] <= '0; dsp_active[1] <= 1'b1; end
                    else if (dsp_active[1]) begin
                        if(!dsp_active[0] && j_cnt[1] == j_max) begin dsp_active[1] <= 1'b0; j_cnt[1] <= '0; end
                        else if(j_cnt[1] == j_max) j_cnt[1] <= '0; 
                        else j_cnt[1] <= j_cnt[1] + 1;
                    end
                    // DSP_2
                    if (dsp_start[2]) begin j_cnt[2] <= '0; dsp_active[2] <= 1'b1; end
                    else if (dsp_active[2]) begin
                        if(j_cnt[2] == j_max) begin 
                            j_cnt[2] <= '0;
                            if(i_cnt[1] == K-2) dsp_active[2] <= 1'b0;
                            else i_cnt[1] <= i_cnt[1] + 2;
                        end else j_cnt[2] <= j_cnt[2] + 1;
                    end
                    // DSP_3
                    if (dsp_start[3]) begin j_cnt[3] <= '0; dsp_active[3] <= 1'b1; end
                    else if (dsp_active[3]) begin
                        if(!dsp_active[2] && j_cnt[3] == j_max) begin dsp_active[3] <= 1'b0; j_cnt[3] <= '0; end
                        else if(j_cnt[3] == j_max) j_cnt[3] <= '0; 
                        else j_cnt[3] <= j_cnt[3] + 1;
                    end
                end
                S_FINAL_SUB: begin
                    // 램에서 4클락 동안 꺼낸다.
                    if (out_cnt < 5) begin
                        case (out_cnt)
                            3'b000: begin 
                                result[W*0  +: W] <= t_read[0];
                                result[W*1  +: W] <= t_read[1];
                                result[W*2  +: W] <= t_read[2];
                                result[W*3  +: W] <= t_read[3];
                                out_cnt <= out_cnt + 1;
                            end
                            3'b001: begin
                                result[W*4  +: W] <= t_read[0];
                                result[W*5  +: W] <= t_read[1];
                                result[W*6  +: W] <= t_read[2];
                                result[W*7  +: W] <= t_read[3];
                                out_cnt <= out_cnt + 1;
                            end
                            3'b010: begin
                                result[W*8  +: W] <= t_read[0];
                                result[W*9  +: W] <= t_read[1];
                                result[W*10 +: W] <= t_read[2];
                                result[W*11 +: W] <= t_read[3];
                                out_cnt <= out_cnt + 1;
                            end
                            3'b011: begin
                                result[W*12 +: W] <= t_read[0];
                                result[W*13 +: W] <= t_read[1];
                                result[W*14 +: W] <= t_read[2];
                                // K=15 (인덱스 0~14) 이므로 t_bank_3[3]는 읽지 않고 버림! (안전장치)
                                out_cnt <= out_cnt + 1;
                            end
                            default: begin 
                                // 4클럭(0~3) 조립이 끝나면 default로 넘어와서 종료
                                state <= S_DONE;
                            end
                        endcase
                        end
                end
                S_DONE: begin
                    done <= 1'b1;
                    state <= S_IDLE; 
                end
            endcase
        end
    end

    // 5.3 T 배열 메모리 쓰기 (Write-Back) 
    always_ff @(posedge clk) begin
        if (state == S_INIT) begin // 메모리 초기화
            if (local_cnt < 5) begin
                t_bank_0[local_cnt[2:0]] <= '0; // Bank 0은 5칸(0~4) 전부 청소
                
                if (local_cnt < 4) begin         // Bank 1~3은 4칸(0~3)까지만 있으므로 예외 처리
                    t_bank_1[local_cnt[2:0]] <= '0; 
                    t_bank_2[local_cnt[2:0]] <= '0; 
                    t_bank_3[local_cnt[2:0]] <= '0; 
                end
            end
        end 
        else if (state == S_RUNNING) begin
            // Bank 0 쓰기
            unique0 if (valid_write_0 && w_addr[0][1:0] == 2'b00) t_bank_0[ w_addr[0][4:2] ] <= dsp_p[0][W-1:0];
            else if   (valid_write_1 && w_addr[1][1:0] == 2'b00) t_bank_0[ w_addr[1][4:2] ] <= dsp_p[1][W-1:0];
            else if   (valid_write_2 && w_addr[2][1:0] == 2'b00) t_bank_0[ w_addr[2][4:2] ] <= dsp_p[2][W-1:0];
            else if   (valid_write_3 && w_addr[3][1:0] == 2'b00) t_bank_0[ w_addr[3][4:2] ] <= dsp_p[3][W-1:0];

            // Bank 1 쓰기
            unique0 if (valid_write_0 && w_addr[0][1:0] == 2'b01) t_bank_1[ w_addr[0][4:2] ] <= dsp_p[0][W-1:0];
            else if   (valid_write_1 && w_addr[1][1:0] == 2'b01) t_bank_1[ w_addr[1][4:2] ] <= dsp_p[1][W-1:0];
            else if   (valid_write_2 && w_addr[2][1:0] == 2'b01) t_bank_1[ w_addr[2][4:2] ] <= dsp_p[2][W-1:0];
            else if   (valid_write_3 && w_addr[3][1:0] == 2'b01) t_bank_1[ w_addr[3][4:2] ] <= dsp_p[3][W-1:0];

            // Bank 2 쓰기
            unique0 if (valid_write_0 && w_addr[0][1:0] == 2'b10) t_bank_2[ w_addr[0][4:2] ] <= dsp_p[0][W-1:0];
            else if   (valid_write_1 && w_addr[1][1:0] == 2'b10) t_bank_2[ w_addr[1][4:2] ] <= dsp_p[1][W-1:0];
            else if   (valid_write_2 && w_addr[2][1:0] == 2'b10) t_bank_2[ w_addr[2][4:2] ] <= dsp_p[2][W-1:0];
            else if   (valid_write_3 && w_addr[3][1:0] == 2'b10) t_bank_2[ w_addr[3][4:2] ] <= dsp_p[3][W-1:0];

            // Bank 3 쓰기
            unique0 if (valid_write_0 && w_addr[0][1:0] == 2'b11) t_bank_3[ w_addr[0][4:2] ] <= dsp_p[0][W-1:0];
            else if   (valid_write_1 && w_addr[1][1:0] == 2'b11) t_bank_3[ w_addr[1][4:2] ] <= dsp_p[1][W-1:0];
            else if   (valid_write_2 && w_addr[2][1:0] == 2'b11) t_bank_3[ w_addr[2][4:2] ] <= dsp_p[2][W-1:0];
            else if   (valid_write_3 && w_addr[3][1:0] == 2'b11) t_bank_3[ w_addr[3][4:2] ] <= dsp_p[3][W-1:0];    
        end
    end
endmodule