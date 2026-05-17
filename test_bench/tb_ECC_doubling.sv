`timescale 1ns/1ps

/**
 * Golden Model Testbench for point_doubling_z1 (Z1=1 optimized)
 * Reads test vectors from file, compares DUT output against expected values.
 * Test vector format: X1 Y1 EX3 EY3 EZ3 (no Z1 input, always 1)
 */
module tb_point_doubling_golden;

    localparam int CLK_PERIOD = 10;
    localparam int TIMEOUT_CYCLES = 50000;
    localparam string VECTOR_FILE = "test_vectors_z1.txt";

    logic         clk, reset, start;
    logic [254:0] x1, y1;
    logic [254:0] x3, y3, z3;
    logic         done;

    point_doubling_z1 uut (
        .clk   (clk),
        .reset (reset),
        .start (start),
        .x1    (x1),
        .y1    (y1),
        .x3    (x3),
        .y3    (y3),
        .z3    (z3),
        .done  (done)
    );

    initial begin clk = 0; forever #(CLK_PERIOD/2) clk = ~clk; end

    // Single doubling task
    task automatic run_doubling(
        input  logic [254:0] in_x1, in_y1,
        output logic [254:0] out_x3, out_y3, out_z3,
        output logic         timed_out
    );
        int wait_cnt;
        timed_out = 0;
        x1 = in_x1; y1 = in_y1;
        @(posedge clk); start = 1;
        @(posedge clk); start = 0;
        wait_cnt = 0;
        while (!done && wait_cnt < TIMEOUT_CYCLES) begin
            @(posedge clk); wait_cnt++;
        end
        if (wait_cnt >= TIMEOUT_CYCLES) begin
            timed_out = 1;
        end else begin
            @(posedge clk);
            out_x3 = x3; out_y3 = y3; out_z3 = z3;
        end
    endtask

    initial begin
        int fd, num_tests, pass_cnt, fail_cnt;
        logic [255:0] v_x1, v_y1, v_ex3, v_ey3, v_ez3;
        logic [254:0] res_x3, res_y3, res_z3;
        logic timed_out;

        $dumpfile("tb_golden_z1.vcd");
        $dumpvars(0, tb_point_doubling_golden);

        reset = 1; start = 0;
        x1 = '0; y1 = '0;
        #100; reset = 0; #20;

        fd = $fopen(VECTOR_FILE, "r");
        if (fd == 0) begin
            $display("ERROR: Cannot open %s", VECTOR_FILE);
            $display("  Run: python gen_test_vectors_z1.py");
            $finish;
        end

        if ($fscanf(fd, "%d", num_tests) != 1) begin
            $display("ERROR: Cannot read test count"); $finish;
        end

        $display("==============================================");
        $display(" Golden Model Test (Z1=1): %0d vectors", num_tests);
        $display("==============================================");

        pass_cnt = 0; fail_cnt = 0;

        for (int i = 0; i < num_tests; i++) begin
            // Format: X1 Y1 EX3 EY3 EZ3 (no Z1)
            if ($fscanf(fd, "%h %h %h %h %h",
                        v_x1, v_y1, v_ex3, v_ey3, v_ez3) != 5) begin
                $display("ERROR: Failed to read vector #%0d", i);
                break;
            end

            run_doubling(v_x1[254:0], v_y1[254:0],
                         res_x3, res_y3, res_z3, timed_out);

            if (timed_out) begin
                $display("[%04d] TIMEOUT!", i);
                fail_cnt++;
            end else if (res_x3 !== v_ex3[254:0] || res_y3 !== v_ey3[254:0] || res_z3 !== v_ez3[254:0]) begin
                $display("[%04d] MISMATCH!", i);
                $display("  X1=%h  Y1=%h", v_x1[254:0], v_y1[254:0]);
                $display("  X3: got=%h exp=%h %s", res_x3, v_ex3[254:0], res_x3 === v_ex3[254:0] ? "OK" : "FAIL");
                $display("  Y3: got=%h exp=%h %s", res_y3, v_ey3[254:0], res_y3 === v_ey3[254:0] ? "OK" : "FAIL");
                $display("  Z3: got=%h exp=%h %s", res_z3, v_ez3[254:0], res_z3 === v_ez3[254:0] ? "OK" : "FAIL");
                fail_cnt++;
                if (fail_cnt >= 10) begin
                    $display("Too many failures, stopping early.");
                    break;
                end
            end else begin
                if (i % 100 == 0) $display("[%04d] PASS", i);
                pass_cnt++;
            end
        end

        $fclose(fd);

        $display("==============================================");
        $display(" RESULT: %0d/%0d PASSED, %0d FAILED",
                 pass_cnt, pass_cnt + fail_cnt, fail_cnt);
        $display("==============================================");
        if (fail_cnt == 0) $display(" >> ALL TESTS PASSED!");
        else               $display(" >> SOME TESTS FAILED!");

        #50; $finish;
    end
endmodule
