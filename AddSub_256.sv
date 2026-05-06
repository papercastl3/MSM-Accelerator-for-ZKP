`timescale 1ns/1ps

/**
 * 모듈명: AddSub_256 (Multi-Cycle Word-Serial Version)
 * 설계 의도: 256비트 병렬 연산기를 WORD_W비트 단위 멀티사이클 구조로 변경하여
 *           LUT 및 Carry Chain 면적을 약 1/(TOTAL_W/WORD_W) 수준으로 대폭 축소.
 *           단 1개의 WORD_W비트 공유 덧셈기로 모든 연산을 수행.
 *
 * 연산 모드:
 * - 2'b00: Lazy Addition  (A + B mod 2N)
 * - 2'b01: Lazy Subtraction (A - B mod 2N)
 * - 2'b10: Final Subtraction (A mod N)
 *
 * 파라미터:
 * - TOTAL_W: 전체 비트 폭 (기본 256)
 * - WORD_W:  Word 단위 비트 폭 (기본 64). 변경 시 면적/사이클 트레이드오프 조절 가능.
 *            예) 32 → LUT 1/8, 16 사이클  |  128 → LUT 1/2, 4 사이클
 *
 * 레이턴시 (WORD_W=64, N_WORDS=4 기준):
 * - Lazy Add/Sub: 2*N_WORDS + 2 = 10 사이클 (래치 1 + Phase1 4 + Phase2 4 + MUX 1)
 * - Final Sub:    N_WORDS + 2   = 6 사이클  (래치 1 + Phase1 4 + MUX 1, Phase2 Bypass)
 */
module AddSub_256 #(
    parameter int TOTAL_W = 256,
    parameter int WORD_W  = 64
)(
    input  logic                clk,
    input  logic                reset,
    input  logic                start,
    input  logic [1:0]          op_mode,
    input  logic [TOTAL_W-1:0]  A,
    input  logic [TOTAL_W-1:0]  B,
    output logic [TOTAL_W-1:0]  result,
    output logic                done
);

    // =========================================================================
    // 상수 및 파라미터
    // =========================================================================
    localparam logic [TOTAL_W-1:0] N     = 256'h2523648240000001BA344D80000000086121000000000013A700000000000013;
    localparam logic [TOTAL_W-1:0] TWO_N = N << 1;

    localparam int N_WORDS  = TOTAL_W / WORD_W;
    localparam int IDX_W    = $clog2(N_WORDS);

    // =========================================================================
    // FSM 상태 정의
    // =========================================================================
    typedef enum logic [1:0] {
        S_IDLE,     // 대기, start 시 입력 래치
        S_PHASE1,   // 1차 가감산 (Word-Serial, N_WORDS 사이클)
        S_PHASE2,   // 범위 보정  (Word-Serial, N_WORDS 사이클, Final Sub 시 Bypass)
        S_DONE      // 최종 MUX 선택 + done (1 사이클)
    } state_e;

    // =========================================================================
    // 내부 레지스터
    // =========================================================================
    state_e              state;
    logic [TOTAL_W-1:0]  a_reg;       // 입력 A 백업 (Final Sub 원본 복원용)
    logic [TOTAL_W-1:0]  b_reg;       // 입력 B 백업 (Word-Serial 액세스용)
    logic [TOTAL_W-1:0]  base_res;    // Phase 1 결과 누적
    logic                carry_ff;    // Word 간 캐리 전파 레지스터
    logic [IDX_W-1:0]    word_idx;    // 현재 처리 중인 Word 인덱스
    logic [1:0]          op_reg;      // 연산 모드 래치
    logic                sign_p1;     // Phase 1 최종 MSB (Lazy Sub 판별용, Phase 2에서도 보존)

    // =========================================================================
    // 조합 논리: WORD_W비트 공유 덧셈기 (Shared Adder)
    // =========================================================================
    logic [WORD_W-1:0] adder_a;
    logic [WORD_W-1:0] adder_b_raw;
    logic              do_sub;
    logic [WORD_W-1:0] eff_b;
    logic [WORD_W:0]   adder_out;
    logic              carry_in;

    always_comb begin
        adder_a     = '0;
        adder_b_raw = '0;
        do_sub      = 1'b0;

        case (state)
            S_PHASE1: begin
                adder_a = a_reg[word_idx*WORD_W +: WORD_W];
                case (op_reg)
                    2'b00: begin
                        adder_b_raw = b_reg[word_idx*WORD_W +: WORD_W];
                        do_sub      = 1'b0;
                    end
                    2'b01: begin
                        adder_b_raw = b_reg[word_idx*WORD_W +: WORD_W];
                        do_sub      = 1'b1;
                    end
                    2'b10: begin
                        adder_b_raw = N[word_idx*WORD_W +: WORD_W];
                        do_sub      = 1'b1;
                    end
                    default: begin
                        adder_b_raw = b_reg[word_idx*WORD_W +: WORD_W];
                        do_sub      = 1'b0;
                    end
                endcase
            end
            S_PHASE2: begin
                adder_a     = base_res[word_idx*WORD_W +: WORD_W];
                adder_b_raw = TWO_N[word_idx*WORD_W +: WORD_W];
                do_sub      = (op_reg == 2'b00);  // Lazy Add: -2N, Lazy Sub: +2N
            end
            default: ;
        endcase

        eff_b    = do_sub ? ~adder_b_raw : adder_b_raw;
        carry_in = (word_idx == '0) ? do_sub : carry_ff;
        adder_out = {1'b0, adder_a} + {1'b0, eff_b} + {{WORD_W{1'b0}}, carry_in};
    end

    // =========================================================================
    // 메인 제어 로직 (Sequential Logic)
    // =========================================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state    <= S_IDLE;
            result   <= '0;
            done     <= 1'b0;
            a_reg    <= '0;
            b_reg    <= '0;
            base_res <= '0;
            carry_ff <= 1'b0;
            word_idx <= '0;
            op_reg   <= 2'b00;
            sign_p1  <= 1'b0;
        end else begin
            case (state)
                // ---------------------------------------------------------
                // S_IDLE: 대기, start=1 감지 시 입력 래치 후 Phase 1 진입
                // ---------------------------------------------------------
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        a_reg    <= A;
                        b_reg    <= B;
                        op_reg   <= op_mode;
                        word_idx <= '0;
                        carry_ff <= 1'b0;
                        state    <= S_PHASE1;
                    end
                end

                // ---------------------------------------------------------
                // S_PHASE1: 1차 가감산을 Word 단위로 순차 수행 (N_WORDS 사이클)
                // ---------------------------------------------------------
                S_PHASE1: begin
                    base_res[word_idx*WORD_W +: WORD_W] <= adder_out[WORD_W-1:0];
                    carry_ff <= adder_out[WORD_W];

                    if (word_idx == IDX_W'(N_WORDS - 1)) begin
                        // Phase 1 완료: 마지막 Word의 MSB = 부호 비트
                        sign_p1  <= adder_out[WORD_W-1];
                        word_idx <= '0;

                        if (op_reg == 2'b10) begin
                            // Final Sub: Phase 2 Bypass → 바로 S_DONE
                            state <= S_DONE;
                        end else begin
                            // Lazy Add/Sub: Phase 2 진입
                            carry_ff <= 1'b0;
                            state    <= S_PHASE2;
                        end
                    end else begin
                        word_idx <= word_idx + 1'b1;
                    end
                end

                // ---------------------------------------------------------
                // S_PHASE2: 범위 보정을 Word 단위로 순차 수행 (N_WORDS 사이클)
                //   Lazy Add(00): base_res - 2N → result에 저장
                //   Lazy Sub(01): base_res + 2N → result에 저장
                //   sign_p1은 덮어쓰지 않고 보존 (Lazy Sub MUX 판별에 사용)
                // ---------------------------------------------------------
                S_PHASE2: begin
                    result[word_idx*WORD_W +: WORD_W] <= adder_out[WORD_W-1:0];
                    carry_ff <= adder_out[WORD_W];

                    if (word_idx == IDX_W'(N_WORDS - 1)) begin
                        word_idx <= '0;
                        state    <= S_DONE;
                    end else begin
                        word_idx <= word_idx + 1'b1;
                    end
                end

                // ---------------------------------------------------------
                // S_DONE: 최종 MUX 선택 + done 출력 (1 사이클)
                // ---------------------------------------------------------
                S_DONE: begin
                    case (op_reg)
                        2'b00: begin
                            // Lazy Add: corr = base_res - 2N (Phase 2에서 result에 저장됨)
                            // result의 MSB(=corr의 부호)로 판별
                            // corr < 0 (MSB=1) → base_res < 2N → base_res 사용
                            // corr >= 0 (MSB=0) → base_res >= 2N → corr 사용 (이미 result에 있음)
                            if (result[TOTAL_W-1]) result <= base_res;
                        end
                        2'b01: begin
                            // Lazy Sub: corr = base_res + 2N (Phase 2에서 result에 저장됨)
                            // Phase 1 부호(sign_p1)로 판별
                            // sign_p1=1 (음수) → corr 사용 (이미 result에 있음)
                            // sign_p1=0 (양수) → base_res 사용
                            if (!sign_p1) result <= base_res;
                        end
                        2'b10: begin
                            // Final Sub: Phase 2 Bypass
                            // sign_p1=1 (음수, A < N) → 원본 A 유지
                            // sign_p1=0 (양수, A >= N) → base_res(= A-N) 사용
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
