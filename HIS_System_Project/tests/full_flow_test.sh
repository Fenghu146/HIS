#!/usr/bin/env bash
# ============================================================
# HIS 医院信息系统 — 全流程 + 边界回归测试
#
# 用法（Linux / macOS / Git Bash）：
#     bash tests/full_flow_test.sh
#
# 特点：
#   * 在 tests/.work/ 下复制一份源码 + 独立 data 目录，绝不改动仓库里的种子数据
#   * 通过 stdin 驱动菜单完成「建科→建医生→建床位→建药品 → 患者自助建号/充值/挂号
#     → 医生接诊/写病历 → 药房发药 → 患者查看费用/取消挂号退款 → 排班 → 预约/取消预约」
#     的完整业务闭环
#   * 覆盖输入校验、金额上限、库存上限、引用完整性、日期合法性与 EOF 等边界场景
#   * 每条断言都会打印 PASS/FAIL，最后给出汇总
# ============================================================
set -u

# 字节级确定性：数据提取（cut/sed）与字符串断言（grep -F）都按字节工作，
# 不受 macOS/BSD 工具在 UTF-8 locale 下对非法字节序列的行为差异影响。
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/.."
WORK="$HERE/.work"
DATA="$WORK/data"
OUT="$WORK/out"

CC="${CC:-gcc}"
CFLAGS="-std=c99 -w -O2 -I."
# 超时保护：功能性探测而非 command -v——Windows Git Bash 的 PATH 里
# timeout 解析到 System32\timeout.exe（拒绝 stdin 重定向，报错即退出），
# 只有能真正跑通 `timeout 1 true` 的实现才可用。
if timeout 1 true >/dev/null 2>&1; then TMO="timeout 60"; else TMO=""; fi

PASS=0
FAIL=0
FAILED_LIST=""

# 动态生成未来日期（避免硬编码日期随时间腐烂）：
# Linux: date -d "+7 days" / BSD/macOS: date -v+7d
if date -d "+7 days" +%F >/dev/null 2>&1; then
    FUTURE_DATE="$(date -d "+7 days" +%F)"
elif date -v+7d +%F >/dev/null 2>&1; then
    FUTURE_DATE="$(date -v+7d +%F)"
else
    FUTURE_DATE="2099-01-01"
fi
echo "  (动态排班日期 = $FUTURE_DATE)"

pass() { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); FAILED_LIST="$FAILED_LIST
  - $1"; printf '  [FAIL] %s\n' "$1"; }

# 断言：文件 $3 中必须出现（字面子串）$2
assert_has() {
    if grep -qF -- "$2" "$3"; then pass "$1"; else fail "$1  ← 输出中未找到「$2」"; fi
}
# 断言：文件 $3 中不得出现 $2
assert_not_has() {
    if grep -qF -- "$2" "$3"; then fail "$1  ← 输出中不应出现「$2」"; else pass "$1"; fi
}
# 断言：$2 与 $3 相等
assert_eq() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  ← 期望 [$3] 实际 [$2]"; fi
}

