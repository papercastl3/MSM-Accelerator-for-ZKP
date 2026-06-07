`timescale 1ns / 1ps

module point_scalar_dispatcher(
    input  logic         clk,
    input  logic         rst_n,

    // from dma0
    input  logic [511:0] in_point_data,
    input  logic         in_point_valid,
    input  logic         in_point_last,
    output logic         in_point_ready,

    // from dma1
    input  logic [255:0] in_scalar_data,
    input  logic         in_scalar_valid,
    input  logic         in_scalar_last,
    output logic         in_scalar_ready,

    // output side
    output logic [767:0] out_data,
    output logic         out_valid,
    output logic         out_last,
    input  logic         out_ready,

    // control signals
    output logic         dispatch_done,
    input  logic         dispatch_start
);

    typedef enum logic [1:0] {
        IDLE,
        DISPATCHING,
        DONE
    } state_t;

    state_t state;

    logic [768:0] fifo_in_bundle;
    logic [768:0] fifo_out_bundle;

    logic fifo_in_ready;
    logic fifo_out_valid;

    logic pair_valid;
    logic pair_last;
    logic pair_fire;

    logic output_fire;
    logic last_output_fire;

    assign pair_valid = (state == DISPATCHING) &&
                        in_point_valid &&
                        in_scalar_valid;

    assign pair_last = in_point_last && in_scalar_last;

    assign fifo_in_bundle = {in_point_data, in_scalar_data, pair_last};

    assign pair_fire = pair_valid && fifo_in_ready;

    assign in_point_ready = (state == DISPATCHING) &&
                            fifo_in_ready &&
                            in_scalar_valid;

    assign in_scalar_ready = (state == DISPATCHING) &&
                             fifo_in_ready &&
                             in_point_valid;

    assign {out_data, out_last} = fifo_out_bundle;
    assign out_valid = fifo_out_valid;

    assign output_fire = out_valid && out_ready;
    assign last_output_fire = output_fire && out_last;

    assign dispatch_done = (state == DONE);

    shift_fifo #(
        .WIDTH(769),
        .DEPTH(4)
    ) u_shift_fifo_4x769 (
        .clk       (clk),
        .rst_n     (rst_n),

        .in_data   (fifo_in_bundle),
        .in_valid  (pair_valid),
        .in_ready  (fifo_in_ready),

        .out_data  (fifo_out_bundle),
        .out_valid (fifo_out_valid),
        .out_ready (out_ready)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            unique case (state)
                IDLE: begin
                    if (dispatch_start)
                        state <= DISPATCHING;
                end

                DISPATCHING: begin
                    if (last_output_fire)
                        state <= DONE;
                end

                DONE: begin
                    if (!dispatch_start)
                        state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule