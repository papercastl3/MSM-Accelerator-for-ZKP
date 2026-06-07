`timescale 1ns / 1ps


module mont_affine_to_mont_jaco(
    input logic [255:0] in_mont_x,
    input logic [255:0] in_mont_y,
    
    output logic [255:0] out_mont_jaco_x,
    output logic [255:0] out_mont_jaco_y,
    output logic [255:0] out_mont_jaco_z
    );
    // R mod p(base field), this value is 254-bit, {2'b0, 254-bit value} is stored in 256-bit variable
    localparam logic [255:0] MONT_ONE = 256'h1f37631a3d9cbfac8f5f7492fcfd4f44d0fd2add2f1c6ae587bee7d24f060572;

    always_comb begin
        out_mont_jaco_x = in_mont_x;
        out_mont_jaco_y = in_mont_y;
        out_mont_jaco_z = MONT_ONE;
    end
endmodule
