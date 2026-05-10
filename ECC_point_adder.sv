module ECC_point_adder(
    input  logic         clk,
    input  logic         reset,
    input  logic         start,
    input  logic [254:0] x1,
    input  logic [254:0] y1,
    input  logic [254:0] z1,
    input  logic [254:0] x2,
    input  logic [254:0] y2,
    input  logic [254:0] z2,
    output logic [254:0] x3,
    output logic [254:0] y3,
    output logic [254:0] z3,
    output logic         done
);
    // data input to mont_multiplier m0, m1, au
    logic [254:0] mul_input_0 [1:0]; //point coordinates
    logic [254:0] mul_input_1 [1:0];
    logic [255:0] au_input [1:0];

    // mont_mul, au control signal
    logic mont_mul_start [1:0];
    logic au_start;
    logic [1:0] au_op_mode;

    // output from mont_multiplier m1, m2, au
    logic [254:0] mont_mul_result [1:0];
    logic [255:0] au_result;
    logic mont_mul_done [1:0];
    logic au_done;

    // output save
    logic [254:0] temp_reg [6:0];

    logic [2:0] sub_phase; // for multi-step subtraction in stage 4 and final stage

    // state
    typedef enum logic [5:0] {
        S_IDLE, S_INIT, 
        MA_STAGE_0_MUL_INIT, MA_STAGE_0_MUL_WAIT, 
        MA_STAGE_1_MUL_INIT, MA_STAGE_1_MUL_WAIT, MA_STAGE_1_SUB_INIT, MA_STAGE_1_SUB_WAIT, 
        MA_STAGE_2_MUL_INIT, MA_STAGE_2_MUL_WAIT, MA_STAGE_2_SUB_INIT, MA_STAGE_2_SUB_WAIT,
        MA_STAGE_3_MUL_INIT, MA_STAGE_3_MUL_WAIT,
        MA_STAGE_4_MUL_INIT, MA_STAGE_4_MUL_WAIT, MA_STAGE_4_SUB_INIT, MA_STAGE_4_SUB_WAIT,
        MA_STAGE_5_MUL_INIT, MA_STAGE_5_MUL_WAIT, MA_STAGE_5_SUB_INIT, MA_STAGE_5_SUB_WAIT,
        MA_FINAL_SUB_INIT, MA_FINAL_SUB_WAIT,
        S_DONE
    } state_e;

    state_e state;

    // mont_mul units
    (* keep_hierarchy = "yes" *)
    mont_multiplier m0(
        .clk(clk),
        .reset(reset),
        .start(mont_mul_start[0]),
        .X(mul_input_0[0]),
        .Y(mul_input_1[0]),
        .result(mont_mul_result[0]),
        .done(mont_mul_done[0])
    );

    (* keep_hierarchy = "yes" *)
    mont_multiplier m1(
        .clk(clk),
        .reset(reset),
        .start(mont_mul_start[1]),
        .X(mul_input_0[1]),
        .Y(mul_input_1[1]),
        .result(mont_mul_result[1]),
        .done(mont_mul_done[1])
    );

    // Artithmetic unit (add and sub)
    (* keep_hierarchy = "yes" *)
    AddSub_256 au(
        .clk(clk),
        .reset(reset),
        .start(au_start),
        .op_mode(au_op_mode),
        .A(au_input[0]),
        .B(au_input[1]),
        .result(au_result),
        .done(au_done)
    );

    // State Transition , start signal for mont_mul and au, save output to temp_reg
    always_ff @(posedge clk) begin
        if (reset) begin
            // 리셋 시 초기화할 핵심 제어 신호들
            state <= S_IDLE;
            done <= 1'b0;
            sub_phase <= 3'b000;
            mont_mul_start[0] <= 1'b0;
            mont_mul_start[1] <= 1'b0;
            au_start <= 1'b0;
        end 
        else begin
            // 리셋이 아닐 때의 기본 동작 (펄스 신호들 0으로 원복)
            mont_mul_start[0] <= 1'b0;
            mont_mul_start[1] <= 1'b0;
            au_start <= 1'b0;
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    // start 신호가 들어오면 스테이트 머신 시작
                    // 여기서 doubling인지 addition인지 구분해야할듯 (doubling은 x1==x2 && y1==y2)
                    if (start) state <= MA_STAGE_0_MUL_INIT;
                end
                MA_STAGE_0_MUL_INIT: begin
                    // 몽고메리 곱셈 시작
                    mont_mul_start[0] <= 1'b1;
                    state<= MA_STAGE_0_MUL_WAIT;
                end
                MA_STAGE_0_MUL_WAIT: begin
                    // 만약 몽고메리 곱셈이 완료되었다면 
                    if(mont_mul_done[0] == 1'b1) begin
                        temp_reg[0] <= mont_mul_result[0]; // (z2)^2 저징
                        state<= MA_STAGE_1_MUL_INIT;
                    end
                end
                MA_STAGE_1_MUL_INIT: begin
                    // 몽고메리 곱셈 시작
                    mont_mul_start[0] <= 1'b1;
                    mont_mul_start[1] <= 1'b1;
                    state <= MA_STAGE_1_MUL_WAIT;
                end
                MA_STAGE_1_MUL_WAIT: begin
                    // 만약 몽고메리 곱셈이 완료되었다면 
                    if(mont_mul_done[0] == 1'b1 && mont_mul_done[1] == 1'b1) begin
                        state<= MA_STAGE_1_SUB_INIT;
                    end
                end
                MA_STAGE_1_SUB_INIT: begin
                    // 뺄셈 시작
                    au_start <= 1'b1;
                    state<= MA_STAGE_1_SUB_WAIT;
                end
                MA_STAGE_1_SUB_WAIT: begin
                    // start 신호는 1클럭만 유지되어야 하므로 다음 클럭에 0으로 만들어준다.
                    au_start <= 1'b0;
                    // 만약 뺄셈이 완료되었다면 
                    if(au_done == 1'b1) begin
                        temp_reg[1] <= mont_mul_result[0]; // (z2)^3 저장
                        temp_reg[2] <= mont_mul_result[1]; // U1 저장
                        temp_reg[3] <= au_result; // H 저장 (나중에 H^2, H^3 계산할 때 사용)
                        state<= MA_STAGE_2_MUL_INIT;
                    end
                end
                MA_STAGE_2_MUL_INIT: begin
                    // 몽고메리 곱셈 시작
                    mont_mul_start[0] <= 1'b1;
                    mont_mul_start[1] <= 1'b1;
                    state <= MA_STAGE_2_MUL_WAIT;
                end
                MA_STAGE_2_MUL_WAIT: begin
                    // 만약 몽고메리 곱셈이 완료되었다면 
                    if(mont_mul_done[0] == 1'b1 && mont_mul_done[1] == 1'b1) begin
                        state<= MA_STAGE_2_SUB_INIT;
                    end
                end
                MA_STAGE_2_SUB_INIT: begin
                    // 뺄셈 시작
                    au_start <= 1'b1;
                    state<= MA_STAGE_2_SUB_WAIT;
                end
                MA_STAGE_2_SUB_WAIT: begin
                    // start 신호는 1클럭만 유지되어야 하므로 다음 클럭에 0으로 만들어준다.
                    au_start <= 1'b0;
                    // 만약 뺄셈이 완료되었다면 
                    if(au_done == 1'b1) begin
                        temp_reg[1] <= mont_mul_result[0]; // S1 저장
                        temp_reg[4] <= mont_mul_result[1]; // H^2 저장
                        temp_reg[5] <= au_result; // r 저장
                        state<= MA_STAGE_3_MUL_INIT;
                    end
                end
                MA_STAGE_3_MUL_INIT: begin
                    sub_phase <= 3'b000; // H^3 계산
                    // 몽고메리 곱셈 시작
                    mont_mul_start[0] <= 1'b1;
                    mont_mul_start[1] <= 1'b1;
                    state <= MA_STAGE_3_MUL_WAIT;
                end
                MA_STAGE_3_MUL_WAIT: begin
                    // 만약 몽고메리 곱셈이 완료되었다면 
                    if(mont_mul_done[0] == 1'b1 && mont_mul_done[1] == 1'b1) begin
                        temp_reg[0] <= mont_mul_result[0]; // Z3 저장
                        temp_reg[6] <= mont_mul_result[1]; // H^3 저장
                        state<= MA_STAGE_4_MUL_INIT;
                    end
                end
                MA_STAGE_4_MUL_INIT: begin
                    // 몽고메리 곱셈 시작
                    sub_phase <= 3'b000;
                    mont_mul_start[0] <= 1'b1;
                    mont_mul_start[1] <= 1'b1;
                    state <= MA_STAGE_4_MUL_WAIT;
                end
                MA_STAGE_4_MUL_WAIT: begin
                    // 만약 몽고메리 곱셈이 완료되었다면 
                    if(mont_mul_done[0] == 1'b1 && mont_mul_done[1] == 1'b1) begin
                        state <= MA_STAGE_4_SUB_INIT;
                    end
                end
                MA_STAGE_4_SUB_INIT: begin
                    // 뺄셈 시작; 
                    au_start <= 1'b1;
                    state<= MA_STAGE_4_SUB_WAIT;
                end
                MA_STAGE_4_SUB_WAIT: begin
                    // start 신호는 1클럭만 유지되어야 하므로 다음 클럭에 0으로 만들어준다.
                    au_start <= 1'b0;
                    // 만약 뺄셈이 완료되었다면 
                    if(au_done == 1'b1) begin
                        case (sub_phase) 
                            3'b000: begin
                                temp_reg[2] <= au_result; // r^2 - H^3 저장
                                state <= MA_STAGE_4_SUB_INIT; // 다음 뺄셈을 위해 다시 뺄셈 스테이지로 이동
                                sub_phase <= 3'b001;
                            end
                            3'b001: begin
                                temp_reg[2] <= au_result; // r^2 - H^3 - V 저장
                                state <= MA_STAGE_4_SUB_INIT; // 다음 뺄셈을 위해 다시 뺄셈 스테이지로 이동
                                sub_phase <= 3'b010;
                            end
                            3'b010: begin
                                temp_reg[3] <= au_result; // X3 저장
                                state <= MA_STAGE_4_SUB_INIT; // 다음 뺄셈을 위해 다시 뺄셈 스테이지로 이동
                                sub_phase <= 3'b011;
                            end
                            3'b011: begin
                                state <= MA_STAGE_5_MUL_INIT; // 다음 스테이지로 이동
                            end
                        endcase
                    end
                end
                MA_STAGE_5_MUL_INIT: begin
                    // 몽고메리 곱셈 시작
                    mont_mul_start[0] <= 1'b1;
                    mont_mul_start[1] <= 1'b1;
                    state <= MA_STAGE_5_MUL_WAIT;
                end
                MA_STAGE_5_MUL_WAIT: begin
                    // 만약 몽고메리 곱셈이 완료되었다면
                    if(mont_mul_done[0] == 1'b1 && mont_mul_done[1] == 1'b1) begin
                        state <= MA_STAGE_5_SUB_INIT;
                    end 
                end
                MA_STAGE_5_SUB_INIT: begin
                    // 뺄셈 시작; 
                    au_start <= 1'b1;
                    state<= MA_STAGE_5_SUB_WAIT;
                end
                MA_STAGE_5_SUB_WAIT: begin
                    // start 신호는 1클럭만 유지되어야 하므로 다음 클럭에 0으로 만들어준다.
                    au_start <= 1'b0;
                    // 만약 뺄셈이 완료되었다면 
                    if(au_done == 1'b1) begin
                        temp_reg[1] <= au_result; // Y3 저장
                        state <= MA_FINAL_SUB_INIT; // 다음 뺄셈을 위해 다시 뺄셈 스테이지로 이동
                        sub_phase <= 3'b000;
                    end
                end
                MA_FINAL_SUB_INIT: begin
                    // 뺄셈 시작; 
                    au_start <= 1'b1;
                    state<= MA_FINAL_SUB_WAIT;
                end
                MA_FINAL_SUB_WAIT: begin
                    // start 신호는 1클럭만 유지되어야 하므로 다음 클럭에 0으로 만들어준다.
                    au_start <= 1'b0;
                    // 만약 뺄셈이 완료되었다면 
                    if(au_done == 1'b1) begin      
                        case (sub_phase) 
                            3'b000: begin
                                temp_reg[1] <= au_result; // Y3 저장
                                state <= MA_FINAL_SUB_INIT; // 다음 뺄셈을 위해 다시 뺄셈 스테이지로 이동
                                sub_phase <= 3'b001;
                            end
                            3'b001: begin
                                temp_reg[1] <= au_result; // Y3 저장
                                state <= MA_FINAL_SUB_INIT; // 다음 뺄셈을 위해 다시 뺄셈 스테이지로 이동
                                sub_phase <= 3'b010;
                            end
                            3'b010: begin
                                temp_reg[0] <= au_result; // Z3 저장
                                state <= MA_FINAL_SUB_INIT; // 다음 뺄셈을 위해 다시 뺄셈 스테이지로 이동
                                sub_phase <= 3'b011;
                            end
                            3'b011: begin
                                temp_reg[0] <= au_result; // Z3 저장
                                state <= MA_FINAL_SUB_INIT; // 다음 뺄셈을 위해 다시 뺄셈 스테이지로 이동
                                sub_phase <= 3'b100;
                            end
                            3'b100: begin
                                temp_reg[3] <= au_result; // X3 저장
                                state <= MA_FINAL_SUB_INIT; // 다음 뺄셈을 위해 다시 뺄셈 스테이지로 이동
                                sub_phase <= 3'b101;
                            end
                            3'b101: begin
                                temp_reg[3] <= au_result; // X3 저장
                                state <= S_DONE; 
                            end
                        endcase    
                    end
                end
                S_DONE: begin
                    done <= 1'b1;
                    sub_phase <= 3'b000;
                    x3 <= temp_reg[3];
                    y3 <= temp_reg[1];
                    z3 <= temp_reg[0]; 
                    state <= S_IDLE; // 완료 후 IDLE로 돌아감
                end
            endcase
        end
    end
    
    // data input Select
    // 점들은 몽고메리 도메인으로 변환되었다고 가정
    always_comb begin
        // Latch 방지를 위한 기본값 (필수)
        mul_input_0[0] = '0; 
        mul_input_1[0] = '0;
        mul_input_0[1] = '0; 
        mul_input_1[1] = '0;
        au_input[0]    = '0; 
        au_input[1]    = '0;
        au_op_mode     = 2'b00;
        case (state)
            MA_STAGE_0_MUL_INIT, MA_STAGE_0_MUL_WAIT: begin
                // m1: Z2 * Z2
                mul_input_0[0] = z2; 
                mul_input_1[0] = z2;
            end
            MA_STAGE_1_MUL_INIT, MA_STAGE_1_MUL_WAIT: begin
                // m1: Z2 * (Z2^2) -> Z2^3
                mul_input_0[0] = z2; 
                mul_input_1[0] = temp_reg[0];
                // m2: X1 * (Z2^2) -> U1
                mul_input_0[1] = x1; 
                mul_input_1[1] = temp_reg[0]; 
            end
            MA_STAGE_1_SUB_INIT, MA_STAGE_1_SUB_WAIT: begin
                // x2 - U1
                au_op_mode  = 2'b01; // Lazy Subtraction (뺄셈 결과가 음수면 + 2N)
                au_input[0] = x2;
                au_input[1] = mont_mul_result[1]; // U1
            end
            MA_STAGE_2_MUL_INIT, MA_STAGE_2_MUL_WAIT: begin
                // m1: Y1 * (Z2^3) -> S1
                mul_input_0[0] = y1; 
                mul_input_1[0] = temp_reg[1]; // (z2)^3
                // m2: H * H -> H^2
                mul_input_0[1] = temp_reg[3]; // H 
                mul_input_1[1] = temp_reg[3]; // H
            end
            MA_STAGE_2_SUB_INIT, MA_STAGE_2_SUB_WAIT: begin
                // y2 - S1
                au_op_mode = 2'b01; // Lazy_subtraction (뺄셈 결과가 음수면 + 2N)
                au_input[0] = y2;
                au_input[1] = mont_mul_result[0]; // S1
            end
            MA_STAGE_3_MUL_INIT, MA_STAGE_3_MUL_WAIT: begin
                // m1: z2 * H
                mul_input_0[0] = z2; // (z2)
                mul_input_1[0] = temp_reg[3]; // H
                // m2: H * (H)^2 -> H^3
                mul_input_0[1] = temp_reg[3]; // H 
                mul_input_1[1] = temp_reg[4]; // (H)^2
            end
            MA_STAGE_4_MUL_INIT, MA_STAGE_4_MUL_WAIT: begin
                // m1 : U1 * H^2
                mul_input_0[0] = temp_reg[2]; // U1
                mul_input_1[0] = temp_reg[4]; // (H)^2
                // m2 : r * r
                mul_input_0[1] = temp_reg[5]; // r
                mul_input_1[1] = temp_reg[5]; // r
            end
            MA_STAGE_4_SUB_INIT, MA_STAGE_4_SUB_WAIT: begin
                au_op_mode = 2'b10; // Lazy_subtraction (뺄셈 결과가 음수면 + 3N)
                case (sub_phase) 
                    3'b000: begin
                        // r^2 - H^3
                        au_input[0] = mont_mul_result[1]; // r^2 
                        au_input[1] = temp_reg[6]; // H^3 
                    end
                    3'b001: begin
                        // r^2 - H^3 - V
                        au_input[0] = temp_reg[2]; // r^2 - H^3
                        au_input[1] = mont_mul_result[0]; // V
                    end
                    3'b010: begin
                        // r^2 - H^3 - V - V
                        au_input[0] = temp_reg[2]; // // r^2 - H^3 - V
                        au_input[1] = mont_mul_result[0]; // V
                    end
                    3'b011: begin
                        // V - X3
                        au_input[0] = mont_mul_result[0]; // V
                        au_input[1] = temp_reg[3]; // X3
                    end
                endcase
            end
            MA_STAGE_5_MUL_INIT, MA_STAGE_5_MUL_WAIT: begin
                // m1 : S1 * H^3
                mul_input_0[0] = temp_reg[1]; // S1
                mul_input_1[0] = temp_reg[6]; // (H)^3
                // m2 : r * (V - X3)
                mul_input_0[1] = temp_reg[5]; // r
                mul_input_1[1] = au_result; // V - X3
            end
            MA_STAGE_5_SUB_INIT, MA_STAGE_5_SUB_WAIT: begin
                // Y_part - W
                au_op_mode = 2'b10; // Lazy_subtraction (뺄셈 결과가 음수면 + 3N)
                au_input[0] = mont_mul_result[1]; // Y_part
                au_input[1] = mont_mul_result[0]; // W
            end
            MA_FINAL_SUB_INIT, MA_FINAL_SUB_WAIT: begin
                au_op_mode = 2'b11; // Addition
                case (sub_phase) 
                    3'b000: begin
                        // Y3 mod N
                        au_input[0] = temp_reg[1]; // Y3
                        au_input[1] = '0;//0
                    end
                    3'b001: begin
                        // Y3 mod N
                        au_input[0] = temp_reg[1]; // Y3
                        au_input[1] = '0;//0
                    end
                    3'b010: begin
                        // Z3 mod N
                        au_input[0] = temp_reg[0]; // Z3
                        au_input[1] = '0;//0
                    end
                    3'b011: begin
                        // Z3 mod N
                        au_input[0] = temp_reg[0]; // Z3
                        au_input[1] = '0;//0
                    end
                    3'b100: begin
                        // X3 mod N
                        au_input[0] = temp_reg[3]; // X3
                        au_input[1] = '0;//0
                    end
                    3'b101: begin
                        // X3 mod N
                        au_input[0] = temp_reg[3]; // X3
                        au_input[1] = '0;//0
                    end
                endcase
            end
            default : begin
               mul_input_0[0] = '0; 
               mul_input_1[0] = '0;
               mul_input_0[1] = '0; 
               mul_input_1[1] = '0;
               au_input[0] = '0; 
               au_input[1] = '0; 
            end
        endcase
    end
endmodule