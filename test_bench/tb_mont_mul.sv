`timescale 1ns/1ps

module tb_mont_mult;

    // 1. 파라미터 정의 (Python 스크립트와 동일하게 설정)
    localparam int NUM_TESTS = 10000;
    localparam int TIMEOUT_CYCLES = 1000; // 무한 대기 방지용 타임아웃

    // 2. 신호 선언
    logic         clk;
    logic         reset;
    logic         start;
    logic [254:0] X;
    logic [254:0] Y;
    logic [254:0] result;
    logic         done;

    // 3. 파일 로딩용 메모리 배열 및 정답 레지스터
    // 파이썬에서 256비트(64자리 헥스) 3개를 언더스코어로 붙여서 출력했으므로 768비트 배열을 선언
    logic [767:0] m_data [0:NUM_TESTS-1]; 
    logic [254:0] expected_result;

    // 4. DUT (Device Under Test) 인스턴스화
    mont_multiplier uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .X(X),
        .Y(Y),
        .result(result),
        .done(done)
    );

    // 5. 클럭 생성 (주기: 10ns, 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 6. 자동화 테스트 시나리오
    initial begin
         // 파이썬으로 생성한 단일 파일을 읽어옵니다. (상대 경로 주의)
        $readmemh("C:/Users/jisun/Desktop/zkp_accel/golden_model/mont_multiplier/mont_mul_test_vectors.hex", m_data);
        // ★ Vivado GSR(Global Set/Reset) 해제 대기 및 초기화
        start = 0;
        X = '0;
        Y = '0;
        reset = 1;
        #100;
        
        // 리셋 해제
        #20;
        reset = 0;
        repeat(5) @(posedge clk);

        $display("========================================");
        $display("Starting Automated Verification: %0d cases", NUM_TESTS);
        $display("========================================\n");

        // 파일에서 읽은 데이터로 루프 실행
        for (int i = 0; i < NUM_TESTS; i++) begin
            @(posedge clk);
            
            // 768비트 데이터를 256비트 단위로 자른 뒤, 하위 255비트만 할당
            X <= m_data[i][512 +: 255]; 
            Y <= m_data[i][256 +: 255]; 
            expected_result = m_data[i][0 +: 255]; 
            
            start <= 1;

            @(posedge clk);
            start <= 0;

            // 연산 완료(done) 신호 대기 (Timeout 안전장치 포함)
            fork
                begin
                    @(posedge done);
                end
                begin
                    repeat(TIMEOUT_CYCLES) @(posedge clk);
                    $display("\n[ERROR] Case %0d: Simulation Timeout! 'done' signal not asserted.", i);
                    $stop;
                end
            join_any
            disable fork; // 하나의 조건이 만족되면 타이머 취소

            // 한 클럭 여유를 두고 결과 검증
            @(posedge clk);
            
            if (result !== expected_result) begin
                $display("\n[FAIL] Test Case %0d Failed!", i);
                $display("  Input X : %x", X);
                $display("  Input Y : %x", Y);
                $display("  Actual  : %x", result);
                $display("  Expect  : %x", expected_result);
                $stop; // 첫 실패 시 시뮬레이션 중단
            end else begin
                // 진행 상황 출력 (너무 길면 i % 10 == 0 일 때만 출력하도록 수정 가능)
                $display("[PASS] Case %0d Successful.", i);
            end
        end

        $display("\n========================================");
        $display("Verification Done. ALL %0d CASES PASSED!", NUM_TESTS);
        $display("========================================");
        #50;
        $finish;
    end

    // 8. VCD 파일 덤프
    initial begin
        $dumpfile("tb_mont_mult.vcd");
        $dumpvars(0, tb_mont_mult);
    end

endmodule