`timescale 1ns/1ps
module point_doubling_z1 (
    input  logic         clk,
    input  logic         reset,
    input  logic         start,
    input  logic [254:0] x1,
    input  logic [254:0] y1,
    output logic [254:0] x3,
    output logic [254:0] y3,
    output logic [254:0] z3,
    output logic         done
);
    localparam M_X1 = 4'd0, M_Y1 = 4'd1;
    localparam M_T0 = 4'd2, M_T1 = 4'd3, M_T2 = 4'd4;
    localparam M_T3 = 4'd5, M_T4 = 4'd6;

    (* ram_style = "block" *)
    logic [255:0] mem [0:7];
    logic [255:0] douta_reg, doutb_reg;
    logic [3:0]   addra, addrb;
    logic [255:0] dina, dinb;
    logic         wea, web;
    logic [255:0] douta, doutb;

    always_ff @(posedge clk) begin
        if (wea) mem[addra] <= dina;
        douta_reg <= mem[addra];
        douta     <= douta_reg;
    end
    always_ff @(posedge clk) begin
        if (web) mem[addrb] <= dinb;
        doutb_reg <= mem[addrb];
        doutb     <= doutb_reg;
    end

    logic [255:0] mul_a_x_reg, mul_a_y_reg;
    logic [255:0] mul_b_x_reg, mul_b_y_reg;
    logic [255:0] au_a_reg, au_b_reg;
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

    typedef enum logic [6:0] {
        S_IDLE, S_LOAD_0, S_LOAD_1,
        S_1_F, S_1_W1, S_1_W2, S_1_L,
        S_1A_F, S_1A_W1, S_1A_W2, S_1A_L, S_1A_D,
        S_1_MW,
        S_W1_F, S_W1_W1, S_W1_W2, S_W1_L, S_W1_D1, S_W1_D2,
        S_2_F0, S_2_F1, S_2_WX, S_2_L0, S_2_L1,
        S_2_MW,
        S_W2_F, S_W2_W1, S_W2_W2, S_W2_L,
        S_W2_D1, S_W2_D2, S_W2_D3,
        S_W2_F2, S_W2_W3, S_W2_W4, S_W2_L2,
        S_W2_D4,
        S_W2_F3, S_W2_W5, S_W2_W6, S_W2_L3,
        S_W2_D5,
        S_3_F0, S_3_F1, S_3_WX, S_3_L0, S_3_L1,
        S_3A_F, S_3A_W1, S_3A_W2, S_3A_L, S_3A_D1, S_3A_D2,
        S_3_MW,
        S_F_F, S_F_W1, S_F_W2, S_F_L,
        S_F_D1, S_F_D2, S_F_D3,
        S_F_F2, S_F_W3, S_F_W4, S_F_L2,
        S_F_D4, S_F_D5, S_F_D6,
        S_O_F0, S_O_F1, S_O_WX, S_O_L0, S_O_L1
    } state_e;
    state_e state;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE; done <= 1'b0;
            mul_a_start <= 0; mul_b_start <= 0; au_start <= 0;
            wea <= 0; web <= 0;
            x3 <= '0; y3 <= '0; z3 <= '0;
        end else begin
            mul_a_start <= 0; mul_b_start <= 0; au_start <= 0;
            wea <= 0; web <= 0;
            case (state)
                // === IDLE & LOAD ===
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        if (y1 == '0) begin
                            x3 <= 255'd1; y3 <= 255'd1; z3 <= 255'd0;
                            done <= 1'b1;
                        end else begin
                            wea <= 1; addra <= M_X1; dina <= {1'b0, x1};
                            web <= 1; addrb <= M_Y1; dinb <= {1'b0, y1};
                            state <= S_LOAD_0;
                        end
                    end
                end
                S_LOAD_0: begin
                    wea <= 1; addra <= M_T0; dina <= {y1, 1'b0};
                    state <= S_LOAD_1;
                end
                S_LOAD_1: begin
                    addra <= M_X1; addrb <= M_Y1;
                    state <= S_1_F;
                end

                // === SLOT 1: mul_a:XX=X1², mul_b:YY=Y1² ===
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

                // BG: final_sub(Z3=2Y1)
                S_1A_F:  state <= S_1A_W1;
                S_1A_W1: state <= S_1A_W2;
                S_1A_W2: state <= S_1A_L;
                S_1A_L: begin
                    au_a_reg <= douta; au_b_reg <= 256'b0;
                    au_op_mode <= 2'b11; au_start <= 1;
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

                // === WAIT 1: M=3XX ===
                S_W1_F:  begin addra <= M_T2; state <= S_W1_W1; end
                S_W1_W1: state <= S_W1_W2;
                S_W1_W2: state <= S_W1_L;
                S_W1_L: begin
                    au_a_reg <= douta; au_b_reg <= douta;
                    au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_W1_D1;
                end
                S_W1_D1: if (au_done) begin
                    au_b_reg <= au_result;
                    au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_W1_D2;
                end
                S_W1_D2: if (au_done) begin
                    wea <= 1; addra <= M_T1; dina <= au_result;
                    state <= S_2_F0;
                end

                // === SLOT 2: mul_a:S_base=X1*YY, mul_b:T=M² (interleaved) ===
                S_2_F0: begin addra <= M_X1; addrb <= M_T3; state <= S_2_F1; end
                S_2_F1: begin addra <= M_T1; state <= S_2_WX; end
                S_2_WX: state <= S_2_L0;
                S_2_L0: begin
                    mul_a_x_reg <= douta; mul_a_y_reg <= doutb;
                    state <= S_2_L1;
                end
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

                // === WAIT 2: adder chain ===
                S_W2_F:  begin addra <= M_T4; state <= S_W2_W1; end
                S_W2_W1: state <= S_W2_W2;
                S_W2_W2: state <= S_W2_L;
                S_W2_L: begin
                    au_a_reg <= douta; au_b_reg <= douta;
                    au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_W2_D1;
                end
                S_W2_D1: if (au_done) begin
                    au_a_reg <= au_result; au_b_reg <= au_result;
                    au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_W2_D2;
                end
                S_W2_D2: if (au_done) begin
                    wea <= 1; addra <= M_T4; dina <= au_result;
                    au_a_reg <= au_result; au_b_reg <= au_result;
                    au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_W2_D3;
                end
                S_W2_D3: if (au_done) begin
                    au_b_reg <= au_result;
                    addra <= M_T2;
                    state <= S_W2_F2;
                end

                // fetch T, compute X3=T-2S
                S_W2_F2: state <= S_W2_W3;
                S_W2_W3: state <= S_W2_W4;
                S_W2_W4: state <= S_W2_L2;
                S_W2_L2: begin
                    au_a_reg <= douta;
                    au_op_mode <= 2'b01; au_start <= 1;
                    state <= S_W2_D4;
                end
                S_W2_D4: if (au_done) begin
                    wea <= 1; addra <= M_T2; dina <= au_result;
                    au_b_reg <= au_result;
                    addrb <= M_T4;
                    state <= S_W2_F3;
                end

                // fetch S, compute temp=S-X3
                S_W2_F3: state <= S_W2_W5;
                S_W2_W5: state <= S_W2_W6;
                S_W2_W6: state <= S_W2_L3;
                S_W2_L3: begin
                    au_a_reg <= doutb;
                    au_op_mode <= 2'b01; au_start <= 1;
                    state <= S_W2_D5;
                end
                S_W2_D5: if (au_done) begin
                    wea <= 1; addra <= M_T4; dina <= au_result;
                    state <= S_3_F0;
                end

                // === SLOT 3: mul_a:U=M*temp, mul_b:YYYY=YY² (interleaved) ===
                S_3_F0: begin addra <= M_T1; addrb <= M_T4; state <= S_3_F1; end
                S_3_F1: begin addra <= M_T3; state <= S_3_WX; end
                S_3_WX: state <= S_3_L0;
                S_3_L0: begin
                    mul_a_x_reg <= douta; mul_a_y_reg <= doutb;
                    state <= S_3_L1;
                end
                S_3_L1: begin
                    mul_b_x_reg <= douta; mul_b_y_reg <= douta;
                    mul_a_start <= 1; mul_b_start <= 1;
                    addra <= M_T2;
                    state <= S_3A_F;
                end

                // BG: fsub(X3) x2
                S_3A_F:  state <= S_3A_W1;
                S_3A_W1: state <= S_3A_W2;
                S_3A_W2: state <= S_3A_L;
                S_3A_L: begin
                    au_a_reg <= douta; au_b_reg <= 256'b0;
                    au_op_mode <= 2'b11; au_start <= 1;
                    state <= S_3A_D1;
                end
                S_3A_D1: if (au_done) begin
                    au_a_reg <= au_result; au_b_reg <= 256'b0;
                    au_op_mode <= 2'b11; au_start <= 1;
                    state <= S_3A_D2;
                end
                S_3A_D2: if (au_done) begin
                    wea <= 1; addra <= M_T2; dina <= au_result;
                    state <= S_3_MW;
                end

                S_3_MW: if (mul_a_done && mul_b_done) begin
                    wea <= 1; addra <= M_T1; dina <= {1'b0, mul_a_result};
                    web <= 1; addrb <= M_T3; dinb <= {1'b0, mul_b_result};
                    state <= S_F_F;
                end

                // === FINAL: Y2,Y4,Y8, Y3=U-Y8, fsub(Y3)x2 ===
                S_F_F:  begin addra <= M_T3; state <= S_F_W1; end
                S_F_W1: state <= S_F_W2;
                S_F_W2: state <= S_F_L;
                S_F_L: begin
                    au_a_reg <= douta; au_b_reg <= douta;
                    au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_F_D1;
                end
                S_F_D1: if (au_done) begin
                    au_a_reg <= au_result; au_b_reg <= au_result;
                    au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_F_D2;
                end
                S_F_D2: if (au_done) begin
                    au_a_reg <= au_result; au_b_reg <= au_result;
                    au_op_mode <= 2'b00; au_start <= 1;
                    state <= S_F_D3;
                end
                S_F_D3: if (au_done) begin
                    au_b_reg <= au_result;
                    addra <= M_T1;
                    state <= S_F_F2;
                end

                // fetch U, compute Y3=U-Y8
                S_F_F2: state <= S_F_W3;
                S_F_W3: state <= S_F_W4;
                S_F_W4: state <= S_F_L2;
                S_F_L2: begin
                    au_a_reg <= douta;
                    au_op_mode <= 2'b01; au_start <= 1;
                    state <= S_F_D4;
                end
                S_F_D4: if (au_done) begin
                    au_a_reg <= au_result; au_b_reg <= 256'b0;
                    au_op_mode <= 2'b11; au_start <= 1;
                    state <= S_F_D5;
                end
                S_F_D5: if (au_done) begin
                    au_a_reg <= au_result; au_b_reg <= 256'b0;
                    au_op_mode <= 2'b11; au_start <= 1;
                    state <= S_F_D6;
                end
                S_F_D6: if (au_done) begin
                    wea <= 1; addra <= M_T1; dina <= au_result;
                    state <= S_O_F0;
                end

                // === OUTPUT (interleaved) ===
                S_O_F0: begin addra <= M_T2; addrb <= M_T1; state <= S_O_F1; end
                S_O_F1: begin addra <= M_T0; state <= S_O_WX; end
                S_O_WX: state <= S_O_L0;
                S_O_L0: begin
                    x3 <= douta[254:0]; y3 <= doutb[254:0];
                    state <= S_O_L1;
                end
                S_O_L1: begin
                    z3 <= douta[254:0];
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
