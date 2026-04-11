`timescale 1ns/1ps

module tb_mont_mult;

    // 1. 신호 선언
    logic         clk;
    logic         reset;
    logic         start;
    logic [254:0] X;
    logic [254:0] Y;
    logic [254:0] result;
    logic         done;

    // 2. DUT (Device Under Test) 인스턴스화
    mont_multiplier uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .X(X),
        .Y(Y),
        .result(result),
        .done(done)
    );

    // 3. 클럭 생성 (주기: 10ns, 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 4. 테스트 시나리오
    initial begin
        // ★ Vivado GSR(Global Set/Reset) 해제 대기 
        #100;
        // 초기화
        reset = 1;
        start = 0;
        X = 255'h0;
        Y = 255'h0;

        // 리셋 유지 후 해제
        #20;
        reset = 0;
        #20;

        //test 1 : N-1 * N-1 
        $display("\n[TEST 1] Starting Max Inputs (N-1) Test...");
        X = 255'h2523648240000001BA344D80000000086121000000000013A700000000000012;
        Y = 255'h2523648240000001BA344D80000000086121000000000013A700000000000012;
        // 연산 시작 (start 펄스 인가)
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        // 연산 완료(done) 신호 대기
        wait(done);
        // 한 클럭 여유를 두고 결과 출력
        @(posedge clk);
        $display("========================================");
        $display("Simulation Time : %0t ns", $time);
        $display("Input X         : %h", X);
        $display("Input Y         : %h", Y);
        $display("Result Output   : %h", result);
        if (result == 255'hfc324f3523e22fb8ff38a9daad048050c61a2802e9ac3516fec55d39eda7679) begin
            $display(">> [PASS] Test 1 Successful! (edge case)");
        end else begin
            $display(">> [FAIL] Test 1 Failed!");
        end

        //test 2 :  0 * 0 
        $display("\n[TEST 2] Starting Back-to-Back (All Zeros) Test...");
        X = 255'h0;
        Y = 255'h0;
        // 연산 시작 (start 펄스 인가)
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        // 연산 완료(done) 신호 대기
        wait(done);
        @(posedge clk);
        $display("========================================");
        $display("Simulation Time : %0t ns", $time);
        $display("Input X         : %h", X);
        $display("Input Y         : %h", Y);
        $display("Result Output   : %h", result);
        if (result == 255'h0) begin
            $display(">> [PASS] Test 2 Successful! (FSM and RAM cleared perfectly)");
        end else begin
            $display(">> [FAIL] Test 2 Failed!");
        end
        $display("----------------------------------------\n");

        //test 3 : 항등원 테스트 1 * R 
        $display("\n[TEST 2] Starting Back-to-Back (All Zeros) Test...");
        X = 255'h1095d2793ffffffad163177fffffffe6dc9cffffffffffc50affffffffffffc7;
        Y = 255'h1;
        // 연산 시작 (start 펄스 인가)
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        // 연산 완료(done) 신호 대기
        wait(done);
        @(posedge clk);
        $display("========================================");
        $display("Simulation Time : %0t ns", $time);
        $display("Input X         : %h", X);
        $display("Input Y         : %h", Y);
        $display("Result Output   : %h", result);
        if (result == 255'h1) begin
            $display(">> [PASS] Test 3 Successful! (unity calculation test)");
        end else begin
            $display(">> [FAIL] Test 3 Failed! ");
        end
        $display("----------------------------------------\n");

        // 시뮬레이션 종료
        #50;
        $finish;
    end



    // VCD 파일 덤프 (ModelSim, Vivado, Icarus Verilog 등)
    initial begin
        $dumpfile("tb_mont_mult.vcd");
        $dumpvars(0, tb_mont_mult);
    end

endmodule