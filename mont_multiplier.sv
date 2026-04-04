`timescale 1ns/1ps
// DSP 4개로 이루어진 몽고메리 곱셈기 (1-block FSM)
module mont_multiplier (
    input  logic         clk,
    input  logic         reset,
    input  logic         start,
    input  logic [254:0] X,
    input  logic [254:0] Y,
    output logic [254:0] result,
    output logic         done
);
    // 파라미터
    localparam W        = 17;   // word 비트 수
    localparam K        = 15;   // word 개수
    localparam SAVE_LAT = 3;    // DSP 파이프라인 레이턴시
    localparam [16:0] N_prime = 17'h35E5; // n_prime
    localparam [254:0] N = 254'h2523648240000001BA344D80000000086121000000000013A700000000000013;

    // DSP별 j_cnt 시작 오프셋
    localparam D0_START = 0;
    localparam D1_START = 4;
    localparam D2_START = 12;
    localparam D3_START = 16;

    // DSP별 활성 신호 -> DSP 시작 시점을 다르게 하기 위해사
    logic dsp_active [0:3];

    // T 배열 (K+2 = 17개)
    logic [W-1:0] t_arr [K+1:0];

     // 입력 데이터 word 단위 분할
    logic [W-1:0] x_word [K-1:0];
    logic [W-1:0] y_word [K-1:0];
    logic [W-1:0] n_word [K-1:0];

    // 분할 단위로 저장
    generate
        for (genvar g = 0; g < K; g++) begin : gen_split
            assign x_word[g] = X[W*g +: W];
            assign y_word[g] = Y[W*g +: W];
            assign n_word[g] = N[W*g +: W];
        end
    endgenerate


   // state 정의
    typedef enum logic [2:0] {
        S_IDLE, S_INIT, S_RUNNING, S_FINAL_SUB, S_DONE
    } state_e;

    state_e       state;
    logic  [8:0]  local_cnt;        // 글로벌 타이머

    logic  [5:0]  j_cnt    [3:0]; // 내부루프 카운터
    logic  [3:0]  i_cnt    [1:0]; // i[0] : 0,2,4,6,8,10,12,14, i[1] : 1,3,5,7,9,11,13 (외부루프 카운터)

    // --- M 값 저장 용도 (DSP_1/DSP_3 inner2용) ---
    logic  [W-1:0] m_val [1:0];    // for, m_val[0]: dsp_1,  m_val[1]: dsp_3

    // --- DSP 시작 펄스 (local_cnt 조건) ---
    logic dsp_start [0:3];
    assign dsp_start[0] = (state == S_RUNNING) && (local_cnt == D0_START);
    assign dsp_start[1] = (state == S_RUNNING) && (local_cnt == D1_START);
    assign dsp_start[2] = (state == S_RUNNING) && (local_cnt == D2_START);
    assign dsp_start[3] = (state == S_RUNNING) && (local_cnt == D3_START);

    // DSP 입출력
    logic [29:0] dsp_a [0:3];
    logic [17:0] dsp_b [0:3];
    logic [47:0] dsp_c [0:3];
    logic [47:0] dsp_p [0:3];

    //DSP_INSTANCING
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

    // 결과 출력 (T 배열 → 255비트)
    generate
        for (genvar r = 0; r < K; r++) begin : gen_result
            assign result[W*r +: W] = t_arr[r];
        end
    endgenerate

    // Final subtraction용 조합 신호
    logic [W*K-1:0] t_concat;   // t_arr 전체 연결 (255비트)
    logic [W*K-1:0] t_sub_val;  // T - N 결과
    generate
        for (genvar r = 0; r < K; r++) begin : gen_t_concat
            assign t_concat[W*r +: W] = t_arr[r];
        end
    endgenerate
    assign t_sub_val = t_concat - {1'b0, N}; // N 255비트로 zero-extend

    // --- DSP 입력 MUX (조합논리) ---
    // DSP_0 / DSP_2 : inner1  →  x[j] * y[i] + t[j]
    //                 carry   →  1    * t[K]  + 0    (j == K)
    // DSP_1 / DSP_3 : cal_M   →  T[0] * N'
    //                 inner2  →  M    * n[j] + t[j] (j < K)
    //                 carry   →  1    * t[K]  + 0    (j == K, placeholder)

    always_comb begin
        for (int d = 0; d < 4; d++) begin
            dsp_a[d] = '0;
            dsp_b[d] = '0;
            dsp_c[d] = '0;
        end

        if (state == S_RUNNING) begin
            // 계산 시작
            // 데이터 입력 결정 조합 회로 로직
            // DSP_0
            if (dsp_active[0]) begin
                if ((j_cnt[0] < K) && (i_cnt[0] < K)) begin
                    // inner loop: x[j] * y[i_even] + t[j]
                    dsp_a[0] = {{(30-W){1'b0}}, x_word[j_cnt[0][3:0]]}; // x[j]
                    dsp_b[0] = {{(18-W){1'b0}}, y_word[i_cnt[0]]}; // y[i]
                    dsp_c[0] = {{(48-W){1'b0}}, t_arr[j_cnt[0]]}; // t[j]
                end else if (j_cnt[0] == K) begin
                    // carry: (C,S) = t[K] + carry_in → 1 * t[K] + 0
                    dsp_a[0] = 30'b1;
                    dsp_b[0] = {{(18-W){1'b0}}, t_arr[K]};
                    dsp_c[0] = '0;
                end
                else begin
                    dsp_a[0] = '0;
                    dsp_b[0] = '0;
                    dsp_c[0] = '0;
                end
            end

            // DSP_1
            if (dsp_active[1]) begin
                if(j_cnt[1]==0) begin
                    // m 계산 위한 입력 : t[0] , N', 0
                    dsp_a[1] = {{(30-W){1'b0}}, t_arr[0]}; // T[0]
                    dsp_b[1] = {{(18-W){1'b0}}, N_prime}; // N'
                    dsp_c[1] = '0;
                end
                else if (j_cnt[1] == 3) begin
                    // j = 0 에 대한 inner2 (저장 x)
                    dsp_a[1] = {{(30-W){1'b0}}, n_word[j_cnt[1]-3]}; // n[0]
                    dsp_b[1] = {{(18-W){1'b0}}, dsp_p[1][W-1:0]}; //  M을 p에서 가져와야 함 (이거 맞는 지 궁금)
                    dsp_c[1] = {{(48-W){1'b0}}, t_arr[j_cnt[1]-3]}; //t[0]
                end 
                else if(4 <= j_cnt[1] && j_cnt[1] < K+3) begin
                    // inner2: M * n[j] + t[j] ( j = 4 ~ 17)
                    dsp_a[1] = {{(30-W){1'b0}}, n_word[j_cnt[1]-3]}; // n[j]
                    dsp_b[1] = {{(18-W){1'b0}}, m_val[0]}; // M
                    dsp_c[1] = {{(48-W){1'b0}}, t_arr[j_cnt[1]-3]}; // t[j]
                end
                else if ((K+3<=j_cnt[1]) && (j_cnt[1]< K+5)) begin
                    // 마지막 캐리 처리 로직 j = 18,19 (저장 o)
                    dsp_a[1] = {{(30-W){1'b0}}, t_arr[j_cnt[1]-3]}; // T[0]
                    dsp_b[1] = 18'b1;
                    dsp_c[1] = '0;
                end
                else begin
                    dsp_a[1] = '0;
                    dsp_b[1] = '0;
                    dsp_c[1] = '0;
                end
            end

            // DSP_2
            if (dsp_active[2]) begin
                if ((j_cnt[2] < K) && (i_cnt[1] < (K-1))) begin
                    // inner loop: x[j] * y[i_even] + t[j]
                    dsp_a[2] = {{(30-W){1'b0}}, x_word[j_cnt[2][3:0]]}; // x[j]
                    dsp_b[2] = {{(18-W){1'b0}}, y_word[i_cnt[1]]}; // y[i]
                    dsp_c[2] = {{(48-W){1'b0}}, t_arr[j_cnt[2]]}; // t[j]
                end else if (j_cnt[2] == K) begin
                    // carry: (C,S) = t[K] + carry_in → 1 * t[K] + 0
                    dsp_a[2] = 30'b1;
                    dsp_b[2] = {{(18-W){1'b0}}, t_arr[K]};
                    dsp_c[2] = '0;
                end
                else begin
                    dsp_a[2] = '0;
                    dsp_b[2] = '0;
                    dsp_c[2] = '0;
                end
                // else: 대기 구간 → 기본값 0
            end


            // DSP_3
            if (dsp_active[3]) begin
                if(j_cnt[3]==0) begin
                    // m 계산 위한 입력 : t[0] , N', 0
                    dsp_a[3] = {{(30-W){1'b0}}, t_arr[0]}; // T[0]
                    dsp_b[3] = {{(18-W){1'b0}}, N_prime}; // N'
                    dsp_c[3] = '0;
                end
                else if (j_cnt[3] == 3) begin
                    // j = 0 에 대한 inner2 (저장 x)
                    dsp_a[3] = {{(30-W){1'b0}}, n_word[j_cnt[3]-3]}; // n[0]
                    dsp_b[3] = {{(18-W){1'b0}}, dsp_p[3][W-1:0]}; //  M을 p에서 가져와야 함 (이거 맞는 지 궁금)
                    dsp_c[3] = {{(48-W){1'b0}}, t_arr[j_cnt[3]-3]}; //t[0]
                end 
                else if(4 <= j_cnt[3] && j_cnt[3] < K+3) begin
                    // inner2: M * n[j] + t[j] ( j = 4 ~ 17)
                    dsp_a[3] = {{(30-W){1'b0}}, n_word[j_cnt[3]-3]}; // n[j]
                    dsp_b[3] = {{(18-W){1'b0}}, m_val[1]}; // M
                    dsp_c[3] = {{(48-W){1'b0}}, t_arr[j_cnt[3]-3]}; // t[j]
                end
                else if ((K+3<=j_cnt[3]) && (j_cnt[3]< K+5)) begin
                    // 마지막 캐리 처리 로직 j = 18,19 (저장 o)
                    dsp_a[3] = {{(30-W){1'b0}}, t_arr[j_cnt[3]-3]}; // T[0]
                    dsp_b[3] = 18'b1;
                    dsp_c[3] = '0;
                end
                else begin
                    dsp_a[3] = '0;
                    dsp_b[3] = '0;
                    dsp_c[3] = '0;
                end
            end
        end
    end

    // =========================================================================
    // 6. 메인 FSM (순차논리)
    // =========================================================================
    always_ff @(posedge clk or posedge reset) begin
        // reset 신호 받았을때
        if (reset) begin
            state     <= S_IDLE;
            local_cnt <= '0;
            done      <= 1'b0;
            m_val[0]  <= '0;
            m_val[1]  <= '0;
            i_cnt[0]  <= '0;
            i_cnt[1]  <= 1'b1;
            for (int i = 0; i <= K+1; i++) t_arr[i] <= '0;
            for (int d = 0; d < 4; d++) begin
                j_cnt[d]      <= '0;
                dsp_active[d] <= 1'b0;
            end
        end else begin
            case (state)
                // IDLE state
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) state <= S_INIT;
                end

                // INIT state
                S_INIT: begin
                    // local_cnt 및 m_val 초기화
                    local_cnt <= '0;
                    m_val[0]  <= '0;
                    m_val[1]  <= '0;
                    i_cnt[0]  <= '0;
                    i_cnt[1]  <= 1'b1;
                    // j_cnt 및 dsp_active 초기화
                    for (int d = 0; d < 4; d++) begin
                        j_cnt[d]      <= '0;
                        dsp_active[d] <= '0;
                    end
                    // t 배열 초기화
                    for (int i = 0; i <= K+1; i++) begin
                        t_arr[i] <= '0;
                    end
                    state <= S_RUNNING;
                end

                // RUNNIG_STATE
                S_RUNNING: begin
                    // 메인 카운터
                    local_cnt <= local_cnt + 1; // 다음 값이 클락에 +1된다.

                    if(local_cnt > 18 && !dsp_active[0] && !dsp_active[1] && !dsp_active[2] && !dsp_active[3]) begin
                        state <=S_FINAL_SUB;
                    end

                    // DSP_0 카운터 로직
                    if (dsp_start[0]) begin
                            j_cnt[0]      <= '0;
                            dsp_active[0] <= 1'b1;
                    end
                    else if (dsp_active[0]) begin
                        // 파이프라인 마지막 도달
                        if((j_cnt[0] == 23)) begin 
                            j_cnt[0] <= '0; // j_cnt 초기화
                            // i_cnt가 마지막 이면 dsp_active를 0으로 변경
                            if(i_cnt[0]==K-1) begin
                                dsp_active[0] <= 1'b0;
                            end
                            else begin
                                i_cnt[0] <= i_cnt[0] + 2; // i 증가
                            end
                        end
                        // 그 외의 경우
                        else begin 
                            j_cnt[0] <= j_cnt[0] + 1;
                        end
                    end

                    // DSP_1 카운터 로직
                    if (dsp_start[1]) begin
                            j_cnt[1]      <= '0;
                            dsp_active[1] <= 1'b1;
                    end
                    else if (dsp_active[1]) begin
                        // dsp_1 종료시점
                        if(!dsp_active[0] && (j_cnt[1]==23))begin
                                dsp_active[1] <= 1'b0;
                                j_cnt[1] <= '0; 
                        end
                        // 파이프라인 마지막 도달 후 j_cnt 초기화
                        else if((j_cnt[1] == 23)) begin 
                                j_cnt[1] <= '0; //다음 클락에 0으로 초기화
                        end
                        // 그 외의 경우
                        else begin 
                            j_cnt[1] <= j_cnt[1] + 1;
                        end
                    end

                    // DSP_2 카운터 로직
                    if (dsp_start[2]) begin
                            j_cnt[2]      <= '0;
                            dsp_active[2] <= 1'b1;
                    end
                    else if (dsp_active[2]) begin
                        // 파이프라인 마지막 도달
                        if((j_cnt[2] == 23)) begin 
                            j_cnt[2] <= '0; // j_cnt 초기화
                            // i_cnt가 마지막 이면 dsp_active를 0으로 변경
                            if(i_cnt[1]==K-2) begin
                                dsp_active[2] <= 1'b0;
                            end
                            else begin
                                i_cnt[1] <= i_cnt[1] + 2; // i 증가
                            end
                        end
                        // 그 외의 경우
                        else begin 
                            j_cnt[2] <= j_cnt[2] + 1;
                        end
                    end

                    // DSP_3 카운터 로직
                    if (dsp_start[3]) begin
                            j_cnt[3]      <= '0;
                            dsp_active[3] <= 1'b1;
                    end
                    else if (dsp_active[3]) begin
                        // dsp_3 종료시점
                        if( !dsp_active[2] && (j_cnt[3]==23))begin
                                dsp_active[3] <= 1'b0;
                                j_cnt[3] <= '0; 
                        end
                        // 파이프라인 마지막 도달 후 j_cnt 초기화
                        else if((j_cnt[3] == 23)) begin 
                                j_cnt[3] <= '0; //다음 클락에 0으로 초기화
                        end
                        // 그 외의 경우
                        else begin 
                            j_cnt[3] <= j_cnt[3] + 1;
                        end
                    end
                    
//--------------------------------------------------------------------------------------------
                    // T 배열 write-back, m write back
                    // 결과는 입력 후 SAVE_LAT(=3) 클럭 뒤에 dsp_p에 등장
                    // DSP_0 
                    if (dsp_active[0]) begin
                        // T 저장 ( j_cnt : 3 ~ 17, 입력 j_cnt=0~14 기준 출력 j_cnt=3~17 )
                        if (j_cnt[0] >= SAVE_LAT && j_cnt[0] < K + SAVE_LAT) begin
                            t_arr[j_cnt[0] - SAVE_LAT] <= dsp_p[0][W-1:0];
                        end 
                        // 마지막 캐리 처리 결과 저장(j_cnt = 18 = K+SAVE_LAT)
                        else if (j_cnt[0] == K + SAVE_LAT) begin
                            // 캐리 결과: t[K]=S, t[K+1]=C
                            t_arr[K]   <= dsp_p[0][W-1:0];
                            t_arr[K+1] <= dsp_p[0][2*W-1:W];
                        end
                    end
                
                    // DSP_1
                    if (dsp_active[1]) begin
                        // M 저장 (j_cnt=0 입력 → j_cnt=3=SAVE_LAT에 출력)
                        if (j_cnt[1] == SAVE_LAT) begin
                            m_val[0] <= dsp_p[1][W-1:0];
                        end
                        // T 저장 (inner2 j=1~K-1, j_cnt=7~20)
                        // j_cnt=3에서 inner2 j=0 입력 → j_cnt=6 출력 (버림)
                        // j_cnt=4에서 inner2 j=1 입력 → j_cnt=7 출력 → t_arr[0]
                        else if (j_cnt[1] > SAVE_LAT+3 && j_cnt[1] <= K + SAVE_LAT+2) begin
                            t_arr[j_cnt[1] - (SAVE_LAT+4)] <= dsp_p[1][W-1:0];
                        end 
                        // 캐리1 결과 저장 (j_cnt=21=K+6=K+SAVE_LAT+3)
                        else if (j_cnt[1] == K + SAVE_LAT+3) begin
                            t_arr[K-1] <= dsp_p[1][W-1:0];
                        end
                        // 캐리2 결과 저장 (j_cnt=22=K+7=K+SAVE_LAT+4)
                        else if (j_cnt[1] == K + SAVE_LAT+4) begin
                            t_arr[K] <= dsp_p[1][W-1:0];
                        end
                    end

                    // DSP_2
                    if (dsp_active[2]) begin
                        // T 저장 ( j_cnt : 3 ~ 17 )
                        if (j_cnt[2] >= SAVE_LAT && j_cnt[2] < K + SAVE_LAT) begin
                            t_arr[j_cnt[2] - SAVE_LAT] <= dsp_p[2][W-1:0];
                        end 
                        // 마지막 캐리 처리 결과 저장(j_cnt = 18 = K+SAVE_LAT)
                        else if (j_cnt[2] == K + SAVE_LAT) begin
                            // 캐리 결과: t[K]=S, t[K+1]=C
                            t_arr[K]   <= dsp_p[2][W-1:0];
                            t_arr[K+1] <= dsp_p[2][2*W-1:W];
                        end
                    end

                    //DSP_3
                    if (dsp_active[3]) begin
                        // M 저장 (j_cnt=0 입력 → j_cnt=3=SAVE_LAT에 출력)
                        if (j_cnt[3] == SAVE_LAT) begin
                            m_val[1] <= dsp_p[3][W-1:0];
                        end
                        // T 저장 (inner2 j=1~K-1, j_cnt=7~20)
                        else if (j_cnt[3] > SAVE_LAT+3 && j_cnt[3] <= K + SAVE_LAT+2) begin
                            t_arr[j_cnt[3] - (SAVE_LAT+4)] <= dsp_p[3][W-1:0];
                        end 
                        // 캐리1 결과 저장 (j_cnt=21=K+SAVE_LAT+3)
                        else if (j_cnt[3] == K + SAVE_LAT+3) begin
                            t_arr[K-1] <= dsp_p[3][W-1:0];
                        end
                        // 캐리2 결과 저장 (j_cnt=22=K+SAVE_LAT+4)
                        else if (j_cnt[3] == K + SAVE_LAT+4) begin
                            t_arr[K] <= dsp_p[3][W-1:0];
                        end
                    end
                end
                // FINAL_SUB_STATE
                S_FINAL_SUB: begin
                    // T >= N 이면 T - N, 아니면 T 유지
                    if (t_concat >= {1'b0, N}) begin
                        for (int r = 0; r < K; r++)
                            t_arr[r] <= t_sub_val[W*r +: W];
                    end
                    state <= S_DONE;
                end
                // DONE_STATE
                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule
