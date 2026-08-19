clc;
clear;
close all;

script_dir = fileparts(mfilename('fullpath'));
repo_dir = fileparts(script_dir);
data_dir = fullfile(repo_dir, 'data');
result_dir = fullfile(repo_dir, 'results');

x = read_hex_vector(fullfile(data_dir, 'sine_values_N100.hex'));
y = read_hex_vector(fullfile(data_dir, 'cos_values_N100.hex'));
x = x(:);
y = y(:);
N = numel(x);

reference_file = fullfile(data_dir, 'ls_input_reference.mat');
if ~isfile(reference_file)
    error('Run matlab/generate_ls_input.m first: %s', reference_file);
end
truth = load(reference_file);

assert(isequal(x, double(truth.x_adc(:))), ...
    'The X HEX file does not match ls_input_reference.mat. Regenerate inputs.');
assert(isequal(y, double(truth.y_adc(:))), ...
    'The Y HEX file does not match ls_input_reference.mat. Regenerate inputs.');

%% MATLAB LS reference model
R = [sum(x.^2 .* y.^2), sum(x .* y.^3),   sum(x.^2 .* y), sum(x .* y.^2), sum(x .* y); ...
     sum(x .* y.^3),    sum(y.^4),         sum(x .* y.^2), sum(y.^3),      sum(y.^2); ...
     sum(x.^2 .* y),    sum(x .* y.^2),    sum(x.^2),      sum(x .* y),    sum(x); ...
     sum(x .* y.^2),    sum(y.^3),         sum(x .* y),    sum(y.^2),      sum(y); ...
     sum(x .* y),       sum(y.^2),         sum(x),         sum(y),         N];

rhs = -[sum(x.^3 .* y); sum(x.^2 .* y.^2); sum(x.^3); ...
        sum(x.^2 .* y); sum(x.^2)];