run_case() { # $1=用例名 $2=输入文件
    ( cd "$WORK" && $TMO ./his < "$2" > "$OUT/$1.out" 2>&1 )
    local rc=$?
    if [ $rc -ne 0 ]; then
        fail "用例 $1 非正常退出（exit=$rc）"
    fi
    # 每个用例结束后快照一次数据文件，便于失败时定位
    mkdir -p "$OUT/$1.snapshot"
    cp "$WORK"/data/*.txt "$WORK"/data/admin.dat "$OUT/$1.snapshot/" 2>/dev/null
}

# ============================================================
# 环境准备
# ============================================================
setup() {
    rm -rf "$WORK"
    mkdir -p "$DATA" "$OUT"
    cp "$SRC"/*.c "$SRC"/*.h "$WORK"/
    : > "$DATA/patient.txt"
    : > "$DATA/doctor.txt"
    : > "$DATA/bed.txt"
    : > "$DATA/drug.txt"
    : > "$DATA/record.txt"
    : > "$DATA/schedule.txt"
    : > "$DATA/appointment.txt"
    printf 'K260920001|内科|0\nK260920002|外科|0\n' > "$DATA/dept.txt"
    printf '123456\n' > "$DATA/admin.dat"

    echo "编译中..."
    ( cd "$WORK" && $CC $CFLAGS ./*.c -o his ) || { echo "编译失败，终止测试"; exit 1; }
    echo
}

# ============================================================
# 阶段 1：管理员建医生 / 床位 / 药品（全流程起点）
# ============================================================
phase_bootstrap() {
    echo "== 阶段1：管理员建档（医生/床位/药品）=="
    cat > "$OUT/in_bootstrap.txt" <<'EOF'
1
admin
123456
2
2
1
K260920001
张医生
心血管内科
doc01
doc123
10
1
K260920001
李医生
呼吸内科
doc02
doc456
10
0
3
1
K260920001
1
0
0
3
1
1
K260920001
测试药品


10.00
100

0
0
0
0
EOF
    run_case bootstrap "$OUT/in_bootstrap.txt"
    local o="$OUT/bootstrap.out"
    assert_has "建科室列表可见" "内科" "$o"
    assert_has "添加医生成功" "[成功] 医生添加成功" "$o"
    assert_has "添加床位成功" "[成功] 床位添加成功" "$o"
    assert_has "添加药品成功" "[成功] 药品添加成功" "$o"
    assert_has "退出提示" "感谢使用！再见" "$o"

    DOC1=$(cut -d'|' -f1 "$DATA/doctor.txt" | sed -n 1p)
    DOC2=$(cut -d'|' -f1 "$DATA/doctor.txt" | sed -n 2p)
    BED1=$(cut -d'|' -f1 "$DATA/bed.txt" | head -1)
    DRUG1=$(cut -d'|' -f1 "$DATA/drug.txt" | head -1)
    echo "  (医生1=$DOC1 医生2=$DOC2 床位=$BED1 药品=$DRUG1)"
    assert_eq "医生记录数" "$(wc -l < "$DATA/doctor.txt" | tr -d ' ')" "2"
    # 医生密码必须是混淆后的存储，不能是明文
    assert_not_has "医生密码非明文存储" "doc123|" "$DATA/doctor.txt"
    echo
}

# ============================================================
# 阶段 2：患者自助建号 + 充值 + 普通挂号
# ============================================================
phase_patient_register() {
    echo "== 阶段2：患者建号 → 充值 → 挂号 =="
    cat > "$OUT/in_patient_reg.txt" <<'EOF'
3
1
张三丰
男
13900000001
20
110105200601011231
654321
6
654321
500
1
1
1
y
0
0
EOF
    run_case patient_register "$OUT/in_patient_reg.txt"
    local o="$OUT/patient_register.out"
    assert_has "新患者创建成功" "已创建" "$o"
    assert_has "充值成功" "【成功】充值成功" "$o"
    assert_has "挂号成功" "【挂号成功】" "$o"
    assert_has "挂号费按医保比例计算" "实际支付: 3.00 元" "$o"

    PID=$(cut -d'|' -f1 "$DATA/patient.txt" | head -1)
    echo "  (患者=$PID)"
    assert_eq "充值500后挂号3元余额" "$(cut -d'|' -f6 "$DATA/patient.txt" | head -1)" "49700"
    assert_eq "挂号状态=待就诊" "$(cut -d'|' -f14 "$DATA/patient.txt" | head -1)" "1"
    assert_eq "挂号医生绑定" "$(cut -d'|' -f12 "$DATA/patient.txt" | head -1)" "$DOC1"
    assert_eq "产生1条挂号记录" "$(wc -l < "$DATA/record.txt" | tr -d ' ')" "1"
    assert_eq "医生当日挂号数+1" "$(cut -d'|' -f8 "$DATA/doctor.txt" | sed -n 1p)" "1"
    echo
}

# ============================================================
# 阶段 3：医生登录 → 查看患者 → 转就诊中 → 写诊断
# ============================================================
phase_doctor_treat() {
    echo "== 阶段3：医生接诊 =="
    cat > "$OUT/in_doctor.txt" <<EOF
2
doc01
doc123
1

2
4
$PID
1
2
$PID
50
复诊检查
0
3

0
0
EOF
    run_case doctor "$OUT/in_doctor.txt"
    local o="$OUT/doctor.out"
    assert_has "医生登录成功" "[登录成功] 医生 张医生" "$o"
    assert_has "医生看到挂号患者" "张三丰" "$o"
    assert_has "就诊状态更新成功" "就诊状态已更新" "$o"
    assert_has "诊断记录添加成功" "[成功] 诊断记录已添加" "$o"
    assert_eq "状态=就诊中" "$(cut -d'|' -f14 "$DATA/patient.txt" | head -1)" "2"
    assert_eq "记录数=2" "$(wc -l < "$DATA/record.txt" | tr -d ' ')" "2"
    echo
}

# ============================================================
# 阶段 4：药房发药（扣库存 + 扣余额 + 生成处方记录）
# ============================================================
phase_dispense() {
    echo "== 阶段4：药房发药 =="
    cat > "$OUT/in_dispense.txt" <<EOF
1
admin
123456
3
3
1
$PID
$DRUG1
2
$DOC1
y
0
0
0
0
EOF
    run_case dispense "$OUT/in_dispense.txt"
    local o="$OUT/dispense.out"
    assert_has "发药成功" "发药成功" "$o"
    assert_has "医保分摊正确" "患者自付: 6.00 元" "$o"
    assert_eq "发药后库存" "$(cut -d'|' -f6 "$DATA/drug.txt" | head -1)" "98"
    assert_eq "发药后余额" "$(cut -d'|' -f6 "$DATA/patient.txt" | head -1)" "49100"
    assert_eq "处方记录已落库" "$(grep -c '|5|' "$DATA/record.txt" || true)" "1"
    echo
}

# ============================================================
# 阶段 5：患者查看记录/费用汇总 + 取消挂号退款
# ============================================================
phase_patient_cancel() {
    echo "== 阶段5：患者查看费用 → 取消挂号退款 =="
    cat > "$OUT/in_patient_cancel.txt" <<EOF
3
$PID
654321
5
654321

4
654321
1
y
0
0
EOF
    run_case patient_cancel "$OUT/in_patient_cancel.txt"
    local o="$OUT/patient_cancel.out"
    assert_has "费用汇总已输出" "累计费用" "$o"
    assert_has "挂号费已退还" "已退还挂号费 3.00 元" "$o"
    assert_has "取消成功" "已取消现场挂号" "$o"
    assert_eq "取消后余额=49100+300" "$(cut -d'|' -f6 "$DATA/patient.txt" | head -1)" "49400"
    assert_eq "取消后状态=未挂号" "$(cut -d'|' -f14 "$DATA/patient.txt" | head -1)" "0"
    assert_eq "挂号记录被标记取消" "$(cut -d'|' -f8 "$DATA/record.txt" | head -1)" "1"
    echo
}

# ============================================================
# 阶段 6：排班（含非法日期边界）
# ============================================================
phase_schedule() {
    echo "== 阶段6：排班（非法日期应被拒绝）=="
    cat > "$OUT/in_schedule.txt" <<EOF
1
admin
123456
2
5
1
K260920001
$DOC1
2026-02-30
2026-13-01
$FUTURE_DATE
上午
3
0
0
0
0
EOF
    run_case schedule "$OUT/in_schedule.txt"
    local o="$OUT/schedule.out"
    assert_has "不存在的日期被拒绝" "日期无效" "$o"
    assert_has "排班添加成功" "排班添加成功" "$o"
    assert_eq "排班记录数" "$(wc -l < "$DATA/schedule.txt" | tr -d ' ')" "1"
    SCHED=$(cut -d'|' -f1 "$DATA/schedule.txt" | head -1)
    echo "  (排班=$SCHED)"
    echo
}

# ============================================================
# 阶段 7：预约挂号 + 取消预约退款
# ============================================================
phase_appointment() {
    echo "== 阶段7：预约挂号 → 取消预约 =="
    cat > "$OUT/in_appointment.txt" <<EOF
3
$PID
654321
2
1
1
y
0
0
EOF
    run_case appointment "$OUT/in_appointment.txt"
    local o="$OUT/appointment.out"
    assert_has "预约成功" "【预约成功】" "$o"
    APPT=$(cut -d'|' -f1 "$DATA/appointment.txt" | head -1)
    echo "  (预约=$APPT)"
    assert_eq "预约后余额=49400-600" "$(cut -d'|' -f6 "$DATA/patient.txt" | head -1)" "48800"

    cat > "$OUT/in_appt_cancel.txt" <<EOF
3
$PID
654321
4
654321
2
$APPT
y
0
0
EOF
    run_case appt_cancel "$OUT/in_appt_cancel.txt"
    local o2="$OUT/appt_cancel.out"
    assert_has "预约取消成功" "预约已取消" "$o2"
    assert_eq "取消预约后余额复原" "$(cut -d'|' -f6 "$DATA/patient.txt" | head -1)" "49400"
    assert_eq "预约状态=已取消" "$(cut -d'|' -f4 "$DATA/appointment.txt" | head -1)" "已取消"
    # 重复取消必须被拒绝（不能二次退款）
    cat > "$OUT/in_appt_cancel2.txt" <<EOF
3
$PID
654321
4
654321
2
$APPT
0
0
EOF
    run_case appt_cancel2 "$OUT/in_appt_cancel2.txt"
    assert_has "重复取消被拒绝" "该预约已经取消过了" "$OUT/appt_cancel2.out"
    assert_eq "余额未被二次退款" "$(cut -d'|' -f6 "$DATA/patient.txt" | head -1)" "49400"
    echo
}

# ============================================================
# 阶段 8：输入校验边界（性别/手机号/年龄/身份证）
# ============================================================
phase_input_boundary() {
    echo "== 阶段8：患者建号输入校验边界 =="
    cat > "$OUT/in_input_boundary.txt" <<'EOF'
3
1
李四
人妖
女
12345
13900000002
abc
200
21
110105200506011233
654321
0
0
EOF
    run_case input_boundary "$OUT/in_input_boundary.txt"
    local o="$OUT/input_boundary.out"
    assert_has "非法性别被拒绝" "性别无效" "$o"
    assert_has "非法手机号被拒绝" "手机号格式错误" "$o"
    assert_has "非数字年龄被拒绝" "年龄无效" "$o"
    assert_has "超范围年龄被拒绝" "年龄无效，请输入0-150" "$o"
    assert_has "第二例患者创建成功" "已创建" "$o"
    PID2=$(cut -d'|' -f1 "$DATA/patient.txt" | sed -n 2p)
    echo "  (患者2=$PID2)"
    assert_eq "患者总数" "$(wc -l < "$DATA/patient.txt" | tr -d ' ')" "2"
    echo
}

# ============================================================
# 阶段 9：金额与库存边界
# ============================================================
phase_money_boundary() {
    echo "== 阶段9：金额/库存边界 =="
    cat > "$OUT/in_money_boundary.txt" <<EOF
3
$PID2
654321
6
654321
0
6
654321
-5
100001
0
1
1
1
y
0
0
EOF
    run_case money_boundary "$OUT/in_money_boundary.txt"
    local o="$OUT/money_boundary.out"
    assert_has "充值0取消" "已取消充值操作" "$o"
    assert_has "负数充值被拒绝" "金额无效" "$o"
    assert_has "超单次上限被拒绝" "单次充值不能超过" "$o"
    assert_has "余额不足无法挂号" "余额不足" "$o"
    assert_eq "零余额患者未被扣款" "$(cut -d'|' -f6 "$DATA/patient.txt" | sed -n 2p)" "0"

    # 入库/发药数量边界：非数字、超上限、超库存
    cat > "$OUT/in_stock_boundary.txt" <<EOF
1
admin
123456
3
2
1
$DRUG1
abc
99999999
3
0
3
1
$PID2
$DRUG1
abc
999999
0
0
0
0
EOF
    run_case stock_boundary "$OUT/in_stock_boundary.txt"
    local o2="$OUT/stock_boundary.out"
    assert_has "非数字入库量被拒绝" "请输入 1-1000000 之间的整数" "$o2"
    assert_has "入库成功" "入库成功" "$o2"
    assert_has "非数字发药量被拒绝" "请输入 1-1000000 之间的整数" "$o2"
    assert_has "超库存发药被拒绝" "库存不足" "$o2"
    assert_eq "库存=98+3且未被非法扣减" "$(cut -d'|' -f6 "$DATA/drug.txt" | head -1)" "101"
    echo
}

# ============================================================
# 阶段 10：引用完整性 + 医生账号唯一性
# ============================================================
phase_integrity_boundary() {
    echo "== 阶段10：引用完整性与账号唯一性 =="
    cat > "$OUT/in_integrity.txt" <<EOF
1
admin
123456
2
1
3
K260920001
0
2
2
$DOC2
4
doc01
0
0
3
2
$BED1
$PID
0
0
1
4
$PID
0
3
1
3
$DRUG1
0
0
0
0
EOF
    run_case integrity "$OUT/in_integrity.txt"
    local o="$OUT/integrity.out"
    assert_has "有医生/床位的科室不可删除" "无法删除" "$o"
    assert_has "医生账号冲突被拦截" "已被其他医生使用" "$o"
    # 冲突后必须仍停留在修改菜单（重复出现菜单标题），且账号不得被改动
    local menu_times
    menu_times=$(grep -c "请选择要修改的字段" "$o" || true)
    if [ "$menu_times" -ge 2 ]; then pass "冲突后仍停留在修改菜单（菜单出现 $menu_times 次）"; else fail "冲突后修改菜单消失（仅出现 $menu_times 次）"; fi
    assert_eq "冲突账号未被写入" "$(cut -d'|' -f5 "$DATA/doctor.txt" | sed -n 2p)" "doc02"
    assert_has "住院办理成功" "住院办理成功" "$o"
    assert_has "有记录/在院的患者不可删除" "有医疗记录" "$o"
    assert_has "有库存的药品不可删除" "无法删除" "$o"
    assert_eq "患者仍在院" "$(cut -d'|' -f7 "$DATA/patient.txt" | head -1)" "1"
    assert_eq "床位被占用" "$(cut -d'|' -f4 "$DATA/bed.txt" | head -1)" "1"
    echo
}

# ============================================================
# 阶段 11：EOF / 管道结束不得死循环
# ============================================================
phase_eof() {
    echo "== 阶段11：输入流结束（EOF）=="
    ( cd "$WORK" && $TMO ./his < /dev/null > "$OUT/eof.out" 2>&1 )
    local rc=$?
    assert_eq "EOF 时正常退出" "$rc" "0"
    assert_has "EOF 时给出提示" "输入流已结束" "$OUT/eof.out"
    local lines
    lines=$(wc -l < "$OUT/eof.out" | tr -d ' ')
    if [ "$lines" -lt 200 ]; then pass "EOF 输出有限（$lines 行，无死循环刷屏）"; else fail "EOF 输出了 $lines 行，疑似死循环"; fi
    echo
}

# ============================================================
# 阶段 12：数据落盘一致性（重启后重新加载）
# ============================================================
phase_persistence() {
    echo "== 阶段12：重启后数据一致性 =="
    cat > "$OUT/in_reload.txt" <<EOF
2
doc01
doc123
5

0
0
EOF
    run_case reload "$OUT/in_reload.txt"
    local o="$OUT/reload.out"
    assert_has "重启后医生仍可登录" "[登录成功] 医生 张医生" "$o"
    assert_has "重启后档案完整" "登录账号: doc01" "$o"

    # 唯一性：各主键文件内不得重复
    for f in patient doctor dept bed drug record schedule appointment; do
        local dup
        dup=$(cut -d'|' -f1 "$DATA/$f.txt" 2>/dev/null | grep -v '^$' | sort | uniq -d | wc -l | tr -d ' ')
        if [ "$dup" = "0" ]; then pass "$f 主键唯一"; else fail "$f 存在 $dup 个重复主键"; fi
    done
    echo
}

# ============================================================
# 阶段 13：凭据存储统一 sha256（含旧格式登录迁移）
# ============================================================
phase_cred_storage() {
    echo "== 阶段13：凭据存储统一 sha256（含旧格式登录迁移） =="

    # 管理员密码（首次 admin 登录时已从明文自动迁移）
    assert_has "管理员密码已哈希存储" "sha256:" "$DATA/admin.dat"
    assert_has "sha256(123456) 算法基准正确" "8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92" "$DATA/admin.dat"
    assert_not_has "管理员密码非明文存储" "123456" "$DATA/admin.dat"

    # 患者 PIN / 医生密码（注册时即哈希，明文不落盘）
    assert_has "患者PIN已哈希存储" "sha256:" "$DATA/patient.txt"
    assert_not_has "患者PIN非明文存储" "654321" "$DATA/patient.txt"
    assert_has "医生密码已哈希存储" "sha256:" "$DATA/doctor.txt"
    assert_not_has "医生密码非明文存储" "doc123" "$DATA/doctor.txt"

    # --- 旧格式登录迁移：植入旧版明文行 + 旧版 hex: 混淆行 ---
    cat >> "$DATA/doctor.txt" <<'SEED'
DL00000001|旧版明文医生|K1|旧专长|legacy1|old123|30|0|2026-10-02
DL00000002|旧版混淆医生|K1|旧专长|legacy2|hex:865687435363|30|0|2026-10-02
SEED
    cat > "$OUT/in_legacy1.txt" <<'IN1'
2
legacy1
old123
0
0
IN1
    run_case legacy1 "$OUT/in_legacy1.txt"
    local o="$OUT/legacy1.out"
    assert_has "旧版明文密码登录成功" "登录成功" "$o"
    assert_has "旧版明文密码登录带迁移提示" "已迁移密码" "$o"
    assert_has "旧版明文密码已迁移为sha256" "sha256:841a94cdd2e04c6cb3e24e3cab7498d176170611382fcc8387ebaa1ac7e95880" "$DATA/doctor.txt"
    assert_not_has "旧版明文密码不再落盘" "old123" "$DATA/doctor.txt"

    cat > "$OUT/in_legacy2.txt" <<'IN2'
2
legacy2
hex456
0
0
IN2
    run_case legacy2 "$OUT/in_legacy2.txt"
    o="$OUT/legacy2.out"
    assert_has "旧版hex混淆密码登录成功" "登录成功" "$o"
    assert_has "旧版hex混淆密码迁移后为sha256" "sha256:bca0d83f2cada579aca35e065f4596fe086d128a905cfe70d91f51c78266ba1f" "$DATA/doctor.txt"
    assert_not_has "旧版hex混淆值不再落盘" "hex:865687435363" "$DATA/doctor.txt"
}

# ============================================================
# 主流程
# ============================================================
setup
phase_bootstrap
phase_patient_register
phase_doctor_treat
phase_dispense
phase_patient_cancel
phase_schedule
phase_appointment
phase_input_boundary
phase_money_boundary
phase_integrity_boundary
phase_eof
phase_persistence
phase_cred_storage

echo "============================================================"
echo "测试汇总：PASS=$PASS  FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf '失败项：%s\n' "$FAILED_LIST"
    echo "详细输出见: $OUT/"
    exit 1
fi
echo "全部通过。详细输出见: $OUT/"
exit 0
