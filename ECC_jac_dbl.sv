`timescale 1ns/1ps

/**
 * Module: point_doubling (BRAM-based version)
 * Jacobian Point Doubling (y^2 = x^3 + b, a=0)
 *
 * Resources:
 *   - Montgomery multiplier x2 (MUL_A, MUL_B)
 *   - AddSub_256 adder/subtractor x1
 *   - True Dual-Port BRAM x1 (16 x 256-bit)
 *
 * BRAM replaces all intermediate 256-bit registers.
 * MUL/Adder input MUX trees removed → fixed register direct connection.
 * Hybrid adder chain: pass add_result directly within chains.
 */
module point_doubling (
    input  logic         clk,
    input  logic         reset,
    input  logic         start,
    input  logic [254:0] X1_in,
    input  logic [254:0] Y1_in,
    input  logic [254:0] Z1_in,
    output logic [254:0] X3_out,
    output logic [254:0] Y3_out,
    output logic [254:0] Z3_out,
    output logic         done
);

    // =========================================================================
    // Memory Map
    // =========================================================================
    localparam M_X1    = 4'd0;
    localparam M_Y1    = 4'd1;
    localparam M_Z1    = 4'd2;
    localparam M_XX    = 4'd3;
    localparam M_YY    = 4'd4;
    localparam M_YYYY  = 4'd5;
    localparam M_2Y1   = 4'd6;
    localparam M_M     = 4'd7;   // 3*XX
    localparam M_SBASE = 4'd8;   // X1*YY
    localparam M_T     = 4'd9;   // M^2
    localparam M_S     = 4'd10;  // 4*X1*YY
    localparam M_X3    = 4'd11;
    localparam M_Y3    = 4'd12;
    localparam M_Z3    = 4'd13;
    localparam M_TEMP  = 4'd14;  // temp/U/Y8 reuse
    localparam M_Y8    = 4'd15;

    // =========================================================================
    // True Dual-Port BRAM
    // =========================================================================
    (* ram_style = "block" *)
    logic [255:0] mem [0:15];
    logic [3:0]   addra, addrb;
    logic [255:0] dina, dinb;
    logic         wea, web;
    logic [255:0] douta, doutb;

    always_ff @(posedge clk) begin
        if (wea) mem[addra] <= dina;
        douta <= mem[addra];
    end
    always_ff @(posedge clk) begin
        if (web) mem[addrb] <= dinb;
        doutb <= mem[addrb];
    end

    // =========================================================================
    // Fixed input registers (no MUX trees)
    // =========================================================================
    logic [255:0] mul_a_x_reg, mul_a_y_reg;
    logic [255:0] mul_b_x_reg, mul_b_y_reg;
    logic [255:0] au_a_reg, au_b_reg;

    // =========================================================================
    // Submodule signals
    // =========================================================================
    logic        mul_a_start, mul_b_start;
    logic [254:0] mul_a_result, mul_b_result;
    logic        mul_a_done, mul_b_done;

    logic        au_start;
    logic [1:0]  au_op;
    logic [255:0] au_result;
    logic        au_done;

    // =========================================================================
    // Submodule Instantiation
    // =========================================================================
    mont_multiplier u_mul_a (
        .clk(clk), .reset(reset), .start(mul_a_start),
        .X(mul_a_x_reg[254:0]), .Y(mul_a_y_reg[254:0]),
        .result(mul_a_result), .done(mul_a_done)
    );

    mont_multiplier u_mul_b (
        .clk(clk), .reset(reset), .start(mul_b_start),
        .X(mul_b_x_reg[254:0]), .Y(mul_b_y_reg[254:0]),
        .result(mul_b_result), .done(mul_b_done)
    );

    AddSub_256 u_adder (
        .clk(clk), .reset(reset), .start(au_start), .op_mode(au_op),
        .A(au_a_reg), .B(au_b_reg), .result(au_result), .done(au_done)
    );

    // =========================================================================
    // FSM
    // =========================================================================
    typedef enum logic [6:0] {
        ST_IDLE,
        ST_LOAD_1, ST_LOAD_2,
        // Slot 1: XX=X1^2, YY=Y1^2
        ST_S1_FETCH, ST_S1_WAIT, ST_S1_LATCH, ST_S1_MUL_WAIT,
        // Slot 2 MUL: Z3=2Y1*Z1, YYYY=YY^2
        ST_S2_FETCH1, ST_S2_FETCH2, ST_S2_LATCH1, ST_S2_LATCH2,
        // Slot 2 Adder (bg): 2XX, M
        ST_S2A_FETCH, ST_S2A_WAIT, ST_S2A_LATCH,
        ST_S2A_W0, ST_S2A_W1,
        ST_S2_MUL_WAIT,
        // Slot 3 MUL: S_base=X1*YY, T=M^2
        ST_S3_FETCH1, ST_S3_FETCH2, ST_S3_LATCH1, ST_S3_LATCH2,
        // Slot 3 Adder (bg): fsub(Z3)
        ST_S3A_FETCH, ST_S3A_WAIT, ST_S3A_LATCH, ST_S3A_WDONE,
        ST_S3_MUL_WAIT,
        // Slot 4 Adder chain: S_2, S, 2S, X3, temp
        ST_S4A_FETCH, ST_S4A_WAIT, ST_S4A_LATCH,
        ST_S4A_W0,    // S_2 = S_base+S_base
        ST_S4A_W1,    // S = S_2+S_2
        ST_S4A_W2,    // 2S = S+S
        ST_S4A_FT, ST_S4A_WT, ST_S4A_LT,  // fetch T
        ST_S4A_W3,    // X3 = T - 2S
        ST_S4A_FS, ST_S4A_WS, ST_S4A_LS,  // fetch S
        ST_S4A_W4,    // temp = S - X3
        // Slot 4 MUL: U=M*temp + BG adder: Y2,Y4,Y8,fsub(X3)x2
        ST_S4M_FETCH1, ST_S4M_FETCH2, ST_S4M_LATCH1, ST_S4M_LATCH2,
        ST_S4BG_FETCH, ST_S4BG_WAIT, ST_S4BG_LATCH,
        ST_S4BG_W0, ST_S4BG_W1, ST_S4BG_W2,  // Y2,Y4,Y8
        ST_S4BG_FX, ST_S4BG_WX, ST_S4BG_LX,  // fetch X3
        ST_S4BG_W3, ST_S4BG_W4,                // fsub(X3)x2
        ST_S4_MUL_WAIT,
        // Final: Y3=U-Y8, fsub(Y3)x2
        ST_F_FETCH, ST_F_WAIT, ST_F_LATCH,
        ST_F_W0, ST_F_W1, ST_F_W2,
        // Output
        ST_OUT1, ST_OUT_WAIT, ST_OUT2, ST_OUT3,
        ST_DONE
    } state_e;

    state_e state;

    // =========================================================================
    // Main FSM
    // =========================================================================
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            done <= 1'b0;
            mul_a_start <= 0; mul_b_start <= 0;
            au_start <= 0;
            wea <= 0; web <= 0;
        end else begin
            mul_a_start <= 0; mul_b_start <= 0;
            au_start <= 0;
            wea <= 0; web <= 0;

            case (state)
                // =============================================================
                // IDLE & LOAD
                // =============================================================
                ST_IDLE: begin
                    done <= 0;
                    if (start) begin
                        // Store X1, Y1 to BRAM
                        wea <= 1; addra <= M_X1; dina <= {1'b0, X1_in};
                        web <= 1; addrb <= M_Y1; dinb <= {1'b0, Y1_in};
                        state <= ST_LOAD_1;
                    end
                end
                ST_LOAD_1: begin
                    // Store Z1, 2Y1
                    wea <= 1; addra <= M_Z1; dina <= {1'b0, Z1_in};
                    web <= 1; addrb <= M_2Y1; dinb <= {Y1_in, 1'b0};
                    state <= ST_LOAD_2;
                end
                ST_LOAD_2: begin
                    state <= ST_S1_FETCH;
                end

                // =============================================================
                // SLOT 1: MUL_A: XX=X1^2, MUL_B: YY=Y1^2
                // =============================================================
                ST_S1_FETCH: begin
                    addra <= M_X1; addrb <= M_Y1;
                    state <= ST_S1_WAIT;
                end
                ST_S1_WAIT: state <= ST_S1_LATCH;
                ST_S1_LATCH: begin
                    mul_a_x_reg <= douta; mul_a_y_reg <= douta;
                    mul_b_x_reg <= doutb; mul_b_y_reg <= doutb;
                    mul_a_start <= 1; mul_b_start <= 1;
                    state <= ST_S1_MUL_WAIT;
                end
                ST_S1_MUL_WAIT: begin
                    if (mul_a_done && mul_b_done) begin
                        wea <= 1; addra <= M_XX; dina <= {1'b0, mul_a_result};
                        web <= 1; addrb <= M_YY; dinb <= {1'b0, mul_b_result};
                        state <= ST_S2_FETCH1;
                    end
                end

                // =============================================================
                // SLOT 2 MUL: Z3=2Y1*Z1, YYYY=YY^2
                // =============================================================
                ST_S2_FETCH1: begin
                    addra <= M_2Y1; addrb <= M_Z1;
                    state <= ST_S2_FETCH2;
                end
                ST_S2_FETCH2: begin
                    addra <= M_YY;
                    state <= ST_S2_LATCH1;
                end
                ST_S2_LATCH1: begin
                    mul_a_x_reg <= douta; mul_a_y_reg <= doutb; // 2Y1, Z1
                    state <= ST_S2_LATCH2;
                end
                ST_S2_LATCH2: begin
                    mul_b_x_reg <= douta; mul_b_y_reg <= douta; // YY, YY
                    mul_a_start <= 1; mul_b_start <= 1;
                    state <= ST_S2A_FETCH;
                end

                // SLOT 2 Adder (bg): 2XX=XX+XX, M=XX+2XX
                ST_S2A_FETCH: begin
                    addra <= M_XX;
                    state <= ST_S2A_WAIT;
                end
                ST_S2A_WAIT: state <= ST_S2A_LATCH;
                ST_S2A_LATCH: begin
                    au_a_reg <= douta; au_b_reg <= douta; // XX, XX
                    au_op <= 2'b00; au_start <= 1;
                    state <= ST_S2A_W0;
                end
                ST_S2A_W0: begin // 2XX = XX+XX done
                    if (au_done) begin
                        // Hybrid: au_a still=XX (latched inside AddSub), set au_b=2XX
                        au_b_reg <= au_result;
                        au_op <= 2'b00; au_start <= 1;
                        state <= ST_S2A_W1;
                    end
                end
                ST_S2A_W1: begin // M = XX+2XX done
                    if (au_done) begin
                        wea <= 1; addra <= M_M; dina <= au_result;
                        state <= ST_S2_MUL_WAIT;
                    end
                end
                ST_S2_MUL_WAIT: begin
                    if (mul_a_done && mul_b_done) begin
                        wea <= 1; addra <= M_Z3; dina <= {1'b0, mul_a_result};
                        web <= 1; addrb <= M_YYYY; dinb <= {1'b0, mul_b_result};
                        state <= ST_S3_FETCH1;
                    end
                end

                // =============================================================
                // SLOT 3 MUL: S_base=X1*YY, T=M^2
                // =============================================================
                ST_S3_FETCH1: begin
                    addra <= M_X1; addrb <= M_YY;
                    state <= ST_S3_FETCH2;
                end
                ST_S3_FETCH2: begin
                    addra <= M_M;
                    state <= ST_S3_LATCH1;
                end
                ST_S3_LATCH1: begin
                    mul_a_x_reg <= douta; mul_a_y_reg <= doutb; // X1, YY
                    state <= ST_S3_LATCH2;
                end
                ST_S3_LATCH2: begin
                    mul_b_x_reg <= douta; mul_b_y_reg <= douta; // M, M
                    mul_a_start <= 1; mul_b_start <= 1;
                    state <= ST_S3A_FETCH;
                end

                // SLOT 3 Adder (bg): final_sub(Z3)
                ST_S3A_FETCH: begin
                    addra <= M_Z3;
                    state <= ST_S3A_WAIT;
                end
                ST_S3A_WAIT: state <= ST_S3A_LATCH;
                ST_S3A_LATCH: begin
                    au_a_reg <= douta; au_b_reg <= '0;
                    au_op <= 2'b11; au_start <= 1;
                    state <= ST_S3A_WDONE;
                end
                ST_S3A_WDONE: begin
                    if (au_done) begin
                        wea <= 1; addra <= M_Z3; dina <= au_result;
                        state <= ST_S3_MUL_WAIT;
                    end
                end
                ST_S3_MUL_WAIT: begin
                    if (mul_a_done && mul_b_done) begin
                        wea <= 1; addra <= M_SBASE; dina <= {1'b0, mul_a_result};
                        web <= 1; addrb <= M_T; dinb <= {1'b0, mul_b_result};
                        state <= ST_S4A_FETCH;
                    end
                end

                // =============================================================
                // SLOT 4 Adder Chain: S_2, S, 2S, X3, temp
                // =============================================================
                // Fetch S_base
                ST_S4A_FETCH: begin
                    addra <= M_SBASE;
                    state <= ST_S4A_WAIT;
                end
                ST_S4A_WAIT: state <= ST_S4A_LATCH;
                ST_S4A_LATCH: begin
                    au_a_reg <= douta; au_b_reg <= douta; // S_base
                    au_op <= 2'b00; au_start <= 1;
                    state <= ST_S4A_W0;
                end
                ST_S4A_W0: begin // S_2 = S_base+S_base
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= au_result;
                        au_op <= 2'b00; au_start <= 1;
                        state <= ST_S4A_W1;
                    end
                end
                ST_S4A_W1: begin // S = S_2+S_2
                    if (au_done) begin
                        // Store S to BRAM for later (step 4: temp=S-X3)
                        wea <= 1; addra <= M_S; dina <= au_result;
                        au_a_reg <= au_result; au_b_reg <= au_result;
                        au_op <= 2'b00; au_start <= 1;
                        state <= ST_S4A_W2;
                    end
                end
                ST_S4A_W2: begin // 2S = S+S
                    if (au_done) begin
                        // Hold 2S in au_b_reg, fetch T from BRAM
                        au_b_reg <= au_result; // save 2S
                        addra <= M_T;
                        state <= ST_S4A_FT;
                    end
                end
                ST_S4A_FT: state <= ST_S4A_WT;
                ST_S4A_WT: state <= ST_S4A_LT;
                ST_S4A_LT: begin
                    au_a_reg <= douta; // T
                    // au_b_reg already = 2S
                    au_op <= 2'b01; au_start <= 1; // lazy sub
                    state <= ST_S4A_W3;
                end
                ST_S4A_W3: begin // X3 = T - 2S
                    if (au_done) begin
                        // Store X3, hold in au_b for step 4
                        wea <= 1; addra <= M_X3; dina <= au_result;
                        au_b_reg <= au_result; // X3
                        // Fetch S for temp = S - X3
                        addrb <= M_S;
                        state <= ST_S4A_FS;
                    end
                end
                ST_S4A_FS: state <= ST_S4A_WS;
                ST_S4A_WS: state <= ST_S4A_LS;
                ST_S4A_LS: begin
                    au_a_reg <= doutb; // S
                    // au_b_reg = X3
                    au_op <= 2'b01; au_start <= 1; // lazy sub
                    state <= ST_S4A_W4;
                end
                ST_S4A_W4: begin // temp = S - X3
                    if (au_done) begin
                        wea <= 1; addra <= M_TEMP; dina <= au_result;
                        state <= ST_S4M_FETCH1;
                    end
                end

                // =============================================================
                // SLOT 4 MUL: U=M*temp + BG Adder: Y2,Y4,Y8,fsub(X3)x2
                // =============================================================
                ST_S4M_FETCH1: begin
                    addra <= M_M; addrb <= M_TEMP;
                    state <= ST_S4M_FETCH2;
                end
                ST_S4M_FETCH2: begin
                    state <= ST_S4M_LATCH1;
                end
                ST_S4M_LATCH1: begin
                    mul_a_x_reg <= douta; mul_a_y_reg <= doutb; // M, temp
                    state <= ST_S4M_LATCH2;
                end
                ST_S4M_LATCH2: begin
                    mul_a_start <= 1;
                    // Start BG adder: fetch YYYY
                    addra <= M_YYYY;
                    state <= ST_S4BG_FETCH;
                end

                // BG Adder: Y2=YYYY+YYYY, Y4=Y2+Y2, Y8=Y4+Y4
                ST_S4BG_FETCH: state <= ST_S4BG_WAIT;
                ST_S4BG_WAIT: state <= ST_S4BG_LATCH;
                ST_S4BG_LATCH: begin
                    au_a_reg <= douta; au_b_reg <= douta; // YYYY
                    au_op <= 2'b00; au_start <= 1;
                    state <= ST_S4BG_W0;
                end
                ST_S4BG_W0: begin // Y2 = YYYY+YYYY
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= au_result;
                        au_op <= 2'b00; au_start <= 1;
                        state <= ST_S4BG_W1;
                    end
                end
                ST_S4BG_W1: begin // Y4 = Y2+Y2
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= au_result;
                        au_op <= 2'b00; au_start <= 1;
                        state <= ST_S4BG_W2;
                    end
                end
                ST_S4BG_W2: begin // Y8 = Y4+Y4
                    if (au_done) begin
                        wea <= 1; addra <= M_Y8; dina <= au_result;
                        // Fetch X3 for fsub
                        addrb <= M_X3;
                        state <= ST_S4BG_FX;
                    end
                end
                ST_S4BG_FX: state <= ST_S4BG_WX;
                ST_S4BG_WX: state <= ST_S4BG_LX;
                ST_S4BG_LX: begin
                    au_a_reg <= doutb; au_b_reg <= '0;
                    au_op <= 2'b11; au_start <= 1;
                    state <= ST_S4BG_W3;
                end
                ST_S4BG_W3: begin // fsub(X3) round 1
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= '0;
                        au_op <= 2'b11; au_start <= 1;
                        state <= ST_S4BG_W4;
                    end
                end
                ST_S4BG_W4: begin // fsub(X3) round 2
                    if (au_done) begin
                        wea <= 1; addra <= M_X3; dina <= au_result;
                        state <= ST_S4_MUL_WAIT;
                    end
                end
                ST_S4_MUL_WAIT: begin
                    if (mul_a_done) begin
                        wea <= 1; addra <= M_TEMP; dina <= {1'b0, mul_a_result}; // U
                        state <= ST_F_FETCH;
                    end
                end

                // =============================================================
                // FINAL: Y3=U-Y8, fsub(Y3)x2
                // =============================================================
                ST_F_FETCH: begin
                    addra <= M_TEMP; addrb <= M_Y8; // U, Y8
                    state <= ST_F_WAIT;
                end
                ST_F_WAIT: state <= ST_F_LATCH;
                ST_F_LATCH: begin
                    au_a_reg <= douta; au_b_reg <= doutb; // U, Y8
                    au_op <= 2'b01; au_start <= 1;
                    state <= ST_F_W0;
                end
                ST_F_W0: begin // Y3 = U - Y8
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= '0;
                        au_op <= 2'b11; au_start <= 1;
                        state <= ST_F_W1;
                    end
                end
                ST_F_W1: begin // fsub(Y3) round 1
                    if (au_done) begin
                        au_a_reg <= au_result; au_b_reg <= '0;
                        au_op <= 2'b11; au_start <= 1;
                        state <= ST_F_W2;
                    end
                end
                ST_F_W2: begin // fsub(Y3) round 2
                    if (au_done) begin
                        wea <= 1; addra <= M_Y3; dina <= au_result;
                        state <= ST_OUT1;
                    end
                end

                // =============================================================
                // OUTPUT
                // =============================================================
                ST_OUT1: begin
                    addra <= M_X3; addrb <= M_Y3;
                    state <= ST_OUT_WAIT;
                end
                ST_OUT_WAIT: begin
                    addra <= M_Z3;
                    state <= ST_OUT2;
                end
                ST_OUT2: begin
                    X3_out <= douta[254:0]; Y3_out <= doutb[254:0];
                    state <= ST_OUT3;
                end
                ST_OUT3: begin
                    Z3_out <= douta[254:0];
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
