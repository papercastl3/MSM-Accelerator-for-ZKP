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
        X = 255'b0;
        Y = 255'b0;

        // 리셋 유지 후 해제
        #20;
        reset = 0;
        #20;

        // 입력 데이터 설정 (253비트 숫자)
        // 참고: 253비트 숫자는 최상위 비트(bit 252)가 1이어야 합니다. 
        // X = 2^252 (가장 단순한 253비트 숫자)
        X = 254'h1000000000000000000000000012367645728000000a987654321; 
        
        // Y = 2^252 + 모두 1로 채워진 값 (극단적인 253비트 숫자)
        Y = 254'h1FFFFFFFFFFFFFFFFFFacdFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

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
        $display("========================================");

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