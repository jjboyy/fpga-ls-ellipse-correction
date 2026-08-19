`timescale 1ns / 1ps

module mac_matrix_calc #(

    parameter DATA_WIDTH = 32		
   // parameter N = 100  // 采样点数
	
)(

    input wire clk,
    input wire rst_n,
    input wire valid_in,
    input wire [DATA_WIDTH-1:0] x_in, //U16Q16
    input wire [DATA_WIDTH-1:0] y_in,
    input wire [15:0] Period_POINTS,
    output wire [15:0] theta_Q13,
	output wire LS_done,
	output wire LS_done_long,
   
	input wire [15:0] fifo_in,
    input wire write_en,   
    // FIFO控制信号
    output wire fifo_wr_en,
    output wire [15:0] fifo_din,
    // FIFO状态信号
    input wire fifo_full,
    input wire fifo_almost_full
);

localparam NxN_matrix = 5;

reg LS_done_reg, LS_done_long_reg;

// 输入数据为32位u16q16的定点数
wire [16-1 : 0] x_in_u16;
wire [16-1 : 0] y_in_u16;

assign x_in_u16 = (x_in + 32768) >> 16;		// 
assign y_in_u16 = (y_in + 32768) >> 16;		// 

/****************************
		 for_tb
****************************/
reg [127:0] sum_matrix_R [0:NxN_matrix-1][0:NxN_matrix-1];	// uint128
reg [127:0] sum_vector_p [0:NxN_matrix-1];					// uint128

/****************************
		 存储输入的信号，100个
****************************/
localparam MAX_PERIOD_POINTS = 500;
reg [DATA_WIDTH-1:0] x_array [0:MAX_PERIOD_POINTS-1];
reg [DATA_WIDTH-1:0] y_array [0:MAX_PERIOD_POINTS-1];

/****************************
		 n×n matrix
****************************/	
integer i,j;
reg [15:0] count;
reg sum_matrix_R_done;

// 用于中间计算的变量
wire [DATA_WIDTH*2-1:0] x2 = x_in_u16 * x_in_u16;
wire [DATA_WIDTH*2-1:0] y2 = y_in_u16 * y_in_u16;
wire [DATA_WIDTH*3-1:0] x3 = x2 * x_in_u16;
wire [DATA_WIDTH*3-1:0] y3 = y2 * y_in_u16;
wire [DATA_WIDTH*4-1:0] y4 = y2 * y2;

wire [DATA_WIDTH*2-1:0] x_y     = x_in_u16 * y_in_u16;
wire [DATA_WIDTH*4-1:0] x2_y2   = x2 * y2;
wire [DATA_WIDTH*4-1:0] x_y3    = x_in_u16 * y3;
wire [DATA_WIDTH*3-1:0] x2_y    = x2 * y_in_u16;
wire [DATA_WIDTH*3-1:0] x_y2    = x_in_u16 * y2;
wire [DATA_WIDTH*4-1:0] x3_y    = x3 * y_in_u16;
wire [DATA_WIDTH*4-1:0] x2_y2_rhs = x2 * y2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || LS_done) begin
            count <= 0;
            sum_matrix_R_done <= 0;
            for (i = 0; i < 5; i = i + 1) begin
				sum_vector_p[i] <= 0;
				for(j = 0; j < 5; j = j + 1) 
					sum_matrix_R[i][j] <= 0;
			end
			for (i = 0; i < MAX_PERIOD_POINTS; i = i + 1) begin
				x_array[i] <= 0;
				y_array[i] <= 0;
			end
        end 
		else if (valid_in && !sum_matrix_R_done) begin
			// LS_done_long_reg <= 0;		// 开启另一轮计算可以置零
            // 左侧矩阵累加
            sum_matrix_R[0][0] <= sum_matrix_R[0][0] + x2_y2;
            sum_matrix_R[0][1] <= sum_matrix_R[0][1] + x_y3;
            sum_matrix_R[0][2] <= sum_matrix_R[0][2] + x2_y;
            sum_matrix_R[0][3] <= sum_matrix_R[0][3] + x_y2;
            sum_matrix_R[0][4] <= sum_matrix_R[0][4] + x_y;
            sum_matrix_R[1][0] <= sum_matrix_R[1][0] + x_y3;
            sum_matrix_R[1][1] <= sum_matrix_R[1][1] + y4;			// 仿真发现最大会到10的17次方
            sum_matrix_R[1][2] <= sum_matrix_R[1][2] + x_y2;
            sum_matrix_R[1][3] <= sum_matrix_R[1][3] + y3;
            sum_matrix_R[1][4] <= sum_matrix_R[1][4] + y2;
            sum_matrix_R[2][0] <= sum_matrix_R[2][0] + x2_y;
            sum_matrix_R[2][1] <= sum_matrix_R[2][1] + x_y2;
            sum_matrix_R[2][2] <= sum_matrix_R[2][2] + x2;
            sum_matrix_R[2][3] <= sum_matrix_R[2][3] + x_y;
            sum_matrix_R[2][4] <= sum_matrix_R[2][4] + x_in_u16;
            sum_matrix_R[3][0] <= sum_matrix_R[3][0] + x_y2;
            sum_matrix_R[3][1] <= sum_matrix_R[3][1] + y3;
            sum_matrix_R[3][2] <= sum_matrix_R[3][2] + x_y;
            sum_matrix_R[3][3] <= sum_matrix_R[3][3] + y2;
            sum_matrix_R[3][4] <= sum_matrix_R[3][4] + y_in_u16;
            sum_matrix_R[4][0] <= sum_matrix_R[4][0] + x_y;
            sum_matrix_R[4][1] <= sum_matrix_R[4][1] + y2;
            sum_matrix_R[4][2] <= sum_matrix_R[4][2] + x_in_u16;
            sum_matrix_R[4][3] <= sum_matrix_R[4][3] + y_in_u16;
            sum_matrix_R[4][4] <= sum_matrix_R[4][4] + 1;

            // 右侧向量累加（取负号之后进行）
			sum_vector_p[0] <= sum_vector_p[0] + x3_y;
            sum_vector_p[1] <= sum_vector_p[1] + x2_y2_rhs;
            sum_vector_p[2] <= sum_vector_p[2] + x3;
            sum_vector_p[3] <= sum_vector_p[3] + x2_y;
            sum_vector_p[4] <= sum_vector_p[4] + x2;

			x_array[count] <= x_in_u16;
			y_array[count] <= y_in_u16;
			
            count <= count + 1;
            if (count == Period_POINTS - 1) begin
                sum_matrix_R_done <= 1;
            end
        end
    end

	
/****************************
 R_Cholesky 按列求解
****************************/	
reg cholesky_done;

reg [31:0] L_matrix [0:NxN_matrix-1][0:NxN_matrix-1]; // L矩阵 float32 

reg [31:0] accumulator; 			// 累加器   f32
reg [NxN_matrix-1:0] k_index;       // 累加索引
reg [NxN_matrix-1:0] j_reg;         // 列索引寄存器
reg [NxN_matrix-1:0] i_reg;         // 行索引寄存器

// 状态定义
parameter IDLE           = 4'd0;
parameter INIT_COL       = 4'd1;  // 初始化当前列 j
parameter DIAG_SQRT_PREP = 4'd2;  // 对角元：准备累加 L[j][k]^2
parameter DIAG_SQRT_LOOP = 4'd3;  // 对角元：循环 k < j，计算 L[j][k]^2 并累加
parameter DIAG_SUB_SQRT  = 4'd4;  // 对角元：R[j][j] - sum，然后 sqrt
parameter OFFDIAG_PREP   = 4'd5;  // 非对角元：准备累加 L[i][k]*L[j][k]
parameter OFFDIAG_LOOP   = 4'd6;  // 非对角元：循环 k < j，累加乘积
parameter OFFDIAG_SUB_DIV= 4'd7;  // 非对角元：R[i][j] - sum，然后 / L[j][j]
parameter NEXT_COL       = 4'd8;  // 进入下一列
parameter DONE           = 4'd9;

reg [3:0] current_state;
reg [3:0] next_state;

// IP核相关接口
reg sqrt_start;
reg [127:0] u128_f32_data;		// uint128
reg [63:0] sqrt_in; 			// uint64
wire float_vld;
wire [31:0] sum_float;			// float32
wire flt_sqrt_vld;
wire [31:0] sqrt_sum_float;		// float32
reg [31:0] L_matrix_temp;		// float32
reg [31:0] mul_result_reg;		// float32 存储乘法结果的中间变量
reg [31:0] sub_result_reg;		// float32 存储加减法结果的中间变量

reg NEXT_COL_first;	// NEXT_COL只执行一次
reg OFFDIAG_SUB_first; // OFFDIAG_SUB只执行一次
reg DIAG_SUB_SQRT_flag; 	// 不让多次执行加减法
reg OFFDIAG_LOOP_flag;

top_u128_f32 top_u128_f32_inst (
	.clk						(clk				),							// 主时钟，例如 100MHz
	.rst_n						(rst_n				),                        // 外部复位，低电平有效
	.in_data					(u128_f32_data		),                      // 来自外部的数据源 input wire [127:0]
	.data_valid					(R_u128_f32_start_pos),                         // 表示 in_data 有效
	.out_result					(sum_float			),                    // 输出 float 结果 output wire [31:0]
	.result_valid				(float_vld			)                     // 结果有效标志
);             

/*************************************************************************************************************************
		n×n matrix u128转f32
**************************************************************************************************************************/
// 状态机定义
parameter IDLE_U128 		= 4'd0;
parameter INIT_U128			= 4'd1;
parameter R_U128_F32		= 4'd2;
parameter P_U128_F32		= 4'd3;
parameter DONE_U128 		= 4'd4;
reg [3:0] current_state_u128;
reg [3:0] next_state_u128;

reg [31:0] sum_matrix_R_f32 [0:NxN_matrix-1][0:NxN_matrix-1];	// f32
reg [31:0] sum_vector_p_f32 [0:NxN_matrix-1];					// f32

reg R_u128_f32_start;
reg [NxN_matrix-1:0] j_u128;         // 列索引寄存器
reg [NxN_matrix-1:0] i_u128;         // 行索引寄存器
reg [NxN_matrix-1:0] i_u128_p;
reg [15:0] count_u128;
reg sum_matrix_R_u128_f32_done;

reg R_u128_f32_start_r;
always @(posedge clk) begin
R_u128_f32_start_r <= R_u128_f32_start;
end
assign R_u128_f32_start_pos = R_u128_f32_start & ~R_u128_f32_start_r;

// 状态寄存器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n || LS_done) begin
        current_state_u128 <= IDLE_U128;
    end else begin
        current_state_u128 <= next_state_u128;
    end
end

// 下一状态逻辑
always @(*) begin
    next_state_u128 = current_state_u128;
    
    case (current_state_u128)
        IDLE_U128: begin
            if (sum_matrix_R_done) 
				next_state_u128 <= INIT_U128;
        end
        
        INIT_U128: begin
            next_state_u128 <= R_U128_F32;
        end
        
        R_U128_F32: begin
            if (i_u128 == 5 && j_u128 == 0)		// 要延迟一个周期
                next_state_u128 <= P_U128_F32;
        end
		        
        P_U128_F32: begin
            if (i_u128_p == 6) begin		// 要延迟一个周期
				next_state_u128 <= DONE_U128;
            end
        end
        
        DONE_U128: begin
            next_state_u128 <= DONE_U128;	// 不再返回
        end
    endcase
end

// 控制逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n || LS_done) begin
        // 复位所有寄存器  
		R_u128_f32_start <= 0;
		count_u128 <= 0;
		sum_matrix_R_u128_f32_done <= 0;
        // 清零
		for (i_u128 = 0; i_u128 < 5; i_u128 = i_u128 + 1) begin
			sum_vector_p_f32[i_u128] <= 0;
			for(j_u128 = 0; j_u128 < 5; j_u128 = j_u128 + 1) 
				sum_matrix_R_f32[i_u128][j_u128] <= 0;
		end
    end 
	
	else begin
		case (current_state_u128)
			IDLE_U128: begin
				if (sum_matrix_R_done)
				sum_matrix_R_u128_f32_done <= 0;
			end
			
			INIT_U128: begin
				i_u128 <= 0; j_u128 <= 0; i_u128_p <= 0;
			end
			
			R_U128_F32: begin
				if (!R_u128_f32_start) begin
					u128_f32_data <= sum_matrix_R[i_u128][j_u128];
					R_u128_f32_start <= 1;
				end
				
				if (float_vld) begin	// 转换结束标志位有效
					R_u128_f32_start <= 0;
					sum_matrix_R_f32[i_u128][j_u128] <= sum_float;
					
					// Step 2: 更新状态到下一个 (i,j)
					if (j_u128 < 4) begin
						i_u128 <= i_u128;
						j_u128 <= j_u128 + 1;
					end
					else if (j_u128 == 4 && i_u128 < 4) begin
						i_u128 <= i_u128 + 1;
						j_u128 <= 0;
					end
					else if (j_u128 == 4 && i_u128 == 4) begin
						// 当前是 (4,4)，写完后跳转到 (5,0)
						j_u128 <= 0;
						i_u128 <= 5;
					end
				end
			end
			
			
			P_U128_F32: begin
				if (!R_u128_f32_start) begin
					u128_f32_data <= sum_vector_p[i_u128_p - 1];	// 由于第一次进状态时i_u128_p为1，所以要减1
					R_u128_f32_start <= 1;
				end
				
				if (float_vld) begin
					R_u128_f32_start <= 0;
					sum_vector_p_f32[i_u128_p - 1] <= {~sum_float[31], sum_float[30:0]};	// p = [-p1; -p2; -p3; -p4; -p5];
					
					if (i_u128_p < 5) begin
						i_u128_p <= i_u128_p + 1;
					end
					else begin
						// i == 4 或更大，完成
						i_u128_p <= 6; // 标记完成
					end
				end
			end
			
			DONE_U128: begin
				sum_matrix_R_u128_f32_done <= 1;
			end
		endcase
	end
end 

/*************************************************************************************************************************
		choleksy分解
**************************************************************************************************************************/

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

// 状态寄存器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n || LS_done) begin
        current_state <= IDLE;
    end else begin
        current_state <= next_state;
    end
end

// 下一状态组合逻辑
always @(*) begin
    next_state <= current_state;
end

// 控制逻辑（时序）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n || LS_done) begin
        j_reg <= 0;
        i_reg <= 0;
        k_index <= 0;
        accumulator <= 0;
        cholesky_done <= 0;

        f32_mul_start <= 0;
        f32_add_sub_start <= 0;
        f32_sqrt_start <= 0;
        f32_div_start <= 0;
		
		OFFDIAG_SUB_first <= 1;
		DIAG_SUB_SQRT_flag <= 0;
		OFFDIAG_LOOP_flag <= 0;
       // 清零L矩阵
        for (i = 0; i < NxN_matrix; i = i + 1) begin
            for (j = 0; j < NxN_matrix; j = j + 1) begin
                L_matrix[i][j] <= 0;
            end
        end

    end else begin

        case (current_state)

            IDLE: begin		// 0
            
                if (sum_matrix_R_u128_f32_done) begin
                    j_reg <= 0;
                    cholesky_done <= 0;
                    next_state <= INIT_COL;
                end
            end

            INIT_COL: begin		// 1
				NEXT_COL_first <= 1;
                accumulator <= 0;
                k_index <= 0;
				next_state <= (j_reg < NxN_matrix) ? DIAG_SQRT_PREP : DONE;
            end

            DIAG_SQRT_PREP: begin		// 2
                if (j_reg == 0) begin
                    // 第一列，无累加项
                    next_state <= DIAG_SUB_SQRT;
                end else if (k_index < j_reg) begin
                    // 计算 L[j][k] * L[j][k]
                    f32_mul_a <= L_matrix[j_reg][k_index];
                    f32_mul_b <= L_matrix[j_reg][k_index];
                    f32_mul_start <= 1;
                    next_state <= DIAG_SQRT_LOOP;
                end else begin
                    next_state <= DIAG_SUB_SQRT;
                end
            end

            DIAG_SQRT_LOOP: begin		// 3
                if (f32_mul_done_dly) begin			// 需要延迟对齐结束标志位和数据
					f32_mul_start <= 0;
                    // 累加到 accumulator
                    f32_add_sub_a <= accumulator;
                    f32_add_sub_b <= f32_mul_result;
                    operation_tdata <= 8'd0; // 加法
                    f32_add_sub_start <= 1;
                end
				else if (f32_add_sub_done_dly) begin
					f32_add_sub_start <= 0;
					accumulator <= f32_add_sub_result;
					if (k_index + 1 < j_reg) begin
						k_index <= k_index + 1;
					end 
					if (k_index < j_reg - 1) begin
						next_state <= DIAG_SQRT_PREP;
					end
					else begin
						next_state <= DIAG_SUB_SQRT;
					end
				end
            end

            DIAG_SUB_SQRT: begin	// 4
                if (!f32_add_sub_start && !DIAG_SUB_SQRT_flag) begin
                    f32_add_sub_a <= sum_matrix_R_f32[j_reg][j_reg];
                    f32_add_sub_b <= accumulator;
                    operation_tdata <= 8'd1; // 减法
                    f32_add_sub_start <= 1;
                end else if (f32_add_sub_done_dly) begin
					f32_add_sub_start <= 0; // 清零
                    f32_sqrt_in <= f32_add_sub_result;
                    f32_sqrt_start <= 1;
					DIAG_SUB_SQRT_flag <= 1;
                end else if (f32_sqrt_done) begin
					f32_sqrt_start <= 0;
                    L_matrix[j_reg][j_reg] <= f32_sqrt_result;
                    // 准备非对角线
                    i_reg <= j_reg + 1;
					current_state <= (j_reg < NxN_matrix-1) ? OFFDIAG_PREP : DONE;	// 需要马上跳转，否则还会再进入一次加减法
					DIAG_SUB_SQRT_flag <= 0;
                end
				else begin
				
				end
            end

            OFFDIAG_PREP: begin		// 5
				OFFDIAG_SUB_first <= 1;
                if (i_reg >= NxN_matrix) begin
                    next_state <= NEXT_COL;
                end else begin
                    accumulator <= 0;
                    k_index <= 0;
                    next_state <= OFFDIAG_LOOP;
                end
            end
			
            OFFDIAG_LOOP: begin		// 6
					if (!f32_mul_start && !OFFDIAG_LOOP_flag) begin
						f32_mul_a <= L_matrix[i_reg][k_index];
						f32_mul_b <= L_matrix[j_reg][k_index];
						f32_mul_start <= 1;
					end

					else if (f32_mul_done_dly) begin
						f32_mul_start <= 0;
						f32_add_sub_a <= accumulator;
						f32_add_sub_b <= f32_mul_result;
						operation_tdata <= 8'd0;
						f32_add_sub_start <= 1;
						OFFDIAG_LOOP_flag <= 1;
					end
					
					else if (f32_add_sub_done_dly) begin		 
						f32_add_sub_start <= 0;
						accumulator <= f32_add_sub_result;
						k_index <= k_index + 1;
						if (k_index < j_reg) begin
							current_state <= OFFDIAG_LOOP;
							OFFDIAG_LOOP_flag <= 0;
						end else begin
							current_state <= OFFDIAG_SUB_DIV;
							OFFDIAG_LOOP_flag <= 0;
						end
					end
            end

            OFFDIAG_SUB_DIV: begin		// 7
				if (!f32_add_sub_start && i_reg < NxN_matrix && OFFDIAG_SUB_first) begin		// 保护不会多进
					f32_add_sub_a <= sum_matrix_R_f32[i_reg][j_reg];
					f32_add_sub_b <= accumulator;
					operation_tdata <= 8'd1;
					f32_add_sub_start <= 1;
				end else if (f32_add_sub_done_dly && OFFDIAG_SUB_first) begin	// 需要延迟，要不然f32_div_a的值不对
					// f32_add_sub_start <= 0;
					f32_div_a <= f32_add_sub_result;
					f32_div_b <= L_matrix[j_reg][j_reg];
					f32_div_start <= 1;
					OFFDIAG_SUB_first <= 0;
				end else if (f32_div_done_dly) begin	// 同样需要延迟
					f32_add_sub_start <= 0;
					f32_div_start <= 0;
					L_matrix[i_reg][j_reg] <= f32_div_result;
					i_reg <= i_reg + 1;
					next_state <= (i_reg < NxN_matrix-1) ? OFFDIAG_PREP : NEXT_COL;
				end
            end

            NEXT_COL: begin		// 8
				OFFDIAG_SUB_first <= 1;
				if (NEXT_COL_first) begin
                j_reg <= j_reg + 1;
				i_reg <= 0;
				NEXT_COL_first <= 0;
				end
				next_state <= (j_reg < NxN_matrix-1) ? INIT_COL : DONE;
            end

            DONE: begin		// 9
                cholesky_done <= 1;
                //next_state <= IDLE;  // 返回到初始状态
            end
        endcase
    end
end

/*************************************************************************************************************************
		求逆模块 求R_inv + 输出
**************************************************************************************************************************/
wire [31:0] R_inv_matrix [0:NxN_matrix-1][0:NxN_matrix-1]; // S矩阵

inverse_R_f32 #(

	.N 						(5			 	), 	// 矩阵维度
	.F32_WIDTH 				(32 			)   // 定点数位宽
	
) inverse_R_f32_inst(
    .clk					(clk			),                      
    .rst_n					(rst_n			),                    
    .start					(cholesky_done	), 
	.LS_done				(LS_done		),
	.L00					(L_matrix[0][0]	),
	.L10					(L_matrix[1][0]	),
	.L20					(L_matrix[2][0]	),
	.L30					(L_matrix[3][0]	),
	.L40					(L_matrix[4][0]	),
	.L11					(L_matrix[1][1]	),
	.L21					(L_matrix[2][1]	),
	.L31					(L_matrix[3][1]	),
	.L41					(L_matrix[4][1]	),
	.L22					(L_matrix[2][2]	),
	.L32					(L_matrix[3][2]	),
	.L42					(L_matrix[4][2]	),
	.L33					(L_matrix[3][3]	),
	.L43					(L_matrix[4][3]	),
	.L44					(L_matrix[4][4]	),
	
//  .R 						(				), 	
	.R00                    (R_inv_matrix[0][0]),
	.R01                    (R_inv_matrix[0][1]),
	.R02                    (R_inv_matrix[0][2]),
	.R03                    (R_inv_matrix[0][3]),
	.R04                    (R_inv_matrix[0][4]),
	.R10                    (R_inv_matrix[1][0]),
	.R11                    (R_inv_matrix[1][1]),
	.R12                    (R_inv_matrix[1][2]),
	.R13                    (R_inv_matrix[1][3]),
	.R14                    (R_inv_matrix[1][4]),
	.R20                    (R_inv_matrix[2][0]),
	.R21                    (R_inv_matrix[2][1]),
	.R22                    (R_inv_matrix[2][2]),
	.R23                    (R_inv_matrix[2][3]),
	.R24                    (R_inv_matrix[2][4]),
	.R30                    (R_inv_matrix[3][0]),
	.R31                    (R_inv_matrix[3][1]),
	.R32                    (R_inv_matrix[3][2]),
	.R33                    (R_inv_matrix[3][3]),
	.R34                    (R_inv_matrix[3][4]),
	.R40                    (R_inv_matrix[4][0]),
	.R41                    (R_inv_matrix[4][1]),
	.R42                    (R_inv_matrix[4][2]),
	.R43                    (R_inv_matrix[4][3]),
	.R44                    (R_inv_matrix[4][4]),

    .inverse_done  			(inverse_done	)
);

wire [31:0] X_vector [0:NxN_matrix-1]; // S矩阵

R_inv_mul_P #(

	.N 						(5			 	), 	// 矩阵维度
	.F32_WIDTH 				(32 			)   // 定点数位宽
	
) R_inv_mul_P_inst(
    .clk					(clk			),                      
    .rst_n					(rst_n			),                    
    .start					(inverse_done	),                    
	.LS_done				(LS_done		),
	
//  .R 						(				), 	
	.R00                    (R_inv_matrix[0][0]),
	.R01                    (R_inv_matrix[0][1]),
	.R02                    (R_inv_matrix[0][2]),
	.R03                    (R_inv_matrix[0][3]),
	.R04                    (R_inv_matrix[0][4]),
	.R10                    (R_inv_matrix[1][0]),
	.R11                    (R_inv_matrix[1][1]),
	.R12                    (R_inv_matrix[1][2]),
	.R13                    (R_inv_matrix[1][3]),
	.R14                    (R_inv_matrix[1][4]),
	.R20                    (R_inv_matrix[2][0]),
	.R21                    (R_inv_matrix[2][1]),
	.R22                    (R_inv_matrix[2][2]),
	.R23                    (R_inv_matrix[2][3]),
	.R24                    (R_inv_matrix[2][4]),
	.R30                    (R_inv_matrix[3][0]),
	.R31                    (R_inv_matrix[3][1]),
	.R32                    (R_inv_matrix[3][2]),
	.R33                    (R_inv_matrix[3][3]),
	.R34                    (R_inv_matrix[3][4]),
	.R40                    (R_inv_matrix[4][0]),
	.R41                    (R_inv_matrix[4][1]),
	.R42                    (R_inv_matrix[4][2]),
	.R43                    (R_inv_matrix[4][3]),
	.R44                    (R_inv_matrix[4][4]),
	
	.P0						(sum_vector_p_f32[0]),
	.P1						(sum_vector_p_f32[1]),
	.P2						(sum_vector_p_f32[2]),
	.P3						(sum_vector_p_f32[3]),
	.P4						(sum_vector_p_f32[4]),
	
	.X0						(X_vector[0]),
	.X1						(X_vector[1]),
	.X2						(X_vector[2]),
	.X3						(X_vector[3]),
	.X4						(X_vector[4]),

    .Xcal_done  			(Xcal_done	)
);

/****************************
		 参数求解 abcde x0 y0
****************************/
reg [31:0] a;  // float32
reg [31:0] b;  // float32
reg [31:0] c;  // float32
reg [31:0] d;  // float32
reg [31:0] e;  // float32

wire [31:0] x0;  // 中心坐标x
wire [31:0] y0;  // 中心坐标y
wire [31:0] r_hat;  // float32
wire [31:0] alpha_hat;  // float32

wire para_solve_f32_done;


para_solve_f32 #(
    .F32_WIDTH				(32				)      // 64bit定点数类型，最高位为符号位，62-38为整数部分，12-0为小数部分
)	
para_solve_f32_inst (	
    .clk					(clk			),                      
    .rst_n					(rst_n			),                    
    .start					(Xcal_done		),  
	.LS_done				(LS_done		),
    .a						(X_vector[0]	),       		// 输入参数 64Q13格式
	.b						(X_vector[1]	),
	.c						(X_vector[2]	),
	.d						(X_vector[3]	),
	.e						(X_vector[4]	),
	
    .x0						(x0				),
	.y0						(y0				),            
    .r_hat					(r_hat			),
	.alpha_hat				(alpha_hat		),            // 计算结果
    .para_solve_f32_done    (para_solve_f32_done)             // 计算完成标志
);


/****************************
	参数格式转换+正余弦求解
****************************/
wire [63:0] x0_q13;  
wire [63:0] y0_q13;  
wire [63:0] r_hat_q13;  
wire [63:0] alpha_hat_q13;  
wire [63:0] cos_alpha_hat_de;
wire [63:0] sin_alpha_hat;    

wire para_f32_fix64q13_DONE;

para_f32_fix64q13 #(
    .F32_WIDTH				(32				),      	// 32bit浮点数类型
    .FIXED_WIDTH			(64				)      // 64bit定点数类型，最高位为符号位，62-13为整数部分，12-0为小数部分
)
para_f32_fix64q13_inst(
    .clk					(clk				),                      
    .rst_n					(rst_n				),                    
    .start					(para_solve_f32_done),  
	.LS_done				(LS_done			), 
    .x0						(x0					),
	.y0						(y0					),
    .r_hat					(r_hat				),
	.alpha_hat				(alpha_hat			),

    .x0_q13					(x0_q13				),
	.y0_q13					(y0_q13				), 
    .r_hat_q13				(r_hat_q13			),
	.alpha_hat_q13			(alpha_hat_q13		),     
    .cos_alpha_hat_de		(cos_alpha_hat_de	),		// 64q13
	.sin_alpha_hat			(sin_alpha_hat		),   	// 64q13
    .para_f32_fix64q13_DONE (para_f32_fix64q13_DONE	)                      // 计算完成标志
);

/****************************
		 实现去除误差的处理，得到了去除误差后的x和y信号，剩下相位求解
****************************/
parameter IDLE_LS 			= 4'd0;
parameter TRANS				= 4'd1;
parameter CALC_LS1 			= 4'd2;
parameter CALC_LS2 			= 4'd3;
parameter CALC_LS3 			= 4'd4;
parameter CALC_LS4 			= 4'd5;
parameter CALC_LS5 			= 4'd6;
parameter ATAN2_PRE 		= 4'd7;
parameter ATAN2 			= 4'd8;
parameter DONE_LS 			= 4'd9;
reg [3:0] current_state_LS;
reg [3:0] next_state_LS;

// 用于中间计算的变量
reg [15:0] count_LS;
reg signed [63:0] x_64q13, y_64q13;
reg signed [63:0] x_LS [0:MAX_PERIOD_POINTS-1];
reg signed [63:0] y_LS [0:MAX_PERIOD_POINTS-1];
reg signed [15:0] theta_hat [0:MAX_PERIOD_POINTS-1];			//16Q13格式

reg signed [63:0] y_temp1, y_temp2, y_temp5;
reg signed [63:0] x_LS_watch, y_LS_watch;
reg signed [127:0] y_temp3, y_temp4, y_temp6;

reg signed [15:0] theta_hat_watch;


reg signed [14:0] x_LS_atan, y_LS_atan;

// ================== atan IP核接口 ==================
reg [31:0] atan_in;     // atan IP核输入
reg atan_start;
wire atan_done;
wire [15:0] atan_result;

reg atan_start_r;
always @(posedge clk) begin
	atan_start_r <= atan_start;
end
assign atan_start_pos = atan_start & ~atan_start_r;

// 调用atan IP核
fix15q13_atan_fix16q13 fix15q13_atan_fix16q13_inst (
	.aclk								(clk),                                        // input wire aclk
	.s_axis_cartesian_tvalid			(atan_start_pos),  // input wire s_axis_cartesian_tvalid
	.s_axis_cartesian_tdata				(atan_in),    		// input wire [31 : 0] s_axis_cartesian_tdata
	.m_axis_dout_tvalid					(atan_done),            // output wire m_axis_dout_tvalid
	.m_axis_dout_tdata					(atan_result)              // output wire [15 : 0] m_axis_dout_tdata
);

/* // FIFO 控制信号
reg  atan_write_enable;
reg  atan_read_enable;
wire fifo_full;
wire fifo_almost_full;
wire [9:0] fifo_data_count;
wire fifo_out;

reg atan_write_enable_r;
always @(posedge clk) begin
	atan_write_enable_r <= atan_write_enable;
end
assign atan_write_enable_pos = atan_write_enable & ~atan_write_enable_r;

reg atan_read_enable_r;
always @(posedge clk) begin
	atan_read_enable_r <= atan_read_enable;
end
assign atan_read_enable_pos = atan_read_enable & ~atan_read_enable_r;

fifo_theta_hat fifo_theta_hat_inst (
  .clk				(clk),                    // input wire clk
  .srst				(~rst_n),                  // input wire srst
  .din				(atan_result),                    // input wire [15 : 0] din
  .wr_en			(atan_write_enable_pos),                // input wire wr_en
  .rd_en			(atan_read_enable_pos),                // input wire rd_en
  .dout				(fifo_out),                  // output wire [15 : 0] dout
  .full				(fifo_full),                  // output wire full
  .almost_full		(fifo_almost_full),    // output wire almost_full
  .empty			(),                // output wire empty
  .almost_empty		(),  // output wire almost_empty
  .data_count		(fifo_data_count)      // output wire [9 : 0] data_count
); */

reg  atan_write_enable;
reg  atan_read_enable;

reg fifo_wr_en_r;
always @(posedge clk) begin
	fifo_wr_en_r <= atan_write_enable;
end
assign fifo_wr_en = atan_write_enable & ~fifo_wr_en_r;

/* always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fifo_wr_en <= 1'b0;
    end else begin
        fifo_wr_en <= write_en && !fifo_full;
    end
end */

assign fifo_din = theta_hat_watch;

// 状态寄存器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n || LS_done) begin
        current_state_LS <= IDLE_LS;
    end else begin
        current_state_LS <= next_state_LS;
    end
end

/* // 下一状态逻辑 ???????????????????????????????????
reg [1:0] count_LS_done;  // 2位计数器，计数到2
always @(posedge clk or posedge rst_n) begin
    if (!rst_n) begin
        count_LS_done <= 0;                // 异步复位计数器
    end else begin
        if (current_state_LS == DONE_LS) begin
            if (LS_done) begin
                if (count_LS_done < 2) begin
                    count_LS_done <= count_LS_done + 1; // 高电平计数
                end else begin
                    count_LS_done <= 0;                // 计数器重置
                end
            end else begin
                count_LS_done <= 0;                    // 如果 LS_done 低电平，计数器重置
            end
        end else begin
            count_LS_done <= 0;                        // 非 DONE_LS 状态下，计数器重置
        end
    end
end */


always @(*) begin
    next_state_LS <= current_state_LS;
    
    case (current_state_LS)
        IDLE_LS: begin
			if (para_f32_fix64q13_DONE)
			next_state_LS <= TRANS;
        end
        
        TRANS: begin
            if (count_LS == Period_POINTS) begin				// 实测从1开始，所以要到100才能表示完整100个数据
                next_state_LS <= DONE_LS;
            end
			else next_state_LS <= CALC_LS1;
        end
		
		CALC_LS1: begin
			next_state_LS <= CALC_LS2;
		end
		
		CALC_LS2: begin
			next_state_LS <= CALC_LS3;
		end
		
		CALC_LS3: begin
			next_state_LS <= CALC_LS4;
		end
		
		CALC_LS4: begin
			next_state_LS <= CALC_LS5;
		end
		
		CALC_LS5: begin
			next_state_LS <= ATAN2_PRE;
		end
		
		ATAN2_PRE: begin
			next_state_LS <= ATAN2;
		end
		//8
		ATAN2: begin
			if (atan_done) begin
			next_state_LS <= TRANS;
			end
		end
        
        DONE_LS: begin
/*             if (LS_done && count_LS_done >= 2) begin
                next_state_LS <= IDLE_LS;
                LS_done_reg <= 0; // 重置完成标志位
            end */
			// LS_done_reg <= 1;
        end
    endcase
end

// 控制逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n || LS_done) begin
        // 复位所有寄存器
		x_64q13 <= 0;y_64q13 <= 0;
		y_temp1 <= 0;y_temp2 <= 0;y_temp3 <= 0;
		y_temp4 <= 0;y_temp5 <= 0;y_temp6 <= 0;
		count_LS <= 0;atan_in <= 0;atan_start <= 0;
		theta_hat_watch <= 0;
		LS_done_reg <= 0;
		LS_done_long_reg <= 0;
		atan_write_enable <= 0; // fifo默认不写
		atan_read_enable <= 0;
        // count_LS_done <= 0;
    end 
	else begin
        case (current_state_LS)
            IDLE_LS: begin

            end
            
            TRANS: begin
				x_64q13 <= {39'd0, x_array[count_LS], 13'd0};
				y_64q13 <= {39'd0, y_array[count_LS], 13'd0};
            end    

            CALC_LS1: begin
				y_temp1 <= x_64q13 - x0_q13;
				y_temp2 <= y_64q13 - y0_q13;
            end 
			
            CALC_LS2: begin
				y_temp3 <= $signed(sin_alpha_hat) * $signed(y_temp1);
				y_temp4 <= $signed(r_hat_q13) * $signed(y_temp2);
            end 
			
            CALC_LS3: begin
				y_temp5 <= y_temp3[76:13] + y_temp4[76:13];
            end 
			
            CALC_LS4: begin
				y_temp6 <= $signed(cos_alpha_hat_de) * $signed(y_temp5);
            end
			
            CALC_LS5: begin
				x_LS[count_LS] <= y_temp1;
				y_LS[count_LS] <= $signed(y_temp6[76:13]);
				x_LS_watch <= y_temp1 >>> 16;						// 右移，保持符号，缩小65536倍
				y_LS_watch <= ($signed(y_temp6[76:13])) >>> 16;     // 右移，保持符号，缩小65536倍
            end
			
			ATAN2_PRE: begin	// 7
				x_LS_atan <= $signed(x_LS_watch[14:0]);
				y_LS_atan <= $signed(y_LS_watch[14:0]);
			end
			
			ATAN2: begin		// 8
				atan_write_enable <= 0; // fifo默认不写
				
				if (!atan_start) begin
					atan_in <= {x_LS_atan[14],x_LS_atan, y_LS_atan[14],y_LS_atan};		// 合成输入格式
					atan_start <= 1;
				end
				
				else if (atan_done) begin
					atan_start <= 0;
					theta_hat_watch <= atan_result;
					theta_hat[count_LS] <= atan_result;
					if (!fifo_full) begin			// 安全写入：只有 FIFO 不满时才写
						atan_write_enable <= 1;
						// count_LS <= count_LS + 1;
					end 
					count_LS <= count_LS + 1;
				end
			end
            
            DONE_LS: begin
				LS_done_reg <= 1;
				LS_done_long_reg <= 1;
                //sum_matrix_R_done <= 0;
            end
        endcase
    end
end	

// 输出数据为U3Q13的相位数据
assign theta_Q13 = theta_hat_watch;

// LS结束标志位
assign LS_done = LS_done_reg;
assign LS_done_long = LS_done_long_reg;	// 这是持续输出

endmodule
