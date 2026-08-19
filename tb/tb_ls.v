`timescale 1ns / 1ps

module tb_ls;

localparam integer N_POINTS = 100;
localparam [15:0] N_POINTS_U16 = N_POINTS;
localparam integer CLK_PERIOD_NS = 10;

reg clk;
reg rst_n;
reg valid_in;
reg [31:0] x_in;
reg [31:0] y_in;

reg [15:0] sine_table [0:N_POINTS-1];
reg [15:0] cos_table [0:N_POINTS-1];

wire [15:0] theta_q13;
wire ls_done;
wire ls_done_long;
wire fifo_wr_en;
wire [15:0] fifo_din;

integer input_index;
integer input_count;
integer output_count;
integer result_file;
integer latency_file;
integer cycle_count;
integer cycle_first_input;
integer cycle_last_input;
integer cycle_parameter_solved;
integer cycle_parameter_ready;
integer cycle_first_output;
integer cycle_last_output;
time time_first_input;
time time_last_input;
time time_parameter_solved;
time time_parameter_ready;
time time_first_output;
time time_last_output;
reg parameter_solved_seen;
reg parameter_ready_seen;
reg first_output_seen;
real theta_rad;

task write_latency_report;
begin
    latency_file = $fopen("../../../../../results/latency_summary.csv", "w");
    if (latency_file == 0) begin
        $display("ERROR: cannot open results/latency_summary.csv");
    end else begin
        $fdisplay(latency_file,
            "metric,start_event,end_event,start_cycle,end_cycle,elapsed_cycles,start_time_ns,end_time_ns,duration_ns");
        $fdisplay(latency_file,
            "input_window,first_input,last_input,%0d,%0d,%0d,%0d,%0d,%0d",
            cycle_first_input, cycle_last_input,
            cycle_last_input - cycle_first_input,
            time_first_input, time_last_input,
            time_last_input - time_first_input);
        $fdisplay(latency_file,
            "parameter_solve,last_input,parameter_solved,%0d,%0d,%0d,%0d,%0d,%0d",
            cycle_last_input, cycle_parameter_solved,
            cycle_parameter_solved - cycle_last_input,
            time_last_input, time_parameter_solved,
            time_parameter_solved - time_last_input);
        $fdisplay(latency_file,
            "parameter_ready,last_input,parameter_ready,%0d,%0d,%0d,%0d,%0d,%0d",
            cycle_last_input, cycle_parameter_ready,
            cycle_parameter_ready - cycle_last_input,
            time_last_input, time_parameter_ready,
            time_parameter_ready - time_last_input);
        $fdisplay(latency_file,
            "first_output_latency,last_input,first_output,%0d,%0d,%0d,%0d,%0d,%0d",
            cycle_last_input, cycle_first_output,
            cycle_first_output - cycle_last_input,
            time_last_input, time_first_output,
            time_first_output - time_last_input);
        $fdisplay(latency_file,
            "output_window,first_output,last_output,%0d,%0d,%0d,%0d,%0d,%0d",
            cycle_first_output, cycle_last_output,
            cycle_last_output - cycle_first_output,
            time_first_output, time_last_output,
            time_last_output - time_first_output);
        $fdisplay(latency_file,
            "total_frame,first_input,last_output,%0d,%0d,%0d,%0d,%0d,%0d",
            cycle_first_input, cycle_last_output,
            cycle_last_output - cycle_first_input,
            time_first_input, time_last_output,
            time_last_output - time_first_input);
        $fclose(latency_file);

        $display("--- LS latency summary (100 MHz, 10 ns/cycle) ---");
        $display("Input window        : %0d cycles, %0d ns",
            cycle_last_input - cycle_first_input,
            time_last_input - time_first_input);
        $display("Parameter solve     : %0d cycles, %0d ns",
            cycle_parameter_solved - cycle_last_input,
            time_parameter_solved - time_last_input);
        $display("Parameter ready     : %0d cycles, %0d ns",
            cycle_parameter_ready - cycle_last_input,
            time_parameter_ready - time_last_input);
        $display("First output latency: %0d cycles, %0d ns",
            cycle_first_output - cycle_last_input,
            time_first_output - time_last_input);
        $display("Output window       : %0d cycles, %0d ns",
            cycle_last_output - cycle_first_output,
            time_last_output - time_first_output);
        $display("Total frame         : %0d cycles, %0d ns",
            cycle_last_output - cycle_first_input,
            time_last_output - time_first_input);
    end
end
endtask

mac_matrix_calc #(
    .DATA_WIDTH(32)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_in),
    .x_in(x_in),
    .y_in(y_in),
    .Period_POINTS(N_POINTS_U16),
    .theta_Q13(theta_q13),
    .LS_done(ls_done),
    .LS_done_long(ls_done_long),
    .fifo_in(16'd0),
    .write_en(1'b0),
    .fifo_wr_en(fifo_wr_en),
    .fifo_din(fifo_din),
    .fifo_full(1'b0),
    .fifo_almost_full(1'b0)
);

always #(CLK_PERIOD_NS / 2) clk = ~clk;

initial begin
    $readmemh("../../../../../data/sine_values_N100.hex", sine_table);
    $readmemh("../../../../../data/cos_values_N100.hex", cos_table);

    result_file = $fopen("../../../../../results/rtl_ls_results_raw.csv", "w");
    if (result_file == 0) begin
        $display("ERROR: cannot open results/rtl_ls_results_raw.csv");
        $finish;
    end
    $fdisplay(result_file, "sample,x_corrected,y_corrected,theta_q13,theta_rad");

    clk = 1'b0;
    rst_n = 1'b0;
    valid_in = 1'b0;
    x_in = 32'd0;
    y_in = 32'd0;
    input_count = 0;
    output_count = 0;
    cycle_count = 0;
    parameter_solved_seen = 1'b0;
    parameter_ready_seen = 1'b0;
    first_output_seen = 1'b0;

    repeat (10) @(negedge clk);
    rst_n = 1'b1;

    for (input_index = 0; input_index < N_POINTS; input_index = input_index + 1) begin
        @(negedge clk);
        // MATLAB HEX data is unsigned 10-bit. The LS core expects U16Q16.
        x_in = {sine_table[input_index], 16'b0};
        y_in = {cos_table[input_index], 16'b0};
        valid_in = 1'b1;
    end

    @(negedge clk);
    valid_in = 1'b0;
    x_in = 32'd0;
    y_in = 32'd0;
end

always @(posedge clk) begin
    if (!rst_n) begin
        cycle_count = 0;
        input_count = 0;
        output_count = 0;
        parameter_solved_seen = 1'b0;
        parameter_ready_seen = 1'b0;
        first_output_seen = 1'b0;
    end else begin
        cycle_count = cycle_count + 1;

        if (valid_in && input_count < N_POINTS) begin
            if (input_count == 0) begin
                cycle_first_input = cycle_count;
                time_first_input = $time;
            end
            if (input_count == N_POINTS - 1) begin
                cycle_last_input = cycle_count;
                time_last_input = $time;
            end
            input_count = input_count + 1;
        end

        if (dut.para_solve_f32_done && !parameter_solved_seen) begin
            cycle_parameter_solved = cycle_count;
            time_parameter_solved = $time;
            parameter_solved_seen = 1'b1;
        end

        if (dut.para_f32_fix64q13_DONE && !parameter_ready_seen) begin
            cycle_parameter_ready = cycle_count;
            time_parameter_ready = $time;
            parameter_ready_seen = 1'b1;
        end

        if (fifo_wr_en && output_count < N_POINTS) begin
            if (!first_output_seen) begin
                cycle_first_output = cycle_count;
                time_first_output = $time;
                first_output_seen = 1'b1;
            end

            theta_rad = $itor($signed(fifo_din)) / 8192.0;
            $fdisplay(
                result_file,
                "%0d,%0d,%0d,%0d,%.10f",
                output_count,
                $signed(dut.x_LS_watch),
                $signed(dut.y_LS_watch),
                $signed(fifo_din),
                theta_rad
            );

            if (output_count == N_POINTS - 1) begin
                cycle_last_output = cycle_count;
                time_last_output = $time;
                write_latency_report;
            end

            output_count = output_count + 1;

            if (output_count == N_POINTS) begin
                $fclose(result_file);
                $display("PASS: exported %0d LS results", output_count);
                $finish;
            end
        end
    end
end

initial begin
    #5000000;
    $display("ERROR: timeout after exporting %0d of %0d results", output_count, N_POINTS);
    if (result_file != 0)
        $fclose(result_file);
    $finish;
end

endmodule
