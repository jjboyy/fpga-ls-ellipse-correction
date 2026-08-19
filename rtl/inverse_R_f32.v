module inverse_R_f32 #(
    parameter N = 5,
    parameter F32_WIDTH = 32
)(
    input clk,
    input rst_n,
    input start,
	input LS_done,
    // 下三角矩阵输入（已展开）
    input [F32_WIDTH-1:0] L00, L10, L20, L30, L40,
                            L11, L21, L31, L41,
                            L22, L32, L42,
                            L33, L43,
                            L44,
    // 输出结果
	
	output reg [F32_WIDTH-1:0] S00, S10, S20, S30, S40,
								 S11, S21, S31, S41,
								 S22, S32, S42,
								 S33, S43,
								 S44, 
								 
	output reg [F32_WIDTH-1:0] 
		R00, R01, R02, R03, R04,
		R10, R11, R12, R13, R14,
		R20, R21, R22, R23, R24,
		R30, R31, R32, R33, R34,
		R40, R41, R42, R43, R44,
    output reg inverse_done
);

//=======================
// 内部信号定义
//=======================
reg [3:0] state;
parameter IDLE = 0;
parameter LOAD_INPUT = 1;
parameter CALC_DIAG = 2;
parameter CALC_OFFDIAG_INIT = 3;
parameter CALC_SUM_LOOP = 4;
parameter DIV_NEG = 5;
parameter S_CAL_DONE = 6;
parameter CALC_ST = 7;           // 计算 S^T
parameter CALC_R_INV_INIT = 8;   // 初始化 R_inv 计算
parameter CALC_R_INV_SUM = 9;    // 计算 R_inv[i][j] 的累加
parameter R_INV_DONE = 10;       // 结束

reg [2:0] i, j, k;                 // 三层循环索引
integer ii, jj;
reg [F32_WIDTH-1:0] sum_term;   // 累加结果
reg [F32_WIDTH-1:0] L_mem [0:N-1][0:N-1];
reg [F32_WIDTH-1:0] S_mem [0:N-1][0:N-1];
reg [F32_WIDTH-1:0] ST_mem [0:N-1][0:N-1];
reg [F32_WIDTH-1:0] R_inv_mem [0:N-1][0:N-1];
reg [F32_WIDTH-1:0] accumulator;		// 累加器

reg mul_first_flag;	// 避免重复进入不需要的状态

// * 乘法 * //
reg fp_mul_start;
reg [31:0] fp_mul_a;			// f32
reg [31:0] fp_mul_b;			// f32
wire [31:0] fp_mul_result;		// f32
wire fp_mul_done;

reg fp_mul_start_r;
always @(posedge clk) begin
	fp_mul_start_r <= fp_mul_start;
end
assign fp_mul_start_pos = fp_mul_start & ~fp_mul_start_r;

reg fp_mul_done_dly;
always @(posedge clk) begin
	fp_mul_done_dly <= fp_mul_done;
end

fp_mul fp_mul_inst (
  .aclk							(clk				),                                  // input wire aclk
  .s_axis_a_tvalid				(1'b1				),            // input wire s_axis_a_tvalid
  .s_axis_a_tready				(					),            // output wire s_axis_a_tready
  .s_axis_a_tdata				(fp_mul_a			),              // input wire [31 : 0] s_axis_a_tdata
  .s_axis_b_tvalid				(fp_mul_start_pos	),            // input wire s_axis_b_tvalid
  .s_axis_b_tready				(					),            // output wire s_axis_b_tready
  .s_axis_b_tdata				(fp_mul_b			),              // input wire [31 : 0] s_axis_b_tdata
  .m_axis_result_tvalid			(fp_mul_done		),  // output wire m_axis_result_tvalid
  .m_axis_result_tready			(1'b1				),  // input wire m_axis_result_tready
  .m_axis_result_tdata			(fp_mul_result		)    // output wire [31 : 0] m_axis_result_tdata
);

// * 除法 * //
reg fp_div_start;
reg [31:0] fp_div_a;			// f32
reg [31:0] fp_div_b;			// f32
wire [31:0] fp_div_result;		// f32
wire fp_div_done;

reg fp_div_start_r;
always @(posedge clk) begin
	fp_div_start_r <= fp_div_start;
end
assign fp_div_start_pos = fp_div_start & ~fp_div_start_r;

reg fp_div_done_dly;
always @(posedge clk) begin
	fp_div_done_dly <= fp_div_done;
end

fp_div fp_div_inst (
  .aclk							(clk				),                                  // input wire aclk
  .s_axis_a_tvalid				(1'b1				),            // input wire s_axis_a_tvalid
  .s_axis_a_tready				(					),            // output wire s_axis_a_tready
  .s_axis_a_tdata				(fp_div_a			),              // input wire [31 : 0] s_axis_a_tdata
  .s_axis_b_tvalid				(fp_div_start_pos	),            // input wire s_axis_b_tvalid
  .s_axis_b_tready				(					),            // output wire s_axis_b_tready
  .s_axis_b_tdata				(fp_div_b			),              // input wire [31 : 0] s_axis_b_tdata
  .m_axis_result_tvalid			(fp_div_done		),  // output wire m_axis_result_tvalid
  .m_axis_result_tready			(1'b1				),        // input wire m_axis_result_tready
  .m_axis_result_tdata			(fp_div_result		)    // output wire [31 : 0] m_axis_result_tdata
);

// * 加减法 * //
reg fp_add_sub_start;
reg [31:0] fp_add_sub_a;			// f32
reg [31:0] fp_add_sub_b;			// f32
wire [31:0] fp_add_sub_result;		// f32
reg [31:0] fp_add_sub_result_dly;
reg [7:0] operation_tdata;			// 8位操作码 8'd0表示加法
wire fp_add_sub_done;

reg fp_add_sub_start_r;
always @(posedge clk) begin
	fp_add_sub_start_r <= fp_add_sub_start;
end
assign fp_add_sub_start_pos = fp_add_sub_start & ~fp_add_sub_start_r;

reg fp_add_sub_done_dly;
always @(posedge clk) begin
	fp_add_sub_done_dly <= fp_add_sub_done;
end

fp_add_sub fp_add_sub_inst (
  .aclk							(clk					),                                        // input wire aclk
  .s_axis_a_tvalid				(1'b1					),                  // input wire s_axis_a_tvalid
  .s_axis_a_tready				(						),                  // output wire s_axis_a_tready
  .s_axis_a_tdata				(fp_add_sub_a			),                    // input wire [31 : 0] s_axis_a_tdata
  .s_axis_b_tvalid				(fp_add_sub_start_pos	),                  // input wire s_axis_b_tvalid
  .s_axis_b_tready				(						),                  // output wire s_axis_b_tready
  .s_axis_b_tdata				(fp_add_sub_b			),                    // input wire [31 : 0] s_axis_b_tdata
  .s_axis_operation_tvalid		(1'b1					),  // input wire s_axis_operation_tvalid
  .s_axis_operation_tready		(						),  // output wire s_axis_operation_tready
  .s_axis_operation_tdata		(operation_tdata		),    // input wire [7 : 0] s_axis_operation_tdata
  .m_axis_result_tvalid			(fp_add_sub_done		),        // output wire m_axis_result_tvalid
  .m_axis_result_tready			(1'b1					),        // input wire m_axis_result_tready
  .m_axis_result_tdata			(fp_add_sub_result		)          // output wire [31 : 0] m_axis_result_tdata
);

//=======================
// 状态机控制
//=======================
always @(posedge clk or negedge rst_n) begin
	if(!rst_n || LS_done) begin
		state <= IDLE;
		inverse_done <= 0;
		fp_div_start <= 0;
		fp_add_sub_start <= 0;
		fp_mul_start <= 0;
		mul_first_flag <= 1;
		accumulator <= 0;
		
		S_mem[0][1] <= 0;S_mem[0][2] <= 0;S_mem[0][3] <= 0;S_mem[0][4] <= 0;
		S_mem[1][2] <= 0;S_mem[1][3] <= 0;S_mem[1][4] <= 0;
		S_mem[2][3] <= 0;S_mem[2][4] <= 0;
		S_mem[3][4] <= 0;
		
		ST_mem[0][1] <= 0;ST_mem[0][2] <= 0;ST_mem[0][3] <= 0;ST_mem[0][4] <= 0;
		ST_mem[1][2] <= 0;ST_mem[1][3] <= 0;ST_mem[1][4] <= 0;
		ST_mem[2][3] <= 0;ST_mem[2][4] <= 0;
		ST_mem[3][4] <= 0;
	end
	else begin
		case(state)
			//--------------------------------0
			IDLE: begin
				if(start) begin
					i <= 0;
					inverse_done <= 0;
					state <= LOAD_INPUT;
				end
			end
			
			//--------------------------------1
			LOAD_INPUT: begin
				// 下三角矩阵赋值
				L_mem[0][0] <= L00;
				L_mem[1][0] <= L10;  L_mem[1][1] <= L11;
				L_mem[2][0] <= L20;  L_mem[2][1] <= L21;  L_mem[2][2] <= L22;
				L_mem[3][0] <= L30;  L_mem[3][1] <= L31;  L_mem[3][2] <= L32;  L_mem[3][3] <= L33;
				L_mem[4][0] <= L40;  L_mem[4][1] <= L41;  L_mem[4][2] <= L42;  L_mem[4][3] <= L43;  L_mem[4][4] <= L44;

				i <= 0;
				j <= 0;
				k <= 0;
				state <= CALC_DIAG;
			end
			
			//--------------------------------2
			CALC_DIAG: begin
				// S(i,i) = 1 / L(i,i)
				// 调用浮点除法器，例如 fp_div(dividend=1.0, divisor=L_mem[i][i])	S_mem[i][i] <= fp_div(32'h3F800000, L_mem[i][i]); // 1.0 / L(i,i)
				if (!fp_div_start) begin
					fp_div_start <= 1;
					fp_div_a <= 32'h3F800000;
					fp_div_b <= L_mem[i][i];
				end
				else if (fp_div_done_dly) begin
					fp_div_start <= 0;
					S_mem[i][i] <= fp_div_result;
					if(i == N-1) begin
						i <= 1; j <= 0; k <= 0;
						state <= CALC_OFFDIAG_INIT;
					end else begin
						i <= i + 1;
					end
				end

			end
			//--------------------------------3
			CALC_OFFDIAG_INIT: begin
				accumulator <= 0;
				if(i < N) begin
					if(j < i) begin
						sum_term <= 0;
						k <= j;
						state <= CALC_SUM_LOOP;
					end else begin
						i <= i + 1;
						j <= 0;
					end
				end else begin
					state <= S_CAL_DONE;
				end
			end
			//--------------------------------4
			CALC_SUM_LOOP: begin
				// sum_term += L(i,k)*S(k,j) sum_term <= sum_term + fp_mult(L_mem[i][k], S_mem[k][j]);
				
				if (!fp_mul_start && mul_first_flag) begin
					fp_mul_start <= 1;
					fp_mul_a <= L_mem[i][k];
					fp_mul_b <= S_mem[k][j];
				end
				else if (fp_mul_done_dly && mul_first_flag) begin
					fp_mul_start <= 0;
					fp_add_sub_a <= accumulator;
					fp_add_sub_b <= fp_mul_result;
					operation_tdata <= 8'd0;	// 加法
					fp_add_sub_start <= 1;
					mul_first_flag <= 0;
				end
				else if (fp_add_sub_done_dly) begin
					mul_first_flag <= 1;
					fp_add_sub_start <= 0;
					accumulator <= fp_add_sub_result;
					if(k == i-1) begin
						state <= DIV_NEG;
					end else begin
						k <= k + 1;
					end
				end
			end
			//--------------------------------5
			DIV_NEG: begin
				// S(i,j) = -sum_term / L(i,i) S_mem[i][j] <= fp_div(-sum_term, L_mem[i][i]);
				
				if (!fp_div_start) begin
					fp_div_start <= 1;
					fp_div_a <= {~accumulator[31], accumulator[30:0]};  	// f32取负数
					fp_div_b <= L_mem[i][i];
				end
				else if (fp_div_done_dly) begin
					fp_div_start <= 0;
					S_mem[i][j] <= fp_div_result;
					if(j == i-1) begin
						i <= i + 1;
						j <= 0;
					end else begin
						j <= j + 1;
					end
					state <= CALC_OFFDIAG_INIT;
				end
			end
			//--------------------------------6
			S_CAL_DONE: begin
				// inverse_done <= 1;
				state <= CALC_ST;
			end
			//--------------------------------7
			CALC_ST: begin
				// 构造 ST[i][j] = S[j][i]
				for (ii = 0; ii < N; ii = ii + 1) begin
					for (jj = 0; jj < N; jj = jj + 1) begin
						ST_mem[ii][jj] <= S_mem[jj][ii];
					end
				end
				// 初始化循环索引
				i <= 0;
				j <= 0;
				k <= 0;
				state <= CALC_R_INV_INIT;
			end

			//--------------------------------8
			CALC_R_INV_INIT: begin
				// 初始化 R_inv[i][j] = 0
				accumulator <= 32'h0;  // +0.0
				if (i < N) begin
					if (j < N) begin
						state <= CALC_R_INV_SUM;
						k <= 0;
					end else begin
						i <= i + 1;
						j <= 0;
						state <= CALC_R_INV_INIT;
					end
				end else begin
					state <= R_INV_DONE;
				end
			end

			//--------------------------------9
			CALC_R_INV_SUM: begin
				// R_inv[i][j] += ST_mem[i][k] * S_mem[k][j]
				// 即：R_inv[i][j] += S[k][i] * S[k][j]

				if (!fp_mul_start && mul_first_flag) begin
					fp_mul_start <= 1;
					fp_mul_a <= ST_mem[i][k];     // S[i][k]
					fp_mul_b <= S_mem[k][j];      // S[k][j]
				end
				else if (fp_mul_done_dly && mul_first_flag) begin
					fp_mul_start <= 0;
					fp_add_sub_a <= accumulator;
					fp_add_sub_b <= fp_mul_result;
					operation_tdata <= 8'd0;  // 加法
					fp_add_sub_start <= 1;
					mul_first_flag <= 0;
				end
				else if (fp_add_sub_done_dly) begin
					mul_first_flag <= 1;
					fp_add_sub_start <= 0;
					accumulator <= fp_add_sub_result;
					if (k == N-1) begin
						// 累加完成，保存结果
						R_inv_mem[i][j] <= fp_add_sub_result;
						if (j == N-1) begin
							i <= i + 1;
							j <= 0;
						end else begin
							j <= j + 1;
						end
						state <= CALC_R_INV_INIT;
					end else begin
						k <= k + 1;
					end
				end
			end

			//--------------------------------10
			R_INV_DONE: begin
				inverse_done <= 1;  // 可保持原信号，或新增 done 信号
			end
		endcase
	end
end

//=======================
// 输出赋值
//=======================
always @(*) begin
	{S00,S10,S20,S30,S40,
	 S11,S21,S31,S41,
	 S22,S32,S42,
	 S33,S43,S44} =
	 {S_mem[0][0], S_mem[1][0], S_mem[2][0], S_mem[3][0], S_mem[4][0],
	  S_mem[1][1], S_mem[2][1], S_mem[3][1], S_mem[4][1],
	  S_mem[2][2], S_mem[3][2], S_mem[4][2],
	  S_mem[3][3], S_mem[4][3], S_mem[4][4]};
	  
	
end
  
always @(*) begin
    {R00, R01, R02, R03, R04,
     R10, R11, R12, R13, R14,
     R20, R21, R22, R23, R24,
     R30, R31, R32, R33, R34,
     R40, R41, R42, R43, R44} =
    {R_inv_mem[0][0], R_inv_mem[0][1], R_inv_mem[0][2], R_inv_mem[0][3], R_inv_mem[0][4],
     R_inv_mem[1][0], R_inv_mem[1][1], R_inv_mem[1][2], R_inv_mem[1][3], R_inv_mem[1][4],
     R_inv_mem[2][0], R_inv_mem[2][1], R_inv_mem[2][2], R_inv_mem[2][3], R_inv_mem[2][4],
     R_inv_mem[3][0], R_inv_mem[3][1], R_inv_mem[3][2], R_inv_mem[3][3], R_inv_mem[3][4],
     R_inv_mem[4][0], R_inv_mem[4][1], R_inv_mem[4][2], R_inv_mem[4][3], R_inv_mem[4][4]};
end 

endmodule
