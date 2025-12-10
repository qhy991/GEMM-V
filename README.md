# GEMM Accelerator - Reconfigurable Systolic Array for Matrix Multiplication

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## 📖 项目概述

本项目实现了一个基于**可重构脉动阵列架构**的通用矩阵乘法（GEMM）硬件加速器。该加速器针对不同形状的矩阵工作负载进行了优化设计，通过**动态互连重构**和**128-bit 宽内存接口**，在所有测试用例中实现了 **100% 的硬件利用率**和**理论最优延迟**。

> 📄 **项目报告**: 完整的设计分析请参阅 `cpaep_2526_report_ZHAO.pdf`

### ✨ 主要特性

| 特性 | 说明 |
|------|------|
| **可重构阵列** | 支持 4×16 ↔ 16×4 动态模式切换 |
| **64 MAC 单元** | 4 个 4×4 PE Block，峰值 64 MACs/cycle |
| **128-bit 带宽** | 满足峰值操作数需求，无停顿操作 |
| **100% 利用率** | 消除结构性冒险，所有用例空间利用率 100% |
| **INT8 输入/INT32 累加** | 防止大 K 维度累加溢出 |

---

## 🎯 设计目标与规格

### 工作负载要求

加速器必须高效处理三种典型矩阵形状：

| 测试用例 | 维度 (M×K×N) | 特点 | 目标延迟 |
|----------|--------------|------|----------|
| **Case 1** | 4×64×16 | 宽矩阵，标准模式 | 64 cycles |
| **Case 2** | 16×64×4 | 高矩阵，需阵列重构 | 64 cycles |
| **Case 3** | 32×32×32 | 大方阵，顺序分块 | 512 cycles |

### 硬件规格

| 参数 | 规格 |
|------|------|
| 计算单元 | 64 MACs (4 × 4×4 PE Block) |
| 计算峰值 | 64 MACs/cycle |
| 内存带宽 | 32 Bytes/cycle (双读端口) |
| 输入精度 | INT8 (有符号) |
| 累加器精度 | INT32 (有符号) |
| SRAM 接口 | 128-bit 宽度 |
| 脊点 (Ridge Point) | AI = 2.0 MACs/Byte |

---

## 🏗️ 架构设计

### 关键设计权衡

#### 1. 可重构互连 vs 固定互连

```
┌─────────────────────────────────────────────────────────────────┐
│                    动态输入分配层                                 │
│  ┌─────────────┐                      ┌─────────────┐           │
│  │   MUX A     │  根据矩阵形状         │   MUX B     │           │
│  │  (A矩阵)    │  动态重构数据流       │  (B矩阵)    │           │
│  └──────┬──────┘                      └──────┬──────┘           │
│         │                                    │                   │
│         ▼                                    ▼                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              PE Array (64 MACs)                          │    │
│  │   Wide Mode (4×16):  A 广播, B 单播 → Case 1 & 3         │    │
│  │   Tall Mode (16×4):  A 单播, B 广播 → Case 2             │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

- **问题**：固定 4×16 阵列处理 Case 2 (16×4 输出) 时，仅 25% 利用率
- **解决**：引入 MUX 层，虚拟重塑为 16×4，利用率提升至 **100%**
- **代价**：增加组合逻辑和路由复杂性

#### 2. 128-bit 宽内存接口

- **需求**：Case 2 每周期需消耗 16 行矩阵 A 数据 (16 × 8-bit = 128-bit)
- **结果**：带宽饱和，实现无停顿 (no-stall) 操作

### 数据流模式

| 模式 | 阵列配置 | A 矩阵 | B 矩阵 | 适用场景 |
|------|----------|--------|--------|----------|
| **Wide Mode** | 4×16 | 广播 | 单播 | Case 1, Case 3 |
| **Tall Mode** | 16×4 | 单播 | 广播 | Case 2 |

### 内存布局策略

为配合 128-bit 读取带宽，采用自适应数据打包：
- **矩阵 A**：转置存储（垂直打包）
- **矩阵 B**：标准存储（水平打包）
- **效果**：一次读取即获得所需的 16 个元素

### 系统框图

```
                    ┌─────────────────────────────────────────────────────────────┐
                    │                  GEMM Accelerator Top                        │
                    │  ┌─────────────────────────────────────────────────────┐    │
                    │  │              GEMM Controller (FSM)                   │    │
                    │  │   ┌──────────┐ ┌──────────┐ ┌──────────┐            │    │
                    │  │   │ M Counter│ │ K Counter│ │ N Counter│            │    │
                    │  │   └──────────┘ └──────────┘ └──────────┘            │    │
                    │  └─────────────────────────────────────────────────────┘    │
                    │                                                              │
                    │  ┌──────────────────────────────────────────────────────┐   │
                    │  │         动态重构 PE 阵列 (64 MACs)                     │   │
                    │  │   ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐│   │
                    │  │   │PE Block 0│ │PE Block 1│ │PE Block 2│ │PE Block 3││   │
                    │  │   │  (4×4)   │ │  (4×4)   │ │  (4×4)   │ │  (4×4)   ││   │
                    │  │   └──────────┘ └──────────┘ └──────────┘ └──────────┘│   │
                    │  └──────────────────────────────────────────────────────┘   │
