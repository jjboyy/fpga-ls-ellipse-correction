# FPGA Least-Squares Ellipse Correction

Standalone FPGA implementation of the least-squares (LS) ellipse-correction
stage. MATLAB and RTL verification use the same 100 input samples.

## Status

- Behavioral RTL simulation verified: 100 output samples are exported.
- Target device: Xilinx Artix-7 `xc7a35tfgg484-2`.
- Board testing has not been performed.
- The initial 100 MHz timing check did not close (`WNS = -1.158 ns`).
- The committed representative case uses `N = 100` and `sigma = 0`; parameter
  sweeps for noise and channel mismatch are future work.

## Requirements

- Vivado 2023.1
- ModelSim SE-64 2020.4, or Vivado Simulator
- MATLAB

## Reproduce

Create the local Vivado project from a Vivado Tcl shell:

```tcl
source scripts/create_project.tcl
```

Generate the shared 10-bit input vectors in MATLAB:

```matlab
run('matlab/generate_ls_input.m')
```

Run RTL simulation in Vivado Tcl:

```tcl
source scripts/run_modelsim.tcl
```

A successful simulation prints `PASS: exported 100 LS results` and writes the
local file `results/rtl_ls_results_raw.csv`.

Compare MATLAB and RTL outputs:

```matlab
run('matlab/compare_rtl_ls.m')
```

The `quantization_mode` in `matlab/generate_ls_input.m` switches between
shared-range, independent fixed-range, and ideal full-scale quantization.

## Layout

```text
rtl/       LS RTL source files
ip/        Vivado IP configurations (.xci)
ip_repo/   Packaged HLS IP definition for u128_to_f32
tb/        Standalone LS testbench
data/      Canonical 100-point input vectors
matlab/    Input generation and comparison scripts
scripts/   Vivado project and simulation Tcl scripts
results/   Selected validation figures and summary metrics
docs/      Stage-result report
```

## Results

`results/` retains the phase and trajectory figures plus phase, parameter,
trajectory, and latency summary CSV files. Generated Vivado caches, run
directories, waveforms, logs, and raw RTL output are ignored by Git and can be
recreated locally.

## License

This project is licensed under the MIT License.

---

# 中文说明

## 项目简介

本项目是从 EMD + LS 信号处理工程中独立整理出的最小二乘法（LS）椭圆校正模块。MATLAB 参考模型与 FPGA RTL 仿真共用同一组 100 点输入数据，用于验证 LS 参数估计与相位校正功能。

## 当前状态

- 行为级 RTL 仿真已通过，可导出 100 个有效输出点。
- 目标器件为 Xilinx Artix-7 `xc7a35tfgg484-2`。
- 尚未进行 FPGA 板级测试，当前结论均来自仿真。
- 初步 100 MHz 时序检查未通过，`WNS = -1.158 ns`，仍需进一步进行 IP 时钟配置与长组合路径优化。
- 当前提交的是 `N = 100`、`sigma = 0` 的代表性测试工况；噪声、偏置、幅值失配和相位失配的多参数鲁棒性测试尚未完成。

## 环境要求

- Vivado 2023.1
- ModelSim SE-64 2020.4，或 Vivado Simulator
- MATLAB

## 复现流程

### 1. 创建 Vivado 工程

在仓库根目录打开 Vivado Tcl Shell，执行：

```tcl
source scripts/create_project.tcl
```

该命令会在本地重新生成 `vivado/CORDIC_LS_only.xpr`。Vivado 自动生成的工程、缓存和实现文件均不纳入 Git。综合顶层为 `mac_matrix_calc`，仿真顶层为 `tb_ls`。

### 2. 生成共享输入数据

在 MATLAB 中执行：

```matlab
run('matlab/generate_ls_input.m')
```

脚本会生成两路带有直流偏置、幅值失配与相位失配的 10 位 ADC 输入，并保存到 `data/`。通过 `quantization_mode` 可切换共享量程、双通道固定量程和理想满量程三种量化模式。

### 3. 运行 RTL 仿真

在 Vivado Tcl 中执行：

```tcl
source scripts/run_modelsim.tcl
```

也可以将 `tb_ls` 设为仿真顶层后使用 Vivado Simulator。仿真成功时将打印：

```text
PASS: exported 100 LS results
```

仿真会生成本地文件 `results/rtl_ls_results_raw.csv`，该文件可重复生成，因此不会提交到 Git。

### 4. MATLAB 对比验证

RTL 仿真完成后，在 MATLAB 中执行：

```matlab
run('matlab/compare_rtl_ls.m')
```

该脚本会计算 MATLAB 与 RTL 的相位误差，并分别与已知真实相位进行对比；同时更新参数估计误差、轨迹校正效果图和结果汇总文件。

## 目录说明

```text
rtl/       LS RTL 源码
ip/        Vivado IP 配置文件（.xci）
ip_repo/   u128_to_f32 的封装 HLS IP
tb/        独立 LS 测试平台
data/      固定的 100 点输入数据
matlab/    数据生成、参考模型与对比脚本
scripts/   Vivado 建工程与仿真 Tcl 脚本
results/   保留的验证图与指标汇总
docs/      阶段成果文档
```

## 结果文件

`results/` 中保留了相位验证图、轨迹校正图，以及相位、参数、轨迹和时延的汇总 CSV。Vivado 缓存、实现文件、波形、日志和原始 RTL 输出均由 `.gitignore` 排除，可在本地重新生成。
