module para_f32_fix64q13 #(
    parameter F32_WIDTH = 32,      	// 32bit浮点数类型
    parameter FIXED_WIDTH = 64      // 64bit定点数类型，最高位为符号位，62-13为整数部分，12-0为小数部分
)
(
    input 								clk,                      
    input 								rst_n,                    
    input 								start,  
	input 								LS_done,  
    input wire [F32_WIDTH-1:0] 			x0,
	input wire [F32_WIDTH-1:0] 			y0,
    input wire [F32_WIDTH-1:0] 			r_hat,
	input wire [F32_WIDTH-1:0] 			alpha_hat,
	
	
    output reg signed [FIXED_WIDTH-1:0] x0_q13,
	output reg signed [FIXED_WIDTH-1:0] y0_q13, 
    output reg signed [FIXED_WIDTH-1:0] r_hat_q13,
	output reg signed [FIXED_WIDTH-1:0] alpha_hat_q13,     
    output reg signed [FIXED_WIDTH-1:0] cos_alpha_hat_de,
	output reg signed [FIXED_WIDTH-1:0] sin_alpha_hat,   
    output reg para_f32_fix64q13_DONE                       // 计算完成标志
);

// ================== f32转有符号64位定点数q13 IP核接口 ==================
reg f32_64q13_start;
reg [F32_WIDTH-1:0] f32_64q13_in; 				// float32
wire f32_64q13_done;
wire [FIXED_WIDTH-1:0] f32_64q13_out;			// 64Q13格式

reg f32_64q13_start_r;
always @(posedge clk) begin
	f32_64q13_start_r <= f32_64q13_start;
end
assign f32_64q13_start_pos = f32_64q13_start & ~f32_64q13_start_r;

f32_to_fix64q13 f32_to_fix64q13_inst (
	.aclk							(clk				),                                  // input wire aclk
	.s_axis_a_tvalid				(f32_64q13_start_pos),            // input wire s_axis_a_tvalid
	.s_axis_a_tready				(					),            // output wire s_axis_a_tready
	.s_axis_a_tdata					(f32_64q13_in		),              // input wire [31 : 0] s_axis_a_tdata
	.m_axis_result_tvalid			(f32_64q13_done		),  // output wire m_axis_result_tvalid
	.m_axis_result_tready			(1'b1				),  // input wire m_axis_result_tready
	.m_axis_result_tdata			(f32_64q13_out		)    // output wire [63 : 0] m_axis_result_tdata
);


// ================== 正余弦IP核接口 ==================
reg [48-1:0] alpha_hat_48bit;
reg [48-1:0] sin_cos_in;
reg sin_cos_start;
wire sin_cos_done;
wire [95:0] sin_cos_result;	

reg sin_cos_start_r;
always @(posedge clk) begin
	sin_cos_start_r <= sin_cos_start;
end
assign sin_cos_start_pos = sin_cos_start & ~sin_cos_start_r;

reg sin_cos_done_r;
always @(posedge clk) begin
	sin_cos_done_r  <= sin_cos_done;
end

sin_cos_alpha_hat sin_cos_alpha_hat_inst (
	.aclk							(clk				),                                // input wire aclk
	.s_axis_phase_tvalid			(sin_cos_start_pos	),  // input wire s_axis_phase_tvalid
	.s_axis_phase_tdata				(sin_cos_in			),    // input wire [47 : 0] s_axis_phase_tdata
	.m_axis_dout_tvalid				(sin_cos_done		),    // output wire m_axis_dout_tvalid
	.m_axis_dout_tdata				(sin_cos_result		)      // output wire [95 : 0] m_axis_dout_tdata
);

// 64Q13格式转换为48Q45格式
wire signed [FIXED_WIDTH-1:0] alpha_hat_48q45;
assign alpha_hat_48q45[47:45] = alpha_hat_q13[15:13];
assign alpha_hat_48q45[44:0]  = {alpha_hat_q13[12:0], 32'b0}; 

// 提取结果（48位Q46格式 --> 64位Q13格式）
wire [48-1:0] cos_out_48q46 = sin_cos_result[47:0];
wire [48-1:0] sin_out_48q46 = sin_cos_result[95:48];
wire [63:0] cos_out = {{49{sin_cos_result[47]}}, sin_cos_result[47:33]}; // 符号扩展 + 左移33位（Q46→Q13）
wire [63:0] sin_out = {{49{sin_cos_result[95]}}, sin_cos_result[95:81]};  // 符号扩展 + 左移33位（Q46→Q13）


// ================== 除法IP核接口 ==================
reg [FIXED_WIDTH-1:0]     divisor_reg;     // 除数
reg [FIXED_WIDTH-1:0]     dividend_reg;    // 被除数
reg div_start;
wire div_done;
wire [79:0] div_result;	
reg signed_flag;			// 一些标志位   

// 计算寄存器
reg signed [FIXED_WIDTH-1:0] alpha_num, alpha_num_temp, alpha_denom;

reg div_start_r;
always @(posedge clk) begin
	div_start_r <= div_start;
end
assign div_start_pos = div_start & ~div_start_r;

reg div_done_r;
always @(posedge clk) begin
	div_done_r  <= div_done;
end

fix64q13_div_fix64q13 fix64q13_div_fix64q13_inst (
	.aclk							(clk			),                                      // input wire aclk
	.s_axis_divisor_tvalid			(1'b1			),    // input wire s_axis_divisor_tvalid
	.s_axis_divisor_tdata			(divisor_reg	),      // input wire [63 : 0] s_axis_divisor_tdata
	.s_axis_dividend_tvalid			(div_start_pos	),  // input wire s_axis_dividend_tvalid
	.s_axis_dividend_tdata			(dividend_reg	),    // input wire [63 : 0] s_axis_dividend_tdata
	.m_axis_dout_tvalid				(div_done		),          // output wire m_axis_dout_tvalid
	.m_axis_dout_tdata				(div_result		)            // output wire [79 : 0] m_axis_dout_tdata
);
// 提取除法结果（64位Q13格式）
wire [FIXED_WIDTH-1:0] div_out = div_result[63:0];


// ************* 状态机定义 ************* //
parameter IDLE				= 4'd0;
parameter TRAN_X0			= 4'd1;
parameter TRAN_Y0			= 4'd2;
parameter TRAN_R			= 4'd3;
parameter TRAN_ALPHA		= 4'd4;
parameter CALC_COS_AND_SIN	= 4'd5;
parameter CALC_COS_DE		= 4'd6;
parameter DONE				= 4'd7;

reg [3:0] state, next_state;

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
		para_f32_fix64q13_DONE <= 0;
		signed_flag <= 0;
		// 默认关闭所有 start 信号
		f32_64q13_start <= 0;
		sin_cos_start <= 0;
		div_start <= 0;
    end else begin
	case (state)
		IDLE: begin
			if (start) begin
				next_state <= TRAN_X0;
			end
		end
		
		TRAN_X0: begin
			if (!f32_64q13_start) begin
				f32_64q13_start <= 1;
				f32_64q13_in <= x0;
			end
			else if (f32_64q13_done) begin
				f32_64q13_start <= 0;
				x0_q13 <= f32_64q13_out;
				state <= TRAN_Y0;
			end
		end
		
		TRAN_Y0: begin
			if (!f32_64q13_start) begin
				f32_64q13_start <= 1;
				f32_64q13_in <= y0;
			end
			else if (f32_64q13_done) begin
				f32_64q13_start <= 0;
				y0_q13 <= f32_64q13_out;
				state <= TRAN_R;
			end
		end
		
		TRAN_R: begin
			if (!f32_64q13_start) begin
				f32_64q13_start <= 1;
				f32_64q13_in <= r_hat;
			end
			else if (f32_64q13_done) begin
				f32_64q13_start <= 0;
				r_hat_q13 <= f32_64q13_out;
				state <= TRAN_ALPHA;
			end
		end
		
		TRAN_ALPHA: begin
			if (!f32_64q13_start) begin
				f32_64q13_start <= 1;
				f32_64q13_in <= alpha_hat;
			end
			else if (f32_64q13_done) begin
				f32_64q13_start <= 0;
				alpha_hat_q13 <= f32_64q13_out;
				state <= CALC_COS_AND_SIN;
			end
		end
		
		CALC_COS_AND_SIN: begin
			if (!sin_cos_start) begin
				sin_cos_in <= alpha_hat_48q45;
				sin_cos_start <= 1;
			end
			
			else if (sin_cos_done) begin
				sin_cos_start <= 0;
				if (!cos_out[63]) begin
					divisor_reg <= cos_out;
					signed_flag <= 0;
				end
				else begin
					divisor_reg <= -cos_out;
					signed_flag <= 1;
				end
				sin_alpha_hat <= sin_out;
				state <= CALC_COS_DE;
			end
		end
		
		CALC_COS_DE: begin
			if (!div_start) begin
				div_start <= 1;
				dividend_reg <= {50'd0,1'd1,13'd0};  // 1.0 in 64Q13
				divisor_reg <= divisor_reg;
			end
			
			else if (div_done) begin
				div_start <= 0;
				if (!signed_flag) cos_alpha_hat_de <= div_out;
				else cos_alpha_hat_de <= -div_out;
				state <= DONE;
			end
		end
		
		DONE: begin
			para_f32_fix64q13_DONE <= 1;
		end
	
	endcase

    end
end

endmodule