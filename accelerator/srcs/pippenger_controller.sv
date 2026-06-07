`timescale 1ns / 1ps

// little-endian
// msb-padding

module pippenger_controller(
    input  logic         clk,
    input  logic         rst_n,

    // input side
    // from point_scalar_dispatcher
    input  logic [767:0] in_point_scalar_data,
    input  logic         in_point_scalar_valid,
    input  logic         in_point_scalar_last,
    output logic         in_point_scalar_ready,

    // output side
    output logic [768 + 88 - 1:0] out_point_and_window_slices_data,
    output logic         out_point_and_window_slices_valid,
    output logic         out_point_and_window_slices_last,
    input  logic         out_point_and_window_slices_ready,

    // control signals
    input  logic         flush_done,

    // current step stream has been fully sent out
    output logic         stream_done
);

    typedef enum logic [2:0] {
        STEP_1,
        STEP_1_STREAM_DONE,
        STEP_2,
        STEP_2_STREAM_DONE,
        STEP_3,
        STEP_3_STREAM_DONE
    } step_t;

    step_t step;

    logic active_step;
    logic stream_done_state;

    logic input_fire;
    logic output_fire;
    logic last_output_fire;

    logic [255:0] mont_affine_x;
    logic [255:0] mont_affine_y;
    logic [255:0] mont_scalar;

    logic [253:0] scalar;

    logic [255:0] mont_jaco_x;
    logic [255:0] mont_jaco_y;
    logic [255:0] mont_jaco_z;

    logic [87:0] window_slices;

    assign active_step = (step == STEP_1) ||
                         (step == STEP_2) ||
                         (step == STEP_3);

    assign stream_done_state = (step == STEP_1_STREAM_DONE) ||
                               (step == STEP_2_STREAM_DONE) ||
                               (step == STEP_3_STREAM_DONE);

    assign stream_done = stream_done_state;

    // ------------------------------------------------------------
    // Input unpacking
    //
    // in_point_scalar_data:
    // {2'b0, x[253:0], 2'b0, y[253:0], 2'b0, scalar[253:0]}
    // ------------------------------------------------------------
    assign mont_affine_x = in_point_scalar_data[767:512];
    assign mont_affine_y = in_point_scalar_data[511:256];
    assign mont_scalar   = in_point_scalar_data[255:0];

    assign scalar = mont_scalar[253:0];

    // ------------------------------------------------------------
    // Affine Montgomery point -> Jacobian Montgomery point
    // NOTE: This module is assumed to be combinational.
    // ------------------------------------------------------------
    mont_affine_to_mont_jaco u_mont_affine_to_mont_jaco_comb (
        .in_mont_x       (mont_affine_x),
        .in_mont_y       (mont_affine_y),
        .out_mont_jaco_x (mont_jaco_x),
        .out_mont_jaco_y (mont_jaco_y),
        .out_mont_jaco_z (mont_jaco_z)
    );

    // ------------------------------------------------------------
    // Select window slices by step
    // ------------------------------------------------------------
    always_comb begin
        window_slices = '0;

        unique case (step)
            STEP_1: begin
                // 11-bit x 8 = 88-bit
                window_slices = scalar[253:166];
            end

            STEP_2: begin
                // 11-bit x 6 + padded 10-bit x 2 = 88-bit
                window_slices = {
                    scalar[165:100],        // 66-bit = 11-bit x 6
                    {1'b0, scalar[99:90]},  // 10-bit -> 11-bit
                    {1'b0, scalar[89:80]}   // 10-bit -> 11-bit
                };
            end

            STEP_3: begin
                // padded 10-bit x 8 = 88-bit
                window_slices = {
                    {1'b0, scalar[79:70]},
                    {1'b0, scalar[69:60]},
                    {1'b0, scalar[59:50]},
                    {1'b0, scalar[49:40]},
                    {1'b0, scalar[39:30]},
                    {1'b0, scalar[29:20]},
                    {1'b0, scalar[19:10]},
                    {1'b0, scalar[9:0]}
                };
            end

            default: begin
                window_slices = '0;
            end
        endcase
    end

    // ------------------------------------------------------------
    // Handshake
    // ------------------------------------------------------------
    assign in_point_scalar_ready =
        active_step && out_point_and_window_slices_ready;

    assign out_point_and_window_slices_valid =
        active_step && in_point_scalar_valid;

    assign out_point_and_window_slices_last =
        active_step && in_point_scalar_valid && in_point_scalar_last;

    assign input_fire =
        in_point_scalar_valid && in_point_scalar_ready;

    assign output_fire =
        out_point_and_window_slices_valid &&
        out_point_and_window_slices_ready;

    assign last_output_fire =
        output_fire && out_point_and_window_slices_last;

    // ------------------------------------------------------------
    // Output packing
    //
    // {x, y, z, window_slices}
    // {256, 256, 256, 88}
    // ------------------------------------------------------------
    assign out_point_and_window_slices_data = {
        mont_jaco_x,
        mont_jaco_y,
        mont_jaco_z,
        window_slices
    };

    // ------------------------------------------------------------
    // Step FSM
    //
    // stream_done means:
    // current step's last stream beat has been accepted by downstream.
    //
    // It does NOT mean:
    // ECC addition finished or buckets_mem write finished.
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step <= STEP_1;
        end else begin
            unique case (step)
                STEP_1: begin
                    if (last_output_fire)
                        step <= STEP_1_STREAM_DONE;
                end

                STEP_1_STREAM_DONE: begin
                    if (flush_done)
                        step <= STEP_2;
                end

                STEP_2: begin
                    if (last_output_fire)
                        step <= STEP_2_STREAM_DONE;
                end

                STEP_2_STREAM_DONE: begin
                    if (flush_done)
                        step <= STEP_3;
                end

                STEP_3: begin
                    if (last_output_fire)
                        step <= STEP_3_STREAM_DONE;
                end

                STEP_3_STREAM_DONE: begin
                    if (flush_done)
                        step <= STEP_1;
                end

                default: begin
                    step <= STEP_1;
                end
            endcase
        end
    end

endmodule