`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/07 14:42:02
// Design Name: 
// Module Name: top_u128_f32
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module top_u128_f32 (
    // 系统时钟与复位
    input        clk,           // 主时钟，例如 100MHz
    input        rst_n,         // 外部复位，低电平有效

    // 外部输入：128位数据
    input  [127:0] in_data,     // 来自外部的数据源
    input          data_valid,  // 表示 in_data 有效（可选）

    // 外部输出：32位浮点结果
    output [31:0]  out_result,  // 输出 float 结果
    output         result_valid // 结果有效标志
);

// =============== 内部信号声明 ===============
// 连接到 HLS IP 的信号
wire [31:0]  out_r;             // HLS 输出数据
wire         out_r_ap_vld;      // HLS 输出有效标志
wire         ap_done;           // 完成标志
wire         ap_ready;          // 就绪标志
wire         ap_idle;           // 空闲标志

reg  [127:0] in_r_reg;          // 锁存输入数据
reg          ap_start_reg;      // 控制 ap_start

// 输出寄存器
reg  [31:0]  out_result_reg;
reg          result_valid_reg;

// =============== 实例化 u128_to_f32 IP ===============
u128_to_f32_0 u128_to_f32_inst (
    .out_r_ap_vld(out_r_ap_vld),  // output wire
    .ap_clk(clk),                 // input wire
    .ap_rst(~rst_n),              // input wire: ap_rst 是高电平复位，所以取反
    .ap_start(ap_start_reg),      // input wire
    .ap_done(ap_done),            // output wire
    .ap_idle(ap_idle),            // output wire
    .ap_ready(ap_ready),          // output wire
    .in_r(in_r_reg),              // input wire [127:0]
    .out_r(out_r)                // output wire [31:0]
);

// =============== 状态定义（Verilog 兼容）===============
parameter IDLE       = 2'd0;
parameter TRIGGER    = 2'd1;
parameter WAIT_DONE  = 2'd2; 
parameter OUTPUT     = 2'd3;

// 状态寄存器
reg [1:0] state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        ap_start_reg <= 0;
        in_r_reg <= 0;
        out_result_reg <= 0;
        result_valid_reg <= 0;
    end else begin
        result_valid_reg <= 0;  // 默认无效

        case (state)
            IDLE: begin
                ap_start_reg <= 0;
                if (data_valid) begin  // 根据 data_valid 触发
                    in_r_reg <= in_data;       // 锁存输入
                    ap_start_reg <= 1;         // 拉高 ap_start
                    state <= TRIGGER;
                end
            end

            TRIGGER: begin
                // ap_start 在上升沿触发
                if (ap_ready) begin  // 可选：等待 ap_ready 再拉低
                    ap_start_reg <= 0;
                end
                if (ap_done) begin
                    state <= OUTPUT;
                end else if (ap_idle && !ap_start_reg) begin
                    // 如果提前进入 idle，也跳转（安全）
                    state <= OUTPUT;
                end
            end

            OUTPUT: begin
                // 直接捕获输出（也可打一拍）
                out_result_reg <= out_r;
                result_valid_reg <= 1;  // 使用 valid 标志
                state <= IDLE;
            end

            default:
                state <= IDLE;
        endcase
    end
end

// =============== 输出连接 ===============
assign out_result = out_result_reg;
assign result_valid = result_valid_reg;

// =============== 可选：空闲状态指示 ===============
// wire module_idle = (state == IDLE) && ap_idle;

endmodule