function L = my_cholesky(R)
    % 输入：对称正定矩阵 R
    % 输出：下三角矩阵 L，使得 R = L * L'
    
    n = size(R, 1);
    L = zeros(n, n); % 初始化下三角矩阵
    
    for j = 1:n
        % 计算对角线元素 L(j,j)
        sum_sq = sum(L(j, 1:j-1).^2);
        L(j,j) = sqrt(R(j,j) - sum_sq);
        % 计算非对角线元素 L(i,j) (i > j)
        for i = j+1:n
            sum_prod = sum(L(i, 1:j-1) .* L(j, 1:j-1));
            L(i,j) = (R(i,j) - sum_prod) / L(j,j);
        end
    end
end