┌─────────────┐     │                         │                                    │     ┌─────────────┐
│  SRAM A     │◄────┤  Address Generation     │                                    ├────►│  SRAM C     │
│ 128-bit R   │     │       Unit (AGU)        │                                    │ W   │ 128-bit W   │
└─────────────┘     │                         ▼                                    │     └─────────────┘
                    │              ┌──────────────────────┐                        │
┌─────────────┐     │              │   Mode Detection     │                        │
│  SRAM B     │◄────┤              │   (is_case2 信号)    │                        │
│ 128-bit R   │     │              └──────────────────────┘                        │
└─────────────┘     └─────────────────────────────────────────────────────────────┘
```

### 模块层次结构

```
gemm_accelerator_top.sv          # 顶层模块 (含模式检测、AGU、写回逻辑)
├── gemm_controller.sv           # 控制器 (FSM + 嵌套循环计数)
│   ├── ceiling_counter.sv       # M 维度计数器
│   ├── ceiling_counter.sv       # K 维度计数器 (最内层)
│   └── ceiling_counter.sv       # N 维度计数器
├── pe_block_4x4.sv              # PE Block 0 (4×4 MAC 阵列)
│   └── general_mac_pe.sv ×16    # 16 个 Output Stationary MAC
├── pe_block_4x4.sv              # PE Block 1
├── pe_block_4x4.sv              # PE Block 2
└── pe_block_4x4.sv              # PE Block 3
```

---

## 📊 性能分析

### Roofline 模型

```
          ▲ Throughput (MACs/cycle)
          │
       64 ├─────────────────────────●────── Compute Roof (64 MACs/cycle)
          │                       ╱ 
          │                     ╱   
          │                   ╱     ● Case 1 & 2 (AI=3.2, Compute-bound)
          │                 ╱       
          │               ╱         ● Case 3 (AI=16.0, Deep Compute-bound)
          │             ╱           
          │           ╱             
          │         ╱ Memory Roof   
          │       ╱   (32 B/cycle)  
          │     ╱                   
          └───●─────────────────────────────► Arithmetic Intensity (MACs/Byte)
              Ridge Point (AI=2.0)
