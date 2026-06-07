`timescale 1ns / 1ps

module uram_matrix_tdp_4096x792 (
    input  logic         clk,
    
    // --- Port A ---
    input  logic         en_a,
    input  logic         we_a,
    input  logic [11:0]  addr_a,
    input  logic [791:0] din_a,
    output logic [791:0] dout_a,
    
    // --- Port B ---
    input  logic         en_b,
    input  logic         we_b,
    input  logic [11:0]  addr_b,
    input  logic [791:0] din_b,
    output logic [791:0] dout_b
);

    // 4096 * 792 = 3,244,032 bits
    localparam int MEM_DEPTH = 4096;
    localparam int DATA_W    = 792;
    localparam int ADDR_W    = 12;

    xpm_memory_tdpram #(
        .ADDR_WIDTH_A           (ADDR_W),
        .ADDR_WIDTH_B           (ADDR_W),

        .AUTO_SLEEP_TIME        (0),
        .BYTE_WRITE_WIDTH_A     (DATA_W),
        .BYTE_WRITE_WIDTH_B     (DATA_W),

        .CASCADE_HEIGHT         (0),
        .CLOCKING_MODE          ("common_clock"),

        .ECC_MODE               ("no_ecc"),

        .MEMORY_INIT_FILE       ("none"),
        .MEMORY_INIT_PARAM      ("0"),
        .MEMORY_OPTIMIZATION    ("true"),
        .MEMORY_PRIMITIVE       ("ultra"),
        .MEMORY_SIZE            (MEM_DEPTH * DATA_W),

        .MESSAGE_CONTROL        (0),

        .READ_DATA_WIDTH_A      (DATA_W),
        .READ_DATA_WIDTH_B      (DATA_W),

        .READ_LATENCY_A         (3),
        .READ_LATENCY_B         (3),

        .READ_RESET_VALUE_A     ("0"),
        .READ_RESET_VALUE_B     ("0"),

        .RST_MODE_A             ("SYNC"),
        .RST_MODE_B             ("SYNC"),

        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT           (0),
        .USE_MEM_INIT_MMI       (0),

        .WAKEUP_TIME            ("disable_sleep"),

        .WRITE_DATA_WIDTH_A     (DATA_W),
        .WRITE_DATA_WIDTH_B     (DATA_W),

        .WRITE_MODE_A           ("no_change"),
        .WRITE_MODE_B           ("no_change"),

        .WRITE_PROTECT          (1)
    ) u_xpm_uram_tdp (
        // Port A
        .clka           (clk),
        .ena            (en_a),
        .wea            (we_a),
        .addra          (addr_a),
        .dina           (din_a),
        .douta          (dout_a),

        // Port B
        .clkb           (clk),
        .enb            (en_b),
        .web            (we_b),
        .addrb          (addr_b),
        .dinb           (din_b),
        .doutb          (dout_b),

        // Output register clock enable
        .regcea         (1'b1),
        .regceb         (1'b1),

        // Reset
        .rsta           (1'b0),
        .rstb           (1'b0),

        // Sleep
        .sleep          (1'b0),

        // ECC injection unused
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .injectsbiterrb (1'b0),
        .injectdbiterrb (1'b0),

        // ECC status unused
        .sbiterra       (),
        .dbiterra       (),
        .sbiterrb       (),
        .dbiterrb       ()
    );

endmodule