# ============================================================
# HIS 医院信息系统 - GNU Make 构建脚本
# 适用于 MinGW-w64 / GCC / Linux / macOS（Windows 下可用 MSYS2 提供的 make）
# 使用：make        —— 编译生成可执行文件
#       make run    —— 编译并运行
#       make clean  —— 清理编译产物
# ============================================================

CC      = gcc
CFLAGS  ?= -std=c99 -Wall -Wextra -O2 -I.
TARGET   = his

SRCS = his_link.c his_tool.c his_main.c patient.c registration.c record.c \
       doctor.c dept_bed.c drug.c schedule.c admin_tools.c
OBJS = $(SRCS:.c=.o)

.PHONY: all run clean test check

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(OBJS) -o $@

# 所有源文件都依赖两个公共头文件
$(OBJS): his.h his_config.h

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(OBJS) $(TARGET) $(TARGET).exe

# 全流程回归测试：在 tests/.work/ 下独立构建与运行，不污染源码树
test: $(TARGET)
	bash tests/full_flow_test.sh

check: test
