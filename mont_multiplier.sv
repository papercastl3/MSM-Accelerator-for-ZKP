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

    // =========================================================================
    // 상수 및 파라미터 정의
    // =========================================================================
    localparam W = 17;   
    localparam K = 15;   
    localparam SAVE_LAT = 3;    
    localparam [16:0] N_prime = 17'h1d5e8; 
    localparam [254:0] N = 254'h30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;

    localparam D0_START = 0;
    localparam D1_START = 5;
    localparam D2_START = 15;
    localparam D3_START = 20;
    localparam j_max    = 29; 

    typedef enum logic [2:0] {
        S_IDLE, S_INIT, S_RUNNING, S_FINAL_SUB, S_DONE
    } state_e;

    // =========================================================================
    // 내부 신호 선언
    // =========================================================================
    (* max_fanout = "20" *) state_e       state;
    (* max_fanout = "10" *) logic [8:0]   local_cnt;
    
    logic [5:0] j_cnt [3:0];
    
    (* keep = "true", equivalent_register_removal = "no", max_fanout = "8" *) logic [5:0] j_mux_0;
    (* keep = "true", equivalent_register_removal = "no", max_fanout = "8" *) logic [5:0] j_mux_1;
    (* keep = "true", equivalent_register_removal = "no", max_fanout = "8" *) logic [5:0] j_mux_2;
    (* keep = "true", equivalent_register_removal = "no", max_fanout = "8" *) logic [5:0] j_mux_3;

    (* max_fanout = "16" *) logic [3:0]   i_cnt [1:0];
    logic [2:0]   out_cnt;
    logic         dsp_active [3:0];
    wire          dsp_start  [3:0];

    // 데이터 회전 레지스터
    logic [254:0] x_rot; 
    logic [254:0] n_rot_1;
    logic [254:0] n_rot_3;

    logic [W-1:0] y_word [K-1:0];
    logic [W-1:0] m_val  [1:0];

    // DSP 입출력 포트
    logic [29:0]  dsp_a [3:0];
    logic [17:0]  dsp_b [3:0];
    logic [47:0]  dsp_c [3:0];
    logic [47:0]  dsp_p [3:0];

    // 메모리 뱅크
    (* ram_style = "distributed" *) logic [W-1:0] t_bank_0 [7:0];
    (* ram_style = "distributed" *) logic [W-1:0] t_bank_1 [7:0];
    (* ram_style = "distributed" *) logic [W-1:0] t_bank_2 [7:0];
    (* ram_style = "distributed" *) logic [W-1:0] t_bank_3 [7:0];

    // 지연선 (Shift Registers)
    (* srl_style = "srl_reg" *) logic [5:0] write_delay_dsp_0 [2:0];
    (* srl_style = "srl_reg" *) logic [5:0] write_delay_dsp_1 [7:0];
    (* srl_style = "srl_reg" *) logic [5:0] write_delay_dsp_2 [2:0];
    (* srl_style = "srl_reg" *) logic [5:0] write_delay_dsp_3 [7:0];

    (* max_fanout = "16" *) logic [4:0] w_addr_reg [3:0];
    (* max_fanout = "16" *) logic [4:0] r_addr_delay_1_reg;
    (* max_fanout = "16" *) logic [4:0] r_addr_delay_3_reg;

    wire  [4:0]   w_addr        [3:0]; 
    wire  [4:0]   r_addr        [3:0]; 
    wire          valid_write_0, valid_write_1, valid_write_2, valid_write_3;
    logic [W-1:0] t_read        [3:0]; 

    //  [신규] 상태 레지스터(Fanout 80)를 대체할 초경량 플래그 (Fanout 4)
    (* max_fanout = "4" *) logic final_sub_en;

    // =========================================================================
    // Wrap-around 완벽 예측 (수학 무결성 유지)
    // =========================================================================
    wire [5:0] nxt_j0 = (j_cnt[0] == j_max) ? '0 : (j_cnt[0] + 1);
    wire [5:0] nxt_j1 = (j_cnt[1] == j_max) ? '0 : (j_cnt[1] + 1);
    wire [5:0] nxt_j2 = (j_cnt[2] == j_max) ? '0 : (j_cnt[2] + 1);
    wire [5:0] nxt_j3 = (j_cnt[3] == j_max) ? '0 : (j_cnt[3] + 1);

    // =========================================================================
    // 파이프라이닝 제어 신호 사전 계산
    // =========================================================================
    logic [4:0] r_addr_0_run, r_addr_2_run;

    (* max_fanout = "16" *) logic dsp0_ph_mult, dsp0_ph_end, dsp0_valid;
    (* max_fanout = "16" *) logic dsp1_ph_zero, dsp1_ph_n, dsp1_ph_one, dsp1_valid;
    (* max_fanout = "16" *) logic dsp2_ph_mult, dsp2_ph_end, dsp2_valid;
    (* max_fanout = "16" *) logic dsp3_ph_zero, dsp3_ph_n, dsp3_ph_one, dsp3_valid;

    always_ff @(posedge clk) begin
        if (dsp_start[0]) begin
            r_addr_0_run <= '0; dsp0_ph_mult <= 1'b1; dsp0_ph_end <= 1'b0; dsp0_valid <= 1'b0;
        end else if (dsp_active[0]) begin
            r_addr_0_run <= nxt_j0[4:0];
            dsp0_ph_mult <= (nxt_j0 < K);
            dsp0_ph_end  <= (nxt_j0 == K);
            dsp0_valid   <= (nxt_j0 >= 3);
        end else begin
            dsp0_ph_mult <= 0; dsp0_ph_end <= 0; dsp0_valid <= 0;
        end

        if (dsp_start[1]) begin
            dsp1_ph_zero <= 1'b1; dsp1_ph_n <= 1'b0; dsp1_ph_one <= 1'b0; dsp1_valid <= 1'b0;
        end else if (dsp_active[1]) begin
            dsp1_ph_zero <= (nxt_j1 == 0);
            dsp1_ph_n    <= (nxt_j1 >= 4 && nxt_j1 < K+4);
            dsp1_ph_one  <= (nxt_j1 >= K+4 && nxt_j1 < K+6);
            dsp1_valid   <= (nxt_j1 >= 8);
        end else begin
            dsp1_ph_zero <= 0; dsp1_ph_n <= 0; dsp1_ph_one <= 0; dsp1_valid <= 0;
        end

        if (dsp_start[2]) begin
            r_addr_2_run <= '0; dsp2_ph_mult <= 1'b1; dsp2_ph_end <= 1'b0; dsp2_valid <= 1'b0;
        end else if (dsp_active[2]) begin
            r_addr_2_run <= nxt_j2[4:0];
            dsp2_ph_mult <= (nxt_j2 < K);
            dsp2_ph_end  <= (nxt_j2 == K);
            dsp2_valid   <= (nxt_j2 >= 3);
        end else begin
            dsp2_ph_mult <= 0; dsp2_ph_end <= 0; dsp2_valid <= 0;
        end

        if (dsp_start[3]) begin
            dsp3_ph_zero <= 1'b1; dsp3_ph_n <= 1'b0; dsp3_ph_one <= 1'b0; dsp3_valid <= 1'b0;
        end else if (dsp_active[3]) begin
            dsp3_ph_zero <= (nxt_j3 == 0);
            dsp3_ph_n    <= (nxt_j3 >= 4 && nxt_j3 < K+4);
            dsp3_ph_one  <= (nxt_j3 >= K+4 && nxt_j3 < K+6);
            dsp3_valid   <= (nxt_j3 >= 8);
        end else begin
            dsp3_ph_zero <= 0; dsp3_ph_n <= 0; dsp3_ph_one <= 0; dsp3_valid <= 0;
        end
    end

    // =========================================================================
    // 인스턴스 및 와이어 할당
    // =========================================================================
    generate
        for (genvar g = 0; g < K; g++) begin : gen_split
            assign y_word[g] = Y[W*g +: W];
        end
    endgenerate

    assign dsp_start[0] = (state == S_RUNNING) && (local_cnt == D0_START);
    assign dsp_start[1] = (state == S_RUNNING) && (local_cnt == D1_START);
    assign dsp_start[2] = (state == S_RUNNING) && (local_cnt == D2_START);
    assign dsp_start[3] = (state == S_RUNNING) && (local_cnt == D3_START);

    // 🌟 [핵심] 무거운 state 검사 대신 초경량 final_sub_en 사용으로 딜레이 극단적 단축
    assign r_addr[0] = final_sub_en ? {out_cnt[2:0], 2'b00} : r_addr_0_run;
    assign r_addr[1] = final_sub_en ? {out_cnt[2:0], 2'b01} : (dsp1_ph_zero ? 5'd0 : r_addr_delay_1_reg);
    assign r_addr[2] = final_sub_en ? {out_cnt[2:0], 2'b10} : r_addr_2_run;
    assign r_addr[3] = final_sub_en ? {out_cnt[2:0], 2'b11} : (dsp3_ph_zero ? 5'd0 : r_addr_delay_3_reg);

    assign w_addr[0] = w_addr_reg[0]; 
    assign w_addr[1] = w_addr_reg[1]; 
    assign w_addr[2] = w_addr_reg[2]; 
    assign w_addr[3] = w_addr_reg[3]; 

    assign valid_write_0 = dsp_active[0] && (w_addr[0] <= 5'd16) && dsp0_valid;
    assign valid_write_1 = dsp_active[1] && (w_addr[1] <= 5'd16) && dsp1_valid;
    assign valid_write_2 = dsp_active[2] && (w_addr[2] <= 5'd16) && dsp2_valid;
    assign valid_write_3 = dsp_active[3] && (w_addr[3] <= 5'd16) && dsp3_valid;

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
    // 조합 논리 회로 (state 변수 완전 제거로 로직 독립 달성!)
    // =========================================================================
    always_comb begin
        for(int d=0; d<4; d++) begin
            case (r_addr[d][1:0]) 
                2'b00: t_read[d] = t_bank_0[r_addr[d][4:2]]; 
                2'b01: t_read[d] = t_bank_1[r_addr[d][4:2]];
                2'b10: t_read[d] = t_bank_2[r_addr[d][4:2]];
                2'b11: t_read[d] = t_bank_3[r_addr[d][4:2]];
            endcase
            dsp_a[d] = '0; dsp_b[d] = '0; dsp_c[d] = '0;
        end

        // [핵심] if (state == S_RUNNING) 제거! 
        // 사전 계산 플래그들이 알아서 Idle 상태를 방어하므로 FSM 껍데기가 필요 없습니다.
        // DSP_0
        if (dsp0_ph_mult) begin
            dsp_a[0] = {{(30-W){1'b0}}, x_rot[W-1:0]}; 
            dsp_b[0] = {{(18-W){1'b0}}, y_word[i_cnt[0]]}; 
            dsp_c[0] = {{(48-W){1'b0}}, t_read[0]}; 
        end else if (dsp0_ph_end) begin
            dsp_a[0] = 30'b1;
            dsp_b[0] = {{(18-W){1'b0}}, t_read[0]}; 
        end

        // DSP_1
        if (dsp1_ph_zero) begin
            dsp_a[1] = {{(30-W){1'b0}}, t_read[1]}; 
            dsp_b[1] = {{(18-W){1'b0}}, N_prime};
        end else if (dsp1_ph_n) begin
            dsp_a[1] = {{(30-W){1'b0}}, n_rot_1[W-1:0]}; 
            dsp_b[1] = {{(18-W){1'b0}}, m_val[0]};
            dsp_c[1] = {{(48-W){1'b0}}, t_read[1]}; 
        end else if (dsp1_ph_one) begin
            dsp_a[1] = {{(30-W){1'b0}}, t_read[1]}; 
            dsp_b[1] = 18'b1;
        end

        // DSP_2
        if (dsp2_ph_mult) begin
            dsp_a[2] = {{(30-W){1'b0}}, x_rot[W-1:0]}; 
            dsp_b[2] = {{(18-W){1'b0}}, y_word[i_cnt[1]]}; 
            dsp_c[2] = {{(48-W){1'b0}}, t_read[2]}; 
        end else if (dsp2_ph_end) begin
            dsp_a[2] = 30'b1;
            dsp_b[2] = {{(18-W){1'b0}}, t_read[2]}; 
        end

        // DSP_3
        if (dsp3_ph_zero) begin
            dsp_a[3] = {{(30-W){1'b0}}, t_read[3]};
            dsp_b[3] = {{(18-W){1'b0}}, N_prime}; 
        end else if (dsp3_ph_n) begin
            dsp_a[3] = {{(30-W){1'b0}}, n_rot_3[W-1:0]}; 
            dsp_b[3] = {{(18-W){1'b0}}, m_val[1]}; 
            dsp_c[3] = {{(48-W){1'b0}}, t_read[3]}; 
        end else if (dsp3_ph_one) begin
            dsp_a[3] = {{(30-W){1'b0}}, t_read[3]}; 
            dsp_b[3] = 18'b1;
        end
    end

    // =========================================================================
    // 순차 논리 회로 - 데이터 회전 동기화
    // =========================================================================
    always_ff @(posedge clk) begin
        if (state == S_IDLE && start) begin
            x_rot   <= X; 
            n_rot_1 <= N;
            n_rot_3 <= N;
        end 
        else if (state == S_RUNNING) begin
            if ((dsp_active[0] && j_cnt[0] < K) || (dsp_active[2] && j_cnt[2] < K))
                x_rot <= {x_rot[W-1:0], x_rot[254:W]}; 
                
            if (dsp_active[1] && j_cnt[1] >= 4 && j_cnt[1] < 19)
                n_rot_1 <= {n_rot_1[W-1:0], n_rot_1[254:W]};
                
            if (dsp_active[3] && j_cnt[3] >= 4 && j_cnt[3] < 19)
                n_rot_3 <= {n_rot_3[W-1:0], n_rot_3[254:W]};
        end
    end

    // =========================================================================
    // 순차 논리 회로 - 지연선 업데이트
    // =========================================================================
    always_ff @(posedge clk) begin
        if (dsp_active[0]) begin 
            write_delay_dsp_0[0] <= j_cnt[0];      
            for (int i = 1; i < 3; i++) write_delay_dsp_0[i] <= write_delay_dsp_0[i-1];
        end
        if (dsp_active[1]) begin 
            write_delay_dsp_1[0] <= j_cnt[1];       
            for (int i = 1; i < 8; i++) write_delay_dsp_1[i] <= write_delay_dsp_1[i-1];
            if (j_cnt[1] == SAVE_LAT) m_val[0] <= dsp_p[1][W-1:0]; 
        end
        if (dsp_active[2]) begin 
            write_delay_dsp_2[0] <= j_cnt[2];       
            for (int i = 1; i < 3; i++) write_delay_dsp_2[i] <= write_delay_dsp_2[i-1]; 
        end
        if (dsp_active[3]) begin
            write_delay_dsp_3[0] <= j_cnt[3];       
            for (int i = 1; i < 8; i++) write_delay_dsp_3[i] <= write_delay_dsp_3[i-1];
            if (j_cnt[3] == SAVE_LAT) m_val[1] <= dsp_p[3][W-1:0]; 
        end
    end

    always_ff @(posedge clk) begin
        w_addr_reg[0] <= write_delay_dsp_0[1][4:0];
        w_addr_reg[1] <= write_delay_dsp_1[6][4:0];
        w_addr_reg[2] <= write_delay_dsp_2[1][4:0];
        w_addr_reg[3] <= write_delay_dsp_3[6][4:0];

        r_addr_delay_1_reg <= write_delay_dsp_1[2][4:0]; 
        r_addr_delay_3_reg <= write_delay_dsp_3[2][4:0]; 
    end

    // =========================================================================
    // 메인 상태 머신 (FSM)
    // =========================================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE; local_cnt <= '0; done <= '0; i_cnt[0] <= '0; i_cnt[1] <= 4'd1;
            result <= '0; out_cnt <= '0; final_sub_en <= 1'b0;
            for (int d = 0; d < 4; d++) begin j_cnt[d] <= '0; dsp_active[d] <= 1'b0; end
            j_mux_0 <= '0; j_mux_1 <= '0; j_mux_2 <= '0; j_mux_3 <= '0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0; local_cnt <=1'b0; final_sub_en <= 1'b0;
                    if (start) state <= S_INIT;
                end
                S_INIT: begin
                    if (local_cnt < 5) begin
                        local_cnt <= local_cnt + 1;
                    end else begin
                        local_cnt <= '0; i_cnt[0]  <= '0; i_cnt[1] <= 4'd1; out_cnt <='0;
                        for (int d = 0; d < 4; d++) begin j_cnt[d] <= '0; dsp_active[d] <= 1'b0; end
                        j_mux_0 <= '0; j_mux_1 <= '0; j_mux_2 <= '0; j_mux_3 <= '0;
                        state <= S_RUNNING;
                    end
                end
                S_RUNNING: begin
                    local_cnt <= local_cnt + 1;
                    if(local_cnt > 50 && !dsp_active[0] && !dsp_active[1] && !dsp_active[2] && !dsp_active[3]) begin
                        state <= S_FINAL_SUB;
                        final_sub_en <= 1'b1; // 🌟 상태 진입 시 초경량 플래그 ON!
                    end

                    // DSP FSM 블록
                    if (dsp_start[0]) begin j_cnt[0] <= '0; j_mux_0 <= '0; dsp_active[0] <= 1'b1; 
                    end else if (dsp_active[0]) begin
                        if(j_cnt[0] == j_max) begin j_cnt[0] <= '0; j_mux_0 <= '0;
                            if(i_cnt[0] == K-1) dsp_active[0] <= 1'b0; else i_cnt[0] <= i_cnt[0] + 2;
                        end else begin j_cnt[0] <= j_cnt[0] + 1; j_mux_0 <= j_cnt[0] + 1; end
                    end
                    
                    if (dsp_start[1]) begin j_cnt[1] <= '0; j_mux_1 <= '0; dsp_active[1] <= 1'b1; 
                    end else if (dsp_active[1]) begin
                        if(!dsp_active[0] && j_cnt[1] == j_max) begin dsp_active[1] <= 1'b0; j_cnt[1] <= '0; j_mux_1 <= '0; 
                        end else if(j_cnt[1] == j_max) begin j_cnt[1] <= '0; j_mux_1 <= '0;
                        end else begin j_cnt[1] <= j_cnt[1] + 1; j_mux_1 <= j_cnt[1] + 1; end
                    end
                    
                    if (dsp_start[2]) begin j_cnt[2] <= '0; j_mux_2 <= '0; dsp_active[2] <= 1'b1; 
                    end else if (dsp_active[2]) begin
                        if(j_cnt[2] == j_max) begin j_cnt[2] <= '0; j_mux_2 <= '0;
                            if(i_cnt[1] == K-2) dsp_active[2] <= 1'b0; else i_cnt[1] <= i_cnt[1] + 2;
                        end else begin j_cnt[2] <= j_cnt[2] + 1; j_mux_2 <= j_cnt[2] + 1; end
                    end
                    
                    if (dsp_start[3]) begin j_cnt[3] <= '0; j_mux_3 <= '0; dsp_active[3] <= 1'b1; 
                    end else if (dsp_active[3]) begin
                        if(!dsp_active[2] && j_cnt[3] == j_max) begin dsp_active[3] <= 1'b0; j_cnt[3] <= '0; j_mux_3 <= '0;
                        end else if(j_cnt[3] == j_max) begin j_cnt[3] <= '0; j_mux_3 <= '0;
                        end else begin j_cnt[3] <= j_cnt[3] + 1; j_mux_3 <= j_cnt[3] + 1; end
                    end
                end
                S_FINAL_SUB: begin
                    if (out_cnt < 5) begin
                        case (out_cnt)
                            3'b000: begin result[W*0  +: W] <= t_read[0]; result[W*1  +: W] <= t_read[1]; result[W*2  +: W] <= t_read[2]; result[W*3  +: W] <= t_read[3]; out_cnt <= out_cnt + 1; end
                            3'b001: begin result[W*4  +: W] <= t_read[0]; result[W*5  +: W] <= t_read[1]; result[W*6  +: W] <= t_read[2]; result[W*7  +: W] <= t_read[3]; out_cnt <= out_cnt + 1; end
                            3'b010: begin result[W*8  +: W] <= t_read[0]; result[W*9  +: W] <= t_read[1]; result[W*10 +: W] <= t_read[2]; result[W*11 +: W] <= t_read[3]; out_cnt <= out_cnt + 1; end
                            3'b011: begin result[W*12 +: W] <= t_read[0]; result[W*13 +: W] <= t_read[1]; result[W*14 +: W] <= t_read[2]; out_cnt <= out_cnt + 1; end
                            default: begin state <= S_DONE; final_sub_en <= 1'b0; end // 🌟 빠져나갈 때 플래그 OFF
                        endcase
                    end
                end
                S_DONE: begin done <= 1'b1; state <= S_IDLE; end
            endcase
        end
    end

    // =========================================================================
    // T 배열 메모리 쓰기
    // =========================================================================
    always_ff @(posedge clk) begin
        if (state == S_INIT) begin 
            if (local_cnt < 5) begin
                t_bank_0[local_cnt[2:0]] <= '0; 
                if (local_cnt < 4) begin        
                    t_bank_1[local_cnt[2:0]] <= '0; t_bank_2[local_cnt[2:0]] <= '0; t_bank_3[local_cnt[2:0]] <= '0; 
                end
            end
        end 
        else if (state == S_RUNNING) begin
            unique0 if (valid_write_0 && w_addr[0][1:0] == 2'b00) t_bank_0[ w_addr[0][4:2] ] <= dsp_p[0][W-1:0];
            else if   (valid_write_1 && w_addr[1][1:0] == 2'b00) t_bank_0[ w_addr[1][4:2] ] <= dsp_p[1][W-1:0];
            else if   (valid_write_2 && w_addr[2][1:0] == 2'b00) t_bank_0[ w_addr[2][4:2] ] <= dsp_p[2][W-1:0];
            else if   (valid_write_3 && w_addr[3][1:0] == 2'b00) t_bank_0[ w_addr[3][4:2] ] <= dsp_p[3][W-1:0];

            unique0 if (valid_write_0 && w_addr[0][1:0] == 2'b01) t_bank_1[ w_addr[0][4:2] ] <= dsp_p[0][W-1:0];
            else if   (valid_write_1 && w_addr[1][1:0] == 2'b01) t_bank_1[ w_addr[1][4:2] ] <= dsp_p[1][W-1:0];
            else if   (valid_write_2 && w_addr[2][1:0] == 2'b01) t_bank_1[ w_addr[2][4:2] ] <= dsp_p[2][W-1:0];
            else if   (valid_write_3 && w_addr[3][1:0] == 2'b01) t_bank_1[ w_addr[3][4:2] ] <= dsp_p[3][W-1:0];

            unique0 if (valid_write_0 && w_addr[0][1:0] == 2'b10) t_bank_2[ w_addr[0][4:2] ] <= dsp_p[0][W-1:0];
            else if   (valid_write_1 && w_addr[1][1:0] == 2'b10) t_bank_2[ w_addr[1][4:2] ] <= dsp_p[1][W-1:0];
            else if   (valid_write_2 && w_addr[2][1:0] == 2'b10) t_bank_2[ w_addr[2][4:2] ] <= dsp_p[2][W-1:0];
            else if   (valid_write_3 && w_addr[3][1:0] == 2'b10) t_bank_2[ w_addr[3][4:2] ] <= dsp_p[3][W-1:0];

            unique0 if (valid_write_0 && w_addr[0][1:0] == 2'b11) t_bank_3[ w_addr[0][4:2] ] <= dsp_p[0][W-1:0];
            else if   (valid_write_1 && w_addr[1][1:0] == 2'b11) t_bank_3[ w_addr[1][4:2] ] <= dsp_p[1][W-1:0];
            else if   (valid_write_2 && w_addr[2][1:0] == 2'b11) t_bank_3[ w_addr[2][4:2] ] <= dsp_p[2][W-1:0];
            else if   (valid_write_3 && w_addr[3][1:0] == 2'b11) t_bank_3[ w_addr[3][4:2] ] <= dsp_p[3][W-1:0];    
        end
    end
endmodule