```

### 性能结果

| 测试用例 | 理论延迟 | 实测延迟 | 利用率 | 状态 |
|----------|----------|----------|--------|------|
| Case 1 (4×64×16) | 64 cycles | **63 cycles** | 100% | ✅ Compute-bound |
| Case 2 (16×64×4) | 64 cycles | **63 cycles** | 100% | ✅ Compute-bound |
| Case 3 (32×32×32) | 512 cycles | **511 cycles** | 100% | ✅ Deep Compute-bound |

> **关键成果**：实测延迟与理论延迟完全一致，表明在计算阶段实现了：
> - 100% PE 空间利用率
> - 无空闲周期
> - 无流水线停顿

### 关键路径

- **识别路径**：SRAM 读取端口 → MAC PE 累加器输入
- **优化建议**：可插入流水线寄存器提升频率（代价：增加面积和控制复杂性）

---

## 🔄 扩展性分析

### 场景 1: 扩展至 256 PEs

| 方面 | 分析 |
|------|------|
| **建议配置** | 16×16 广播阵列 |
| **带宽需求** | 现有 128-bit 仍足够 (每周期 16 元素) |
| **风险** | 小矩阵 (M=4) 利用率降至 25% |

### 场景 2: 带宽减半/四分之一

| 方面 | 影响 |
|------|------|
| **状态变化** | 从 Compute-bound → **Memory-bound** |
| **必要措施** | 引入多周期取数 (Multi-cycle fetching) 和输入缓冲 |
| **性能影响** | 吞吐量线性下降 (带宽减半 → 性能减半) |

---

## 📁 目录结构

```
cpaep_2526_Project_code/
├── rtl/                          # RTL 源代码
│   ├── gemm/                     # GEMM 加速器核心模块
│   │   ├── gemm_accelerator_top.sv    # 顶层 (模式检测 + AGU + 写回)
│   │   ├── gemm_controller.sv         # 控制状态机
│   │   ├── general_mac_pe.sv          # MAC 处理单元 (Output Stationary)
│   │   └── pe_block_4x4.sv            # 4×4 PE Block
│   └── common/                   # 通用模块
│       ├── ceiling_counter.sv         # 带上限嵌套计数器
│       └── single_port_memory.sv      # 单端口 SRAM
├── tb/                           # 测试平台
│   ├── tb_one_mac_gemm.sv             # 主测试平台 (3 个测试用例)
│   ├── tb_mac_pe.sv                   # MAC PE 单元测试
│   ├── tb_ceiling_counter.sv          # 计数器单元测试
│   └── tb_single_port_memory.sv       # SRAM 单元测试
├── includes/                     # SystemVerilog 头文件
│   ├── common_tasks.svh               # 通用任务
│   ├── test_tasks.svh                 # 测试任务
│   └── test_func.svh                  # 测试函数 (含 Golden Model)
├── flists/                       # 文件列表
├── bin/                          # 编译输出目录
├── Makefile                      # 构建脚本
└── LICENSE                       # Apache 2.0 许可证
```

---

## 🚀 快速开始

### 环境要求

- **Verilator** >= 5.0（开源 Verilog/SystemVerilog 仿真器）
- **Make** 构建工具
- **C++ 编译器**（如 clang++ 或 g++）

### 安装 Verilator

```bash
# macOS (Homebrew)
brew install verilator

# Ubuntu/Debian
sudo apt-get install verilator

# 验证安装
verilator --version
```

### 编译与运行

```bash
# 1. 编译顶层测试平台
make TEST_MODULE=tb_one_mac_gemm

# 2. 运行仿真
./bin/tb_one_mac_gemm

# 3. 清理构建文件
make clean
```

### 覆盖率测试 (Verilator)

```bash
# 一键编译、运行并生成覆盖率报告
make coverage

# 查看覆盖率摘要
verilator_coverage coverage.dat

# 查看逐行覆盖详情
cat coverage_report/annotated/gemm_accelerator_top.sv
```

**覆盖率报告格式**：
| 前缀 | 含义 |
|------|------|
| `%000000` | 未覆盖 (需关注) |
| `~000xxx` | 部分覆盖 |
| ` 001234` | 完全覆盖 (执行次数) |

### 预期输出

```
========================================
Starting Case 1
Dimensions -> M: 4, K: 64, N: 16
Starting Hardware Execution...
Case 1 Finished.
----------------------------------------
Cycles Taken: 63
----------------------------------------
Result matrix C verification passed!

========================================
Starting Case 2
Dimensions -> M: 16, K: 64, N: 4
Starting Hardware Execution...
Case 2 Finished.
----------------------------------------
Cycles Taken: 63
----------------------------------------
Result matrix C verification passed!

========================================
Starting Case 3
Dimensions -> M: 32, K: 32, N: 32
Starting Hardware Execution...
Case 3 Finished.
----------------------------------------
Cycles Taken: 511
----------------------------------------
Result matrix C verification passed!

========================================
All 3 Cases Verified Successfully!
```

---

## 🧪 验证与测试

### 测试策略

验证采用**模块级**和**系统级**双重策略：

#### 单元测试 (Unit Tests)

| 测试平台 | 验证内容 |
|----------|----------|
| `tb_mac_pe` | PE 算术逻辑正确性 |
| `tb_ceiling_counter` | 计数器循环嵌套逻辑 |
| `tb_single_port_memory` | SRAM 读写时序和数据对齐 |

#### 顶层集成测试 (Top-Level Test)

主测试平台 `tb_one_mac_gemm` 执行三个强制性工作负载：

| 用例 | 验证目标 |
|------|----------|
| **Case 1** (4×64×16) | 默认水平阵列模式 |
| **Case 2** (16×64×4) | 垂直阵列模式，数据通路重构逻辑 |
| **Case 3** (32×32×32) | 大矩阵顺序分块 (Tiling) 策略 |

### 验证流程

1. **Golden Model**：软件参考实现 `gemm_golden()` 计算期望结果
2. **随机激励**：使用 `$urandom()` 生成随机输入矩阵
3. **逐元素比对**：`verify_result_c()` 对比硬件输出与参考结果
4. **延迟测量**：捕捉 `start_i` 和 `done_o` 信号边沿计算周期数

### 代码覆盖率 (QuestaSim)

> ⚠️ 覆盖率数据来自 QuestaSim 仿真工具，Verilator 可运行功能测试但覆盖率收集方式不同

#### 总体覆盖率：**85.63%**

| 覆盖率类型 | 指标 | 说明 |
|------------|------|------|
| **语句覆盖率** | 98.14% | 顶层模块每行代码至少执行一次，证明控制器、AGU、PE 阵列集成稳健 |
| **分支覆盖率** | 93.33% | if/else、case 分支全覆盖，验证 Wide/Tall 模式切换正确 |
| **FSM 状态覆盖率** | 100% | 控制器所有状态遍历，无死角 |
| **翻转覆盖率** | ~43% | 较低但符合预期 (见下方说明) |

#### 翻转覆盖率低的原因

翻转覆盖率检查信号是否发生 0→1 和 1→0 变化。低分原因：
- 计数器按通用位宽设计 (16/32 位)
- 测试用例仅要求计数到 64
- 计数器高位 (MSB) 始终为 0，未发生翻转

**结论**：这是合理的工程权衡，非验证缺陷。

### 已知验证缺口

| 缺口 | 说明 | 风险等级 |
|------|------|----------|
| 非 4 倍数维度 | 未测试 5×7 等角点情况 | 中 |
| 背靠背测试 | 缺乏连续 GEMM 压力测试 | 低 |
| 溢出边界 | 未验证极端数值下累加器溢出 | 中 |

---

## 🔧 Makefile 命令

| 命令 | 说明 |
|------|------|
| `make` | 编译默认测试 (tb_one_mac_gemm) |
| `make TEST_MODULE=<name>` | 编译指定测试 |
| `make clean` | 清理构建产物 |

可用测试模块：
- `tb_one_mac_gemm` - 顶层 GEMM 测试 ⭐
- `tb_mac_pe` - MAC PE 单元测试
- `tb_ceiling_counter` - 计数器测试
- `tb_single_port_memory` - SRAM 测试

---

## 📄 许可证

本项目采用 [Apache License 2.0](LICENSE) 许可证。

---

## 🔗 相关资源

- **项目报告**: `cpaep_2526_report_ZHAO.pdf` (详细设计分析)
- **KU Leuven CPAEP 课程**: Computer Architecture & Embedded Processors
- **Verilator 官方文档**: https://verilator.org/guide/latest/

---

## 💡 设计亮点总结

| 亮点 | 描述 |
|------|------|
| **动态重构** | MUX 层实现 4×16 ↔ 16×4 虚拟重塑，消除结构性冒险 |
| **带宽匹配** | 128-bit 接口满足峰值需求，实现 no-stall 操作 |
| **理论最优** | 所有用例达到理论最小延迟 |
| **高利用率** | Case 2 利用率从 25% 提升至 100% |
| **开源验证** | 完全基于 Verilator 开源工具链 |