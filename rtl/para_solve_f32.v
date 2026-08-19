module para_solve_f32 #(
    parameter F32_WIDTH = 32      // 32bit浮点数类型
)
(
    input 								clk,                      
    input 								rst_n,                    
    input 								start,  
	input 								LS_done,  
    input wire [F32_WIDTH-1:0] a,       		// 输入参数 f32
	input wire [F32_WIDTH-1:0] b,
	input wire [F32_WIDTH-1:0] c,
	input wire [F32_WIDTH-1:0] d,
	input wire [F32_WIDTH-1:0] e,  	
	
    output reg [F32_WIDTH-1:0] x0,
	output reg [F32_WIDTH-1:0] y0,
    output reg [F32_WIDTH-1:0] r_hat,
	output reg [F32_WIDTH-1:0] alpha_hat,      
    output reg para_solve_f32_done                       // 计算完成标志
);


// ************* float计算需要IP核大集合 **************** //
// * 乘法 * //
reg f32_mul_start;
reg [31:0] f32_mul_a;			// f32
reg [31:0] f32_mul_b;			// f32
wire [31:0] f32_mul_result;		// f32
wire f32_mul_done;

reg f32_mul_start_r;
always @(posedge clk) begin
	f32_mul_start_r <= f32_mul_start;
end
assign f32_mul_start_pos = f32_mul_start & ~f32_mul_start_r;

reg f32_mul_done_dly;
always @(posedge clk) begin
	f32_mul_done_dly <= f32_mul_done;
end

f32_mul_f32 f32_mul_f32_inst (
  .aclk							(clk				),                                  // input wire aclk
  .s_axis_a_tvalid				(1'b1				),            // input wire s_axis_a_tvalid
  .s_axis_a_tready				(					),            // output wire s_axis_a_tready
  .s_axis_a_tdata				(f32_mul_a			),              // input wire [31 : 0] s_axis_a_tdata
  .s_axis_b_tvalid				(f32_mul_start_pos	),            // input wire s_axis_b_tvalid
  .s_axis_b_tready				(					),            // output wire s_axis_b_tready
  .s_axis_b_tdata				(f32_mul_b			),              // input wire [31 : 0] s_axis_b_tdata
  .m_axis_result_tvalid			(f32_mul_done		),  // output wire m_axis_result_tvalid
  .m_axis_result_tready			(1'b1				),  // input wire m_axis_result_tready
  .m_axis_result_tdata			(f32_mul_result		)    // output wire [31 : 0] m_axis_result_tdata
);

// * 除法 * //
reg f32_div_start;
reg [31:0] f32_div_a;			// f32
reg [31:0] f32_div_b;			// f32
wire [31:0] f32_div_result;		// f32
wire f32_div_done;

reg f32_div_start_r;
always @(posedge clk) begin
	f32_div_start_r <= f32_div_start;
end
assign f32_div_start_pos = f32_div_start & ~f32_div_start_r;

reg f32_div_done_dly;
always @(posedge clk) begin
	f32_div_done_dly <= f32_div_done;
end

f32_div f32_div_inst (
  .aclk							(clk				),                                  // input wire aclk
  .s_axis_a_tvalid				(1'b1				),            // input wire s_axis_a_tvalid
  .s_axis_a_tready				(					),            // output wire s_axis_a_tready
  .s_axis_a_tdata				(f32_div_a			),              // input wire [31 : 0] s_axis_a_tdata
  .s_axis_b_tvalid				(f32_div_start_pos	),            // input wire s_axis_b_tvalid
  .s_axis_b_tready				(					),            // output wire s_axis_b_tready
  .s_axis_b_tdata				(f32_div_b			),              // input wire [31 : 0] s_axis_b_tdata
  .m_axis_result_tvalid			(f32_div_done		),  // output wire m_axis_result_tvalid
  .m_axis_result_tready			(1'b1				),        // input wire m_axis_result_tready
  .m_axis_result_tdata			(f32_div_result		)    // output wire [31 : 0] m_axis_result_tdata
);

// * 加减法 * //
reg f32_add_sub_start;
reg [31:0] f32_add_sub_a;			// f32
reg [31:0] f32_add_sub_b;			// f32
wire [31:0] f32_add_sub_result;		// f32
reg [31:0] f32_add_sub_result_dly;
reg [7:0] operation_tdata;			// 8位操作码 8'd0表示加法
wire f32_add_sub_done;

reg f32_add_sub_start_r;
always @(posedge clk) begin
	f32_add_sub_start_r <= f32_add_sub_start;
end
assign f32_add_sub_start_pos = f32_add_sub_start & ~f32_add_sub_start_r;

reg f32_add_sub_done_dly;
always @(posedge clk) begin
	f32_add_sub_done_dly <= f32_add_sub_done;
end

f32_add_sub_f32 f32_add_sub_f32_inst (
  .aclk							(clk					),                                        // input wire aclk
  .s_axis_a_tvalid				(1'b1					),                  // input wire s_axis_a_tvalid
  .s_axis_a_tready				(						),                  // output wire s_axis_a_tready
  .s_axis_a_tdata				(f32_add_sub_a			),                    // input wire [31 : 0] s_axis_a_tdata
  .s_axis_b_tvalid				(f32_add_sub_start_pos	),                  // input wire s_axis_b_tvalid
  .s_axis_b_tready				(						),                  // output wire s_axis_b_tready
  .s_axis_b_tdata				(f32_add_sub_b			),                    // input wire [31 : 0] s_axis_b_tdata
  .s_axis_operation_tvalid		(1'b1					),  // input wire s_axis_operation_tvalid
  .s_axis_operation_tready		(						),  // output wire s_axis_operation_tready
  .s_axis_operation_tdata		(operation_tdata		),    // input wire [7 : 0] s_axis_operation_tdata
  .m_axis_result_tvalid			(f32_add_sub_done		),        // output wire m_axis_result_tvalid
  .m_axis_result_tready			(1'b1					),        // input wire m_axis_result_tready
  .m_axis_result_tdata			(f32_add_sub_result		)          // output wire [31 : 0] m_axis_result_tdata
);

// * 开方 * //
reg f32_sqrt_start;
reg [31:0] f32_sqrt_in;			// f32
wire [31:0] f32_sqrt_result;		// f32
wire f32_sqrt_done;

reg f32_sqrt_start_r;
always @(posedge clk) begin
	f32_sqrt_start_r <= f32_sqrt_start;
end
assign f32_sqrt_start_pos = f32_sqrt_start & ~f32_sqrt_start_r;

reg f32_sqrt_done_dly, f32_sqrt_done_dly2;
always @(posedge clk) begin
	f32_sqrt_done_dly <= f32_sqrt_done;
	f32_sqrt_done_dly2 <= f32_sqrt_done_dly;
end

f32_sqrt f32_sqrt_inst (
  .aclk							(clk				),                                  // input wire aclk
  .s_axis_a_tvalid				(f32_sqrt_start_pos	),            // input wire s_axis_a_tvalid
  .s_axis_a_tready				(					),            // output wire s_axis_a_tready
  .s_axis_a_tdata				(f32_sqrt_in		),              // input wire [31 : 0] s_axis_a_tdata
  .m_axis_result_tvalid			(f32_sqrt_done		),  // output wire m_axis_result_tvalid
  .m_axis_result_tready			(1'b1				),  // input wire m_axis_result_tready
  .m_axis_result_tdata			(f32_sqrt_result	)    // output wire [31 : 0] m_axis_result_tdata
);


// ************* 状态机定义 ************* //
parameter IDLE					= 4'd0;
parameter CALC_DEN_1			= 4'd1;
parameter CALC_DEN_2			= 4'd2;
parameter CALC_NUM_X_1			= 4'd3;
parameter CALC_NUM_X_2			= 4'd4;
parameter CALC_NUM_Y_1			= 4'd5;
parameter CALC_NUM_Y_2			= 4'd6;
parameter CALC_X0				= 4'd7;
parameter CALC_Y0				= 4'd8;
parameter CALC_R_HAT			= 4'd9;
parameter CALC_ALPHA_HAT		= 4'd10;
parameter DONE					= 4'd11;

reg [3:0] state, next_state;

// ************* 中间变量寄存器 ************* //
reg [31:0] den;           // 分母: a*a - 4*b
reg [31:0] num_x;         // 2*b*c - a*d
reg [31:0] num_y;         // 2*d - a*c
reg [31:0] r_hat_reg;     // sqrt(b)
reg [31:0] half_a;        // 0.5 * a

reg [31:0] add_sub_a;		// 临时存储变量
reg [31:0] add_sub_b;		// 临时存储变量
reg [2:0] mul_count;		// 乘法计算次数计数器
reg mul_first_flag;	// 避免重复进入不需要的状态

// ************* 常量定义 ************* //
localparam float_2 = 32'h40000000;   // 单精度浮点数 2.0
localparam float_4 = 32'h40800000;   // 单精度浮点数 4.0
localparam float_0p5 = 32'h3f000000; // 单精度浮点数 0.5

// ************* 状态机与时序逻辑 ************* //
always @(posedge clk or negedge rst_n) begin
    if (!rst_n || LS_done) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end

// 下一状态组合逻辑
always @(*) begin
    next_state = state;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n || LS_done) begin		
		mul_count <= 0;
		mul_first_flag <= 1;

		// 默认关闭所有 start 信号
		f32_mul_start = 0;
		f32_div_start = 0;
		f32_add_sub_start = 0;
		f32_sqrt_start = 0;
		operation_tdata = 8'd0; // 默认加法
		f32_add_sub_a <= 0;
		f32_add_sub_b <= 0;
    end else begin
    case (state)
        IDLE: begin		// 0
            if (start) begin
                next_state = CALC_DEN_1;
            end
        end

        // --- 步骤1: 计算 den = a*a - 4*b ---
        CALC_DEN_1: begin	// 1
            // 子步骤1.1: a*a
			if (!f32_mul_start) begin
				f32_mul_start = 1;
				f32_mul_a = a;
				f32_mul_b = a;
			end
			else if (f32_mul_done_dly) begin
				f32_mul_start <= 0;
				f32_add_sub_a <= f32_mul_result;
				state <= CALC_DEN_2;	
			end
        end

        CALC_DEN_2: begin	// 2
		
			if (!f32_mul_start && mul_first_flag) begin
				f32_mul_start = 1;
				f32_mul_a = float_4;
				f32_mul_b = b;
			end
			
			else if (f32_mul_done_dly && mul_first_flag) begin
				f32_mul_start <= 0;
				
				f32_add_sub_a <= f32_add_sub_a;
				f32_add_sub_b <= f32_mul_result;
				operation_tdata <= 8'd1;	// 减法
				f32_add_sub_start <= 1;
				mul_first_flag <= 0;
			end
			
			else if (f32_add_sub_done_dly) begin
				mul_first_flag <= 1;
				f32_add_sub_start <= 0;
				den <= f32_add_sub_result;
				state <= CALC_NUM_X_1;
			end
        end

        // --- 步骤2: 计算 num_x = 2*b*c - a*d ---
        CALC_NUM_X_1: begin	// 3
			if (!f32_mul_start) begin
				f32_mul_start <= 1;
				if (mul_count == 3'd0) begin
					f32_mul_a = float_2;
					f32_mul_b = b;
				end
				else if (mul_count == 3'd1) begin
					f32_mul_a = f32_mul_result;
					f32_mul_b = c;
				end
			end
			
			else if (f32_mul_done_dly && mul_count == 3'd0) begin
				f32_mul_start <= 0;
				mul_count <= mul_count + 1;
			end
			
			else if (f32_mul_done_dly && mul_count == 3'd1) begin
				f32_mul_start <= 0;
				f32_add_sub_a <= f32_mul_result;
				mul_count <= 0;
				state <= CALC_NUM_X_2;
			end
        end

        CALC_NUM_X_2: begin		// 4
			if (!f32_mul_start && mul_first_flag) begin
				f32_mul_start <= 1;
                f32_mul_a = a;
                f32_mul_b = d;
			end
			
			else if (f32_mul_done_dly && mul_first_flag) begin
				f32_mul_start <= 0;
				
				f32_add_sub_a <= f32_add_sub_a;
				f32_add_sub_b <= f32_mul_result;
				operation_tdata <= 8'd1;	// 减法
				f32_add_sub_start <= 1;
				mul_first_flag <= 0;
			end
			
			else if (f32_add_sub_done_dly) begin
				mul_first_flag <= 1;
				f32_add_sub_start <= 0;
				num_x <= f32_add_sub_result;
				state <= CALC_NUM_Y_1;
			end
        end

		// --- 步骤3: 计算 num_y = 2*d - a*c ---
        CALC_NUM_Y_1: begin		// 5
			if (!f32_mul_start) begin
				f32_mul_start <= 1;
                f32_mul_a = float_2;
                f32_mul_b = d;
			end
			
			else if (f32_mul_done_dly) begin
				f32_mul_start <= 0;
                f32_add_sub_a = f32_mul_result;
				state <= CALC_NUM_Y_2;
			end
        end

        CALC_NUM_Y_2: begin		// 6
			if (!f32_mul_start && mul_first_flag) begin
				f32_mul_start <= 1;
                f32_mul_a = a;
                f32_mul_b = c;
			end
			
			else if (f32_mul_done_dly && mul_first_flag) begin
				f32_mul_start <= 0;
				
				f32_add_sub_a <= f32_add_sub_a;
				f32_add_sub_b <= f32_mul_result;
				operation_tdata <= 8'd1;	// 减法
				f32_add_sub_start <= 1;
				mul_first_flag <= 0;
			end
			
			else if (f32_add_sub_done_dly) begin
				mul_first_flag <= 1;
				f32_add_sub_start <= 0;
				num_y <= f32_add_sub_result;
				state <= CALC_X0;
			end
        end

        CALC_X0: begin		// 7
			if (!f32_div_start) begin
				f32_div_start <= 1;
				f32_div_a <= num_x;
				f32_div_b <= den;
			end
			
			else if (f32_div_done_dly) begin
				f32_div_start <= 0;
				x0 <= f32_div_result;
				state <= CALC_Y0;
			end
        end

        CALC_Y0: begin		// 8
			if (!f32_div_start) begin
				f32_div_start <= 1;
				f32_div_a <= num_y;
				f32_div_b <= den;
			end
			
			else if (f32_div_done_dly) begin
				f32_div_start <= 0;
				y0 <= f32_div_result;
				state <= CALC_R_HAT;
			end
        end

        CALC_R_HAT: begin		// 9
			if (!f32_sqrt_start) begin
				f32_sqrt_start <= 1;
				f32_sqrt_in <= b;
			end
			else if (f32_sqrt_done_dly) begin
				f32_sqrt_start <= 0;
				r_hat <= f32_sqrt_result;
				state <= CALC_ALPHA_HAT;
			end
        end

        CALC_ALPHA_HAT: begin		// 10
			if (!f32_mul_start && mul_first_flag) begin
				f32_mul_start <= 1;
                f32_mul_a = float_0p5;
                f32_mul_b = a;
			end
			
			else if (f32_mul_done_dly && mul_first_flag) begin
				f32_mul_start <= 0;
				
				f32_div_a <= f32_mul_result;
				f32_div_b <= r_hat;
				f32_div_start <= 1;
				mul_first_flag <= 0;
			end
			
			else if (f32_div_done_dly) begin
				mul_first_flag <= 1;
				f32_div_start <= 0;
				alpha_hat <= f32_div_result;
				state <= DONE;
			end
        end

        DONE: begin		// 11
			para_solve_f32_done <= 1;
        end

    endcase
    end
end

// ************* 输出完成标志 ************* //
always @(posedge clk or negedge rst_n) begin
    if (!rst_n || LS_done) begin
        para_solve_f32_done <= 0;
    end else begin
        para_solve_f32_done <= (state == DONE);
    end
end

// ************* 初始化输出 ************* //
initial begin
    x0 = 0;
    y0 = 0;
    r_hat = 0;
    alpha_hat = 0;
    para_solve_f32_done = 0;
end

endmodule