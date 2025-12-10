# ==== CONFIGURABLE VARIABLES ====
VERILATOR       := verilator

TEST_MODULE     := tb_one_mac_gemm

INCLUDE_DIRS    := +incdir+.

FLIST_DIRS		:= flists
FILELIST        := $(TEST_MODULE).flist
FILE_PATH 		:= $(FLIST_DIRS)/$(FILELIST)

# Verilator 基础标志
VLT_FLAGS       := -O3
VLT_FLAGS       += --trace
VLT_FLAGS	    += --trace-structs

# Verilator 覆盖率标志
VLT_COV_FLAGS   := --coverage
VLT_COV_FLAGS   += --coverage-line
VLT_COV_FLAGS   += --coverage-toggle
VLT_COV_FLAGS   += --assert

# Verilator 警告抑制
VLT_WAIVE 		:= -Wno-CASEINCOMPLETE
VLT_WAIVE 		+= -Wno-WIDTHTRUNC
VLT_WAIVE 		+= -Wno-WIDTHEXPAND
VLT_WAIVE 		+= -Wno-fatal

# QuestaSim 标志 (可选)
QST_FLAGS	    := -voptargs=\"+acc\"
QST_FLAGS	    += -coverage

# 目录
BIN_DIR			:= bin
OBJ_DIR         := obj_dir
COV_DIR         := coverage_report

# 从文件列表获取源文件
SRCS := $(shell cat $(FILE_PATH))

# ==== 默认目标 ====
all: $(BIN_DIR)/$(TEST_MODULE)

$(BIN_DIR):
	mkdir -p $@

# ==== 普通编译 (无覆盖率) ====
$(BIN_DIR)/$(TEST_MODULE): $(BIN_DIR) $(FILE_PATH)
	$(VERILATOR) --sv $(SRCS) $(INCLUDE_DIRS) $(VLT_WAIVE) $(VLT_FLAGS) --binary -o $(TEST_MODULE)
	cp $(OBJ_DIR)/$(TEST_MODULE) $(BIN_DIR)/.
	rm -rf $(OBJ_DIR)

# ==== 带覆盖率编译 ====
.PHONY: coverage
coverage: $(BIN_DIR) $(FILE_PATH)
	@echo "=========================================="
	@echo "Building with coverage instrumentation..."
	@echo "=========================================="
	$(VERILATOR) --sv $(SRCS) $(INCLUDE_DIRS) $(VLT_WAIVE) $(VLT_FLAGS) $(VLT_COV_FLAGS) --binary -o $(TEST_MODULE)_cov
	@echo ""
	@echo "=========================================="
	@echo "Running simulation with coverage..."
	@echo "=========================================="
	./$(OBJ_DIR)/$(TEST_MODULE)_cov
	@echo ""
	@echo "=========================================="
	@echo "Generating coverage report..."
	@echo "=========================================="
	mkdir -p $(COV_DIR)
	verilator_coverage --annotate $(COV_DIR)/annotated coverage.dat
	verilator_coverage --write-info $(COV_DIR)/coverage.info coverage.dat
	@echo ""
	@echo "=========================================="
	@echo "Coverage Summary:"
	@echo "=========================================="
	verilator_coverage coverage.dat
	@echo ""
	@echo "Detailed report: $(COV_DIR)/annotated/"
	@echo "=========================================="

# ==== 仅运行覆盖率报告 (假设已运行仿真) ====
.PHONY: coverage-report
coverage-report:
	@if [ ! -f coverage.dat ]; then \
		echo "Error: coverage.dat not found. Run 'make coverage' first."; \
		exit 1; \
	fi
	mkdir -p $(COV_DIR)
	verilator_coverage --annotate $(COV_DIR)/annotated coverage.dat
	verilator_coverage coverage.dat
	@echo ""
	@echo "Report generated in $(COV_DIR)/annotated/"

# ==== QuestaSim 目标 (可选) ====
questasim.do: $(FILE_PATH)
	@echo 'Generating $@'
	@echo vlib work > $@
	@echo vlog +cover +acc -sv -f $(FILE_PATH) $(INCLUDE_DIRS) >> $@
	@echo vsim $(QST_FLAGS) work.$(TEST_MODULE) >> $@
	@echo add wave -r \/\* >> $@
	@echo run -all >> $@

questasim-run: questasim.do
	@echo 'Running Questasim simulation w/ Command Line Interface'
	vsim -c -do questasim.do

questasim-run-gui: questasim.do
	@echo 'Running Questasim simulation w/ GUI'
	vsim -gui -do questasim.do

# ==== 清理 ====
.PHONY: clean
clean:
	rm -rf $(OBJ_DIR) $(BIN_DIR) $(COV_DIR) *.vcd *.dat transcript *.do work *.wlf *covhtmlreport *report.txt

# ==== 帮助 ====
.PHONY: help
help:
	@echo "GEMM Accelerator Makefile"
	@echo "========================="
	@echo ""
	@echo "Usage:"
	@echo "  make                    - Build simulation binary"
	@echo "  make coverage           - Build, run, and generate coverage report"
	@echo "  make coverage-report    - Generate report from existing coverage.dat"
	@echo "  make clean              - Remove all generated files"
	@echo "  make help               - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  TEST_MODULE=<name>      - Specify test module (default: tb_one_mac_gemm)"
	@echo ""
	@echo "Examples:"
	@echo "  make TEST_MODULE=tb_mac_pe"
	@echo "  make coverage TEST_MODULE=tb_one_mac_gemm"