`timescale 1ns/1ps

module tb_addsub_256;

    // =========================================================================
    // 1. 신호 선언
    // =========================================================================
    logic         clk;
    logic         reset;
    logic         start;
    logic [1:0]   op_mode;
    logic [255:0] A;
    logic [255:0] B;
    logic [255:0] result;
    logic         done;


    // 상수 정의 (골든 모델 비교용)
    localparam logic [255:0] N     = 256'h30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;
    localparam logic [255:0] TWO_N = N << 1;

    // 테스트 카운터
    int pass_cnt = 0;
    int fail_cnt = 0;
    int test_num = 0;

    // =========================================================================
    // 2. DUT 인스턴스화
    // =========================================================================
    AddSub_256 uut (
        .clk     (clk),
        .reset   (reset),
        .start   (start),
        .op_mode (op_mode),
        .A       (A),
        .B       (B),
        .result  (result),
        .done    (done)
    );

    // =========================================================================
    // 3. 클럭 생성 (100MHz, 주기 10ns)
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // =========================================================================
    // 4. 공통 태스크: 연산 실행 & 결과 검증
    // =========================================================================
    task automatic run_and_check(
        input string       test_name,
        input logic [1:0]  mode,
        input logic [255:0] in_a,
        input logic [255:0] in_b,
        input logic [255:0] expected
    );
        test_num++;
        op_mode = mode;
        A       = in_a;
        B       = in_b;

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // done 대기
        wait(done);
        @(posedge clk);

        $display("========================================");
        $display("[TEST %0d] %s", test_num, test_name);
        $display("  op_mode : %2b", mode);
        $display("  A       : %h", in_a);
        $display("  B       : %h", in_b);
        $display("  result  : %h", result);
        $display("  expected: %h", expected);

        if (result === expected) begin
            $display("  >> [PASS]");
            pass_cnt++;
        end else begin
            $display("  >> [FAIL]");
            fail_cnt++;
        end
    endtask

    // =========================================================================
    // 5. 테스트 시나리오
    // =========================================================================
    initial begin
        // 초기화
        reset   = 1;
        start   = 0;
        op_mode = 2'b00;
        A       = '0;
        B       = '0;

        #100; // GSR 해제 대기
        #20;
        reset = 0;
        #20;

        // =====================================================================
        // [Group 1] Lazy Addition (op_mode = 2'b00)
        //   result = (A+B < 2N) ? A+B : A+B-2N
        // =====================================================================
        $display("\n############################################");
        $display("# Group 1: Lazy Addition (op = 00)         #");
        $display("############################################");

        // Test 1: 작은 값, 오버플로우 없음 (A+B < 2N)
        // 1 + 2 = 3
        run_and_check(
            "Lazy Add: small values (no wrap)",
            2'b00,
            256'h1,
            256'h2,
            256'h3
        );

        // Test 2: 경계값 (A+B == 2N → 2N 차감하여 0)
        // N + N = 2N → result = 0
        run_and_check(
            "Lazy Add: exact boundary (A+B = 2N)",
            2'b00,
            N,
            N,
            256'h0
        );

        // Test 3: 오버플로우 발생 (A+B > 2N)
        // (N+100) + (N+200) = 2N + 300 → result = 300 = 0x12C
        run_and_check(
            "Lazy Add: overflow (A+B > 2N)",
            2'b00,
            N + 256'd100,
            N + 256'd200,
            256'h12C
        );

        // Test 4: A=0 (항등원 테스트)
        // 0 + N-1 = N-1
        run_and_check(
            "Lazy Add: identity (A=0)",
            2'b00,
            256'h0,
            N - 1,
            N - 1
        );

        // =====================================================================
        // [Group 2] Lazy Subtraction (op_mode = 2'b01)
        //   result = (A-B >= 0) ? A-B : A-B+2N
        // =====================================================================
        $display("\n############################################");
        $display("# Group 2: Lazy Subtraction (op = 01)      #");
        $display("############################################");

        // Test 5: 양수 결과 (A > B)
        // 5 - 3 = 2
        run_and_check(
            "Lazy Sub: positive result (A > B)",
            2'b01,
            256'h5,
            256'h3,
            256'h2
        );

        // Test 6: 음수 결과 (A < B → +2N 보정)
        // 3 - 5 = -2 → 2N - 2
        run_and_check(
            "Lazy Sub: negative wrap (A < B)",
            2'b01,
            256'h3,
            256'h5,
            TWO_N - 256'h2
        );

        // Test 7: A == B → 0
        run_and_check(
            "Lazy Sub: equal values (A = B)",
            2'b01,
            N,
            N,
            256'h0
        );

        // Test 8: A=0, B=1 → 2N-1
        run_and_check(
            "Lazy Sub: zero minus one",
            2'b01,
            256'h0,
            256'h1,
            TWO_N - 256'h1
        );

        // =====================================================================
        // [Group 3] Final Subtraction (op_mode = 2'b10)
        //   result = (A >= N) ? A-N : A
        // =====================================================================
        $display("\n############################################");
        $display("# Group 3: Final Subtraction (op = 10)     #");
        $display("############################################");

        // Test 9: A >= N → A - N
        // A = N + 5 → result = 5
        run_and_check(
            "Final Sub: A >= N (subtract N)",
            2'b10,
            N + 256'd5,
            256'h0, // B는 Final Sub에서 사용하지 않음
            256'h5
        );

        // Test 10: A < N → 원본 A 유지
        // A = 5 → result = 5
        run_and_check(
            "Final Sub: A < N (keep original)",
            2'b10,
            256'h5,
            256'h0,
            256'h5
        );

        // Test 11: A == N → result = 0
        run_and_check(
            "Final Sub: A = N (exact boundary)",
            2'b10,
            N,
            256'h0,
            256'h0
        );

        // Test 12: A = 2N-1 (최대 입력) → result = N-1
        run_and_check(
            "Final Sub: A = 2N-1 (max input)",
            2'b10,
            TWO_N - 256'h1,
            256'h0,
            N - 256'h1
        );

        // =====================================================================
        // [Group 4] Back-to-Back & Edge Cases
        // =====================================================================
        $display("\n############################################");
        $display("# Group 4: Back-to-Back & Edge Cases       #");
        $display("############################################");

        // Test 13: 연속 연산 (Lazy Add → Lazy Sub → Final Sub)
        // Add: N-1 + N-1 = 2N-2 < 2N → result = 2N-2
        run_and_check(
            "Back-to-Back 1/3: Lazy Add",
            2'b00,
            N - 1,
            N - 1,
            TWO_N - 256'h2
        );

        // Sub: (2N-2) - (N-1) = N-1 → positive
        run_and_check(
            "Back-to-Back 2/3: Lazy Sub",
            2'b01,
            TWO_N - 256'h2,
            N - 256'h1,
            N - 256'h1
        );

        // Final: N-1 → N-1 < N 이므로 원본 유지
        run_and_check(
            "Back-to-Back 3/3: Final Sub",
            2'b10,
            N - 256'h1,
            256'h0,
            N - 256'h1
        );

        // Test 14: 모든 비트 1 (Lazy Sub에서 큰 보정 테스트)
        // 0 - (2N-1) = -(2N-1) → +2N = 1
        run_and_check(
            "Edge: 0 - (2N-1) = 1",
            2'b01,
            256'h0,
            TWO_N - 256'h1,
            256'h1
        );
//============================================================================================        

        // =====================================================================
        // [Group 5] Randomized Testing (100 runs)
        // =====================================================================
        $display("\n############################################");
        $display("# Group 5: Randomized Testing (100 runs)   #");
        $display("############################################");
        
        for (int i=0; i<100; i++) begin
            automatic logic [255:0] rand_A, rand_B;
            automatic logic [256:0] temp_sum;
            automatic logic [256:0] temp_sub;
            
            // 256비트 랜덤 생성 ($urandom은 32비트씩 생성하므로 8번 연접)
            rand_A = {$urandom, $urandom, $urandom, $urandom, $urandom, $urandom, $urandom, $urandom} % TWO_N;
            rand_B = {$urandom, $urandom, $urandom, $urandom, $urandom, $urandom, $urandom, $urandom} % TWO_N;
            
            // 1. Lazy Add (00) 랜덤
            temp_sum = rand_A + rand_B;
            if (temp_sum >= TWO_N) temp_sum = temp_sum - TWO_N;
            run_and_check(
                $sformatf("Random %0d: Lazy Add", i+1),
                2'b00, rand_A, rand_B, temp_sum[255:0]
            );
            
            // 2. Lazy Sub (01) 랜덤
            if (rand_A >= rand_B) temp_sub = rand_A - rand_B;
            else                  temp_sub = rand_A - rand_B + TWO_N;
            run_and_check(
                $sformatf("Random %0d: Lazy Sub", i+1),
                2'b01, rand_A, rand_B, temp_sub[255:0]
            );
            
            // 3. Final Sub (10) 랜덤 (B는 무관, rand_A만 사용)
            if (rand_A >= N) temp_sub = rand_A - N;
            else             temp_sub = rand_A;
            run_and_check(
                $sformatf("Random %0d: Final Sub", i+1),
                2'b10, rand_A, 256'd0, temp_sub[255:0]
            );
        end

        // =====================================================================
        // 결과 요약
        // =====================================================================
        $display("\n============================================");
        $display("  TEST SUMMARY");
        $display("============================================");
        $display("  Total : %0d", test_num);
        $display("  PASS  : %0d", pass_cnt);
        $display("  FAIL  : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display("  >> ALL TESTS PASSED!");
        else
            $display("  >> SOME TESTS FAILED!");
        $display("============================================\n");

        #50;
        $finish;
    end

    // =========================================================================
    // 6. VCD 덤프
    // =========================================================================
    initial begin
        $dumpfile("tb_addsub_256.vcd");
        $dumpvars(0, tb_addsub_256);
    end

endmodule
