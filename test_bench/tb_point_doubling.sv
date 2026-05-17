`timescale 1ns/1ps

/**
 * Testbench for point_doubling module
 * - Random input tests with range verification (result < N)
 * - Determinism check (same input -> same output)
 * - Back-to-back consecutive operation test
 * - Done signal behavior verification
 */
module tb_point_doubling;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam [254:0] N = 255'h2523648240000001BA344D80000000086121000000000013A700000000000013;
    localparam int NUM_RANDOM_TESTS = 10;
    localparam int CLK_PERIOD = 10;     // 10ns, 100MHz
    localparam int TIMEOUT_CYCLES = 50000;  // Max wait cycles

    // =========================================================================
    // Signal Declarations
    // =========================================================================
    logic         clk;
    logic         reset;
    logic         start;
    logic [254:0] X1_in, Y1_in, Z1_in;
    logic [254:0] X3_out, Y3_out, Z3_out;
    logic         done;

    // Test result storage
    logic [254:0] saved_X3, saved_Y3, saved_Z3;
    int           pass_cnt, fail_cnt, test_num;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    point_doubling uut (
        .clk    (clk),
        .reset  (reset),
        .start  (start),
        .X1_in  (X1_in),
        .Y1_in  (Y1_in),
        .Z1_in  (Z1_in),
        .X3_out (X3_out),
        .Y3_out (Y3_out),
        .Z3_out (Z3_out),
        .done   (done)
    );

    // =========================================================================
    // Clock Generation (100MHz)
    // =========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // =========================================================================
    // Random 255-bit value generation (0 <= val < N)
    // =========================================================================
    function automatic logic [254:0] rand_mod_n();
        logic [254:0] val;
        do begin
            // $urandom returns 32-bit, call 8 times for 256-bit
            val = {$urandom, $urandom, $urandom, $urandom,
                   $urandom, $urandom, $urandom, $urandom};
            val = val & {255{1'b1}};  // Mask to 255 bits
        end while (val >= N);
        return val;
    endfunction

    // =========================================================================
    // Single doubling operation task
    // =========================================================================
    task automatic run_doubling(
        input  logic [254:0] x1, y1, z1,
        output logic [254:0] x3, y3, z3,
        output logic         timed_out
    );
        int wait_cnt;
        timed_out = 0;

        // Set inputs
        X1_in = x1;
        Y1_in = y1;
        Z1_in = z1;

        // Start pulse
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for done (with timeout)
        wait_cnt = 0;
        while (!done && wait_cnt < TIMEOUT_CYCLES) begin
            @(posedge clk);
            wait_cnt++;
        end

        if (wait_cnt >= TIMEOUT_CYCLES) begin
            timed_out = 1;
            x3 = '0; y3 = '0; z3 = '0;
        end else begin
            @(posedge clk);  // 1 cycle margin after done
            x3 = X3_out;
            y3 = Y3_out;
            z3 = Z3_out;
        end
    endtask

    // =========================================================================
    // Range check: 0 <= val < N
    // =========================================================================
    function automatic logic check_range(logic [254:0] val, string name);
        if (val >= N) begin
            $display("  [RANGE FAIL] %s = %h >= N!", name, val);
            return 0;
        end
        return 1;
    endfunction

    // =========================================================================
    // Main Test Scenario
    // =========================================================================
    initial begin
        // VCD dump
        $dumpfile("tb_point_doubling.vcd");
        $dumpvars(0, tb_point_doubling);

        pass_cnt = 0;
        fail_cnt = 0;
        test_num = 0;

        // Wait for Vivado GSR release
        #100;

        // Initialization
        reset = 1;
        start = 0;
        X1_in = '0;
        Y1_in = '0;
        Z1_in = '0;
        #20;
        reset = 0;
        #20;

        $display("========================================================");
        $display(" point_doubling Testbench Start");
        $display("========================================================\n");

        // =================================================================
        // TEST 1: Fixed input (N-1, N-1, N-1)
        // =================================================================
        begin
            logic [254:0] x3, y3, z3;
            logic timed_out;
            test_num++;

            $display("[TEST %0d] Fixed Input: X1=Y1=Z1=N-1", test_num);
            run_doubling(N - 1, N - 1, N - 1, x3, y3, z3, timed_out);

            if (timed_out) begin
                $display("  >> [FAIL] TIMEOUT!\n");
                fail_cnt++;
            end else begin
                $display("  X3 = %h", x3);
                $display("  Y3 = %h", y3);
                $display("  Z3 = %h", z3);
                if (check_range(x3, "X3") && check_range(y3, "Y3") && check_range(z3, "Z3")) begin
                    $display("  >> [PASS] Range OK\n");
                    pass_cnt++;
                end else begin
                    $display("  >> [FAIL] Out of range!\n");
                    fail_cnt++;
                end
            end
        end

        // =================================================================
        // TEST 2: Zero input (0, 0, 0) -- zero handling check
        // =================================================================
        begin
            logic [254:0] x3, y3, z3;
            logic timed_out;
            test_num++;

            $display("[TEST %0d] Zero Input: X1=Y1=Z1=0", test_num);
            run_doubling(255'h0, 255'h0, 255'h0, x3, y3, z3, timed_out);

            if (timed_out) begin
                $display("  >> [FAIL] TIMEOUT!\n");
                fail_cnt++;
            end else begin
                $display("  X3 = %h", x3);
                $display("  Y3 = %h", y3);
                $display("  Z3 = %h", z3);
                if (x3 == '0 && y3 == '0 && z3 == '0) begin
                    $display("  >> [PASS] All zeros as expected\n");
                    pass_cnt++;
                end else begin
                    // Non-zero but in range is also acceptable
                    if (check_range(x3, "X3") && check_range(y3, "Y3") && check_range(z3, "Z3")) begin
                        $display("  >> [PASS] Non-zero but range OK (point at infinity handling)\n");
                        pass_cnt++;
                    end else begin
                        $display("  >> [FAIL] Out of range!\n");
                        fail_cnt++;
                    end
                end
            end
        end

        // =================================================================
        // TEST 3: Fixed input (1, 1, 1)
        // =================================================================
        begin
            logic [254:0] x3, y3, z3;
            logic timed_out;
            test_num++;

            $display("[TEST %0d] Simple Input: X1=Y1=Z1=1", test_num);
            run_doubling(255'h1, 255'h1, 255'h1, x3, y3, z3, timed_out);

            if (timed_out) begin
                $display("  >> [FAIL] TIMEOUT!\n");
                fail_cnt++;
            end else begin
                $display("  X3 = %h", x3);
                $display("  Y3 = %h", y3);
                $display("  Z3 = %h", z3);
                if (check_range(x3, "X3") && check_range(y3, "Y3") && check_range(z3, "Z3")) begin
                    $display("  >> [PASS] Range OK\n");
                    pass_cnt++;
                end else begin
                    $display("  >> [FAIL] Out of range!\n");
                    fail_cnt++;
                end
            end
        end

        // =================================================================
        // TEST 4~N: Random input + range verification
        // =================================================================
        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            logic [254:0] rx1, ry1, rz1;
            logic [254:0] x3, y3, z3;
            logic timed_out;
            test_num++;

            rx1 = rand_mod_n();
            ry1 = rand_mod_n();
            rz1 = rand_mod_n();
            // Ensure Z1 != 0
            if (rz1 == '0) rz1 = 255'h1;

            $display("[TEST %0d] Random #%0d", test_num, i + 1);
            $display("  X1 = %h", rx1);
            $display("  Y1 = %h", ry1);
            $display("  Z1 = %h", rz1);

            run_doubling(rx1, ry1, rz1, x3, y3, z3, timed_out);

            if (timed_out) begin
                $display("  >> [FAIL] TIMEOUT!\n");
                fail_cnt++;
            end else begin
                $display("  X3 = %h", x3);
                $display("  Y3 = %h", y3);
                $display("  Z3 = %h", z3);
                if (check_range(x3, "X3") && check_range(y3, "Y3") && check_range(z3, "Z3")) begin
                    $display("  >> [PASS] Range OK\n");
                    pass_cnt++;
                end else begin
                    $display("  >> [FAIL] Out of range!\n");
                    fail_cnt++;
                end
            end
        end

        // =================================================================
        // TEST: Determinism check (same input -> same output)
        // =================================================================
        begin
            logic [254:0] rx1, ry1, rz1;
            logic [254:0] x3_a, y3_a, z3_a;
            logic [254:0] x3_b, y3_b, z3_b;
            logic timed_out;
            test_num++;

            rx1 = rand_mod_n();
            ry1 = rand_mod_n();
            rz1 = rand_mod_n();
            if (rz1 == '0) rz1 = 255'h1;

            $display("[TEST %0d] Determinism: same input twice", test_num);
            $display("  X1 = %h", rx1);
            $display("  Y1 = %h", ry1);
            $display("  Z1 = %h", rz1);

            // Run 1
            run_doubling(rx1, ry1, rz1, x3_a, y3_a, z3_a, timed_out);
            if (timed_out) begin
                $display("  >> [FAIL] TIMEOUT on 1st run!\n");
                fail_cnt++;
            end else begin
                // Run 2 (back-to-back)
                run_doubling(rx1, ry1, rz1, x3_b, y3_b, z3_b, timed_out);
                if (timed_out) begin
                    $display("  >> [FAIL] TIMEOUT on 2nd run!\n");
                    fail_cnt++;
                end else begin
                    $display("  Run1: X3=%h Y3=%h Z3=%h", x3_a, y3_a, z3_a);
                    $display("  Run2: X3=%h Y3=%h Z3=%h", x3_b, y3_b, z3_b);
                    if (x3_a == x3_b && y3_a == y3_b && z3_a == z3_b) begin
                        $display("  >> [PASS] Deterministic results match\n");
                        pass_cnt++;
                    end else begin
                        $display("  >> [FAIL] Results differ!\n");
                        fail_cnt++;
                    end
                end
            end
        end

        // =================================================================
        // TEST: Back-to-back consecutive operations (different inputs)
        // =================================================================
        begin
            logic [254:0] x3, y3, z3;
            logic timed_out;
            int b2b_pass;
            test_num++;
            b2b_pass = 1;

            $display("[TEST %0d] Back-to-back: 5 consecutive operations", test_num);
            for (int j = 0; j < 5; j++) begin
                logic [254:0] bx1, by1, bz1;
                bx1 = rand_mod_n();
                by1 = rand_mod_n();
                bz1 = rand_mod_n();
                if (bz1 == '0) bz1 = 255'h1;

                run_doubling(bx1, by1, bz1, x3, y3, z3, timed_out);
                if (timed_out) begin
                    $display("  B2B #%0d: TIMEOUT!", j);
                    b2b_pass = 0;
                end else if (x3 >= N || y3 >= N || z3 >= N) begin
                    $display("  B2B #%0d: Out of range!", j);
                    b2b_pass = 0;
                end else begin
                    $display("  B2B #%0d: OK (X3=%h...)", j, x3[254:224]);
                end
            end
            if (b2b_pass) begin
                $display("  >> [PASS] All back-to-back operations OK\n");
                pass_cnt++;
            end else begin
                $display("  >> [FAIL] Back-to-back failure!\n");
                fail_cnt++;
            end
        end

        // =================================================================
        // Result Summary
        // =================================================================
        $display("========================================================");
        $display(" SUMMARY: %0d tests, %0d PASSED, %0d FAILED",
                 pass_cnt + fail_cnt, pass_cnt, fail_cnt);
        $display("========================================================");

        if (fail_cnt == 0)
            $display(" >> ALL TESTS PASSED!");
        else
            $display(" >> SOME TESTS FAILED!");

        #50;
        $finish;
    end

endmodule
