`timescale 1ns/1ps

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

    localparam [254:0] N = 254'h2523648240000001BA344D80000000086121000000000013A700000000000013;

    // ==========================================
    // 2. True Dual-Port BRAM
    // ==========================================
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
    // 3. 연산기 및 제어 신호
    // ==========================================
    logic [255:0] mul_a_x_reg, mul_a_y_reg;
    logic [255:0] mul_b_x_reg, mul_b_y_reg;
    logic [255:0] au_a_reg, au_b_reg;
    logic [255:0] v_reg; 

    logic mul_a_start, mul_b_start, au_start;
    logic [254:0] mul_a_result, mul_b_result;
    logic mul_a_done, mul_b_done, au_done;
    logic [1:0] au_op_mode;
    logic [255:0] au_result;

    logic h_is_zero_reg;
    logic r_is_zero_reg;

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
    // 4. 주소 기반 메인 FSM 
    // ==========================================
    typedef enum {
        ST_IDLE, ST_LOAD_0, ST_LOAD_1,
        MA_ST0_FETCH_0, MA_ST0_WAIT_1, MA_ST0_WAIT_2, MA_ST0_LATCH_0, MA_ST0_MUL_WAIT_0,
        MA_ST1_FETCH_0, MA_ST1_FETCH_1, MA_ST1_FETCH_X2, MA_ST1_LATCH_0, MA_ST1_LATCH_1, MA_ST1_LATCH_X2, MA_ST1_MUL_WAIT_0, MA_ST1_AU_WAIT_0,
        MA_ST2_FETCH_0, MA_ST2_FETCH_1, MA_ST2_WAIT_0, MA_ST2_LATCH_0, MA_ST2_LATCH_1, MA_ST2_MUL_WAIT_0, MA_ST2_AU_WAIT_0,
        
        ST_IS_DBL_CHK_FETCH, ST_IS_DBL_CHK_W1, ST_IS_DBL_CHK_W2, ST_IS_DBL_CHK_LATCH, ST_IS_DBL_CHK, 
        
        MA_ST3_FETCH_0, MA_ST3_FETCH_1, MA_ST3_WAIT_0, MA_ST3_LATCH_0, MA_ST3_LATCH_1, MA_ST3_MUL_WAIT_0,
        MA_ST4_FETCH_0, MA_ST4_FETCH_1, MA_ST4_WAIT_0, MA_ST4_LATCH_0, MA_ST4_LATCH_1, MA_ST4_MUL_WAIT_0,
        MA_ST4_AU_WAIT_0, MA_ST4_AU_WAIT_1, MA_ST4_AU_WAIT_2, MA_ST4_AU_WAIT_3,
        MA_ST5_FETCH_0, MA_ST5_FETCH_1, MA_ST5_WAIT_0, MA_ST5_LATCH_0, MA_ST5_LATCH_1, MA_ST5_MUL_WAIT_0, MA_ST5_AU_WAIT_0,
        MA_FINAL_FETCH_Y, MA_FINAL_WAIT_Y1, MA_FINAL_WAIT_Y2, MA_FINAL_LATCH_Y, MA_FINAL_AU_WAIT_Y1, MA_FINAL_AU_WAIT_Y2,
        MA_FINAL_FETCH_Z, MA_FINAL_WAIT_Z1, MA_FINAL_WAIT_Z2, MA_FINAL_LATCH_Z, MA_FINAL_AU_WAIT_Z1, MA_FINAL_AU_WAIT_Z2,
        MA_FINAL_FETCH_X, MA_FINAL_WAIT_X1, MA_FINAL_WAIT_X2, MA_FINAL_LATCH_X, MA_FINAL_AU_WAIT_X1, MA_FINAL_AU_WAIT_X2,
        
        S_LOAD_DBL_0, S_LOAD_DBL_1, 
        
        S_1_F, S_1_W1, S_1_W2, S_1_L,
        S_1A_F, S_1A_W1, S_1A_W2, S_1A_L, S_1A_D, S_1_MW,
        S_W1_F, S_W1_W1, S_W1_W2, S_W1_L, S_W1_D1, S_W1_D2,
        S_2_F0, S_2_F1, S_2_WX, S_2_L0, S_2_L1, S_2_MW,
        S_W2_F, S_W2_W1, S_W2_W2, S_W2_L, S_W2_D1, S_W2_D2, S_W2_D3,
        S_W2_F2, S_W2_W3, S_W2_W4, S_W2_L2, S_W2_D4,
        S_W2_F3, S_W2_W5, S_W2_W6, S_W2_L3, S_W2_D5,
        S_3_F0, S_3_F1, S_3_WX, S_3_L0, S_3_L1,
        S_3A_F, S_3A_W1, S_3A_W2, S_3A_L, S_3A_D1, S_3A_D2, S_3_MW,
        S_F_F, S_F_W1, S_F_W2, S_F_L, S_F_D1, S_F_D2, S_F_D3,
        S_F_F2, S_F_W3, S_F_W4, S_F_L2, S_F_D4, S_F_D5, S_F_D6,
        S_O_F0, S_O_F1, S_O_WX, S_O_L0, S_O_L1,
        S_DONE
    } state_e;

   state_e state;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE; done <= 1'b0;
            h_is_zero_reg <= 1'b0; r_is_zero_reg <= 1'b0;
            mul_a_start <= 0; mul_b_start <= 0; au_start <= 0;
            wea <= 0; web <= 0; v_reg <= '0;
            x3 <= '0; y3 <= '0; z3 <= '0;
        end 
        else begin
            mul_a_start <= 0; mul_b_start <= 0; au_start <= 0;
            wea <= 0; web <= 0;

            case (state)
                ST_IDLE: begin
                    done <= 1'b0;
                    h_is_zero_reg <= 1'b0; r_is_zero_reg <= 1'b0;
                    if (start) begin
                        if (z2 == 255'd0) begin // 예외 처리 
                            x3 <= x1; 
                            y3 <= y1; 
                            z3 <= z1;
                            state <= S_DONE;
                        end 
                        else if (z1 == 255'd0) begin // 예외 처리
                            x3 <= x2; 
                            y3 <= y2; 
                            z3 <= z2;
                            state <= S_DONE;
                        end 
                        else begin // 일반 처리
                            wea <= 1; addra <= M_X1; dina <= {1'b0, x1};
                            web <= 1; addrb <= M_Y1; dinb <= {1'b0, y1};
                            state <= ST_LOAD_0;
                        end
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

                MA_ST0_FETCH_0: begin addra <= M_Z2; state <= MA_ST0_WAIT_1; end
                MA_ST0_WAIT_1:  begin state <= MA_ST0_WAIT_2; end 
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

                MA_ST1_FETCH_0:  begin addra <= M_Z2; addrb <= M_T0; state <= MA_ST1_FETCH_1; end
                MA_ST1_FETCH_1:  begin addra <= M_X1; addrb <= M_T0; state <= MA_ST1_FETCH_X2; end
                MA_ST1_FETCH_X2: begin addra <= M_X2; state <= MA_ST1_LATCH_0; end 
                MA_ST1_LATCH_0:  begin mul_a_x_reg <= douta; mul_a_y_reg <= doutb; state <= MA_ST1_LATCH_1; end
                MA_ST1_LATCH_1:  begin 
                    mul_b_x_reg <= douta; mul_b_y_reg <= doutb; 
                    mul_a_start <= 1; mul_b_start <= 1; 
                    state <= MA_ST1_LATCH_X2; 
                end
                MA_ST1_LATCH_X2: begin au_a_reg <= douta; state <= MA_ST1_MUL_WAIT_0; end
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

                MA_ST2_FETCH_0: begin addra <= M_Y1; addrb <= M_T1; state <= MA_ST2_FETCH_1; end
                MA_ST2_FETCH_1: begin addra <= M_T3; addrb <= M_Y2; state <= MA_ST2_WAIT_0; end
                MA_ST2_WAIT_0:  begin state <= MA_ST2_LATCH_0; end
                MA_ST2_LATCH_0: begin mul_a_x_reg <= douta; mul_a_y_reg <= doutb; state <= MA_ST2_LATCH_1; end
                MA_ST2_LATCH_1: begin 
                    mul_b_x_reg <= douta; mul_b_y_reg <= douta; au_a_reg <= doutb; 
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
                        state <= ST_IS_DBL_CHK_FETCH;
                    end
                end
                ST_IS_DBL_CHK_FETCH: begin
                    addra <= M_T3; addrb <= M_T5; 
                    state <= ST_IS_DBL_CHK_W1;
                end
                ST_IS_DBL_CHK_W1: begin
                    state <= ST_IS_DBL_CHK_W2; 
                end
                ST_IS_DBL_CHK_W2: begin
                    state <= ST_IS_DBL_CHK_LATCH; 
                end
                ST_IS_DBL_CHK_LATCH: begin
                    h_is_zero_reg <= (douta[254:0] == 255'd0) || (douta[254:0] == N);
                    r_is_zero_reg <= (doutb[254:0] == 255'd0) || (doutb[254:0] == N);
                    state <= MA_ST3_FETCH_0;
                end

                MA_ST3_FETCH_0: begin 
                    if (h_is_zero_reg) begin
                        if (r_is_zero_reg) begin
                            state <= S_LOAD_DBL_0; 
                        end else begin
                            x3 <= '0; y3 <= '0; z3 <= '0; 
                            state <= S_DONE;
                        end
                    end 
                    else begin
                        addra <= M_Z2; addrb <= M_T3; 
                        state <= MA_ST3_FETCH_1; 
                    end
                end

                // --- [Addition 경로] ---
                MA_ST3_FETCH_1: begin addra <= M_T3; addrb <= M_T4; state <= MA_ST3_WAIT_0; end
                MA_ST3_WAIT_0:  begin state <= MA_ST3_LATCH_0; end
                MA_ST3_LATCH_0: begin 
                    mul_a_x_reg <= douta; mul_a_y_reg <= doutb; 
                    state <= MA_ST3_LATCH_1; 
                end
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

                MA_ST4_FETCH_0: begin addra <= M_T2; addrb <= M_T4; state <= MA_ST4_FETCH_1; end 
                MA_ST4_FETCH_1: begin addra <= M_T5; addrb <= M_T6; state <= MA_ST4_WAIT_0; end
                MA_ST4_WAIT_0:  begin state <= MA_ST4_LATCH_0; end
                MA_ST4_LATCH_0: begin 
                    mul_a_x_reg <= douta; mul_a_y_reg <= doutb; 
                    state <= MA_ST4_LATCH_1; 
                end
                MA_ST4_LATCH_1: begin
                    mul_b_x_reg <= douta; mul_b_y_reg <= douta; au_b_reg <= doutb;    
                    mul_a_start <= 1; mul_b_start <= 1; 
                    state <= MA_ST4_MUL_WAIT_0;
                end
                MA_ST4_MUL_WAIT_0: begin
                    if (mul_a_done && mul_b_done) begin
                        v_reg <= {1'b0, mul_a_result}; au_a_reg <= {1'b0, mul_b_result}; 
                        au_start <= 1; au_op_mode <= 2'b10; 
                        state <= MA_ST4_AU_WAIT_0;
                    end
                end
                MA_ST4_AU_WAIT_0: begin
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= v_reg; au_start <= 1; au_op_mode <= 2'b10; 
                        state <= MA_ST4_AU_WAIT_1;
                    end
                end
                MA_ST4_AU_WAIT_1: begin
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= v_reg; au_start <= 1; au_op_mode <= 2'b10; 
                        state <= MA_ST4_AU_WAIT_2;
                    end
                end
                MA_ST4_AU_WAIT_2: begin
                    if (au_done) begin
                        wea <= 1; addra <= M_T3; dina <= au_result; 
                        au_a_reg <= v_reg; au_b_reg <= au_result; au_start <= 1; au_op_mode <= 2'b10; 
                        state <= MA_ST4_AU_WAIT_3;
                    end
                end
                MA_ST4_AU_WAIT_3: begin
                    if (au_done) begin
                        wea <= 1; addra <= M_T4; dina <= au_result; 
                        state <= MA_ST5_FETCH_0;
                    end
                end

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
                        au_a_reg <= {1'b0, mul_b_result}; au_b_reg <= {1'b0, mul_a_result}; 
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

                MA_FINAL_FETCH_Y: begin addra <= M_T1; state <= MA_FINAL_WAIT_Y1; end
                MA_FINAL_WAIT_Y1: begin state <= MA_FINAL_WAIT_Y2; end
                MA_FINAL_WAIT_Y2: begin state <= MA_FINAL_LATCH_Y; end
                MA_FINAL_LATCH_Y: begin
                    au_a_reg <= douta; au_b_reg <= 256'b0; au_op_mode <= 2'b11; au_start <= 1;
                    state <= MA_FINAL_AU_WAIT_Y1;
                end
                MA_FINAL_AU_WAIT_Y1: begin
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= 256'b0; au_op_mode <= 2'b11; au_start <= 1;
                        state <= MA_FINAL_AU_WAIT_Y2;
                    end
                end
                MA_FINAL_AU_WAIT_Y2: begin if (au_done) begin y3 <= au_result[254:0]; state <= MA_FINAL_FETCH_Z; end end

                MA_FINAL_FETCH_Z: begin addra <= M_T0; state <= MA_FINAL_WAIT_Z1; end
                MA_FINAL_WAIT_Z1: begin state <= MA_FINAL_WAIT_Z2; end
                MA_FINAL_WAIT_Z2: begin state <= MA_FINAL_LATCH_Z; end
                MA_FINAL_LATCH_Z: begin
                    au_a_reg <= douta; au_b_reg <= 256'b0; au_op_mode <= 2'b11; au_start <= 1;
                    state <= MA_FINAL_AU_WAIT_Z1;
                end
                MA_FINAL_AU_WAIT_Z1: begin
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= 256'b0; au_op_mode <= 2'b11; au_start <= 1;
                        state <= MA_FINAL_AU_WAIT_Z2;
                    end
                end
                MA_FINAL_AU_WAIT_Z2: begin if (au_done) begin z3 <= au_result[254:0]; state <= MA_FINAL_FETCH_X; end end

                MA_FINAL_FETCH_X: begin addra <= M_T3; state <= MA_FINAL_WAIT_X1; end
                MA_FINAL_WAIT_X1: begin state <= MA_FINAL_WAIT_X2; end
                MA_FINAL_WAIT_X2: begin state <= MA_FINAL_LATCH_X; end
                MA_FINAL_LATCH_X: begin
                    au_a_reg <= douta; au_b_reg <= 256'b0; au_op_mode <= 2'b11; au_start <= 1;
                    state <= MA_FINAL_AU_WAIT_X1;
                end
                MA_FINAL_AU_WAIT_X1: begin
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= 256'b0; au_op_mode <= 2'b11; au_start <= 1;
                        state <= MA_FINAL_AU_WAIT_X2;
                    end
                end
                MA_FINAL_AU_WAIT_X2: begin if (au_done) begin x3 <= au_result[254:0]; state <= S_DONE; end end

                // =========================================================================
                // [Doubling 경로]
                // =========================================================================
                S_LOAD_DBL_0: begin
                    wea <= 1; addra <= M_T0; dina <= {y1, 1'b0}; 
                    state <= S_LOAD_DBL_1;
                end
                S_LOAD_DBL_1: begin
                    addra <= M_X1; addrb <= M_Y1; 
                    state <= S_1_F;
                end

                S_1_F:  state <= S_1_W1;
                S_1_W1: state <= S_1_W2;
                S_1_W2: state <= S_1_L;
                S_1_L: begin
                    mul_a_x_reg <= douta; mul_a_y_reg <= douta;
                    mul_b_x_reg <= doutb; mul_b_y_reg <= doutb;
                    mul_a_start <= 1; mul_b_start <= 1;
                    addra <= M_T0;
                    state <= S_1A_F;
                end
                S_1A_F:  state <= S_1A_W1;
                S_1A_W1: state <= S_1A_W2;
                S_1A_W2: state <= S_1A_L;
                S_1A_L: begin
                    au_a_reg <= douta; au_b_reg <= 256'b0; au_op_mode <= 2'b11; au_start <= 1;
                    state <= S_1A_D;
                end
                S_1A_D: if (au_done) begin
                    wea <= 1; addra <= M_T0; dina <= au_result;
                    state <= S_1_MW;
                end
                S_1_MW: if (mul_a_done && mul_b_done) begin
                    wea <= 1; addra <= M_T2; dina <= {1'b0, mul_a_result};
                    web <= 1; addrb <= M_T3; dinb <= {1'b0, mul_b_result};
                    state <= S_W1_F;
                end
                S_W1_F:  begin addra <= M_T2; state <= S_W1_W1; end
                S_W1_W1: state <= S_W1_W2;
                S_W1_W2: state <= S_W1_L;
                S_W1_L: begin
                    au_a_reg <= douta; au_b_reg <= douta; au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_W1_D1;
                end
                S_W1_D1: if (au_done) begin
                    au_b_reg <= au_result; au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_W1_D2;
                end
                S_W1_D2: if (au_done) begin
                    wea <= 1; addra <= M_T1; dina <= au_result;
                    state <= S_2_F0;
                end
                S_2_F0: begin addra <= M_X1; addrb <= M_T3; state <= S_2_F1; end
                S_2_F1: begin addra <= M_T1; state <= S_2_WX; end
                S_2_WX: state <= S_2_L0;
                S_2_L0: begin mul_a_x_reg <= douta; mul_a_y_reg <= doutb; state <= S_2_L1; end 
                S_2_L1: begin
                    mul_b_x_reg <= douta; mul_b_y_reg <= douta;
                    mul_a_start <= 1; mul_b_start <= 1;
                    state <= S_2_MW;
                end
                S_2_MW: if (mul_a_done && mul_b_done) begin
                    wea <= 1; addra <= M_T4; dina <= {1'b0, mul_a_result};
                    web <= 1; addrb <= M_T2; dinb <= {1'b0, mul_b_result};
                    state <= S_W2_F;
                end
                S_W2_F:  begin addra <= M_T4; state <= S_W2_W1; end
                S_W2_W1: state <= S_W2_W2;
                S_W2_W2: state <= S_W2_L;
                S_W2_L: begin
                    au_a_reg <= douta; au_b_reg <= douta; au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_W2_D1;
                end
                S_W2_D1: if (au_done) begin
                    au_a_reg <= au_result; au_b_reg <= au_result; au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_W2_D2;
                end
                S_W2_D2: if (au_done) begin
                    wea <= 1; addra <= M_T4; dina <= au_result;
                    au_a_reg <= au_result; au_b_reg <= au_result; au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_W2_D3;
                end
                S_W2_D3: if (au_done) begin au_b_reg <= au_result; addra <= M_T2; state <= S_W2_F2; end
                S_W2_F2: state <= S_W2_W3;
                S_W2_W3: state <= S_W2_W4;
                S_W2_W4: state <= S_W2_L2;
                S_W2_L2: begin
                    au_a_reg <= douta; au_op_mode <= 2'b01; au_start <= 1;
                    state <= S_W2_D4;
                end
                S_W2_D4: if (au_done) begin
                    wea <= 1; addra <= M_T2; dina <= au_result;
                    au_b_reg <= au_result; addrb <= M_T4;
                    state <= S_W2_F3;
                end
                S_W2_F3: state <= S_W2_W5;
                S_W2_W5: state <= S_W2_W6;
                S_W2_W6: state <= S_W2_L3;
                S_W2_L3: begin
                    au_a_reg <= doutb; au_op_mode <= 2'b01; au_start <= 1;
                    state <= S_W2_D5;
                end
                S_W2_D5: if (au_done) begin wea <= 1; addra <= M_T4; dina <= au_result; state <= S_3_F0; end
                S_3_F0: begin addra <= M_T1; addrb <= M_T4; state <= S_3_F1; end
                S_3_F1: begin addra <= M_T3; state <= S_3_WX; end
                S_3_WX: state <= S_3_L0;
                S_3_L0: begin mul_a_x_reg <= douta; mul_a_y_reg <= doutb; state <= S_3_L1; end
                S_3_L1: begin
                    mul_b_x_reg <= douta; mul_b_y_reg <= douta;
                    mul_a_start <= 1; mul_b_start <= 1;
                    addra <= M_T2;
                    state <= S_3A_F;
                end
                S_3A_F:  state <= S_3A_W1;
                S_3A_W1: state <= S_3A_W2;
                S_3A_W2: state <= S_3A_L;
                S_3A_L: begin
                    au_a_reg <= douta; au_b_reg <= 256'b0; au_op_mode <= 2'b11; au_start <= 1;
                    state <= S_3A_D1;
                end
                S_3A_D1: if (au_done) begin
                    au_a_reg <= au_result; au_b_reg <= 256'b0; au_op_mode <= 2'b11; au_start <= 1;
                    state <= S_3A_D2;
                end
                S_3A_D2: if (au_done) begin wea <= 1; addra <= M_T2; dina <= au_result; state <= S_3_MW; end
                S_3_MW: if (mul_a_done && mul_b_done) begin
                    wea <= 1; addra <= M_T1; dina <= {1'b0, mul_a_result};
                    web <= 1; addrb <= M_T3; dinb <= {1'b0, mul_b_result};
                    state <= S_F_F;
                end
                S_F_F:  begin addra <= M_T3; state <= S_F_W1; end
                S_F_W1: state <= S_F_W2;
                S_F_W2: state <= S_F_L;
                S_F_L: begin
                    au_a_reg <= douta; au_b_reg <= douta; au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_F_D1;
                end
                S_F_D1: if (au_done) begin
                    au_a_reg <= au_result; au_b_reg <= au_result; au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_F_D2;
                end
                S_F_D2: if (au_done) begin
                    au_a_reg <= au_result; au_b_reg <= au_result; au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_F_D3;
                end
                S_F_D3: if (au_done) begin au_b_reg <= au_result; addra <= M_T1; state <= S_F_F2; end
                S_F_F2: state <= S_F_W3;
                S_F_W3: state <= S_F_W4;
                S_F_W4: state <= S_F_L2;
                S_F_L2: begin au_a_reg <= douta; au_op_mode <= 2'b01; au_start <= 1; state <= S_F_D4; end
                S_F_D4: if (au_done) begin
                    au_a_reg <= au_result; au_b_reg <= 256'b0; au_op_mode <= 2'b11; au_start <= 1;
                    state <= S_F_D5;
                end
                S_F_D5: if (au_done) begin
                    au_a_reg <= au_result; au_b_reg <= 256'b0; au_op_mode <= 2'b11; au_start <= 1;
                    state <= S_F_D6;
                end
                S_F_D6: if (au_done) begin wea <= 1; addra <= M_T1; dina <= au_result; state <= S_O_F0; end

                S_O_F0: begin addra <= M_T2; addrb <= M_T1; state <= S_O_F1; end
                S_O_F1: begin addra <= M_T0; state <= S_O_WX; end
                S_O_WX: state <= S_O_L0;
                // ? [최종 수정 완료] S_O_L0의 무한 루프 늪을 S_O_L1로 완벽하게 탈출!
                S_O_L0: begin x3 <= douta[254:0]; y3 <= doutb[254:0]; state <= S_O_L1; end 
                S_O_L1: begin z3 <= douta[254:0]; state <= S_DONE; end

                S_DONE: begin
                    done <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule