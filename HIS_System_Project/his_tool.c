#include "his.h"
#include <errno.h>

/*
 * 通用工具函数模块
 *   ClearInputBuffer / readString / getConfirm / getValidChoice
 *   GenerateID / ValidateNumber/Phone/IDCard/NoPipe
 *   GetSystemTime / SaveDataToFile / LoadDataFromFile
 *   PrintSeparator / passwordObfuscate
 *   所有模块共用的输入校验、文件 I/O、菜单辅助函数
 */

// 清除输入缓冲区
void ClearInputBuffer() {
    int c;
    while ((c = getchar()) != '\n' && c != EOF);
}

// 统一字符串输入：使用 fgets 安全读取，去除末尾换行，溢出时清空缓冲区
void readString(char* buf, int size) {
    if (!fgets(buf, size, stdin)) {
        ClearInputBuffer();
        buf[0] = '\0';
        return;
    }
    char* nl = strchr(buf, '\n');
    if (nl) *nl = '\0';
    else ClearInputBuffer();
}

// 安全的行输入：封装 fgets + 溢出清理，返回 1 成功 / 0 失败（EOF/错误）
int inputLine(char* buf, size_t size) {
    if (!fgets(buf, (int)size, stdin)) {
        ClearInputBuffer();
        return 0;
    }
    char* nl = strchr(buf, '\n');
    if (nl) *nl = '\0';
    else ClearInputBuffer();
    return 1;
}

// 统一确认输入：读取 y/n，返回 1 表示确认，0 表示取消
int getConfirm(void) {
    char buf[64];
    fflush(stdout);
    if (!fgets(buf, sizeof(buf), stdin)) {
        ClearInputBuffer();
        return 0;
    }
    return buf[0] == 'y' || buf[0] == 'Y';
}

// 带消息提示的统一确认：打印 msg + "(y/n): "，返回 1=确认 0=取消
int confirmAction(const char* msg) {
    if (msg) printf("%s (y/n): ", msg);
    fflush(stdout);
    return getConfirm();
}

// 等待用户按回车键继续
void waitForEnter(void) {
    printf("\n按回车键继续...");
    getchar();
}

// 统一菜单输入校验：读取[min, max]范围内的整数选项，避免 scanf 遗留问题
int getValidChoice(int min, int max) {
    char buf[64];
    int choice;
    while (1) {
        if (!inputLine(buf, sizeof(buf))) {
            /* 输入流结束（如管道/重定向读完）时必须退出，否则会无限循环刷屏 */
            if (feof(stdin)) {
                printf("\n[提示] 输入流已结束，系统退出。\n");
                exit(0);
            }
            printf("输入异常，请重新输入: ");
            continue;
        }

        // 检查是否全为数字
        int valid = 1;
        for (int i = 0; buf[i]; i++) {
            if (buf[i] < '0' || buf[i] > '9') {
                valid = 0;
                break;
            }
        }

        if (strlen(buf) == 0) {
            printf("输入不能为空，请重新输入 (%d-%d): ", min, max);
            continue;
        }
        if (!valid) {
            printf("输入无效，只能输入数字 (%d-%d): ", min, max);
            continue;
        }

        choice = atoi(buf);
        if (choice >= min && choice <= max) {
            return choice;
        }
        printf("输入超出范围，请重新输入 (%d-%d): ", min, max);
    }
}

// 打印菜单分隔线
void PrintSeparator() {
    printf("\n");
    for (int i = 0; i < MENU_LINE_LEN; i++) printf("=");
    printf("\n");
}

/* 生成 ID 用的全局自增序号（进程内单调递增） */
static int s_id_seq = 1;

/* 取得当天日期前缀 YYMMDD */
static void getIDDatePrefix(char* out, size_t cap) {
    time_t t = time(NULL);
    struct tm* tm = localtime(&t);
    if (!tm || strftime(out, cap, "%y%m%d", tm) == 0) {
        HIS_STRNCPY(out, "000000", cap);
    }
}

/*
 * 将自增序号推进到「已存在的同前缀、同日期 ID 最大序号 + 1」。
 *
 * 背景：序号是 static 变量，程序重启后归 1；若当天已生成过数据，
 * 重启后前若干次生成都会与历史 ID 撞号，而 generateUniqueID 只重试
 * MAX_ID_RETRY(10) 次，撞号超过 10 个就会彻底无法生成新 ID。
 * 在生成前扫描链表对齐序号，可根治该问题（ID 格式保持不变）。
 */
static void syncIDSequence(LinkList* list, char prefix) {
    if (!list) return;
    char date_prefix[16];
    getIDDatePrefix(date_prefix, sizeof(date_prefix));
    size_t dlen = strlen(date_prefix);

    int max_seq = 0;
    ListNode* p = list->head;
    while (p) {
        const char* id = p->id;
        size_t len = strlen(id);
        if (len > 1 + dlen && id[0] == prefix && strncmp(id + 1, date_prefix, dlen) == 0) {
            const char* tail = id + 1 + dlen;
            int all_digit = (*tail != '\0');
            for (const char* q = tail; *q; q++) {
                if (*q < '0' || *q > '9') { all_digit = 0; break; }
            }
            if (all_digit) {
                long v = atol(tail);
                if (v > 0 && v < 100000000L && (int)v > max_seq) max_seq = (int)v;
            }
        }
        p = p->next;
    }
    if (max_seq + 1 > s_id_seq) s_id_seq = max_seq + 1;
}

// 自动生成ID (前缀 + 日期6位 + 序号)，序号单调递增，长度不足 20 字节时已截断保护
void GenerateID(char* id, char type) {
    char date_prefix[16];
    getIDDatePrefix(date_prefix, sizeof(date_prefix));
    snprintf(id, MAX_ID_LEN, "%c%s%03d", type, date_prefix, s_id_seq++);
    id[MAX_ID_LEN - 1] = '\0';
}

// 安全地生成唯一ID：最多尝试 MAX_ID_RETRY 次，返回 0 成功 / -1 失败
int generateUniqueID(char* out_id, char prefix, LinkList* list) {
    if (!out_id) return -1;
    syncIDSequence(list, prefix);   /* 与已持久化数据对齐，避免重启后撞号 */
    for (int i = 0; i < MAX_ID_RETRY; i++) {
        GenerateID(out_id, prefix);
        if (!FindNode(list, out_id)) return 0;
    }
    return -1;
}

// 校验纯数字
int ValidateNumber(const char* str) {
    if (!str || strlen(str) == 0) return 0;
    for (int i = 0; str[i]; i++) {
        if (str[i] < '0' || str[i] > '9') return 0;
    }
    return 1;
}

/*
 * 严格解析整数：仅允许可选正负号 + 纯数字 + 首尾空白。
 * 成功返回 0 并写入 *out；失败（空串、夹杂字符、溢出）返回 -1。
 */
int parseLongStrict(const char* str, long long* out) {
    if (!str || !out) return -1;
    char* endptr = NULL;
    errno = 0;
    long long v = strtoll(str, &endptr, 10);
    if (endptr == str || errno == ERANGE) return -1;
    while (*endptr == ' ' || *endptr == '\t' || *endptr == '\r' || *endptr == '\n') endptr++;
    if (*endptr != '\0') return -1;
    *out = v;
    return 0;
}

/* 2024-02 闰年判断（仅用于排班日期合法性校验） */
static int isLeapYear(int y) {
    return (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
}

/*
 * 校验 YYYY-MM-DD 日期是否真实存在（含月份天数与闰年），
 * 仅做格式/范围校验，不限制必须为未来日期。合法返回 1。
 */
int ValidateDateString(const char* date) {
    if (!date || strlen(date) != 10) return 0;
    if (date[4] != '-' || date[7] != '-') return 0;
    for (int i = 0; i < 10; i++) {
        if (i == 4 || i == 7) continue;
        if (date[i] < '0' || date[i] > '9') return 0;
    }
    int y = (date[0] - '0') * 1000 + (date[1] - '0') * 100 + (date[2] - '0') * 10 + (date[3] - '0');
    int m = (date[5] - '0') * 10 + (date[6] - '0');
    int d = (date[8] - '0') * 10 + (date[9] - '0');
    if (y < 1900 || y > 2999) return 0;
    if (m < 1 || m > 12) return 0;
    static const int days_in_month[12] = { 31,28,31,30,31,30,31,31,30,31,30,31 };
    int max_day = days_in_month[m - 1];
    if (m == 2 && isLeapYear(y)) max_day = 29;
    if (d < 1 || d > max_day) return 0;
    return 1;
}

// 校验ID格式
// 手机号校验：11位数字，以1开头
int ValidatePhone(const char* phone) {
    if (!phone) return 0;
    size_t len = strlen(phone);
    if (len != 11) return 0;
    if (phone[0] != '1') return 0;
    for (size_t i = 0; i < len; i++) {
        if (phone[i] < '0' || phone[i] > '9') return 0;
    }
    return 1;
}

// 身份证校验：18位，前17位为数字，末位为数字或X/x，实现18位加权
int ValidateIDCard(const char* id_card) {
    if (!id_card) return 0;
    size_t len = strlen(id_card);
    if (len != 18) return 0;
    for (size_t i = 0; i < 17; i++) {
        if (id_card[i] < '0' || id_card[i] > '9') return 0;
    }
    char last = id_card[17];
    if (!(last >= '0' && last <= '9') && last != 'X' && last != 'x') return 0;
    // 加权校验 (GB 11643-1999)
    static const int weights[17] = { 7,9,10,5,8,4,2,1,6,3,7,9,10,5,8,4,2 };
    static const char check_chars[] = "10X98765432";
    int sum = 0;
    for (size_t i = 0; i < 17; i++) {
        sum += (id_card[i] - '0') * weights[i];
    }
    int expected_idx = sum % 11;
    char expected_check = check_chars[expected_idx];
    char actual_last = (last >= 'a' && last <= 'z') ? last - 'a' + 'A' : last;
    if (actual_last != expected_check) {
        printf("    [提示] 校验位应为 %c，实际输入为 %c\n", expected_check, actual_last);
    }
    return actual_last == expected_check;
}

// 防止字段分隔符"|"检测
int ValidateNoPipe(const char* str) {
    return str && strchr(str, '|') == NULL;
}

void passwordObfuscate(char* pwd) {
    if (!pwd) return;
    for (int i = 0; pwd[i]; i++) {
        pwd[i] = ((pwd[i] << 4) | ((unsigned char)pwd[i] >> 4));
    }
}

// 密码字段持久化编码：把任意字节的混淆密码转成纯 ASCII 十六进制文本。
// 背景：密码经 nibble-swap 混淆后会产生非法 UTF-8 的高位字节，
// 直接写入"文本文件"会破坏文件契约——macOS/BSD 的 cut/sed 在 UTF-8
// locale 下会丢弃含非法字节的行，导致按行提取字段全部落空。
// 字段格式："hex:" + 大写十六进制；旧版原始字节字段由解码函数兼容读取。
#define PWD_HEX_PREFIX "hex:"
static int his_hexval(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

void passwordHexEncode(const char* raw, char* out, size_t cap) {
    static const char HEX[] = "0123456789ABCDEF";
    size_t n = raw ? strlen(raw) : 0;
    size_t need = sizeof(PWD_HEX_PREFIX) + n * 2;
    if (cap < need) {
        if (cap > 0) out[0] = '\0';
        return;
    }
    memcpy(out, PWD_HEX_PREFIX, sizeof(PWD_HEX_PREFIX) - 1);
    for (size_t i = 0; i < n; i++) {
        unsigned char b = (unsigned char)raw[i];
        out[sizeof(PWD_HEX_PREFIX) - 1 + i * 2] = HEX[b >> 4];
        out[sizeof(PWD_HEX_PREFIX) - 1 + i * 2 + 1] = HEX[b & 0x0F];
    }
    out[sizeof(PWD_HEX_PREFIX) - 1 + n * 2] = '\0';
}

int passwordHexDecode(const char* field, char* out, size_t cap) {
    if (!field || !out || cap == 0) return 0;
    if (strncmp(field, PWD_HEX_PREFIX, sizeof(PWD_HEX_PREFIX) - 1) != 0) {
        // 旧版格式：原始字节直接存储，按原样拷贝以兼容历史数据
        his_strncpy(out, field, cap);
        return 0;
    }
    const char* p = field + sizeof(PWD_HEX_PREFIX) - 1;
    size_t n = strlen(p);
    if (n % 2 != 0 || n / 2 + 1 > cap) {
        out[0] = '\0';
        return 0;
    }
    for (size_t i = 0; i < n; i += 2) {
        int hi = his_hexval(p[i]);
        int lo = his_hexval(p[i + 1]);
        if (hi < 0 || lo < 0) {
            out[0] = '\0';
            return 0;
        }
        out[i / 2] = (char)((hi << 4) | lo);
    }
    out[n / 2] = '\0';
    return 1;
}

void GetSystemTime(char* time_str) {
    time_t t = time(NULL);
    struct tm* tm = localtime(&t);
    if (!tm || strftime(time_str, MAX_TIME_LEN, "%Y-%m-%d %H:%M:%S", tm) == 0) {
        HIS_STRNCPY(time_str, "1970-01-01 00:00:00", MAX_TIME_LEN);
    }
}

// 保存数据到文件
int SaveDataToFile(LinkList* list, const char* filename, void (*format_func)(void*, char*)) {
    if (!list || !filename || !format_func) return -1;
    char tmpname[MAX_LINE_LEN];
    snprintf(tmpname, sizeof(tmpname), "%s.tmp", filename);
    FILE* fp = fopen(tmpname, "w");
    if (!fp) return -1;

    ListNode* p = list->head;
    char line[MAX_LINE_LEN];
    while (p) {
        format_func(p->data, line);
        fprintf(fp, "%s\n", line);
        p = p->next;
    }
    fclose(fp);

    remove(filename);
    if (rename(tmpname, filename) != 0) return -1;
    return 0;
}

int LoadDataFromFile(LinkList* list, const char* filename, void (*parse_func)(char*, void*)) {
    if (!list || !filename || !parse_func) return -1;
    FILE* fp = fopen(filename, "r");
    if (!fp) return -1;

    char line[MAX_LINE_LEN];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;
        // 修改：去掉可能的 \r (Windows换行符)
        size_t len = strlen(line);
        if (len > 0 && line[len - 1] == '\r') line[len - 1] = '\0';

        // 跳过空行或只有分隔符的行
        int all_sep = 1;
        for (int i = 0; line[i]; i++) {
            if (line[i] != '|' && line[i] != ' ') { all_sep = 0; break; }
        }
        if (strlen(line) == 0 || line[0] == '|' || line[0] == '\0' || all_sep) continue;
        // 跳过以|开头或只有分隔符的空行，修复之前bug产生的空白记录

        void* data = malloc(MAX_DATA_SIZE);
        if (!data) continue;
        memset(data, 0, MAX_DATA_SIZE);
        parse_func(line, data);

        // 检查解析的ID是否有效，ID不为空，且第一个字符必须是前缀字符
        const char* parsed_id = (const char*)data;
        if (strlen(parsed_id) < 4) {
            // ID太短，跳过无效记录，释放内存
            free(data);
            continue;
        }
        InsertNode(list, -1, data, MAX_DATA_SIZE, parsed_id);
        free(data);
    }
    fclose(fp);
    return 0;
}

/* ==================== SHA-256（RFC 6234 同源算法） ====================
 * 消息按 64 字节块流式处理，不设长度上限；
 * 凭据字段统一存储其摘要 "sha256:<64位十六进制>"，明文不落盘。 */

typedef struct {
    unsigned int h[8];
    unsigned long long total_len;
    unsigned char blk[64];
    size_t blk_len;
} HisSha256Ctx;

static const unsigned int his_k256[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

static unsigned int his_rotr32(unsigned int x, int n) {
    return (x >> n) | (x << (32 - n));
}

static void his_sha256_block(unsigned int h[8], const unsigned char blk[64]) {
    unsigned int w[64];
    unsigned int a, b, c, d, e, f, g, hh, t1, t2;
    int i;
    for (i = 0; i < 16; i++) {
        w[i] = ((unsigned int)blk[i * 4] << 24) | ((unsigned int)blk[i * 4 + 1] << 16)
             | ((unsigned int)blk[i * 4 + 2] << 8) | (unsigned int)blk[i * 4 + 3];
    }
    for (i = 16; i < 64; i++) {
        unsigned int s0 = his_rotr32(w[i - 15], 7) ^ his_rotr32(w[i - 15], 18) ^ (w[i - 15] >> 3);
        unsigned int s1 = his_rotr32(w[i - 2], 17) ^ his_rotr32(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    a = h[0]; b = h[1]; c = h[2]; d = h[3];
    e = h[4]; f = h[5]; g = h[6]; hh = h[7];
    for (i = 0; i < 64; i++) {
        unsigned int S1 = his_rotr32(e, 6) ^ his_rotr32(e, 11) ^ his_rotr32(e, 25);
        unsigned int ch = (e & f) ^ (~e & g);
        unsigned int S0 = his_rotr32(a, 2) ^ his_rotr32(a, 13) ^ his_rotr32(a, 22);
        unsigned int maj = (a & b) ^ (a & c) ^ (b & c);
        t1 = hh + S1 + ch + his_k256[i] + w[i];
        t2 = S0 + maj;
        hh = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d;
    h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

void his_sha256_hex(const void* data, size_t len, char out_hex[65]) {
    HisSha256Ctx ctx;
    const unsigned char* p = (const unsigned char*)data;
    static const char hexc[] = "0123456789abcdef";
    unsigned long long bits;
    unsigned int i, j;

    ctx.h[0] = 0x6a09e667; ctx.h[1] = 0xbb67ae85; ctx.h[2] = 0x3c6ef372; ctx.h[3] = 0xa54ff53a;
    ctx.h[4] = 0x510e527f; ctx.h[5] = 0x9b05688c; ctx.h[6] = 0x1f83d9ab; ctx.h[7] = 0x5be0cd19;
    ctx.total_len = len;
    ctx.blk_len = 0;

    while (len >= 64) {
        his_sha256_block(ctx.h, p);
        p += 64;
        len -= 64;
    }

    /* 收尾：余量 + 填充（0x80 + 0x00... + 64 位大端比特长度） */
    memcpy(ctx.blk, p, len);
    ctx.blk[len] = 0x80;
    if (len < 56) {
        memset(ctx.blk + len + 1, 0, 56 - len - 1);
    } else {
        memset(ctx.blk + len + 1, 0, 64 - len - 1);
        his_sha256_block(ctx.h, ctx.blk);
        memset(ctx.blk, 0, 56);
    }
    bits = ctx.total_len * 8ULL;
    for (i = 0; i < 8; i++) {
        ctx.blk[56 + i] = (unsigned char)(bits >> (56 - 8 * i));
    }
    his_sha256_block(ctx.h, ctx.blk);

    for (i = 0; i < 8; i++) {
        for (j = 0; j < 4; j++) {
            unsigned char byte = (unsigned char)(ctx.h[i] >> (24 - 8 * j));
            out_hex[i * 8 + j * 2] = hexc[byte >> 4];
            out_hex[i * 8 + j * 2 + 1] = hexc[byte & 0x0F];
        }
    }
    out_hex[64] = '\0';
}

/* ==================== 统一凭据字段 ==================== */

#define CRED_HASH_PREFIX "sha256:"

void credHash(char* out, size_t cap, const char* plain) {
    char hex[65];
    size_t plen = strlen(CRED_HASH_PREFIX);
    /* 先完整读取 plain 再写 out，支持 out 与 plain 同一缓冲 */
    his_sha256_hex(plain, strlen(plain), hex);
    if (cap < plen + 65) {
        if (cap > 0) out[0] = '\0';
        return;
    }
    memcpy(out, CRED_HASH_PREFIX, plen);
    memcpy(out + plen, hex, 65);
}

int credIsHashed(const char* field) {
    return field && strncmp(field, CRED_HASH_PREFIX, strlen(CRED_HASH_PREFIX)) == 0;
}

int credHashMatch(const char* field, const char* plain) {
    char hex[65];
    if (!credIsHashed(field)) return 0;
    his_sha256_hex(plain, strlen(plain), hex);
    return strcmp(field + strlen(CRED_HASH_PREFIX), hex) == 0;
}
