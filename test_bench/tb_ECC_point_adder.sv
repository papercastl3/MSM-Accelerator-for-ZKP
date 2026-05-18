`timescale 1ns/1ps

module tb_ECC_point_adder();
    // 1. 파라미터 정의
    localparam int NUM_TESTS = 10000;
    localparam int TIMEOUT_CYCLES = 100000;

    // 2. 신호 선언
    logic clk;
    logic reset, start, done;
    logic [254:0] x1, y1, z1;
    logic [254:0] x2, y2, z2;
    logic [254:0] x3, y3, z3;

    // 3. 메모리 배열 (Python에서 9개 변수를 한 줄에 출력하므로 총 2304비트)
    logic [2303:0] m_data [0: NUM_TESTS-1]; 
    
    logic [254:0] r_x3;
    logic [254:0] r_y3;
    logic [254:0] r_z3;

    // 4. DUT 연결
    ECC_point_adder dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .x1(x1), .y1(y1), .z1(z1),
        .x2(x2), .y2(y2), .z2(z2),
        .x3(x3), .y3(y3), .z3(z3),
        .done(done) 
    );

    // 클럭 생성 (100MHz 테스트 기준. 400MHz는 #1.25)
    always #5 clk = ~clk;

    initial begin
        // Python 코드에서 만든 파일명으로 경로 수정 (상대경로로 변경 시 더 좋음)
        // 파일 이름을 파이썬 스크립트 출력명(ecc_test_vectors.hex)으로 맞췄습니다.
        $readmemh("all_covering_test_vectors.hex", m_data);
        
        // 초기화
        clk = 0;
        start = 0;
        x1 = '0; y1 = '0; z1 = '0;
        x2 = '0; y2 = '0; z2 = '0;
        reset = 1;
        #100;
        
        reset = 1; 
        repeat(10) @(posedge clk);
        reset <= 0;
        repeat(2) @(posedge clk);

        // 7. 테스트 루프
        for (int i = 0; i < NUM_TESTS; i++) begin
            @(posedge clk);
            
            // ? [핵심 수정] Python 출력(x1_y1_z1_x2_y2_z2_x3_y3_z3) 순서에 맞춰
            // 오른쪽(LSB)부터 z3, y3, x3, z2, y2, x2, z1, y1, x1 순으로 거꾸로 읽어옵니다.
            // 또한 256비트 블록에서 하위 255비트만 자릅니다 (logic [254:0]에 맞춤).
            r_z3 <= m_data[i][0*256 +: 255]; // 오른쪽 끝 (z3)
            r_y3 <= m_data[i][1*256 +: 255];
            r_x3 <= m_data[i][2*256 +: 255]; 
            
            z2   <= m_data[i][3*256 +: 255];
            y2   <= m_data[i][4*256 +: 255]; 
            x2   <= m_data[i][5*256 +: 255]; 
            
            z1   <= m_data[i][6*256 +: 255];
            y1   <= m_data[i][7*256 +: 255]; 
            x1   <= m_data[i][8*256 +: 255]; // 왼쪽 끝 (x1)

            start <= 1;
            @(posedge clk);
            start <= 0;

            // Timeout 로직
            fork
                begin
                    @(posedge done);
                end
                begin
                    repeat(TIMEOUT_CYCLES) @(posedge clk);
                    $display("[ERROR] Case %0d: Simulation Timeout!", i);
                    $stop;
                end
            join_any
            disable fork; 

            // 결과 검증
            if ($isunknown(x3) || $isunknown(y3) || $isunknown(z3) ||
            x3 !== r_x3 || y3 !== r_y3 || z3 !== r_z3) begin
                $display("[FAIL] Case %0d Mismatch!", i);
                $display("  Actual: x=%h, y=%h, z=%h", x3, y3, z3);
                $display("  Expect: x=%h, y=%h, z=%h", r_x3, r_y3, r_z3);
                $stop;
            end else begin
                $display("[PASS] Case %0d", i);
            end
        end

        $display("========================================");
        $display("Verification Done. ALL %0d CASES PASSED!", NUM_TESTS);
        $display("========================================");
        $finish;
    end
endmodule  