`timescale 1ns / 1ps

module ecc_adder_8x(
    input  logic         clk,
    input  logic         rst_n,

    input  logic         start,

    input  logic [254:0] x1[8],
    input  logic [254:0] y1[8],
    input  logic [254:0] z1[8],

    input  logic [254:0] x2[8],
    input  logic [254:0] y2[8],
    input  logic [254:0] z2[8],

    output logic [767:0] jaco_point[8],
    output logic         all_done
);

    logic [7:0] done_each_pulse;
    logic [7:0] done_each;
    logic [7:0] done_each_next;

    // Raw outputs from each ECC_point_adder
    logic [254:0] x3[8];
    logic [254:0] y3[8];
    logic [254:0] z3[8];

    // Captured outputs
    logic [254:0] x3_hold[8];
    logic [254:0] y3_hold[8];
    logic [254:0] z3_hold[8];

    // ------------------------------------------------------------
    // Local input registers
    //
    // Purpose:
    // Break long routing path:
    // ecc_adder_controller regs -> ECC_point_adder internal input regs
    //
    // New path:
    // ecc_adder_controller regs -> local regs
    // local regs -> ECC_point_adder internal regs
    //
    // ECC_point_adder start is delayed by 1 cycle so that local inputs
    // are already stable when each adder captures them.
    // ------------------------------------------------------------
    logic [254:0] x1_local[8];
    logic [254:0] y1_local[8];
    logic [254:0] z1_local[8];

    logic [254:0] x2_local[8];
    logic [254:0] y2_local[8];
    logic [254:0] z2_local[8];

    logic start_q;
    logic start_pulse;

    assign start_pulse = start_q;

    // ------------------------------------------------------------
    // Input capture + start delay
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_q <= 1'b0;

            for (int i = 0; i < 8; i++) begin
                x1_local[i] <= 255'd0;
                y1_local[i] <= 255'd0;
                z1_local[i] <= 255'd0;

                x2_local[i] <= 255'd0;
                y2_local[i] <= 255'd0;
                z2_local[i] <= 255'd0;
            end
        end else begin
            start_q <= start;

            if (start) begin
                for (int i = 0; i < 8; i++) begin
                    x1_local[i] <= x1[i];
                    y1_local[i] <= y1[i];
                    z1_local[i] <= z1[i];

                    x2_local[i] <= x2[i];
                    y2_local[i] <= y2[i];
                    z2_local[i] <= z2[i];
                end
            end
        end
    end

    // ------------------------------------------------------------
    // 8 parallel ECC adders
    // ------------------------------------------------------------
    genvar gi;
    generate
        for (gi = 0; gi < 8; gi++) begin : ecc_adders
            ECC_point_adder u_ECC_point_adder (
                .clk   (clk),
                .rst_n (rst_n),

                .start (start_pulse),

                .x1    (x1_local[gi]),
                .y1    (y1_local[gi]),
                .z1    (z1_local[gi]),

                .x2    (x2_local[gi]),
                .y2    (y2_local[gi]),
                .z2    (z2_local[gi]),

                .x3    (x3[gi]),
                .y3    (y3[gi]),
                .z3    (z3[gi]),

                .done  (done_each_pulse[gi])
            );
        end
    endgenerate

    // ------------------------------------------------------------
    // Done accumulation
    //
    // start_pulse is the actual start given to ECC_point_adder.
    // Therefore done_each must be cleared on start_pulse, not raw start.
    // ------------------------------------------------------------
    assign done_each_next = start_pulse ? 8'b0 :
                            (done_each | done_each_pulse);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_each <= 8'b0;
        end else begin
            done_each <= done_each_next;
        end
    end

    assign all_done = &done_each_next;

    // ------------------------------------------------------------
    // Capture each adder result when its done pulse arrives
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 8; i++) begin
                x3_hold[i] <= 255'd0;
                y3_hold[i] <= 255'd0;
                z3_hold[i] <= 255'd0;
            end
        end else begin
            for (int i = 0; i < 8; i++) begin
                if (done_each_pulse[i]) begin
                    x3_hold[i] <= x3[i];
                    y3_hold[i] <= y3[i];
                    z3_hold[i] <= z3[i];
                end
            end
        end
    end

    // ------------------------------------------------------------
    // Output packing
    //
    // jaco_point[i] = {x, y, z}
    // each coordinate is 256-bit aligned:
    // {1'b0, 255-bit value}
    // ------------------------------------------------------------
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            jaco_point[i] = {
                1'b0, x3_hold[i],
                1'b0, y3_hold[i],
                1'b0, z3_hold[i]
            };
        end
    end

endmodule