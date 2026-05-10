`timescale 1ns/1ps

module tb_ECC_point_adder;

    // 1. 신호 선언
    logic         clk;
    logic         reset;
    logic         start;
    logic [254:0] x1, y1, z1;
    logic [254:0] x2, y2, z2;
    logic [254:0] x3, y3, z3; 
    logic [254:0] result;
    logic         done;

    // 2. DUT 인스턴스화
    ECC_point_adder uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .x1(x1), .y1(y1), .z1(z1),
        .x2(x2), .y2(y2), .z2(z2),
        .x3(x3), .y3(y3), .z3(z3), 
        .done(done)
    );

    // 3. 클럭 생성 (주기: 10ns, 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ★ Watchdog Timer (무한 루프 방지용)
    initial begin
        #5000000; // 500us 후에도 안끝나면 강제 종료 (필요 시 시간 조절)
        $display("========================================");
        $display(" [FAIL] Simulation TIMEOUT! (FSM Hang)");
        $display("========================================");
        $finish;
    end

    // 4. 테스트 시나리오
    initial begin
        // 초기값 설정
        reset = 1;
        start = 0;
        x1 = '0; y1 = '0; z1 = '0;
        x2 = '0; y2 = '0; z2 = '0;

        // Global Reset 대기 및 리셋 해제 (클럭 엣지에 동기화하여 해제하는 것이 좋음)
        #100;
        @(negedge clk); 
        reset = 0; 
        #20;

        // 5. [중요] 실제 수학적으로 검증된 ECC Point 데이터 입력
        // TODO: 아래 값들을 파이썬 레퍼런스 모델에서 뽑아낸 '몽고메리 도메인' 값으로 교체하세요.
        @(posedge clk);
        x1 = 255'h12345678; // P1_x (Montgomery)
        y1 = 255'hABCDEF;   // P1_y (Montgomery)
        z1 = 255'h1;        // 보통 Mixed Addition에서 Z1 = 1 (Montgomery Domain의 1 = R mod N)
        
        x2 = 255'h87654321; // P2_X (Montgomery)
        y2 = 255'hFEDCBA;   // P2_Y (Montgomery)
        z2 = 255'h1;        // P2_Z (Montgomery)
        
        start = 1;  // 연산 시작 신호

        @(posedge clk);
        start = 0;  // start 신호는 1클럭만 유지

        // 6. 연산 완료 대기 (done 신호 감시)
        wait(done);
        
        // 결과 출력 및 레퍼런스와 비교
        $display("========================================");
        $display(" Calculation Finished Successfully! ");
        $display("========================================");
        $display("X3: %h", x3);
        $display("Y3: %h", y3);
        $display("Z3: %h", z3);
        // TODO: 파이썬에서 계산한 정답값과 X3, Y3, Z3가 일치하는지 확인하는 자동 체크 로직 추가 권장

        #100;
        $finish;
    end

    // VCD 파일 덤프
    initial begin
        $dumpfile("tb_ECC_point_adder.vcd");
        $dumpvars(0, tb_ECC_point_adder);
    end

endmodule