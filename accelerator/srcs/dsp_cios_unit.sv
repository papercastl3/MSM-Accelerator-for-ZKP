`timescale 1ns/1ps

module dsp_cios_3stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [29:0] x_in,
    input  logic [17:0] y_in,
    input  logic [47:0] t_in,
    output logic [47:0] p_out
);

    logic rst;
    assign rst = ~rst_n;

    logic [47:0] P1;
    logic [47:0] delayed_t_in;

    always_ff @(posedge clk) begin
        if (!rst_n) delayed_t_in <= '0;
        else        delayed_t_in <= t_in;
    end

    DSP48E2 #(
        .AREG(1),
        .BREG(1),
        .MREG(1),
        .PREG(1),
        .CREG(1),
        .USE_MULT("MULTIPLY")
    ) dsp_unit (
        .CLK(clk),

        .A(x_in),
        .B(y_in),
        .C(delayed_t_in),
        .P(P1),

        .OPMODE(9'b11_110_01_01),
        .ALUMODE(4'b0000),

        .CECTRL(1'b1),
        .CEALUMODE(1'b1),
        .CEINMODE(1'b1),
        .CEA1(1'b1),
        .CEA2(1'b1),
        .CEB1(1'b1),
        .CEB2(1'b1),
        .CEM(1'b1),
        .CEC(1'b1),
        .CEP(1'b1),

        .RSTA(rst),
        .RSTB(rst),
        .RSTC(rst),
        .RSTM(rst),
        .RSTP(rst),
        .RSTCTRL(rst),
        .RSTALUMODE(rst),
        .RSTALLCARRYIN(rst),
        .RSTINMODE(rst),

        .INMODE(5'b00000),
        .ACIN('0),
        .BCIN('0),
        .PCIN('0),
        .CARRYIN(1'b0)
    );

    assign p_out = P1;

endmodule

// `timescale 1ns/1ps

// module dsp_cios_3stage (
//     input  logic        clk,
//     input  logic        reset,
//     input  logic [29:0] x_in,       // A port X[j] or N[j]
//     input  logic [17:0] y_in,       // B port Y[i] or M
//     input  logic [47:0] t_in,       // T[j] C port
//     output logic [47:0] p_out    // ���ŵ� T_new[j]
// );

//     logic [47:0] P1; // ��°�� ���� T[]

//     // C ��, A,B�� Ÿ�̹� ���߱� ���� 1Ŭ�� �б� 
//     logic [47:0] delayed_t_in;
//     always_ff @(posedge clk) begin
//         if (reset) delayed_t_in <= '0;
//         else       delayed_t_in <= t_in;
//     end
 
//     DSP48E2 #(
//         .AREG(1), .BREG(1), .MREG(1), .PREG(1), .CREG(1), .USE_MULT("MULTIPLY")
//     ) dsp_unit (
//         .CLK(clk), 
//         .A(x_in), .B(y_in), .C(delayed_t_in), .P(P1), 
//         .OPMODE(9'b11_110_01_01), .ALUMODE(4'b0000), 
//         .CECTRL(1'b1), .CEALUMODE(1'b1), .CEINMODE(1'b1),
//         .CEA1(1'b1), .CEA2(1'b1), .CEB1(1'b1), .CEB2(1'b1), .CEM(1'b1), .CEC(1'b1), .CEP(1'b1),
//         .RSTA(reset), .RSTB(reset), .RSTC(reset), .RSTM(reset), .RSTP(reset), 
//         .RSTCTRL(reset), .RSTALUMODE(reset), .RSTALLCARRYIN(reset), .RSTINMODE(reset),
//         .INMODE(5'b00000), .ACIN('0), .BCIN('0), .PCIN('0), .CARRYIN(1'b0)
//     );
//     // ��� ���� 
//     assign p_out = P1;

// endmodule