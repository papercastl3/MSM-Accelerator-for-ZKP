`timescale 1ns / 1ps

module ecc_adder_controller (
    input  logic         clk,
    input  logic         rst_n,

    // ------------------------------------------------------------
    // input side
    // from pippenger_controller
    //
    // out_point_and_window_slices_data:
    // {x, y, z, window_slices}
    // {256, 256, 256, 88}
    // ------------------------------------------------------------
    input  logic [768 + 88 - 1:0] out_point_and_window_slices_data,
    input  logic                  out_point_and_window_slices_valid,
    output logic                  out_point_and_window_slices_ready,
    input  logic                  out_point_and_window_slices_last,

    // ------------------------------------------------------------
    // to buckets_mem
    // 4 matrices x 2 logical banks = 8 banks
    // address range: 0 ~ 2047
    // ------------------------------------------------------------
    output logic                  mem_en   [4][2],
    output logic                  mem_we   [4][2],
    output logic [10:0]           mem_addr [4][2],
    output logic [767:0]          mem_din  [4][2],
    input  logic [767:0]          mem_dout [4][2],

    // ------------------------------------------------------------
    // status
    // ------------------------------------------------------------
    output logic                  add_busy,
    output logic                  add_stream_done
);

    localparam int MEM_READ_LATENCY = 4;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_READ_BUCKET,
        ST_WAIT_READ,
        ST_START_ADD,
        ST_WAIT_ADD,
        ST_WRITE_BUCKET,
        ST_WRITE_COMMIT,
        ST_DONE_PULSE
    } state_t;

    state_t state;

    logic input_fire;

    logic [255:0] in_x_256;
    logic [255:0] in_y_256;
    logic [255:0] in_z_256;
    logic [87:0]  in_window_slices;

    logic [254:0] x1[8];
    logic [254:0] y1[8];
    logic [254:0] z1[8];

    logic [254:0] x2[8];
    logic [254:0] y2[8];
    logic [254:0] z2[8];

    logic [767:0] add_result[8];

    logic [10:0] bucket_addr[8];
    logic [10:0] bucket_addr_q[8];

    logic current_last_q;

    logic ecc_start;
    logic ecc_all_done;

    logic [2:0] read_wait_cnt;

    // ------------------------------------------------------------
    // Registered memory outputs
    // ------------------------------------------------------------
    logic                  mem_en_r   [4][2];
    logic                  mem_we_r   [4][2];
    logic [10:0]           mem_addr_r [4][2];
    logic [767:0]          mem_din_r  [4][2];

    always_comb begin
        for (int m = 0; m < 4; m++) begin
            for (int p = 0; p < 2; p++) begin
                mem_en[m][p]   = mem_en_r[m][p];
                mem_we[m][p]   = mem_we_r[m][p];
                mem_addr[m][p] = mem_addr_r[m][p];
                mem_din[m][p]  = mem_din_r[m][p];
            end
        end
    end

    // ------------------------------------------------------------
    // Handshake
    // ------------------------------------------------------------
    assign out_point_and_window_slices_ready = (state == ST_IDLE);

    assign input_fire =
        out_point_and_window_slices_valid &&
        out_point_and_window_slices_ready;

    assign add_busy = (state != ST_IDLE);

    assign add_stream_done = (state == ST_DONE_PULSE);

    // ------------------------------------------------------------
    // Unpack pippenger_controller output
    //
    // {x, y, z, window_slices}
    // {256, 256, 256, 88}
    // ------------------------------------------------------------
    assign in_x_256         = out_point_and_window_slices_data[855:600];
    assign in_y_256         = out_point_and_window_slices_data[599:344];
    assign in_z_256         = out_point_and_window_slices_data[343:88];
    assign in_window_slices = out_point_and_window_slices_data[87:0];

    // ------------------------------------------------------------
    // window_slices -> bucket addresses
    //
    // bucket_addr[0] = window_slices[87:77]
    // bucket_addr[1] = window_slices[76:66]
    // ...
    // bucket_addr[7] = window_slices[10:0]
    // ------------------------------------------------------------
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            bucket_addr[i] = in_window_slices[87 - (i * 11) -: 11];
        end
    end

    // ------------------------------------------------------------
    // ecc_adder_8x instance
    // ------------------------------------------------------------
    assign ecc_start = (state == ST_START_ADD);

    ecc_adder_8x u_ecc_adder_8x (
        .clk        (clk),
        .rst_n      (rst_n),

        .start      (ecc_start),

        .x1         (x1),
        .y1         (y1),
        .z1         (z1),

        .x2         (x2),
        .y2         (y2),
        .z2         (z2),

        .jaco_point (add_result),
        .all_done   (ecc_all_done)
    );

    // ------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            current_last_q <= 1'b0;
            read_wait_cnt  <= 3'd0;

            for (int i = 0; i < 8; i++) begin
                x1[i]            <= 255'd0;
                y1[i]            <= 255'd0;
                z1[i]            <= 255'd0;

                x2[i]            <= 255'd0;
                y2[i]            <= 255'd0;
                z2[i]            <= 255'd0;

                bucket_addr_q[i] <= 11'd0;
            end

            for (int m = 0; m < 4; m++) begin
                for (int p = 0; p < 2; p++) begin
                    mem_en_r[m][p]   <= 1'b0;
                    mem_we_r[m][p]   <= 1'b0;
                    mem_addr_r[m][p] <= 11'd0;
                    mem_din_r[m][p]  <= 768'd0;
                end
            end
        end else begin
            // default: memory command inactive
            for (int m = 0; m < 4; m++) begin
                for (int p = 0; p < 2; p++) begin
                    mem_en_r[m][p]   <= 1'b0;
                    mem_we_r[m][p]   <= 1'b0;
                    mem_addr_r[m][p] <= 11'd0;
                    mem_din_r[m][p]  <= 768'd0;
                end
            end

            unique case (state)
                ST_IDLE: begin
                    read_wait_cnt <= 3'd0;

                    if (input_fire) begin
                        current_last_q <= out_point_and_window_slices_last;

                        for (int i = 0; i < 8; i++) begin
                            // point1 = pippenger output point
                            //
                            // pippenger point coordinate format:
                            // 256-bit = {1'b0, 255-bit}
                            //
                            // ECC_point_adder input:
                            // 255-bit
                            x1[i] <= in_x_256[254:0];
                            y1[i] <= in_y_256[254:0];
                            z1[i] <= in_z_256[254:0];

                            bucket_addr_q[i] <= bucket_addr[i];
                        end

                        state <= ST_READ_BUCKET;
                    end
                end

                // Register read command.
                // The actual URAM sees this command on the next clock edge.
                ST_READ_BUCKET: begin
                    for (int i = 0; i < 8; i++) begin
                        mem_en_r[i >> 1][i & 1]   <= 1'b1;
                        mem_we_r[i >> 1][i & 1]   <= 1'b0;
                        mem_addr_r[i >> 1][i & 1] <= bucket_addr_q[i];
                        mem_din_r[i >> 1][i & 1]  <= 768'd0;
                    end

                    read_wait_cnt <= 3'd0;
                    state         <= ST_WAIT_READ;
                end

                // MEM_READ_LATENCY = 4 because memory command outputs are registered.
                ST_WAIT_READ: begin
                    if (read_wait_cnt == MEM_READ_LATENCY - 1) begin
                        for (int i = 0; i < 8; i++) begin
                            // mem_dout 768-bit format:
                            // {x, y, z}
                            // {256, 256, 256}
                            //
                            // ECC_point_adder input uses lower 255-bit of each coordinate.
                            x2[i] <= mem_dout[i >> 1][i & 1][766:512];
                            y2[i] <= mem_dout[i >> 1][i & 1][510:256];
                            z2[i] <= mem_dout[i >> 1][i & 1][254:0];
                        end

                        read_wait_cnt <= 3'd0;
                        state         <= ST_START_ADD;
                    end else begin
                        read_wait_cnt <= read_wait_cnt + 3'd1;
                    end
                end

                // 1-cycle start pulse for ecc_adder_8x
                ST_START_ADD: begin
                    state <= ST_WAIT_ADD;
                end

                // Wait until all 8 ECC additions finish
                ST_WAIT_ADD: begin
                    if (ecc_all_done) begin
                        state <= ST_WRITE_BUCKET;
                    end
                end

                // Register write command.
                // The actual URAM write happens on the next clock edge.
                ST_WRITE_BUCKET: begin
                    for (int i = 0; i < 8; i++) begin
                        mem_en_r[i >> 1][i & 1]   <= 1'b1;
                        mem_we_r[i >> 1][i & 1]   <= 1'b1;
                        mem_addr_r[i >> 1][i & 1] <= bucket_addr_q[i];
                        mem_din_r[i >> 1][i & 1]  <= add_result[i];
                    end

                    state <= ST_WRITE_COMMIT;
                end

                // Wait one cycle so the registered write command is sampled by URAM.
                ST_WRITE_COMMIT: begin
                    if (current_last_q) begin
                        state <= ST_DONE_PULSE;
                    end else begin
                        state <= ST_IDLE;
                    end
                end

                // 1-cycle pulse:
                // all pippenger stream inputs have been consumed,
                // and the last input's bucket write-back is complete.
                ST_DONE_PULSE: begin
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule