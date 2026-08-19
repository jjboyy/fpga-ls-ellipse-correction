module R_inv_mul_P #(
    parameter N = 5,
    parameter F32_WIDTH = 32
)(
    input clk,
    input rst_n,
    input start,
	input LS_done,
    // R逆矩阵	
	input [F32_WIDTH-1:0] 
		R00, R01, R02, R03, R04,
		R10, R11, R12, R13, R14,
		R20, R21, R22, R23, R24,
		R30, R31, R32, R33, R34,
		R40, R41, R42, R43, R44,

	input [F32_WIDTH-1:0] P0, P1, P2, P3, P4,

    // 输出结果
	output reg [F32_WIDTH-1:0] X0, X1, X2, X3, X4,
    output reg Xcal_done
);

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

/****************************
		 X = R_inv × P
****************************/
// 输出结果向量
reg [31:0] R_inv_matrix [0:N-1][0:N-1]; // R逆矩阵
reg [31:0] sum_vector_p_f32 [0:N-1];
reg [31:0] X_vector [0:N-1];  // float32 X_vector[5]

// 控制变量
reg [2:0] i_Xcal;     // 行索引 i
reg [2:0] j_Xcal;     // 列索引 j
reg [2:0] k_Xcal;     // 索引 k
reg [31:0] accumulator_Xcal; // 累加器，用于每行的累加

reg mul_first_flag;		// 避免重复乘法

// 状态机定义（矩阵乘法）
parameter IDLE_XCAL     = 4'd0;
parameter INIT_XCAL     = 4'd1;
parameter SUM_XCAL     	= 4'd2;
parameter DONE_XCAL     = 4'd3;

reg [3:0] state_Xcal;

always @(posedge clk or negedge rst_n) begin
	if(!rst_n || LS_done) begin
		state_Xcal <= IDLE_XCAL;
		Xcal_done <= 0;
		f32_add_sub_start <= 0;
		f32_mul_start <= 0;
		accumulator_Xcal <= 0;
		mul_first_flag <= 1;
		
	end
	else begin
		case(state_Xcal)
			IDLE_XCAL: begin
				if(start) begin
					i_Xcal <= 0;
					j_Xcal <= 0;
					k_Xcal <= 0;
					state_Xcal <= INIT_XCAL;
				end
			end
			
			INIT_XCAL: begin
				// 初始化 X_vector[i][j] = 0
				accumulator_Xcal <= 32'h0;  // +0.0
				if (i_Xcal < N) begin
					if (j_Xcal < N) begin
						state_Xcal <= SUM_XCAL;
						k_Xcal <= 0;
					end else begin
						i_Xcal <= i_Xcal + 1;
						j_Xcal <= 0;
						state_Xcal <= INIT_XCAL;
					end
				end else begin
					state_Xcal <= DONE_XCAL;
				end
			end
			
			SUM_XCAL: begin
				// X[i][0] += R_inv[i][k] * sum_vector_p_f32[k]
				if (!f32_mul_start && mul_first_flag) begin
					f32_mul_start <= 1;
					f32_mul_a <= R_inv_matrix[i_Xcal][k_Xcal];     // S[i][k]
					f32_mul_b <= sum_vector_p_f32[k_Xcal];      // S[k][0]
				end
				else if (f32_mul_done_dly && mul_first_flag) begin
					f32_mul_start <= 0;
					f32_add_sub_a <= accumulator_Xcal;
					f32_add_sub_b <= f32_mul_result;
					operation_tdata <= 8'd0;  // 加法
					f32_add_sub_start <= 1;
					mul_first_flag <= 0;
				end
				else if (f32_add_sub_done_dly) begin
					mul_first_flag <= 1;
					f32_add_sub_start <= 0;
					accumulator_Xcal <= f32_add_sub_result;
					if (k_Xcal == N-1) begin
						// 累加完成，保存结果
						X_vector[i_Xcal] <= f32_add_sub_result;
						i_Xcal <= i_Xcal + 1;
						state_Xcal <= INIT_XCAL;
					end else begin
						k_Xcal <= k_Xcal + 1;
					end
				end
			end
			
			DONE_XCAL: begin
				Xcal_done <= 1;
			end
		
		endcase
	end
	
end

always @(*) begin
    {R_inv_matrix[0][0], R_inv_matrix[0][1], R_inv_matrix[0][2], R_inv_matrix[0][3], R_inv_matrix[0][4],
     R_inv_matrix[1][0], R_inv_matrix[1][1], R_inv_matrix[1][2], R_inv_matrix[1][3], R_inv_matrix[1][4],
     R_inv_matrix[2][0], R_inv_matrix[2][1], R_inv_matrix[2][2], R_inv_matrix[2][3], R_inv_matrix[2][4],
     R_inv_matrix[3][0], R_inv_matrix[3][1], R_inv_matrix[3][2], R_inv_matrix[3][3], R_inv_matrix[3][4],
     R_inv_matrix[4][0], R_inv_matrix[4][1], R_inv_matrix[4][2], R_inv_matrix[4][3], R_inv_matrix[4][4]} =
	{R00, R01, R02, R03, R04,
     R10, R11, R12, R13, R14,
     R20, R21, R22, R23, R24,
     R30, R31, R32, R33, R34,
     R40, R41, R42, R43, R44};

end 

always @(*) begin
    {sum_vector_p_f32[0], sum_vector_p_f32[1], sum_vector_p_f32[2], sum_vector_p_f32[3], sum_vector_p_f32[4]} =
    {P0, P1, P2, P3, P4};
end 

always @(*) begin
    {X0, X1, X2, X3, X4} =
    {X_vector[0], X_vector[1], X_vector[2], X_vector[3], X_vector[4]};
end 


endmodule
