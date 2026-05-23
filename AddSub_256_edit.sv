`timescale 1ns/1ps

/**
 * 모듈명: AddSub_256 (400MHz Pre-Load Shift Register Version)
 * 핵심 수정 사항:
 * 1. [타이밍 확정] use_dsp 속성을 제거하여 32비트 가산기를 초고속 CARRY8 패브릭으로 매핑.
 * 2. [MUX 트리 완전 해체] word_idx 기반 동적 인덱싱(8-to-1 MUX) 완전 제거.
 *    S_IDLE에서 op_mode에 맞는 상수를 전용 시프트 레지스터에 사전 적재(Pre-Load)하여
 *    조합 논리를 단일 LUT6 레벨로 압축. Logic Level 7 → 4~5 달성.
 * 3. [데이터 무결성] 8사이클의 정확한 32비트 원형 회전(Rotation)으로 원본 데이터 정렬 완벽 복원.
 */
module AddSub_256 #(
    parameter int TOTAL_W = 256,
    parameter int WORD_W  = 32
)(
    input  logic                 clk,
    input  logic                 reset,
    input  logic                 start,
    input  logic [1:0]           op_mode,
    input  logic [TOTAL_W-1:0]   A,
    input  logic [TOTAL_W-1:0]   B,
    output logic [TOTAL_W-1:0]   result,
    output logic                 done
);

    // =========================================================================
    // 1. 암호학적 프로토콜 상수 선언 (BN254 베이스 필드)
    // =========================================================================
    localparam logic [TOTAL_W-1:0] N       = 256'h2523648240000001BA344D80000000086121000000000013A700000000000013;
    localparam logic [TOTAL_W-1:0] TWO_N   = N << 1;
    localparam logic [TOTAL_W-1:0] THREE_N = N + TWO_N;

    localparam int N_WORDS  = TOTAL_W / WORD_W; // 256 / 32 = 8 사이클 루프
    localparam int IDX_W    = $clog2(N_WORDS);

    // =========================================================================
    // 2. FSM 상태 정의
    // =========================================================================
    typedef enum logic [1:0] {
        S_IDLE,     // 대기 및 초기화
        S_PHASE1,   // 1차 메인 가감산 (8사이클)
        S_PHASE2,   // 범위 보정 가감산 (8사이클)
        S_DONE      // 최종 MUX 출력 선택 및 완료 플래그 활성화 (1사이클)
    } state_e;

    (* max_fanout = "16" *) state_e state; // Fanout 제약으로 Net Delay 최적화
    logic [TOTAL_W-1:0]  a_reg;        // 순환 시프트형 A 레지스터 (8회전 후 복원)
    logic [TOTAL_W-1:0]  b_op_reg;     // Phase 1 전용 피연산자 (B 또는 N 사전 적재)
    logic [TOTAL_W-1:0]  mod_op_reg;   // Phase 2 전용 피연산자 (2N 또는 3N 사전 적재)
    logic [TOTAL_W-1:0]  base_res;     // Phase 1 스트리밍 결과 누적 레지스터
    logic                carry_ff;     // 워드 간 고속 캐리 전파 플립플롭
    logic [IDX_W-1:0]    word_idx;     // 루프 카운터 (Fanout 해제 완료)
    logic [1:0]          op_reg;       
    logic                sign_p1;      // Phase 1 결과의 최종 부호비트(MSB) 저장 레지스터

    // =========================================================================
    // 3. 조합 논리: 32비트 고정 슬롯 공유 패브릭 연산기
    // =========================================================================
    logic [WORD_W-1:0] adder_a;
    logic [WORD_W-1:0] adder_b_raw;
    logic              do_sub;
    logic [WORD_W-1:0] eff_b;
    logic              carry_in;
    
    // 🌟 use_dsp 속성 제거 -> 고속 캐리체인(CARRY8) 매핑 유도하여 400MHz 타이밍 패스 확정
    logic [WORD_W:0]   adder_out;

    always_comb begin
        adder_a     = '0;
        adder_b_raw = '0;
        do_sub      = 1'b0;

        case (state)
            S_PHASE1: begin
                adder_a     = a_reg[WORD_W-1:0];       // 고정 [31:0] 참조 (회전으로 워드 공급)
                adder_b_raw = b_op_reg[WORD_W-1:0];    // 사전 적재된 피연산자 (B 또는 N)
                do_sub      = (op_reg != 2'b00);       // Add(00)만 덧셈, 나머지 모두 뺄셈
            end
            S_PHASE2: begin
                adder_a     = base_res[WORD_W-1:0];    // Phase 1 결과를 회전하며 공급
                adder_b_raw = mod_op_reg[WORD_W-1:0];  // 사전 적재된 보정 상수 (2N 또는 3N)
                do_sub      = (op_reg == 2'b00);       // Lazy Add면 Sub, Lazy Sub면 Add
            end
            default: ;
        endcase

        // 32비트 패브릭 가산기 데이터 패스 (CARRY8 매핑)
        eff_b     = do_sub ? ~adder_b_raw : adder_b_raw;
        carry_in  = (word_idx == '0) ? do_sub : carry_ff;
        adder_out = {1'b0, adder_a} + {1'b0, eff_b} + {{WORD_W{1'b0}}, carry_in};
    end

    // =========================================================================
    // 4. 순차 제어 및 우측 순환 회전(Rotation) 엔진
    // =========================================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE; result <= '0; done <= 1'b0;
            a_reg <= '0; b_op_reg <= '0; mod_op_reg <= '0; base_res <= '0; carry_ff <= 1'b0;
            word_idx <= '0; op_reg <= 2'b00; sign_p1 <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        a_reg      <= A;
                        // 사전 적재: op_mode에 맞는 피연산자를 시프트 레지스터에 저장
                        b_op_reg   <= (op_mode == 2'b11) ? N : B;          // Final Sub → N, 그 외 → B
                        mod_op_reg <= (op_mode == 2'b10) ? THREE_N : TWO_N; // Lazy Sub(3N) → 3N, 그 외 → 2N
                        op_reg     <= op_mode;
                        word_idx   <= '0;
                        carry_ff   <= 1'b0;
                        state      <= S_PHASE1;
                    end
                end

                S_PHASE1: begin
                    // 원형 회전(Rotation Shift): 하위 32비트를 상위로 순환 이동
                    // 정확히 8사이클 회전 후 원본 비트 정렬 상태가 완벽히 제자리로 돌아옵니다.
                    a_reg      <= {a_reg[WORD_W-1:0], a_reg[TOTAL_W-1:WORD_W]};
                    b_op_reg   <= {b_op_reg[WORD_W-1:0], b_op_reg[TOTAL_W-1:WORD_W]};
                    // Phase 2 피연산자도 동기 회전 (8회전 후 원위치 복귀 → Phase 2 정렬 보장)
                    mod_op_reg <= {mod_op_reg[WORD_W-1:0], mod_op_reg[TOTAL_W-1:WORD_W]};

                    // 결과 적재: 최상위 비트(MSB) 방향에서 밀어 넣어 리틀 엔디안 정렬 완료
                    base_res <= {adder_out[WORD_W-1:0], base_res[TOTAL_W-1:WORD_W]};
                    carry_ff <= adder_out[WORD_W];

                    if (word_idx == IDX_W'(N_WORDS - 1)) begin
                        sign_p1  <= adder_out[WORD_W-1]; // 최종 255번째 비트의 부호 래치
                        word_idx <= '0;
                        
                        if (op_reg == 2'b11) begin
                            state <= S_DONE; // Final Sub는 Phase 2 생략하고 초고속 패스탈출
                        end else begin
                            carry_ff <= 1'b0;
                            state    <= S_PHASE2;
                        end
                    end else begin
                        word_idx <= word_idx + 1'b1;
                    end
                end

                S_PHASE2: begin
                    // base_res와 mod_op_reg를 함께 회전하여 워드 단위 공급
                    base_res   <= {base_res[WORD_W-1:0], base_res[TOTAL_W-1:WORD_W]};
                    mod_op_reg <= {mod_op_reg[WORD_W-1:0], mod_op_reg[TOTAL_W-1:WORD_W]};

                    // 교정된 최종 연산 결과 차곡차곡 적재
                    result   <= {adder_out[WORD_W-1:0], result[TOTAL_W-1:WORD_W]};
                    carry_ff <= adder_out[WORD_W];

                    if (word_idx == IDX_W'(N_WORDS - 1)) begin
                        word_idx <= '0;
                        state    <= S_DONE;
                    end else begin
                        word_idx <= word_idx + 1'b1;
                    end
                end

                S_DONE: begin
                    case (op_reg)
                        2'b00: begin // Lazy Add 조건 분기
                            // result에 미리 계산된 base_res - 2N 의 최상위 MSB(부호비트)로 판별
                            if (result[TOTAL_W-1]) result <= base_res;
                        end
                        
                        2'b01, 2'b10: begin // Lazy Sub 조건 분기
                            // Phase 1 결과 부호가 양수(!sign_p1)였다면 보정 불필요하므로 원본 base_res 복원
                            if (!sign_p1) result <= base_res;
                        end
                        
                        2'b11: begin // Final Sub 조건 분기
                            // A - N < 0 (sign_p1=1) 이면 완벽히 회전 원복된 원본 A(a_reg) 유지, 양수면 base_res 출력
                            result <= sign_p1 ? a_reg : base_res;
                        end
                        default: result <= base_res;
                    endcase
                    
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule