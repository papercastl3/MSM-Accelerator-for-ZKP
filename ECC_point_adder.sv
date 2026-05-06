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
    output logic [254:0] result,
    output logic         done
);
    // data input to mont_multiplier m1, m2
    logic [254:0] input_1 [1:0]; //point coordinates
    logic [254:0] input_2 [1:0];

    // mont_mul control signal
    logic mont_mul_start [1:0];

    // output from mont_multiplier m1, m2
    logic[254:0] mont_mul_result [1:0];
    logic mont_mul_done [1:0];

    // output save
    logic[254:0] reg [5:0];

    // state
    typedef enum logic [3:0] {
        S_IDLE, S_INIT, STAGE_0, STAGE_1, STAGE_2, STAGE_3, STAGE_4, STAGE_5, S_DONE
    } state_e;

    // mont_mul units
    mont_multiplier m1(
        .clk(clk),
        .reset(reset),
        .start(mont_mul_start[0]),
        .X(input_1[0]),
        .Y(input_2[0]),
        .result(mont_mul_result[0]),
        .done(mont_mul_done[0])
    );

    mont_multiplier m2(
        .clk(clk),
        .reset(reset),
        .start(mont_mul_start[1]),
        .X(input_1[1]),
        .Y(input_2[1]),
        .result(mont_mul_result[1]),
        .done(mont_mul_done[1])
    );
    
    // data input Select
    // 점들은 몽고메리 도메인으로 변환되었다고 가정
    always_comb begin
        for (int d = 0; d < 2; d++) begin
            input_1[d] = '0; input_1[d] = '0;
        end
        case (state)
            S_IDLE: begin
                
            end
            S_INIT: begin
                state <= S_RUNNING;
            end
            STAGE_0: begin
                //input
                input_1[0] = z2; 
                input_2[0] = z2;
            end
             STAGE_1: begin
                // mont_mul input
                input_1[0] = z2; 
                input_2[0] = reg[0]; //(z2)^2
                input_1[1] = x1; 
                input_2[1] = reg[0]; //(z2)^2
                // need subtracotor input

            end
            STAGE2: begin
                // mont_mul input
                input_1[0] = y1; 
                input_2[0] = reg[1]; //(z2)^3
                input_1[1] = reg[3]; // H 
                input_2[1] = reg[3]; // H
                // need subtracotor input
            end
            STAGE3: begin
                input_1[0] = z2; 
                input_2[0] = reg[0]; //(z2)^2
                input_1[1] = x1; 
                input_2[1] = reg[0]; //(z2)^2
                 // need subtracotor input
            end
            STAGE4: begin

            end
            DONE: begin
                done <= 1'b1;
            end

        endcase
        
    end

    // State Transition and control signal
    always_ff @(posedge clk) begin
        case (state)
            S_IDLE: begin
                done <= 1'b0;
                if (start) state <= S_INIT;
            end
            S_INIT: begin
                state <= S_RUNNING;
            end
            STAGE1: begin
                if(mont_mul_done[0]) begin
                    reg[0] <=mont_mul_result[0];
                end
            end
            STAGE2: begin

            end
            STAGE3: begin

            end
            STAGE4: begin

            end
            DONE: begin
                done <= 1'b1;
            end

        endcase

    end

    
endmodule