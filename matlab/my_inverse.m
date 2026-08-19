function S = my_inverse(L)
    % 检查输入矩阵是否为方阵
    [n, m] = size(L);
    if n ~= m
        error('输入矩阵必须是方阵');
    end
    
    % 初始化 S 矩阵为零矩阵
    S = zeros(n, n);
    
    % 计算对角线元素
    for i = 1:n
        S(i, i) = 1 / L(i, i);
    end
    
    % 计算非对角线元素
    for i = 2:n
        for j = 1:i-1
            sum_term = 0;
            for k = j:i-1
                sum_term = sum_term + L(i, k) * S(k, j);
            end
            S(i, j) = -sum_term / L(i, i);
        end
    end
    
    % 上三角部分已经初始化为 0，无需额外操作
end