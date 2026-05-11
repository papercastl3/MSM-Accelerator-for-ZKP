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

    // ==========================================
    // 1. 메모리 맵 정의 (Memory Map)
    // ==========================================
    localparam M_X1 = 4'd0, M_Y1 = 4'd1, M_Z1 = 4'd2;
    localparam M_X2 = 4'd3, M_Y2 = 4'd4, M_Z2 = 4'd5;
    localparam M_T0 = 4'd6, M_T1 = 4'd7, M_T2 = 4'd8;
    localparam M_T3 = 4'd9, M_T4 = 4'd10, M_T5 = 4'd11, M_T6 = 4'd12;

    // ==========================================
    // 2. True Dual-Port BRAM 인스턴스
    // ==========================================
    (* ram_style = "block" *)
    logic [255:0] mem [0:15]; // 16 x 256-bit BRAM
    logic [3:0]   addra, addrb; 
    logic [255:0] dina, dinb; 
    logic         wea, web; 
    logic [255:0] douta, doutb; 

    // BRAM 동작: 클럭 상승 에지에서 쓰기/읽기 수행 (읽기 지연 1 Cycle)
    always_ff @(posedge clk) begin
        if (wea) mem[addra] <= dina;
        douta <= mem[addra];
    end
    always_ff @(posedge clk) begin
        if (web) mem[addrb] <= dinb;
        doutb <= mem[addrb];
    end

    // ==========================================
    // 3. 연산기 고정 입력 레지스터 (MUX 제거)
    // ==========================================
    logic [255:0] m0_x_reg, m0_y_reg;
    logic [255:0] m1_x_reg, m1_y_reg;
    logic [255:0] au_a_reg, au_b_reg;

    logic mont_mul_start [1:0];
    logic au_start;
    logic [1:0] au_op_mode;

    logic [254:0] mont_mul_result [1:0];
    logic [255:0] au_result;
    logic mont_mul_done [1:0];
    logic au_done;

    logic [2:0] sub_phase;

    // 하위 모듈 인스턴스화
    //(* keep_hierarchy = "yes" *)
    mont_multiplier m0(
        .clk(clk), .reset(reset), .start(mont_mul_start[0]),
        .X(m0_x_reg), .Y(m0_y_reg), .result(mont_mul_result[0]), .done(mont_mul_done[0])
    );

    //(* keep_hierarchy = "yes" *)
    mont_multiplier m1(
        .clk(clk), .reset(reset), .start(mont_mul_start[1]),
        .X(m1_x_reg), .Y(m1_y_reg), .result(mont_mul_result[1]), .done(mont_mul_done[1])
    );

    //(* keep_hierarchy = "yes" *)
    AddSub_256 au(
        .clk(clk), .reset(reset), .start(au_start), .op_mode(au_op_mode),
        .A(au_a_reg), .B(au_b_reg), .result(au_result), .done(au_done)
    );

    // ==========================================
    // 4. 주소 기반 FSM (BRAM 읽기 파이프라인 완벽 적용)
    // ==========================================
    
    typedef enum logic [6:0] {
        S_IDLE, S_LOAD_1, S_LOAD_2, S_LOAD_3,
        MA_STAGE_0_FETCH, MA_STAGE_0_WAIT_RAM, MA_STAGE_0_LATCH, MA_STAGE_0_WAIT,
        MA_STAGE_1_FETCH_1, MA_STAGE_1_FETCH_2, MA_STAGE_1_LATCH_1, MA_STAGE_1_LATCH_2, MA_STAGE_1_WAIT,
        MA_STAGE_1_SUB_FETCH, MA_STAGE_1_SUB_WAIT_RAM, MA_STAGE_1_SUB_LATCH, MA_STAGE_1_SUB_WAIT,
        MA_STAGE_2_FETCH_1, MA_STAGE_2_FETCH_2, MA_STAGE_2_LATCH_1, MA_STAGE_2_LATCH_2, MA_STAGE_2_WAIT,
        MA_STAGE_2_SUB_FETCH, MA_STAGE_2_SUB_WAIT_RAM, MA_STAGE_2_SUB_LATCH, MA_STAGE_2_SUB_WAIT,
        MA_STAGE_3_FETCH_1, MA_STAGE_3_FETCH_2, MA_STAGE_3_LATCH_1, MA_STAGE_3_LATCH_2, MA_STAGE_3_WAIT,
        MA_STAGE_4_FETCH_1, MA_STAGE_4_FETCH_2, MA_STAGE_4_LATCH_1, MA_STAGE_4_LATCH_2, MA_STAGE_4_WAIT,
        MA_STAGE_4_SUB_FETCH_0, MA_STAGE_4_SUB_WAIT_RAM_0, MA_STAGE_4_SUB_LATCH_0, MA_STAGE_4_SUB_WAIT_0,
        MA_STAGE_4_SUB_FETCH_1, MA_STAGE_4_SUB_WAIT_RAM_1, MA_STAGE_4_SUB_LATCH_1, MA_STAGE_4_SUB_WAIT_1,
        MA_STAGE_4_SUB_FETCH_2, MA_STAGE_4_SUB_WAIT_RAM_2, MA_STAGE_4_SUB_LATCH_2, MA_STAGE_4_SUB_WAIT_2,
        MA_STAGE_4_SUB_FETCH_3, MA_STAGE_4_SUB_WAIT_RAM_3, MA_STAGE_4_SUB_LATCH_3, MA_STAGE_4_SUB_WAIT_3,
        MA_STAGE_5_FETCH_1, MA_STAGE_5_FETCH_2, MA_STAGE_5_LATCH_1, MA_STAGE_5_LATCH_2, MA_STAGE_5_WAIT,
        MA_STAGE_5_SUB_FETCH, MA_STAGE_5_SUB_WAIT_RAM, MA_STAGE_5_SUB_LATCH, MA_STAGE_5_SUB_WAIT,
        MA_FINAL_SUB_FETCH, MA_FINAL_SUB_WAIT_RAM, MA_FINAL_SUB_LATCH, MA_FINAL_SUB_WAIT,
        S_OUTPUT_1, S_OUTPUT_WAIT_RAM, S_OUTPUT_2, S_OUTPUT_3, S_DONE
    } state_e;

    state_e state;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            done <= 1'b0;
            sub_phase <= 3'b000;
            mont_mul_start[0] <= 1'b0;
            mont_mul_start[1] <= 1'b0;
            au_start <= 1'b0;
            wea <= 1'b0; 
            web <= 1'b0;
        end else begin
            // 펄스 신호 초기화
            mont_mul_start[0] <= 1'b0;
            mont_mul_start[1] <= 1'b0;
            au_start <= 1'b0;
            wea <= 1'b0; web <= 1'b0;

            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) state <= S_LOAD_1;
                end
                
                // 외부 입력 적재
                S_LOAD_1: begin wea<=1; addra<=M_X1; dina<=x1; web<=1; addrb<=M_Y1; dinb<=y1; state<=S_LOAD_2; end
                S_LOAD_2: begin wea<=1; addra<=M_Z1; dina<=z1; web<=1; addrb<=M_X2; dinb<=x2; state<=S_LOAD_3; end
                S_LOAD_3: begin wea<=1; addra<=M_Y2; dina<=y2; web<=1; addrb<=M_Z2; dinb<=z2; state<=MA_STAGE_0_FETCH; end

                // ------------------ STAGE 0 ------------------
                MA_STAGE_0_FETCH: begin addra <= M_Z2; state <= MA_STAGE_0_WAIT_RAM; end
                MA_STAGE_0_WAIT_RAM: begin state <= MA_STAGE_0_LATCH; end
                MA_STAGE_0_LATCH: begin
                    m0_x_reg <= douta; m0_y_reg <= douta;
                    mont_mul_start[0] <= 1'b1;
                    state <= MA_STAGE_0_WAIT;
                end
                MA_STAGE_0_WAIT: begin
                    if (mont_mul_done[0]) begin
                        wea <= 1; addra <= M_T0; dina <= mont_mul_result[0]; // (Z2)^2
                        state <= MA_STAGE_1_FETCH_1;
                    end
                end

                // ------------------ STAGE 1 ------------------
                MA_STAGE_1_FETCH_1: begin
                    addra <= M_Z2; addrb <= M_T0; 
                    state <= MA_STAGE_1_FETCH_2;
                end
                MA_STAGE_1_FETCH_2: begin
                    addra <= M_X1; // 다음 사이클 읽기용 주소 세팅
                    state <= MA_STAGE_1_LATCH_1;
                end
                MA_STAGE_1_LATCH_1: begin
                    m0_x_reg <= douta; m0_y_reg <= doutb; // Z2, (Z2)^2 (FETCH_1 결과 수신)
                    m1_y_reg <= doutb; // (Z2)^2
                    state <= MA_STAGE_1_LATCH_2;
                end
                MA_STAGE_1_LATCH_2: begin
                    m1_x_reg <= douta; // X1 (FETCH_2 결과 수신)
                    mont_mul_start[0] <= 1; mont_mul_start[1] <= 1;
                    state <= MA_STAGE_1_WAIT;
                end
                MA_STAGE_1_WAIT: begin
                    if (mont_mul_done[0] && mont_mul_done[1]) begin
                        wea <= 1; addra <= M_T1; dina <= mont_mul_result[0]; // (Z2)^3
                        web <= 1; addrb <= M_T2; dinb <= mont_mul_result[1]; // U1
                        state <= MA_STAGE_1_SUB_FETCH;
                    end
                end
                MA_STAGE_1_SUB_FETCH: begin addra <= M_X2; addrb <= M_T2; state <= MA_STAGE_1_SUB_WAIT_RAM; end
                MA_STAGE_1_SUB_WAIT_RAM: begin state <= MA_STAGE_1_SUB_LATCH; end
                MA_STAGE_1_SUB_LATCH: begin
                    au_a_reg <= douta; au_b_reg <= doutb;
                    au_op_mode <= 2'b01; au_start <= 1;
                    state <= MA_STAGE_1_SUB_WAIT;
                end
                MA_STAGE_1_SUB_WAIT: begin
                    if (au_done) begin
                        wea <= 1; addra <= M_T3; dina <= au_result; // H
                        state <= MA_STAGE_2_FETCH_1;
                    end
                end

                // ------------------ STAGE 2 ------------------
                MA_STAGE_2_FETCH_1: begin
                    addra <= M_Y1; addrb <= M_T1; 
                    state <= MA_STAGE_2_FETCH_2;
                end
                MA_STAGE_2_FETCH_2: begin
                    addra <= M_T3; 
                    state <= MA_STAGE_2_LATCH_1;
                end
                MA_STAGE_2_LATCH_1: begin
                    m0_x_reg <= douta; m0_y_reg <= doutb; // Y1, (Z2)^3
                    state <= MA_STAGE_2_LATCH_2;
                end
                MA_STAGE_2_LATCH_2: begin
                    m1_x_reg <= douta; m1_y_reg <= douta; // H, H
                    mont_mul_start[0] <= 1; mont_mul_start[1] <= 1;
                    state <= MA_STAGE_2_WAIT;
                end
                MA_STAGE_2_WAIT: begin
                    if (mont_mul_done[0] && mont_mul_done[1]) begin
                        wea <= 1; addra <= M_T1; dina <= mont_mul_result[0]; // S1
                        web <= 1; addrb <= M_T4; dinb <= mont_mul_result[1]; // H^2
                        state <= MA_STAGE_2_SUB_FETCH;
                    end
                end
                MA_STAGE_2_SUB_FETCH: begin addra <= M_Y2; addrb <= M_T1; state <= MA_STAGE_2_SUB_WAIT_RAM; end
                MA_STAGE_2_SUB_WAIT_RAM: begin state <= MA_STAGE_2_SUB_LATCH; end
                MA_STAGE_2_SUB_LATCH: begin
                    au_a_reg <= douta; au_b_reg <= doutb;
                    au_op_mode <= 2'b01; au_start <= 1;
                    state <= MA_STAGE_2_SUB_WAIT;
                end
                MA_STAGE_2_SUB_WAIT: begin
                    if (au_done) begin
                        wea <= 1; addra <= M_T5; dina <= au_result; // r
                        state <= MA_STAGE_3_FETCH_1;
                    end
                end

                // ------------------ STAGE 3 ------------------
                MA_STAGE_3_FETCH_1: begin
                    addra <= M_Z2; addrb <= M_T3; 
                    state <= MA_STAGE_3_FETCH_2;
                end
                MA_STAGE_3_FETCH_2: begin
                    addrb <= M_T4; // H^2 (포트 B 사용)
                    state <= MA_STAGE_3_LATCH_1;
                end
                MA_STAGE_3_LATCH_1: begin
                    m0_x_reg <= douta; m0_y_reg <= doutb; // Z2, H
                    m1_x_reg <= doutb; // H
                    state <= MA_STAGE_3_LATCH_2;
                end
                MA_STAGE_3_LATCH_2: begin
                    m1_y_reg <= doutb; // H^2
                    mont_mul_start[0] <= 1; mont_mul_start[1] <= 1;
                    state <= MA_STAGE_3_WAIT;
                end
                MA_STAGE_3_WAIT: begin
                    if (mont_mul_done[0] && mont_mul_done[1]) begin
                        wea <= 1; addra <= M_T0; dina <= mont_mul_result[0]; // Z3
                        web <= 1; addrb <= M_T6; dinb <= mont_mul_result[1]; // H^3
                        state <= MA_STAGE_4_FETCH_1;
                    end
                end

                // ------------------ STAGE 4 ------------------
                MA_STAGE_4_FETCH_1: begin
                    addra <= M_T2; addrb <= M_T4; 
                    state <= MA_STAGE_4_FETCH_2;
                end
                MA_STAGE_4_FETCH_2: begin
                    addra <= M_T5; 
                    state <= MA_STAGE_4_LATCH_1;
                end
                MA_STAGE_4_LATCH_1: begin
                    m0_x_reg <= douta; m0_y_reg <= doutb; // U1, H^2
                    state <= MA_STAGE_4_LATCH_2;
                end
                MA_STAGE_4_LATCH_2: begin
                    m1_x_reg <= douta; m1_y_reg <= douta; // r, r
                    mont_mul_start[0] <= 1; mont_mul_start[1] <= 1;
                    state <= MA_STAGE_4_WAIT;
                end
                MA_STAGE_4_WAIT: begin
                    if (mont_mul_done[0] && mont_mul_done[1]) begin
                        wea <= 1; addra <= M_T4; dina <= mont_mul_result[0]; // V
                        web <= 1; addrb <= M_T2; dinb <= mont_mul_result[1]; // r^2
                        state <= MA_STAGE_4_SUB_FETCH_0;
                    end
                end
                
                // STAGE 4 다중 뺄셈
                MA_STAGE_4_SUB_FETCH_0: begin addra <= M_T2; addrb <= M_T6; state <= MA_STAGE_4_SUB_WAIT_RAM_0; end 
                MA_STAGE_4_SUB_WAIT_RAM_0: begin state <= MA_STAGE_4_SUB_LATCH_0; end
                MA_STAGE_4_SUB_LATCH_0: begin au_a_reg <= douta; au_b_reg <= doutb; au_op_mode <= 2'b10; au_start <= 1; state <= MA_STAGE_4_SUB_WAIT_0; end
                MA_STAGE_4_SUB_WAIT_0:  begin if (au_done) begin wea <= 1; addra <= M_T2; dina <= au_result; state <= MA_STAGE_4_SUB_FETCH_1; end end 

                MA_STAGE_4_SUB_FETCH_1: begin addra <= M_T2; addrb <= M_T4; state <= MA_STAGE_4_SUB_WAIT_RAM_1; end
                MA_STAGE_4_SUB_WAIT_RAM_1: begin state <= MA_STAGE_4_SUB_LATCH_1; end
                MA_STAGE_4_SUB_LATCH_1: begin au_a_reg <= douta; au_b_reg <= doutb; au_op_mode <= 2'b10; au_start <= 1; state <= MA_STAGE_4_SUB_WAIT_1; end
                MA_STAGE_4_SUB_WAIT_1:  begin if (au_done) begin wea <= 1; addra <= M_T2; dina <= au_result; state <= MA_STAGE_4_SUB_FETCH_2; end end 

                MA_STAGE_4_SUB_FETCH_2: begin addra <= M_T2; addrb <= M_T4; state <= MA_STAGE_4_SUB_WAIT_RAM_2; end
                MA_STAGE_4_SUB_WAIT_RAM_2: begin state <= MA_STAGE_4_SUB_LATCH_2; end
                MA_STAGE_4_SUB_LATCH_2: begin au_a_reg <= douta; au_b_reg <= doutb; au_op_mode <= 2'b10; au_start <= 1; state <= MA_STAGE_4_SUB_WAIT_2; end
                MA_STAGE_4_SUB_WAIT_2:  begin if (au_done) begin wea <= 1; addra <= M_T3; dina <= au_result; state <= MA_STAGE_4_SUB_FETCH_3; end end // X3 저장

                MA_STAGE_4_SUB_FETCH_3: begin addra <= M_T4; addrb <= M_T3; state <= MA_STAGE_4_SUB_WAIT_RAM_3; end
                MA_STAGE_4_SUB_WAIT_RAM_3: begin state <= MA_STAGE_4_SUB_LATCH_3; end
                MA_STAGE_4_SUB_LATCH_3: begin au_a_reg <= douta; au_b_reg <= doutb; au_op_mode <= 2'b10; au_start <= 1; state <= MA_STAGE_4_SUB_WAIT_3; end
                MA_STAGE_4_SUB_WAIT_3:  begin if (au_done) begin wea <= 1; addra <= M_T4; dina <= au_result; state <= MA_STAGE_5_FETCH_1; end end // W 저장

                // ------------------ STAGE 5 ------------------
                MA_STAGE_5_FETCH_1: begin
                    addra <= M_T1; addrb <= M_T6; 
                    state <= MA_STAGE_5_FETCH_2;
                end
                MA_STAGE_5_FETCH_2: begin
                    addra <= M_T5; addrb <= M_T4; 
                    state <= MA_STAGE_5_LATCH_1;
                end
                MA_STAGE_5_LATCH_1: begin
                    m0_x_reg <= douta; m0_y_reg <= doutb; // S1, H^3
                    state <= MA_STAGE_5_LATCH_2;
                end
                MA_STAGE_5_LATCH_2: begin
                    m1_x_reg <= douta; m1_y_reg <= doutb; // r, W
                    mont_mul_start[0] <= 1; mont_mul_start[1] <= 1;
                    state <= MA_STAGE_5_WAIT;
                end
                MA_STAGE_5_WAIT: begin
                    if (mont_mul_done[0] && mont_mul_done[1]) begin
                        wea <= 1; addra <= M_T1; dina <= mont_mul_result[0]; // S1*H^3
                        web <= 1; addrb <= M_T5; dinb <= mont_mul_result[1]; // r*W
                        state <= MA_STAGE_5_SUB_FETCH;
                    end
                end
                MA_STAGE_5_SUB_FETCH: begin addra <= M_T5; addrb <= M_T1; state <= MA_STAGE_5_SUB_WAIT_RAM; end
                MA_STAGE_5_SUB_WAIT_RAM: begin state <= MA_STAGE_5_SUB_LATCH; end
                MA_STAGE_5_SUB_LATCH: begin
                    au_a_reg <= douta; au_b_reg <= doutb;
                    au_op_mode <= 2'b10; au_start <= 1;
                    state <= MA_STAGE_5_SUB_WAIT;
                end
                MA_STAGE_5_SUB_WAIT: begin
                    if (au_done) begin
                        wea <= 1; addra <= M_T1; dina <= au_result; // Y3 저장
                        sub_phase <= 0;
                        state <= MA_FINAL_SUB_FETCH;
                    end
                end

                // ------------------ FINAL MOD N SUB ------------------
                MA_FINAL_SUB_FETCH: begin
                    case(sub_phase)
                        0, 1: addra <= M_T1; // Y3
                        2, 3: addra <= M_T0; // Z3
                        4, 5: addra <= M_T3; // X3
                        default: addra <= M_T1;
                    endcase
                    state <= MA_FINAL_SUB_WAIT_RAM;
                end
                MA_FINAL_SUB_WAIT_RAM: begin
                    state <= MA_FINAL_SUB_LATCH;
                end
                MA_FINAL_SUB_LATCH: begin
                    au_a_reg <= douta;
                    au_b_reg <= '0; 
                    au_op_mode <= 2'b11; au_start <= 1;
                    state <= MA_FINAL_SUB_WAIT;
                end
                MA_FINAL_SUB_WAIT: begin
                    if (au_done) begin
                        wea <= 1; dina <= au_result;
                        case(sub_phase)
                            0, 1: addra <= M_T1;
                            2, 3: addra <= M_T0;
                            4, 5: addra <= M_T3;
                            default: addra <= M_T1;
                        endcase
                        
                        if (sub_phase == 3'd5) begin
                            state <= S_OUTPUT_1; 
                        end else begin
                            sub_phase <= sub_phase + 1;
                            state <= MA_FINAL_SUB_FETCH;
                        end
                    end
                end

                // ------------------ DONE & OUTPUT ------------------
                S_OUTPUT_1: begin
                    addra <= M_T3; addrb <= M_T1; // X3, Y3 
                    state <= S_OUTPUT_WAIT_RAM;
                end
                S_OUTPUT_WAIT_RAM: begin
                    addra <= M_T0; // Z3 주소 세팅
                    state <= S_OUTPUT_2;
                end
                S_OUTPUT_2: begin
                    x3 <= douta; y3 <= doutb; // X3, Y3 출력
                    state <= S_OUTPUT_3;
                end
                S_OUTPUT_3: begin
                    z3 <= douta; // Z3 출력
                    done <= 1'b1;
                    state <= S_IDLE; 
                end
            endcase
        end
    end
endmodule