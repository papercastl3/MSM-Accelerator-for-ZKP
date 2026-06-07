`timescale 1ns / 1ps

module shift_fifo #(
    parameter int WIDTH = 768,
    parameter int DEPTH = 4
)(
    input  logic             clk,
    input  logic             rst_n,

    // input side
    input  logic [WIDTH-1:0] in_data,
    input  logic             in_valid,
    output logic             in_ready,

    // output side
    output logic [WIDTH-1:0] out_data,
    output logic             out_valid,
    input  logic             out_ready
);

    localparam int COUNT_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);

    logic [WIDTH-1:0] data [DEPTH-1:0];

    logic [COUNT_W-1:0] count;

    logic push;
    logic pop;

    assign out_data  = data[0];
    assign out_valid = count != '0;

    // full이어도 같은 cycle에 pop이 일어나면 push 허용
    assign in_ready = (count != DEPTH[COUNT_W-1:0]) || pop;

    assign push = in_valid  && in_ready;
    assign pop  = out_valid && out_ready;

    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= '0;

            for (i = 0; i < DEPTH; i = i + 1) begin
                data[i] <= '0;
            end
        end else begin
            unique case ({push, pop})

                // no push, no pop
                2'b00: begin
                    count <= count;
                end

                // push only
                2'b10: begin
                    data[count] <= in_data;
                    count <= count + {{(COUNT_W-1){1'b0}}, 1'b1};
                end

                // pop only
                2'b01: begin
                    for (i = 0; i < DEPTH-1; i = i + 1) begin
                        if (i < count - 1) begin
                            data[i] <= data[i+1];
                        end
                    end

                    data[count-1] <= '0;
                    count <= count - {{(COUNT_W-1){1'b0}}, 1'b1};
                end

                // push and pop same cycle
                2'b11: begin
                    for (i = 0; i < DEPTH-1; i = i + 1) begin
                        if (i < count - 1) begin
                            data[i] <= data[i+1];
                        end
                    end

                    // pop 후 생긴 tail 위치에 새 데이터 삽입
                    data[count-1] <= in_data;

                    // push/pop 동시 발생이므로 count 유지
                    count <= count;
                end

                default: begin
                    count <= count;
                end
            endcase
        end
    end

endmodule