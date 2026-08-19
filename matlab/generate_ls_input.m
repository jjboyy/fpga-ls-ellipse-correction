clc;
clear;
close all;

script_dir = fileparts(mfilename('fullpath'));
repo_dir = fileparts(script_dir);
data_dir = fullfile(repo_dir, 'data');

%% Quantization mode
% 'shared_range'      : both ADC channels use the same fixed range.
% 'independent_fixed' : each channel uses its own fixed range with margin.
% 'ideal_full_scale'  : each sampled record is independently mapped to
%                       0..1023; use only as an ideal verification baseline.
quantization_mode = 'independent_fixed';

%% Signal parameters
p = 0.3;
q = 0.2;
alpha = deg2rad(3);
sigma = 0;
Amx = 0.8;
Amy = 2;

N = 100;
f_sample = 10;
fs = N * f_sample;
t_sample = (0:N-1) / fs;

%% Two low-frequency raw signals (no high-frequency interference)
phase = 2 * pi * f_sample .* t_sample;
yssin = p + Amx * sin(phase) + sigma * randn(1, N);
yscos = q + Amy * cos(phase + alpha) + sigma * randn(1, N);

%% 10-bit ADC quantization
width = 10;
max_value = 2^width - 1;

switch quantization_mode
    case 'shared_range'
        % Same reference range and analog gain for both channels.
        x_adc_min = -2.5;
        x_adc_max =  2.5;
        y_adc_min = -2.5;
        y_adc_max =  2.5;

    case 'independent_fixed'
        % Two fixed analog front ends, each with about 10 percent margin.
        % These limits are configured in advance, not calculated from the
        % minimum and maximum values of the current sample record.
        x_adc_min = -0.6;
        x_adc_max =  1.2;
        y_adc_min = -2.0;
        y_adc_max =  2.4;

    case 'ideal_full_scale'
        % Ideal per-record normalization. This maximizes ADC-code usage but
        % assumes the extrema are known in advance, so it does not represent
        % an ordinary fixed-gain ADC front end.
        x_adc_min = min(yssin);
        x_adc_max = max(yssin);
        y_adc_min = min(yscos);
        y_adc_max = max(yscos);

    otherwise
        error('Unknown quantization_mode: %s', quantization_mode);
end

assert(all(yssin >= x_adc_min & yssin <= x_adc_max), ...
    'yssin exceeds the selected X-channel ADC range');
assert(all(yscos >= y_adc_min & yscos <= y_adc_max), ...
    'yscos exceeds the selected Y-channel ADC range');

x_adc = quantize_adc(yssin, x_adc_min, x_adc_max, max_value);
y_adc = quantize_adc(yscos, y_adc_min, y_adc_max, max_value);

write_hex_vector(fullfile(data_dir, 'sine_values_N100.hex'), x_adc, width);
write_hex_vector(fullfile(data_dir, 'cos_values_N100.hex'), y_adc, width);

% Save the physical ground truth and quantization configuration. The
% comparison script uses this file to distinguish algorithm accuracy from
% MATLAB-to-RTL implementation agreement.
save(fullfile(data_dir, 'ls_input_reference.mat'), ...
    'phase', 't_sample', 'yssin', 'yscos', 'x_adc', 'y_adc', ...
    'quantization_mode', 'p', 'q', 'alpha', 'sigma', 'Amx', 'Amy', ...
    'N', 'f_sample', 'fs', 'width', 'max_value', ...
    'x_adc_min', 'x_adc_max', 'y_adc_min', 'y_adc_max');

fprintf('Generated %d samples per channel.\n', N);
fprintf('Quantization mode: %s\n', quantization_mode);
fprintf('X physical range: %.3f to %.3f\n', x_adc_min, x_adc_max);
fprintf('Y physical range: %.3f to %.3f\n', y_adc_min, y_adc_max);
fprintf('X ADC range: %d to %d\n', min(x_adc), max(x_adc));
fprintf('Y ADC range: %d to %d\n', min(y_adc), max(y_adc));

figure('Name', 'LS input signals');
subplot(2, 1, 1);
plot(t_sample, yssin, 'LineWidth', 1.2);
hold on;
plot(t_sample, yscos, 'LineWidth', 1.2);
grid on;
xlabel('Time (s)');
ylabel('Amplitude');
legend('yssin', 'yscos');
title('Original low-frequency signals');

subplot(2, 1, 2);
plot(x_adc, y_adc, '.-');
axis equal;
grid on;
xlabel('X ADC code');
ylabel('Y ADC code');
title(sprintf('Quantized ellipse supplied to LS (%s)', ...
    strrep(quantization_mode, '_', '\_')));

function codes = quantize_adc(signal, adc_min, adc_max, max_value)
    codes = round((signal - adc_min) / (adc_max - adc_min) * max_value);
    codes = max(0, min(max_value, codes));
end

function write_hex_vector(path, values, width)
    hex_digits = ceil(width / 4);
    fid = fopen(path, 'w');
    assert(fid ~= -1, 'Cannot open %s', path);
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, ['%0' num2str(hex_digits) 'X\n'], values);
end
