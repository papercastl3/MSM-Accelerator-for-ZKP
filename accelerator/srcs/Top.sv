`timescale 1ns / 1ps

module Top(
    input  wire          aclk,
    input  wire          aresetn,

    // AXI4-Stream Slave input: point DMA
    input  wire  [511:0] s0_axis_tdata,
    input  wire          s0_axis_tvalid,
    output reg           s0_axis_tready,
    input  wire          s0_axis_tlast,

    // AXI4-Stream Slave input: scalar DMA
    input  wire  [255:0] s1_axis_tdata,
    input  wire          s1_axis_tvalid,
    output reg           s1_axis_tready,
    input  wire          s1_axis_tlast,

    // AXI4-Stream Master output: flush result to DMA
    output reg   [767:0] m_axis_tdata,
    output reg           m_axis_tvalid,
    input  wire          m_axis_tready,
    output reg           m_axis_tlast
);

    // ============================================================
    // Dispatcher control
    // ============================================================

    localparam TOP_RUN_STEP        = 2'd0;
    localparam TOP_WAIT_FLUSH_DONE = 2'd1;

    reg [1:0] top_state;

    reg  dispatch_start;
    wire dispatch_done;

    // ============================================================
    // point_scalar_dispatcher -> pippenger_controller
    // ============================================================

    wire [767:0] ps_data;
    wire         ps_valid;
    wire         ps_ready;
    wire         ps_last;

    wire         s0_axis_tready_w;
    wire         s1_axis_tready_w;

    // ============================================================
    // pippenger_controller -> ecc_adder_controller
    // ============================================================

    wire [768 + 88 - 1:0] pw_data;
    wire                  pw_valid;
    wire                  pw_ready;
    wire                  pw_last;

    wire                  pippenger_stream_done;

    // ============================================================
    // ecc_adder_controller memory interface
    // ============================================================

    wire         ecc_mem_en   [0:3][0:1];
    wire         ecc_mem_we   [0:3][0:1];
    wire [10:0]  ecc_mem_addr [0:3][0:1];
    wire [767:0] ecc_mem_din  [0:3][0:1];
    wire [767:0] ecc_mem_dout [0:3][0:1];

    wire         add_busy;
    wire         add_stream_done;

    // ============================================================
    // flush_controller memory interface
    // ============================================================

    wire         flush_mem_en   [0:3][0:1];
    wire         flush_mem_we   [0:3][0:1];
    wire [10:0]  flush_mem_addr [0:3][0:1];
    wire [767:0] flush_mem_din  [0:3][0:1];
    wire [767:0] flush_mem_dout [0:3][0:1];

    wire         flush_start;
    wire         flush_busy;
    wire         flush_done;

    wire [767:0] m_axis_tdata_w;
    wire         m_axis_tvalid_w;
    wire         m_axis_tlast_w;

    // ============================================================
    // arbiter -> buckets_mem
    // ============================================================

    wire         mem_en   [0:3][0:1];
    wire         mem_we   [0:3][0:1];
    wire [10:0]  mem_addr [0:3][0:1];
    wire [767:0] mem_din  [0:3][0:1];
    wire [767:0] mem_dout [0:3][0:1];

    wire         mem_grant_flush;
    wire         mem_grant_ecc;

    // ============================================================
    // Output reg drive
    // ============================================================

    always @(*) begin
        s0_axis_tready = s0_axis_tready_w;
        s1_axis_tready = s1_axis_tready_w;

        m_axis_tdata   = m_axis_tdata_w;
        m_axis_tvalid  = m_axis_tvalid_w;
        m_axis_tlast   = m_axis_tlast_w;
    end

    // ============================================================
    // Top-level control
    // ============================================================

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            top_state      <= TOP_RUN_STEP;
            dispatch_start <= 1'b0;
        end else begin
            case (top_state)
                TOP_RUN_STEP: begin
                    dispatch_start <= 1'b1;

                    if (dispatch_done) begin
                        dispatch_start <= 1'b0;
                        top_state      <= TOP_WAIT_FLUSH_DONE;
                    end
                end

                TOP_WAIT_FLUSH_DONE: begin
                    dispatch_start <= 1'b0;

                    if (flush_done) begin
                        dispatch_start <= 1'b1;
                        top_state      <= TOP_RUN_STEP;
                    end
                end

                default: begin
                    dispatch_start <= 1'b0;
                    top_state      <= TOP_RUN_STEP;
                end
            endcase
        end
    end

    // ============================================================
    // point_scalar_dispatcher
    // ============================================================

    point_scalar_dispatcher u_point_scalar_dispatcher (
        .clk              (aclk),
        .rst_n            (aresetn),

        .in_point_data    (s0_axis_tdata),
        .in_point_valid   (s0_axis_tvalid),
        .in_point_last    (s0_axis_tlast),
        .in_point_ready   (s0_axis_tready_w),

        .in_scalar_data   (s1_axis_tdata),
        .in_scalar_valid  (s1_axis_tvalid),
        .in_scalar_last   (s1_axis_tlast),
        .in_scalar_ready  (s1_axis_tready_w),

        .out_data         (ps_data),
        .out_valid        (ps_valid),
        .out_last         (ps_last),
        .out_ready        (ps_ready),

        .dispatch_done    (dispatch_done),
        .dispatch_start   (dispatch_start)
    );

    // ============================================================
    // pippenger_controller
    // ============================================================

    pippenger_controller u_pippenger_controller (
        .clk                                  (aclk),
        .rst_n                                (aresetn),

        .in_point_scalar_data                 (ps_data),
        .in_point_scalar_valid                (ps_valid),
        .in_point_scalar_last                 (ps_last),
        .in_point_scalar_ready                (ps_ready),

        .out_point_and_window_slices_data     (pw_data),
        .out_point_and_window_slices_valid    (pw_valid),
        .out_point_and_window_slices_last     (pw_last),
        .out_point_and_window_slices_ready    (pw_ready),

        .flush_done                           (flush_done),
        .stream_done                          (pippenger_stream_done)
    );

    // ============================================================
    // ecc_adder_controller
    // ============================================================

    ecc_adder_controller u_ecc_adder_controller (
        .clk                                  (aclk),
        .rst_n                                (aresetn),

        .out_point_and_window_slices_data     (pw_data),
        .out_point_and_window_slices_valid    (pw_valid),
        .out_point_and_window_slices_ready    (pw_ready),
        .out_point_and_window_slices_last     (pw_last),

        .mem_en                               (ecc_mem_en),
        .mem_we                               (ecc_mem_we),
        .mem_addr                             (ecc_mem_addr),
        .mem_din                              (ecc_mem_din),
        .mem_dout                             (ecc_mem_dout),

        .add_busy                             (add_busy),
        .add_stream_done                      (add_stream_done)
    );

    // ============================================================
    // flush_controller
    // ============================================================

    flush_controller u_flush_controller (
        .clk             (aclk),
        .rst_n           (aresetn),

        .flush_start     (flush_start),
        .flush_busy      (flush_busy),
        .flush_done      (flush_done),

        .mem_en          (flush_mem_en),
        .mem_we          (flush_mem_we),
        .mem_addr        (flush_mem_addr),
        .mem_din         (flush_mem_din),
        .mem_dout        (flush_mem_dout),

        .m_axis_tdata    (m_axis_tdata_w),
        .m_axis_tvalid   (m_axis_tvalid_w),
        .m_axis_tready   (m_axis_tready),
        .m_axis_tlast    (m_axis_tlast_w)
    );

    // ============================================================
    // buckets_mem_arbiter
    // ============================================================

    buckets_mem_arbiter u_buckets_mem_arbiter (
        .clk             (aclk),
        .rst_n           (aresetn),

        .add_stream_done (add_stream_done),
        .flush_busy      (flush_busy),
        .flush_done      (flush_done),

        .flush_start     (flush_start),

        .mem_grant_flush (mem_grant_flush),
        .mem_grant_ecc   (mem_grant_ecc),

        .ecc_mem_en      (ecc_mem_en),
        .ecc_mem_we      (ecc_mem_we),
        .ecc_mem_addr    (ecc_mem_addr),
        .ecc_mem_din     (ecc_mem_din),
        .ecc_mem_dout    (ecc_mem_dout),

        .flush_mem_en    (flush_mem_en),
        .flush_mem_we    (flush_mem_we),
        .flush_mem_addr  (flush_mem_addr),
        .flush_mem_din   (flush_mem_din),
        .flush_mem_dout  (flush_mem_dout),

        .mem_en          (mem_en),
        .mem_we          (mem_we),
        .mem_addr        (mem_addr),
        .mem_din         (mem_din),
        .mem_dout        (mem_dout)
    );

    // ============================================================
    // buckets_mem
    // ============================================================

    buckets_mem u_buckets_mem (
        .clk   (aclk),

        .en    (mem_en),
        .we    (mem_we),
        .addr  (mem_addr),
        .din   (mem_din),
        .dout  (mem_dout)
    );

endmodule