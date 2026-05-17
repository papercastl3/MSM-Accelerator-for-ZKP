module ECC_point_adder(
    input  logic         clk,
    input  logic         reset,
    input  logic         start,
    input  logic [254:0] x1,
    input  logic [254:0] y1,
    input  logic [254:0] z1,
    input  logic [254:0] x2, 
    input  logic [254:0] y2, 
    input  logic [254:0] z2, 
    output logic [254:0] x3,
    output logic [254:0] y3,
    output logic [254:0] z3,
    output logic         done
);

    // ==========================================
    // 1. 메모리 맵 정의 
    // ==========================================
    localparam M_X1 = 4'd0, M_Y1 = 4'd1, M_Z1 = 4'd2;
    localparam M_X2 = 4'd3, M_Y2 = 4'd4, M_Z2 = 4'd5;
    localparam M_2Y1= 4'd6; 
    localparam M_T0 = 4'd7, M_T1 = 4'd8, M_T2 = 4'd9;
    localparam M_T3 = 4'd10, M_T4 = 4'd11, M_T5 = 4'd12, M_T6 = 4'd13;

    // ==========================================
    // 2. True Dual-Port BRAM (Latency 2)
    // ==========================================
    //(* ram_style = "block" *)
    (* ram_style = "block" *)
    logic [255:0] mem [0:15];
    logic [255:0] douta_reg, doutb_reg;
    logic [3:0]   addra, addrb;
    logic [255:0] dina, dinb;
    logic         wea, web;
    logic [255:0] douta, doutb;

    always_ff @(posedge clk) begin
        if (wea) mem[addra] <= dina;
        douta_reg <= mem[addra];
        douta <= douta_reg;
    end
    always_ff @(posedge clk) begin
        if (web) mem[addrb] <= dinb;
        doutb_reg <= mem[addrb];
        doutb <= doutb_reg;
    end

    // ==========================================
    // 3. 연산기 고정 입력 레지스터
    // ==========================================
    logic [255:0] mul_a_x_reg, mul_a_y_reg;
    logic [255:0] mul_b_x_reg, mul_b_y_reg;
    logic [255:0] au_a_reg, au_b_reg;
    logic [255:0] v_reg; // Stage 4 연속 뺄셈용 보존 레지스터

    logic mul_a_start, mul_b_start, au_start;
    logic [254:0] mul_a_result, mul_b_result;
    logic mul_a_done, mul_b_done, au_done;
    logic [1:0] au_op_mode;
    logic [255:0] au_result;

    mont_multiplier mul_a (
        .clk(clk), .reset(reset), .start(mul_a_start),
        .X(mul_a_x_reg[254:0]), .Y(mul_a_y_reg[254:0]),
        .result(mul_a_result), .done(mul_a_done)
    );

    mont_multiplier mul_b (
        .clk(clk), .reset(reset), .start(mul_b_start),
        .X(mul_b_x_reg[254:0]), .Y(mul_b_y_reg[254:0]),
        .result(mul_b_result), .done(mul_b_done)
    );

    AddSub_256 au (
        .clk(clk), .reset(reset), .start(au_start), .op_mode(au_op_mode),
        .A(au_a_reg), .B(au_b_reg), .result(au_result), .done(au_done)
    );

    // ==========================================
    // 4. 주소 기반 FSM (Latency 2 정밀 매칭)
    // ==========================================
    typedef enum logic [6:0] {
        ST_IDLE, ST_LOAD_0, ST_LOAD_1,
        MA_ST0_FETCH_0, MA_ST0_WAIT_1, MA_ST0_WAIT_2, MA_ST0_LATCH_0, MA_ST0_MUL_WAIT_0,
        MA_ST1_FETCH_0, MA_ST1_FETCH_1, MA_ST1_FETCH_X2, MA_ST1_LATCH_0, MA_ST1_LATCH_1, MA_ST1_LATCH_X2, MA_ST1_MUL_WAIT_0, MA_ST1_AU_WAIT_0,
        MA_ST2_FETCH_0, MA_ST2_FETCH_1, MA_ST2_WAIT_0, MA_ST2_LATCH_0, MA_ST2_LATCH_1, MA_ST2_MUL_WAIT_0, MA_ST2_AU_WAIT_0,
        MA_ST3_FETCH_0, MA_ST3_FETCH_1, MA_ST3_WAIT_0, MA_ST3_LATCH_0, MA_ST3_LATCH_1, MA_ST3_MUL_WAIT_0,
        MA_ST4_FETCH_0, MA_ST4_FETCH_1, MA_ST4_WAIT_0, MA_ST4_LATCH_0, MA_ST4_LATCH_1, MA_ST4_MUL_WAIT_0,
        MA_ST4_AU_WAIT_0, MA_ST4_AU_WAIT_1, MA_ST4_AU_WAIT_2, MA_ST4_AU_WAIT_3,
        MA_ST5_FETCH_0, MA_ST5_FETCH_1, MA_ST5_WAIT_0, MA_ST5_LATCH_0, MA_ST5_LATCH_1, MA_ST5_MUL_WAIT_0, MA_ST5_AU_WAIT_0,
        MA_FINAL_FETCH_Y, MA_FINAL_WAIT_Y1, MA_FINAL_WAIT_Y2, MA_FINAL_LATCH_Y, MA_FINAL_AU_WAIT_Y1, MA_FINAL_AU_WAIT_Y2,
        MA_FINAL_FETCH_Z, MA_FINAL_WAIT_Z1, MA_FINAL_WAIT_Z2, MA_FINAL_LATCH_Z, MA_FINAL_AU_WAIT_Z1, MA_FINAL_AU_WAIT_Z2,
        MA_FINAL_FETCH_X, MA_FINAL_WAIT_X1, MA_FINAL_WAIT_X2, MA_FINAL_LATCH_X, MA_FINAL_AU_WAIT_X1, MA_FINAL_AU_WAIT_X2,
        S_DONE
    } state_e;

    state_e state;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            done <= 1'b0;
            mul_a_start <= 0; mul_b_start <= 0; au_start <= 0;
            wea <= 0; web <= 0;
            v_reg <= '0;
            x3 <= '0; y3 <= '0; z3 <= '0;
        end 
        else begin
            mul_a_start <= 0; mul_b_start <= 0; au_start <= 0;
            wea <= 0; web <= 0;

            case (state)
                ST_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        wea <= 1; addra <= M_X1; dina <= {1'b0, x1};
                        web <= 1; addrb <= M_Y1; dinb <= {1'b0, y1};
                        state <= ST_LOAD_0;
                    end
                end
                ST_LOAD_0: begin 
                    wea <= 1; addra <= M_Z2; dina <= {1'b0, z2};
                    web <= 1; addrb <= M_2Y1; dinb <= {y1, 1'b0};
                    state <= ST_LOAD_1; 
                end
                ST_LOAD_1: begin    
                    wea <= 1; addra <= M_X2; dina <= {1'b0, x2};
                    web <= 1; addrb <= M_Y2; dinb <= {1'b0, y2};
                    state <= MA_ST0_FETCH_0; 
                end

                // --- STAGE 0 ---
                MA_ST0_FETCH_0: begin addra <= M_Z2; state <= MA_ST0_WAIT_1; end
                MA_ST0_WAIT_1:  begin state <= MA_ST0_WAIT_2; end // BRAM Latency 대기
                MA_ST0_WAIT_2:  begin state <= MA_ST0_LATCH_0; end
                MA_ST0_LATCH_0: begin 
                    mul_a_x_reg <= douta; mul_a_y_reg <= douta; 
                    mul_a_start <= 1; state <= MA_ST0_MUL_WAIT_0; 
                end
                MA_ST0_MUL_WAIT_0: begin 
                    if (mul_a_done) begin
                        wea <= 1; addra <= M_T0; dina <= {1'b0, mul_a_result}; 
                        state <= MA_ST1_FETCH_0;
                    end
                end

                // --- STAGE 1 (Gapless Pipeline) ---
                MA_ST1_FETCH_0:  begin addra <= M_Z2; addrb <= M_T0; state <= MA_ST1_FETCH_1; end
                MA_ST1_FETCH_1:  begin addra <= M_X1; addrb <= M_T0; state <= MA_ST1_FETCH_X2; end
                MA_ST1_FETCH_X2: begin addra <= M_X2; state <= MA_ST1_LATCH_0; end // 주소 던짐과 동시에 FETCH_0의 데이터가 나옴
                MA_ST1_LATCH_0:  begin 
                    mul_a_x_reg <= douta; mul_a_y_reg <= doutb; // Z2, T0 래치
                    state <= MA_ST1_LATCH_1; 
                end
                MA_ST1_LATCH_1:  begin 
                    mul_b_x_reg <= douta; mul_b_y_reg <= doutb; // X1, T0 래치
                    mul_a_start <= 1; mul_b_start <= 1; 
                    state <= MA_ST1_LATCH_X2; 
                end
                MA_ST1_LATCH_X2: begin
                    au_a_reg <= douta; // X2 래치
                    state <= MA_ST1_MUL_WAIT_0;
                end
                MA_ST1_MUL_WAIT_0: begin 
                    if (mul_a_done && mul_b_done) begin
                        wea <= 1; addra <= M_T1; dina <= {1'b0, mul_a_result}; 
                        web <= 1; addrb <= M_T2; dinb <= {1'b0, mul_b_result}; 
                        au_b_reg <= {1'b0, mul_b_result}; 
                        au_start <= 1; au_op_mode <= 2'b01; 
                        state <= MA_ST1_AU_WAIT_0;
                    end
                end
                MA_ST1_AU_WAIT_0: begin
                    if (au_done) begin
                        wea <= 1; addra <= M_T3; dina <= au_result;
                        state <= MA_ST2_FETCH_0;
                    end
                end

                // --- STAGE 2 ---
                MA_ST2_FETCH_0: begin addra <= M_Y1; addrb <= M_T1; state <= MA_ST2_FETCH_1; end
                MA_ST2_FETCH_1: begin addra <= M_T3; addrb <= M_Y2; state <= MA_ST2_WAIT_0; end
                MA_ST2_WAIT_0:  begin state <= MA_ST2_LATCH_0; end
                MA_ST2_LATCH_0: begin mul_a_x_reg <= douta; mul_a_y_reg <= doutb; state <= MA_ST2_LATCH_1; end
                MA_ST2_LATCH_1: begin 
                    mul_b_x_reg <= douta; mul_b_y_reg <= douta; 
                    au_a_reg <= doutb; // Y2 래치
                    mul_a_start <= 1; mul_b_start <= 1; 
                    state <= MA_ST2_MUL_WAIT_0; 
                end
                MA_ST2_MUL_WAIT_0: begin 
                    if (mul_a_done && mul_b_done) begin
                        wea <= 1; addra <= M_T1; dina <= {1'b0, mul_a_result}; 
                        web <= 1; addrb <= M_T4; dinb <= {1'b0, mul_b_result}; 
                        au_b_reg <= {1'b0, mul_a_result}; 
                        au_start <= 1; au_op_mode <= 2'b01; 
                        state <= MA_ST2_AU_WAIT_0;
                    end
                end
                MA_ST2_AU_WAIT_0: begin
                    if (au_done) begin
                        wea <= 1; addra <= M_T5; dina <= au_result; 
                        state <= MA_ST3_FETCH_0;
                    end
                end

                // --- STAGE 3 ---
                MA_ST3_FETCH_0: begin addra <= M_Z2; addrb <= M_T3; state <= MA_ST3_FETCH_1; end
                MA_ST3_FETCH_1: begin addra <= M_T3; addrb <= M_T4; state <= MA_ST3_WAIT_0; end
                MA_ST3_WAIT_0:  begin state <= MA_ST3_LATCH_0; end
                MA_ST3_LATCH_0: begin mul_a_x_reg <= douta; mul_a_y_reg <= doutb; state <= MA_ST3_LATCH_1; end
                MA_ST3_LATCH_1: begin 
                    mul_b_x_reg <= douta; mul_b_y_reg <= doutb; 
                    mul_a_start <= 1; mul_b_start <= 1; 
                    state <= MA_ST3_MUL_WAIT_0; 
                end
                MA_ST3_MUL_WAIT_0: begin
                    if (mul_a_done && mul_b_done) begin
                        wea <= 1; addra <= M_T0; dina <= {1'b0, mul_a_result}; 
                        web <= 1; addrb <= M_T6; dinb <= {1'b0, mul_b_result}; 
                        state <= MA_ST4_FETCH_0;
                    end
                end

                // --- STAGE 4 ---
                MA_ST4_FETCH_0: begin addra <= M_T2; addrb <= M_T4; state <= MA_ST4_FETCH_1; end 
                MA_ST4_FETCH_1: begin addra <= M_T5; addrb <= M_T6; state <= MA_ST4_WAIT_0; end
                MA_ST4_WAIT_0:  begin state <= MA_ST4_LATCH_0; end
                MA_ST4_LATCH_0: begin mul_a_x_reg <= douta; mul_a_y_reg <= doutb; state <= MA_ST4_LATCH_1; end
                MA_ST4_LATCH_1: begin
                    mul_b_x_reg <= douta; mul_b_y_reg <= douta; 
                    au_b_reg <= doutb;    // H^3 래치
                    mul_a_start <= 1; mul_b_start <= 1; 
                    state <= MA_ST4_MUL_WAIT_0;
                end
                MA_ST4_MUL_WAIT_0: begin
                    if (mul_a_done && mul_b_done) begin
                        v_reg <= {1'b0, mul_a_result}; 
                        au_a_reg <= {1'b0, mul_b_result}; 
                        au_start <= 1; au_op_mode <= 2'b10; 
                        state <= MA_ST4_AU_WAIT_0;
                    end
                end
                MA_ST4_AU_WAIT_0: begin
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= v_reg;     
                        au_start <= 1; au_op_mode <= 2'b10; 
                        state <= MA_ST4_AU_WAIT_1;
                    end
                end
                MA_ST4_AU_WAIT_1: begin
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= v_reg;     
                        au_start <= 1; au_op_mode <= 2'b10; 
                        state <= MA_ST4_AU_WAIT_2;
                    end
                end
                MA_ST4_AU_WAIT_2: begin
                    if (au_done) begin
                        wea <= 1; addra <= M_T3; dina <= au_result; 
                        au_a_reg <= v_reg; au_b_reg <= au_result; 
                        au_start <= 1; au_op_mode <= 2'b10; 
                        state <= MA_ST4_AU_WAIT_3;
                    end
                end
                MA_ST4_AU_WAIT_3: begin
                    if (au_done) begin
                        wea <= 1; addra <= M_T4; dina <= au_result; 
                        state <= MA_ST5_FETCH_0;
                    end
                end

                // --- STAGE 5 ---
                MA_ST5_FETCH_0: begin addra <= M_T1; addrb <= M_T6; state <= MA_ST5_FETCH_1; end 
                MA_ST5_FETCH_1: begin addra <= M_T5; addrb <= M_T4; state <= MA_ST5_WAIT_0; end
                MA_ST5_WAIT_0:  begin state <= MA_ST5_LATCH_0; end
                MA_ST5_LATCH_0: begin mul_a_x_reg <= douta; mul_a_y_reg <= doutb; state <= MA_ST5_LATCH_1; end
                MA_ST5_LATCH_1: begin
                    mul_b_x_reg <= douta; mul_b_y_reg <= doutb; 
                    mul_a_start <= 1; mul_b_start <= 1; 
                    state <= MA_ST5_MUL_WAIT_0;
                end
                MA_ST5_MUL_WAIT_0: begin
                    if (mul_a_done && mul_b_done) begin
                        au_a_reg <= {1'b0, mul_b_result}; 
                        au_b_reg <= {1'b0, mul_a_result}; 
                        au_start <= 1; au_op_mode <= 2'b10; 
                        state <= MA_ST5_AU_WAIT_0;
                    end
                end
                MA_ST5_AU_WAIT_0: begin
                    if (au_done) begin
                        wea <= 1; addra <= M_T1; dina <= au_result; 
                        state <= MA_FINAL_FETCH_Y;
                    end
                end

                // --- FINAL REDUCTION ---
                // --- FINAL REDUCTION (Double Pass for 3N -> N) ---
                // Lazy Reduction 결과값이 최대 3N-1이므로, 완벽한 모듈러 N을 위해 2번씩 뺍니다.

                // 1. Y3 Double Reduction
                MA_FINAL_FETCH_Y: begin addra <= M_T1; state <= MA_FINAL_WAIT_Y1; end
                MA_FINAL_WAIT_Y1: begin state <= MA_FINAL_WAIT_Y2; end
                MA_FINAL_WAIT_Y2: begin state <= MA_FINAL_LATCH_Y; end
                MA_FINAL_LATCH_Y: begin
                    au_a_reg <= douta; au_b_reg <= 256'b0; 
                    au_op_mode <= 2'b11; au_start <= 1; // 첫 번째 mod N
                    state <= MA_FINAL_AU_WAIT_Y1;
                end
                MA_FINAL_AU_WAIT_Y1: begin
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= 256'b0;
                        au_op_mode <= 2'b11; au_start <= 1; // 두 번째 mod N (결과를 바로 다시 넣음)
                        state <= MA_FINAL_AU_WAIT_Y2;
                    end
                end
                MA_FINAL_AU_WAIT_Y2: begin
                    if (au_done) begin
                        y3 <= au_result[254:0];
                        state <= MA_FINAL_FETCH_Z;
                    end
                end

                // 2. Z3 Double Reduction
                MA_FINAL_FETCH_Z: begin addra <= M_T0; state <= MA_FINAL_WAIT_Z1; end
                MA_FINAL_WAIT_Z1: begin state <= MA_FINAL_WAIT_Z2; end
                MA_FINAL_WAIT_Z2: begin state <= MA_FINAL_LATCH_Z; end
                MA_FINAL_LATCH_Z: begin
                    au_a_reg <= douta; au_b_reg <= 256'b0;
                    au_op_mode <= 2'b11; au_start <= 1; // 첫 번째 mod N
                    state <= MA_FINAL_AU_WAIT_Z1;
                end
                MA_FINAL_AU_WAIT_Z1: begin
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= 256'b0;
                        au_op_mode <= 2'b11; au_start <= 1; // 두 번째 mod N
                        state <= MA_FINAL_AU_WAIT_Z2;
                    end
                end
                MA_FINAL_AU_WAIT_Z2: begin
                    if (au_done) begin
                        z3 <= au_result[254:0];
                        state <= MA_FINAL_FETCH_X;
                    end
                end

                // 3. X3 Double Reduction
                MA_FINAL_FETCH_X: begin addra <= M_T3; state <= MA_FINAL_WAIT_X1; end
                MA_FINAL_WAIT_X1: begin state <= MA_FINAL_WAIT_X2; end
                MA_FINAL_WAIT_X2: begin state <= MA_FINAL_LATCH_X; end
                MA_FINAL_LATCH_X: begin
                    au_a_reg <= douta; au_b_reg <= 256'b0;
                    au_op_mode <= 2'b11; au_start <= 1; // 첫 번째 mod N
                    state <= MA_FINAL_AU_WAIT_X1;
                end
                MA_FINAL_AU_WAIT_X1: begin
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= 256'b0;
                        au_op_mode <= 2'b11; au_start <= 1; // 두 번째 mod N
                        state <= MA_FINAL_AU_WAIT_X2;
                    end
                end
                MA_FINAL_AU_WAIT_X2: begin
                    if (au_done) begin
                        x3 <= au_result[254:0];
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule