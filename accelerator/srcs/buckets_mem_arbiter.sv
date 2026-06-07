`timescale 1ns / 1ps

module buckets_mem_arbiter (
    input  logic         clk,
    input  logic         rst_n,

    // ------------------------------------------------------------
    // status / control
    // ------------------------------------------------------------
    input  logic         add_stream_done, // from ecc_adder_controller
    input  logic         flush_busy,      // from flush_controller
    input  logic         flush_done,      // from flush_controller

    output logic         flush_start,     // to flush_controller

    // optional status
    output logic         mem_grant_flush,
    output logic         mem_grant_ecc,

    // ------------------------------------------------------------
    // from ecc_adder_controller
    // ------------------------------------------------------------
    input  logic         ecc_mem_en   [4][2],
    input  logic         ecc_mem_we   [4][2],
    input  logic [10:0]  ecc_mem_addr [4][2],
    input  logic [767:0] ecc_mem_din  [4][2],
    output logic [767:0] ecc_mem_dout [4][2],

    // ------------------------------------------------------------
    // from flush_controller
    // ------------------------------------------------------------
    input  logic         flush_mem_en   [4][2],
    input  logic         flush_mem_we   [4][2],
    input  logic [10:0]  flush_mem_addr [4][2],
    input  logic [767:0] flush_mem_din  [4][2],
    output logic [767:0] flush_mem_dout [4][2],

    // ------------------------------------------------------------
    // to buckets_mem
    // ------------------------------------------------------------
    output logic         mem_en   [4][2],
    output logic         mem_we   [4][2],
    output logic [10:0]  mem_addr [4][2],
    output logic [767:0] mem_din  [4][2],
    input  logic [767:0] mem_dout [4][2]
);

    typedef enum logic [1:0] {
        GRANT_ECC,
        GRANT_FLUSH
    } grant_t;

    grant_t grant;

    // ------------------------------------------------------------
    // Grant FSM
    //
    // add_stream_done이 들어오면 flush_controller에 flush_start를 1클록 발생.
    // flush_busy가 유지되는 동안 buckets_mem은 flush_controller가 독점.
    // flush_done 후 다시 ECC에 grant.
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            grant       <= GRANT_ECC;
            flush_start <= 1'b0;
        end else begin
            flush_start <= 1'b0;

            unique case (grant)
                GRANT_ECC: begin
                    if (add_stream_done) begin
                        flush_start <= 1'b1;
                        grant       <= GRANT_FLUSH;
                    end
                end

                GRANT_FLUSH: begin
                    if (flush_done) begin
                        grant <= GRANT_ECC;
                    end
                end

                default: begin
                    grant <= GRANT_ECC;
                end
            endcase
        end
    end

    assign mem_grant_flush = (grant == GRANT_FLUSH);
    assign mem_grant_ecc   = (grant == GRANT_ECC);

    // ------------------------------------------------------------
    // Memory command mux
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

        unique case (grant)
            GRANT_ECC: begin
                for (int m = 0; m < 4; m++) begin
                    for (int p = 0; p < 2; p++) begin
                        mem_en[m][p]   = ecc_mem_en[m][p];
                        mem_we[m][p]   = ecc_mem_we[m][p];
                        mem_addr[m][p] = ecc_mem_addr[m][p];
                        mem_din[m][p]  = ecc_mem_din[m][p];
                    end
                end
            end

            GRANT_FLUSH: begin
                for (int m = 0; m < 4; m++) begin
                    for (int p = 0; p < 2; p++) begin
                        mem_en[m][p]   = flush_mem_en[m][p];
                        mem_we[m][p]   = flush_mem_we[m][p];
                        mem_addr[m][p] = flush_mem_addr[m][p];
                        mem_din[m][p]  = flush_mem_din[m][p];
                    end
                end
            end

            default: begin
                // inactive
            end
        endcase
    end

    // ------------------------------------------------------------
    // Memory read data fanout
    //
    // mem_dout은 둘 다 볼 수 있게 fanout.
    // 실제로 의미 있는 쪽은 현재 grant를 받은 controller.
    // ------------------------------------------------------------
    always_comb begin
        for (int m = 0; m < 4; m++) begin
            for (int p = 0; p < 2; p++) begin
                ecc_mem_dout[m][p]   = mem_dout[m][p];
                flush_mem_dout[m][p] = mem_dout[m][p];
            end
        end
    end

endmodule