L = my_cholesky(R);
S = my_inverse(L);
coef = (S' * S) * rhs;
A = coef(1);
B = coef(2);
C = coef(3);
D = coef(4);

x0 = (2 * B * C - A * D) / (A^2 - 4 * B);
y0 = (2 * D - A * C) / (A^2 - 4 * B);
r_hat = sqrt(B);
alpha_hat = 0.5 * A / r_hat;

x_corrected = x - x0;
y_corrected = (1 / cos(alpha_hat)) .* ...
    ((x - x0) .* sin(alpha_hat) + r_hat .* (y - y0));
theta_matlab = atan2(x_corrected, y_corrected);

%% RTL results and true phase
rtl_file = fullfile(result_dir, 'rtl_ls_results_raw.csv');
if ~isfile(rtl_file)
    error('Run the Vivado/ModelSim simulation first: %s', rtl_file);
end

rtl = readtable(rtl_file);
n = min([height(rtl), N, numel(truth.phase)]);
theta_true = truth.phase(1:n).';
theta_true = theta_true(:);
theta_true_wrapped = wrap_error(theta_true);
theta_matlab_n = theta_matlab(1:n);
theta_rtl = rtl.theta_rad(1:n);

error_rtl_matlab = wrap_error(theta_rtl - theta_matlab_n);
error_matlab_true = wrap_error(theta_matlab_n - theta_true);
error_rtl_true = wrap_error(theta_rtl - theta_true);

[mae_rm, rmse_rm, max_rm] = error_metrics(error_rtl_matlab);
[mae_mt, rmse_mt, max_mt] = error_metrics(error_matlab_true);
[mae_rt, rmse_rt, max_rt] = error_metrics(error_rtl_true);

comparison = ["RTL_vs_MATLAB"; "MATLAB_vs_true"; "RTL_vs_true"];
points = repmat(n, 3, 1);
MAE_rad = [mae_rm; mae_mt; mae_rt];
RMSE_rad = [rmse_rm; rmse_mt; rmse_rt];
MaxError_rad = [max_rm; max_mt; max_rt];
MAE_deg = rad2deg(MAE_rad);
RMSE_deg = rad2deg(RMSE_rad);
MaxError_deg = rad2deg(MaxError_rad);

phase_summary = table(comparison, points, MAE_rad, RMSE_rad, MaxError_rad, ...
    MAE_deg, RMSE_deg, MaxError_deg);
writetable(phase_summary, fullfile(result_dir, 'phase_validation_summary.csv'));

% Retain the original one-row output for compatibility with existing notes.
legacy_summary = table(n, mae_rm, rmse_rm, max_rm, ...
    'VariableNames', {'Points', 'MAE_rad', 'RMSE_rad', 'MaxError_rad'});
writetable(legacy_summary, fullfile(result_dir, 'error_summary.csv'));

%% Parameter estimates against the configured physical ground truth
x_scale = truth.max_value / (truth.x_adc_max - truth.x_adc_min);
y_scale = truth.max_value / (truth.y_adc_max - truth.y_adc_min);
x0_true = (truth.p - truth.x_adc_min) * x_scale;
y0_true = (truth.q - truth.y_adc_min) * y_scale;
r_true = (truth.Amx * x_scale) / (truth.Amy * y_scale);
alpha_true = truth.alpha;

parameter = ["x0_adc"; "y0_adc"; "amplitude_ratio"; "alpha_rad"; "alpha_deg"];
true_value = [x0_true; y0_true; r_true; alpha_true; rad2deg(alpha_true)];
matlab_estimate = [x0; y0; r_hat; alpha_hat; rad2deg(alpha_hat)];
absolute_error = abs(matlab_estimate - true_value);
parameter_summary = table(parameter, true_value, matlab_estimate, absolute_error);
writetable(parameter_summary, fullfile(result_dir, 'parameter_validation_summary.csv'));

%% Ellipse-to-circle quality
raw_radius = hypot(x - x0_true, y - y0_true);
matlab_radius = hypot(x_corrected, y_corrected);
rtl_x_corrected = double(rtl.x_corrected(1:n));
rtl_y_corrected = double(rtl.y_corrected(1:n));
rtl_radius = hypot(rtl_x_corrected, rtl_y_corrected);

trajectory = ["raw_ADC"; "MATLAB_corrected"; "RTL_corrected"];
radius_mean = [mean(raw_radius); mean(matlab_radius); mean(rtl_radius)];
radius_std = [std(raw_radius); std(matlab_radius); std(rtl_radius)];
circularity_CV = radius_std ./ radius_mean;
trajectory_summary = table(trajectory, radius_mean, radius_std, circularity_CV);
writetable(trajectory_summary, fullfile(result_dir, 'trajectory_validation_summary.csv'));

%% Console report
fprintf('Quantization mode: %s\n', truth.quantization_mode);
fprintf('Compared points : %d\n\n', n);
disp(phase_summary);
disp(parameter_summary);
disp(trajectory_summary);

%% Figures for the report
sample = (0:n-1).';
phase_figure = figure('Name', 'LS phase validation', 'Color', 'w');
subplot(2, 1, 1);
plot(sample, theta_true_wrapped, 'k-', 'LineWidth', 1.3);
hold on;
plot(sample, theta_matlab_n, 'b--', 'LineWidth', 1.1);
plot(sample, theta_rtl, 'r:', 'LineWidth', 1.2);
grid on;
xlabel('Sample');
ylabel('Phase (rad)');
legend('True', 'MATLAB LS', 'RTL LS', 'Location', 'best');
title('True phase, MATLAB LS, and RTL LS');

subplot(2, 1, 2);
plot(sample, error_matlab_true, 'b-', 'LineWidth', 1.0);
hold on;
plot(sample, error_rtl_true, 'r--', 'LineWidth', 1.0);
plot(sample, error_rtl_matlab, 'Color', [0.2 0.6 0.2], 'LineWidth', 1.0);
grid on;
xlabel('Sample');
ylabel('Wrapped error (rad)');
legend('MATLAB - true', 'RTL - true', 'RTL - MATLAB', 'Location', 'best');
title('Phase errors');
exportgraphics(phase_figure, fullfile(result_dir, 'phase_validation.png'), ...
    'Resolution', 200);

trajectory_figure = figure('Name', 'Ellipse correction validation', 'Color', 'w');
subplot(1, 3, 1);
plot(x, y, '.-');
axis equal;
grid on;
xlabel('X ADC');
ylabel('Y ADC');
title('Before correction');

subplot(1, 3, 2);
plot(x_corrected, y_corrected, '.-');
axis equal;
grid on;
xlabel('X corrected');
ylabel('Y corrected');
title('MATLAB corrected');

subplot(1, 3, 3);
plot(rtl_x_corrected, rtl_y_corrected, '.-');
axis equal;
grid on;
xlabel('X corrected');
ylabel('Y corrected');
title('RTL corrected');
exportgraphics(trajectory_figure, fullfile(result_dir, 'trajectory_validation.png'), ...
    'Resolution', 200);

function values = read_hex_vector(path)
    fid = fopen(path, 'r');
    assert(fid ~= -1, 'Cannot open %s', path);
    raw = textscan(fid, '%s');
    fclose(fid);
    values = double(hex2dec(raw{1}));
end

function error = wrap_error(delta)
    error = atan2(sin(delta), cos(delta));
end

function [mae, rmse, max_error] = error_metrics(error)
    mae = mean(abs(error));
    rmse = sqrt(mean(error.^2));
    max_error = max(abs(error));
end
