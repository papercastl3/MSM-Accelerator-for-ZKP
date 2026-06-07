`timescale 1ns / 1ps

module buckets_mem (
    input  logic         clk,

    // 4 URAM matrices x 2 logical banks = 8 banks
    // Each logical bank exposes only 2048-depth address space.
    input  logic         en    [4][2],
    input  logic         we    [4][2],
    input  logic [10:0]  addr  [4][2],
    input  logic [767:0] din   [4][2],
    output logic [767:0] dout  [4][2]
);

    logic [11:0]  real_addr [4][2];

    logic [791:0] uram_din  [4][2];
    logic [791:0] uram_dout [4][2];

    genvar i;

    generate
        for (i = 0; i < 4; i++) begin : uram_matrixs

            // Logical bank [i][0] -> physical address 0 ~ 2047
            assign real_addr[i][0] = {1'b0, addr[i][0]};

            // Logical bank [i][1] -> physical address 2048 ~ 4095
            assign real_addr[i][1] = {1'b1, addr[i][1]};

            // 768-bit data -> 792-bit URAM word
            // Upper 24 bits are zero padding.
            assign uram_din[i][0] = {24'b0, din[i][0]};
            assign uram_din[i][1] = {24'b0, din[i][1]};

            // 792-bit URAM word -> 768-bit data
            // Ignore upper 24 padding bits.
            assign dout[i][0] = uram_dout[i][0][767:0];
            assign dout[i][1] = uram_dout[i][1][767:0];

            uram_matrix_tdp_4096x792 u_uram_matrix_tdp_4096x792 (
                .clk    (clk),

                // Port A = logical bank [i][0]
                .en_a   (en        [i][0]),
                .we_a   (we        [i][0]),
                .addr_a (real_addr [i][0]),
                .din_a  (uram_din  [i][0]),
                .dout_a (uram_dout [i][0]),

                // Port B = logical bank [i][1]
                .en_b   (en        [i][1]),
                .we_b   (we        [i][1]),
                .addr_b (real_addr [i][1]),
                .din_b  (uram_din  [i][1]),
                .dout_b (uram_dout [i][1])
            );

        end
    endgenerate

endmodule