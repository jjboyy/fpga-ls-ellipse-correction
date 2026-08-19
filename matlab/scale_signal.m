% 动态缩放函数（确保信号在[0, max_value]范围内）
function scaled_signal = scale_signal(signal, max_value)
    min_raw = min(signal);
    max_raw = max(signal);
    scale = max_value / (max_raw - min_raw);
    offset = -min_raw * scale;
    scaled_signal = round(signal * scale + offset);
    scaled_signal = max(0, min(max_value, scaled_signal)); % 确保不越界
end