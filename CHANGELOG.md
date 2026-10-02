# 更新日志

本项目所有值得记录的变更都写在这里。
格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

> 定位说明：本仓库（C 版）是课程设计存档版，定位为教学留档与边界场景参照；
> 新功能开发在主力实现 `Fenghu146/HIS_cpp`（C++ 版）进行。

## [1.0.0] - 2026-10-02

课程设计存档版的首个正式基线，同时是生产级规范化改造后的状态。

### 新增

- 全流程回归测试：业务闭环（建科→医生→床位→药品→挂号→接诊→发药→退费→排班→预约）
  加边界场景与凭据存储守护（95 项断言）；`make test` / `make check` 一键运行
- GitHub Actions CI：Linux / macOS / Windows 三平台构建 + 零告警门（含 MSVC）+ 回归测试 +
  lint 门（shellcheck / cppcheck，均已清零）
- 工程规范：`CHANGELOG.md`、`.editorconfig`

### 修复

- 预约链路 5 项回归失败：测试硬编码排班日期随时间腐烂，改为运行时动态生成未来日期（GNU/BSD date 双兼容）
- 编译告警 61 → 0：`HIS_STRNCPY` 宏的 `strncpy` 截断告警改 `memcpy` + 显式结尾；
  手拼日期改 `strftime`；床位统计标题缓冲不足的截断隐患
- **数据文件文本契约**：医生密码混淆后的原始字节（非法 UTF-8）+ 种子数据 GBK/CRLF ——
  macOS/BSD 文本工具整行丢弃 → 医生 ID 提取为空 → 输入流全链路错位。
  密码字段改为 `hex:` 文本持久化，种子数据全量迁移 UTF-8/LF
- Makefile `CC ?= gcc` 无效赋值（GNU make 内置变量已定义，环境无 `cc` 即构建失败）
- MSVC 执行字符集：中文字符串字面量按 1252 输出（单次构建 14620 条 C4566）→ `/utf-8`

### 变更

- **凭据统一 SHA-256 摘要**（admin.dat / 医生密码 / 患者 PIN）：登录成功自动迁移旧格式
  （`hex:` 半字节混淆、裸明文）为摘要；种子数据预哈希，随仓库分发的默认凭据不再以明文形态出现
- README 补 CI 徽章、测试与回归、十分钟上手路径

[1.0.0]: https://github.com/Fenghu146/HIS/releases/tag/v1.0.0
