# HIS 医院信息系统

> 一个基于 **C99** 实现的纯控制台医院信息系统（Hospital Information System）。
> 采用**通用单向链表**在内存中管理业务数据，使用 **文本文件 + 原子写入**持久化，
> 覆盖**管理员 / 医生 / 患者**三种角色的完整业务闭环。

![Language](https://img.shields.io/badge/language-C99-blue.svg)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey.svg)
![Build](https://img.shields.io/badge/build-VS2022%20%7C%20GCC-green.svg)
![License](https://img.shields.io/badge/license-MIT-orange.svg)

---

## 目录

- [一、项目简介](#一项目简介)
- [二、功能特性](#二功能特性)
- [三、技术架构](#三技术架构)
- [四、目录结构](#四目录结构)
- [五、环境要求](#五环境要求)
- [六、安装与使用](#六安装与使用)
- [七、配置说明](#七配置说明)
- [八、核心机制](#八核心机制)
- [九、文档索引](#九文档索引)
- [十、贡献指南](#十贡献指南)
- [十一、许可证](#十一许可证)

---

## 一、项目简介

HIS 医院信息系统是一个用于模拟真实医院业务流转的 C 语言课程设计项目。系统以**科室—医生—患者—床位—药品—医疗记录**为主线，串联起挂号、就诊、开单、发药、住院、退费等完整流程，并在三个角色之间进行清晰的权限隔离。

项目特点：

- **零第三方依赖**：仅使用 C 标准库，开箱即用；
- **泛型数据结构**：基于 `void*` 深拷贝的通用单向链表，8 张业务表共用同一套增删查改逻辑；
- **数据落地可靠**：`write-then-rename` 原子写入，避免写入中断导致的文件损坏；
- **业务校验完备**：手机号 / 身份证 / 年龄一致性 / 唯一性 / 金额精度等多项校验；
- **三端权限隔离**：管理员、医生、患者各自独立菜单与会话，敏感操作需二次验证。

---

## 二、功能特性

### 2.1 角色与权限

| 角色 | 登录方式 | 说明 |
| --- | --- | --- |
| 管理员 | 账号 `admin` + 密码（默认 `123456`，可修改并持久化） | 全系统数据管理与统计 |
| 医生 | 档案中的登录账号 + 密码（`nibble-swap` 混淆存储） | 仅能操作与自己相关的患者与记录 |
| 患者 | 患者 ID + 6 位访问 PIN（可选设置） | 自助挂号 / 预约 / 缴费 / 查询 |

> 三种角色的登录均带**连续失败 5 次锁定**保护（进程级）。

### 2.2 功能矩阵

**管理员**

- 患者与医疗记录管理：患者 CRUD、按 ID / 姓名 / 科室 / 状态查询、医疗记录 CRUD
- 科室 / 医生 / 床位管理：科室 CRUD、医生 CRUD（含账号密码）、床位 CRUD 与住院 / 出院、床位使用率统计
- 排班管理：新增 / 查看 / 修改 / 删除排班与号源
- 药品药房管理：药品 CRUD、模糊查询、入库 / 出库、库存预警、门诊发药
- 全局统计与运维：一站式全局查询、管理员统计报表导出、一键数据备份
- 修改管理员密码（持久化至 `data/admin.dat`）

**医生（医生工作站）**

- 查看我的患者（现场挂号 + 预约列表）
- 管理医疗记录：新增诊断 / 处方、查看患者记录、就诊状态流转（待就诊 → 就诊中 → 已完成）
- 查看患者预约信息、查看我的排班、查看个人信息、修改登录密码

**患者（自助服务，无需登录验证直接进入）**

- 普通挂号（现场选科室 / 医生，实时扣费）
- 预约挂号（选择医生排班时段）
- 查看挂号 / 预约记录
- 取消挂号 / 预约（精确退费、释放号源）
- 查看个人医疗记录与费用汇总（PIN 保护）
- 自助充值（单次上限 10 万元，账户总额上限 50 万元）

---

## 三、技术架构

### 3.1 技术栈

| 项 | 说明 |
| --- | --- |
| 语言标准 | C99 |
| 编译器 | MSVC v143（Visual Studio 2022）/ GCC / Clang |
| 界面 | Windows 控制台（标准输入输出） |
| 数据结构 | 通用单向链表（`void*` + 深拷贝） |
| 持久化 | 文本文件，`|` 分隔字段，`write-then-rename` 原子写入 |
| 依赖 | 无（仅 C 标准库） |

### 3.2 分层架构

```
┌──────────────────────────────────────────────────────────┐
│                        表示层（控制台菜单）                 │
│   his_main.c：三角色登录 + 主菜单路由                       │
├──────────────────────────────────────────────────────────┤
│                        业务层（8 个业务模块）               │
│   patient.c  registration.c  record.c  doctor.c           │
│   dept_bed.c  schedule.c  drug.c  admin_tools.c           │
├──────────────────────────────────────────────────────────┤
│                        基础层                              │
│   his_link.c（通用链表）  his_tool.c（工具 / I/O / 校验）   │
├──────────────────────────────────────────────────────────┤
│                        配置层                              │
│   his.h（结构体 / 声明 / 全局变量）  his_config.h（常量）    │
└──────────────────────────────────────────────────────────┘
```

### 3.3 模块清单

| 文件 | 职责 |
| --- | --- |
| `his_config.h` | 长度常量、枚举、ID 前缀、文件路径、业务默认值 |
| `his.h` | 8 个业务结构体、通用链表定义、全部函数声明、`HIS_STRNCPY` 安全宏、8 个全局链表 `extern` |
| `his_link.c` | 通用单向链表：`InitList / InsertNode / DeleteNode / FindNode / TraverseList / FreeList` |
| `his_tool.c` | 输入校验、唯一 ID 生成、文件读写、密码混淆、身份证校验、时间获取、菜单辅助 |
| `his_main.c` | 程序入口 `main()`、三角色登录认证、主菜单路由、管理员密码持久化 |
| `patient.c` | 患者 CRUD、独立输入校验、PIN 验证、自助充值、患者登录与自助服务菜单 |
| `registration.c` | 普通挂号、预约挂号、查看 / 取消挂号与退费 |
| `record.c` | 医疗记录 CRUD、医生端权限校验与就诊状态流转 |
| `doctor.c` | 医生 CRUD、账号唯一性与密码管理 |
| `dept_bed.c` | 科室 CRUD、床位 CRUD、住院 / 出院、床位统计 |
| `schedule.c` | 医生排班 CRUD 与号源管理 |
| `drug.c` | 药品 CRUD、库存出入库与预警、门诊发药 |
| `admin_tools.c` | 全局查询统计、统计报表导出、一键数据备份 |

### 3.4 模块依赖关系

```
his_config.h ──► his.h ──► his_main.c ──► 各业务模块
                  │
                  ├── his_link.c   （通用链表，被所有模块使用）
                  └── his_tool.c   （工具函数，被所有模块使用）

业务模块之间的关键调用：
  patient.c      ──► record.c（管理员医疗记录 CRUD）
  registration.c ──► patient.c / record.c / schedule.c / doctor.c
  record.c       ──► patient.c / doctor.c / schedule.c
  drug.c         ──► admin_tools.c（全局统计 / 备份）
  dept_bed.c     ──► doctor.c（医生子菜单）、schedule.c（排班子菜单）
```

### 3.5 核心数据模型

| 结构体 | 关键字段 | 说明 |
| --- | --- | --- |
| `Patient` | id / name / age / gender / balance / insurance_ratio / register_status / pin | 患者档案与挂号状态、账户余额（分） |
| `Doctor` | id / name / dept_id / account / password / max_register | 医生档案、登录账号与每日号源上限 |
| `Department` | id / name / doctor_count | 科室信息 |
| `Bed` | id / room_type / dept_id / status / patient_id | 床位与住院状态 |
| `Drug` | id / general_name / price / stock / warning_threshold | 药品信息与库存预警 |
| `MedicalRecord` | id / patient_id / doctor_id / type / cost / cancelled | 医疗记录（挂号 / 诊断 / 检查 / 住院 / 处方） |
| `DoctorSchedule` | id / doctor_id / date / time_slot / max_patients | 医生排班与号源 |
| `Appointment` | id / patient_id / schedule_id / status / cost | 预约记录 |

主要枚举：`BedStatus`、`InpatientStatus`、`RecordType`、`RoomType`、`RegStatus`（定义于 `his_config.h`）。

### 3.6 数据持久化方案

- 每条记录序列化为一行文本，字段以 `|` 分隔，例如患者行：
  `id|name|age|gender|ratio|balance|is_inpatient|bed_id|record_count|phone|id_card|doctor_id|dept_id|status|time|pin|record_id`
- 写入采用 **write-then-rename**：先写临时文件 `.tmp`，`fclose` 后 `remove` 原文件并 `rename`，保证原子性；
- 解析器对**可选尾部字段做了向后兼容**处理，旧数据文件可直接加载；
- 运行期每次修改即时回写文件，退出时再统一保存一次兜底。

---

## 四、目录结构

```
HIS/
├── README.md                     # 项目说明（本文件）
├── .gitignore                    # 忽略编译产物与运行时生成文件
├── .gitattributes                # 二进制文件声明
│
├── HIS_System_Project/           # 源代码工程
│   ├── his.h                     # 全局头文件（结构体 / 声明 / 全局变量）
│   ├── his_config.h              # 配置常量与枚举
│   ├── his_main.c                # 程序入口与角色登录
│   ├── his_link.c                # 通用单向链表
│   ├── his_tool.c                # 工具函数（校验 / I/O / ID 生成）
│   ├── patient.c                 # 患者模块
│   ├── registration.c            # 挂号 / 预约模块
│   ├── record.c                  # 医疗记录模块
│   ├── doctor.c                  # 医生模块
│   ├── dept_bed.c                # 科室 / 床位模块
│   ├── schedule.c                # 排班模块
│   ├── drug.c                    # 药品 / 药房模块
│   ├── admin_tools.c             # 全局统计与备份
│   ├── Makefile                  # GNU Make 构建脚本（GCC）
│   ├── HIS_System_Project.sln    # Visual Studio 解决方案
│   ├── HIS_System_Project.vcxproj
│   └── data/                     # 持久化数据目录（程序运行时读写）
│       ├── patient.txt  doctor.txt  dept.txt  bed.txt
│       ├── drug.txt     record.txt  schedule.txt  appointment.txt
│       └── admin.dat             # 管理员密码（运行时生成）
│
└── docs/                         # 设计与测试文档（归档）
    ├── 分析报告/                 # 模块分析、项目概览、流程说明
    ├── 流程图/                   # 管理员 / 医生 / 患者系统流程图
    ├── 测试报告/                 # 功能 / 边界 / 权限 / 容量测试报告
    └── 课程报告/                 # 课程总结报告（md / docx / pdf / html 及截图）
```

---

## 五、环境要求

| 项 | 最低要求 |
| --- | --- |
| 操作系统 | Windows 10+ / Linux / macOS |
| 编译器 | Visual Studio 2022（v143）或 GCC 9+ / Clang 10+ |
| 构建工具 | MSBuild（VS）或 GNU Make + GCC |
| 字符编码 | 源文件为 UTF-8；Windows 控制台建议切换到 UTF-8 代码页 |
| 其它 | 终端需支持中文显示 |

---

## 六、安装与使用

### 6.1 方式一：Visual Studio（推荐 Windows 用户）

1. 使用 Visual Studio 2022 打开 `HIS_System_Project/HIS_System_Project.sln`；
2. 选择 `Debug | x64` 或 `Release | x64` 配置；
3. 直接按 `F5` 编译运行。

### 6.2 方式二：GCC / Make（跨平台）

```bash
# 进入源代码目录
cd HIS_System_Project

# 编译（生成可执行文件 his / his.exe）
make

# 编译并运行
make run

# 清理编译产物
make clean
```

也可以不使用 Makefile，直接调用 gcc：

```bash
gcc -std=c99 -Wall -I. *.c -o his
```

### 6.3 运行说明（重要）

程序通过**相对路径** `data/xxx.txt` 读写数据文件，因此**必须在 `HIS_System_Project` 目录下运行**，以保证 `data/` 能被正确访问：

```bash
cd HIS_System_Project
./his            # Linux / macOS
his.exe          # Windows
```

> 若在 Windows 控制台出现中文乱码，可先执行 `chcp 65001` 切换到 UTF-8 代码页。

### 6.4 默认账号

| 角色 | 账号 | 密码 |
| --- | --- | --- |
| 管理员 | `admin` | `123456` |
| 医生 | 见 `data/doctor.txt` 中的 `account` 字段 | 由管理员创建时设置（文件中为混淆存储） |
| 患者 | 患者 ID（`P` 开头） | 6 位访问 PIN（创建时可留空不设置） |

---

## 七、配置说明

所有可调参数集中在 `his_config.h` 中，修改后重新编译即可生效。

### 7.1 业务常量

| 常量 | 默认值 | 含义 |
| --- | --- | --- |
| `REGISTRATION_FEE` | `1000` | 普通挂号费（分，即 10 元） |
| `APPOINTMENT_FEE` | `2000` | 预约挂号费（分，即 20 元） |
| `DEFAULT_INSURANCE` | `0.7f` | 新患者默认医保报销比例（70%） |
| `DRUG_WARNING_RATIO` | `0.2f` | 药品库存预警系数（默认阈值为库存的 20%） |
| `MAX_ID_RETRY` | `10` | 唯一 ID 生成最大重试次数 |
| `ADMIN_USERNAME` | `admin` | 管理员账号（硬编码，不可修改） |
| `ADMIN_PASSWORD` | `123456` | 管理员默认密码（可在系统内修改并持久化） |

### 7.2 ID 前缀约定

| 前缀 | 业务实体 | 前缀 | 业务实体 |
| --- | --- | --- | --- |
| `P` | 患者 | `R` | 医疗记录 |
| `D` | 医生 | `A` | 预约 |
| `K` | 科室 | `S` | 排班 |
| `B` | 床位 | `M` | 药品 |

ID 规则：`前缀 + 年月日(6位) + 3位序号`，共 10 字符，全局唯一。

### 7.3 数据文件

| 文件 | 对应实体 |
| --- | --- |
| `data/patient.txt` | 患者 |
| `data/doctor.txt` | 医生（密码为混淆存储） |
| `data/dept.txt` | 科室 |
| `data/bed.txt` | 床位 |
| `data/drug.txt` | 药品 |
| `data/record.txt` | 医疗记录 |
| `data/schedule.txt` | 排班 |
| `data/appointment.txt` | 预约 |
| `data/admin.dat` | 管理员密码（首次修改后生成） |

---

## 八、核心机制

### 8.1 安全机制

- **登录锁定**：管理员 / 医生连续 5 次登录失败后锁定（进程级）。
- **密码混淆**：医生密码以 `nibble-swap`（半字节交换）形式存储，属**自逆变换**，仅用于避免明文落盘，**不是加密**；登录时兼容旧版明文数据并自动迁移。
- **PIN 保护**：查看医疗记录、取消挂号、充值等敏感操作需验证 6 位访问 PIN（未设置时直接放行）。
- **字段防注入**：所有自由文本字段禁止包含分隔符 `|`，防止破坏文件格式。

### 8.2 输入与业务校验

- 手机号：11 位数字且以 `1` 开头，全局唯一；
- 身份证：18 位，按 **GB 11643-1999** 加权算法校验校验位，并推导出生日期；
- 一致性：身份证推算年龄必须与录入年龄一致，否则要求重新输入；
- 状态机：就诊状态严格按「待就诊 → 就诊中 → 已完成」流转；
- 删除保护：存在关联数据（记录 / 预约 / 住院 / 挂号）的患者不允许删除，有人挂号的医生、有床位的科室、非空库存的药品、有未取消预约的排班均不允许删除；
- 金额精度：所有金额以「分」（`long long`）存储与计算，避免浮点误差。

### 8.3 数据一致性

- 挂号 / 发药等涉及扣款的流程，均**先校验、后构造记录、再执行不可逆操作**，并在失败时回滚；
- 取消挂号通过 `register_record_id` 精确定位原挂号记录并退费（标记 `cancelled`，汇总时过滤）；
- 一键备份与退出保存确保内存最新状态完整落盘。

---

## 九、文档索引

项目的详细设计与测试资料已归档在 `docs/` 目录：

| 目录 | 内容 |
| --- | --- |
| `docs/分析报告/` | 项目全景概览、三角色运转流程、各模块（`patient.c` / `drug.c` / `dept_bed.c`）分析、问题修复与校验逻辑说明 |
| `docs/流程图/` | 管理员 / 医生 / 患者三端系统流程图 |
| `docs/测试报告/` | 功能测试用例、边界场景、权限控制、数据容量与并发稳定性测试报告 |
| `docs/课程报告/` | 课程总结报告（Markdown / Word / PDF / HTML 及配套截图） |

---

## 十、贡献指南

欢迎提交 Issue 与 Pull Request 共同完善本项目。

### 10.1 开发流程

1. Fork 本仓库并克隆到本地；
2. 从 `master` 切出功能分支：`git checkout -b feature/xxx`；
3. 本地编译验证：`cd HIS_System_Project && make`，确保零编译错误；
4. 提交时遵循清晰的提交信息，例如：
   - `feat: 新增药品批量导入`
   - `fix: 修复取消挂号退费金额错误`
   - `refactor: 抽取重复的 ID 生成逻辑`
   - `docs: 补充 README 配置说明`
5. 推送到你的分支并发起 Pull Request，说明改动背景与测试方式。

### 10.2 编码规范

- 遵循 C99，缩进 **4 空格**，源文件统一 **UTF-8**；
- 新增函数须在 `his.h` 中声明，并保持 `extern` 与实现一致；
- 涉及字符串拷贝请使用安全宏 `HIS_STRNCPY`；
- 自由文本字段需通过 `ValidateNoPipe` 校验；
- 新增业务常量请集中定义在 `his_config.h`，不要散落魔法数字；
- 修改后请至少通过 `gcc -std=c99 -Wall -Wextra -I. *.c` 编译。

---

## 十一、许可证

本项目基于 **MIT License** 发布，可自由学习、修改与分发。

> 本项目为《程序设计基础课程设计》课程作品，仅供学习交流使用。
