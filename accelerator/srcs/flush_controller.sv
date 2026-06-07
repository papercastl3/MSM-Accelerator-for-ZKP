`timescale 1ns / 1ps

module flush_controller (
    input  logic         clk,
    input  logic         rst_n,

    // control
    input  logic         flush_start,
    output logic         flush_busy,
    output logic         flush_done,

    // to buckets_mem
    output logic         mem_en   [4][2],
    output logic         mem_we   [4][2],
    output logic [10:0]  mem_addr [4][2],
    output logic [767:0] mem_din  [4][2],
    input  logic [767:0] mem_dout [4][2],

    // AXI-Stream-like output to DMA
    output logic [767:0] m_axis_tdata,
    output logic         m_axis_tvalid,
    input  logic         m_axis_tready,
    output logic         m_axis_tlast
);

    localparam int MEM_READ_LATENCY = 3;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_READ_REQ,
        ST_READ_WAIT,
        ST_SEND,
        ST_CLEAR,
        ST_DONE
    } state_t;

    state_t state;

    logic [2:0]  flush_bank;   // 0 ~ 7
    logic [10:0] flush_addr;   // 0 ~ 2047
    logic [10:0] clear_addr;   // 0 ~ 2047

    logic [2:0]  read_bank_q;
    logic [10:0] read_addr_q;

    logic [1:0]  read_wait_cnt;

    logic [767:0] stream_data_reg;
    logic         stream_valid_reg;
    logic         stream_last_reg;

    logic [1:0] cur_matrix;
    logic       cur_port;

    logic [1:0] read_matrix_q;
    logic       read_port_q;

    logic stream_fire;

    assign cur_matrix = flush_bank[2:1];
    assign cur_port   = flush_bank[0];

    assign read_matrix_q = read_bank_q[2:1];
    assign read_port_q   = read_bank_q[0];

    assign stream_fire = m_axis_tvalid && m_axis_tready;

    assign m_axis_tdata  = stream_data_reg;
    assign m_axis_tvalid = stream_valid_reg;
    assign m_axis_tlast  = stream_last_reg;

    assign flush_busy = (state != ST_IDLE);
    assign flush_done = (state == ST_DONE);

    // ------------------------------------------------------------
    // Memory control
    // ------------------------------------------------------------
    always_comb begin
        for (int m = 0; m < 4; m++) begin
            for (int p = 0; p < 2; p++) begin
                mem_en[m][p]   = 1'b0;
                mem_we[m][p]   = 1'b0;
                mem_addr[m][p] = 11'd0;
                mem_din[m][p]  = 768'd0;
            end
        end

        unique case (state)
            ST_READ_REQ: begin
                mem_en[cur_matrix][cur_port]   = 1'b1;
                mem_we[cur_matrix][cur_port]   = 1'b0;
                mem_addr[cur_matrix][cur_port] = flush_addr;
                mem_din[cur_matrix][cur_port]  = 768'd0;
            end

            ST_CLEAR: begin
                for (int m = 0; m < 4; m++) begin
                    for (int p = 0; p < 2; p++) begin
                        mem_en[m][p]   = 1'b1;
                        mem_we[m][p]   = 1'b1;
                        mem_addr[m][p] = clear_addr;
                        mem_din[m][p]  = 768'd0;
                    end
                end
            end

            default: begin
                // default values
            end
        endcase
    end

    // ------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;

            flush_bank       <= 3'd0;
            flush_addr       <= 11'd0;
            clear_addr       <= 11'd0;

            read_bank_q      <= 3'd0;
            read_addr_q      <= 11'd0;
            read_wait_cnt    <= 2'd0;

            stream_data_reg  <= 768'd0;
            stream_valid_reg <= 1'b0;
            stream_last_reg  <= 1'b0;
        end else begin
            unique case (state)
                ST_IDLE: begin
                    flush_bank       <= 3'd0;
                    flush_addr       <= 11'd0;
                    clear_addr       <= 11'd0;

                    read_bank_q      <= 3'd0;
                    read_addr_q      <= 11'd0;
                    read_wait_cnt    <= 2'd0;

                    stream_data_reg  <= 768'd0;
                    stream_valid_reg <= 1'b0;
                    stream_last_reg  <= 1'b0;

                    if (flush_start) begin
                        state <= ST_READ_REQ;
                    end
                end

                // Issue read request to one logical bank
                ST_READ_REQ: begin
                    read_bank_q   <= flush_bank;
                    read_addr_q   <= flush_addr;
                    read_wait_cnt <= 2'd0;

                    state <= ST_READ_WAIT;
                end

                // XPM URAM read latency = 3 cycles
                ST_READ_WAIT: begin
                    if (read_wait_cnt == MEM_READ_LATENCY - 1) begin
                        stream_data_reg <= mem_dout[read_matrix_q][read_port_q];

                        stream_last_reg <=
                            (read_bank_q == 3'd7) &&
                            (read_addr_q == 11'd2047);

                        stream_valid_reg <= 1'b1;
                        read_wait_cnt    <= 2'd0;

                        state <= ST_SEND;
                    end else begin
                        read_wait_cnt <= read_wait_cnt + 2'd1;
                    end
                end

                // Hold stream beat until DMA accepts it
                ST_SEND: begin
                    if (stream_fire) begin
                        stream_valid_reg <= 1'b0;
                        stream_last_reg  <= 1'b0;

                        if ((flush_bank == 3'd7) && (flush_addr == 11'd2047)) begin
                            flush_bank <= 3'd0;
                            flush_addr <= 11'd0;
                            clear_addr <= 11'd0;
                            state      <= ST_CLEAR;
                        end else begin
                            if (flush_addr == 11'd2047) begin
                                flush_addr <= 11'd0;
                                flush_bank <= flush_bank + 3'd1;
                            end else begin
                                flush_addr <= flush_addr + 11'd1;
                            end

                            state <= ST_READ_REQ;
                        end
                    end
                end

                // Clear all 8 logical banks at the same address each cycle
                ST_CLEAR: begin
                    if (clear_addr == 11'd2047) begin
                        clear_addr <= 11'd0;
                        state      <= ST_DONE;
                    end else begin
                        clear_addr <= clear_addr + 11'd1;
                    end
                end

                // 1-cycle flush_done pulse
                ST_DONE: begin
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule