#!/bin/sh
# smoke.sh —— 在临时工作区上把每条 flow-* 命令的廉价路径跑一遍;任一红即 RC=1。移植验收与改脚本后的回归都跑它。
# 用法: tests/smoke.sh   (不碰任何真实项目;临时目录在 $TMPDIR 下,结束即删)
set -u
KIT="$(cd "$(dirname "$0")/.." && pwd)"
PATH="$KIT/bin:$PATH"; export PATH
T=$(mktemp -d "${TMPDIR:-/tmp}/flow-smoke.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT
red=0
in_dir() { d="$1"; shift; ( cd "$d" && "$@" ); }   # 子 shell 只包住命令;红绿在父进程记(子 shell 里的 red=1 传不回来 = 假绿)
ok()   { printf 'ok   %s\n' "$*"; }
fail() { printf 'RED  %s\n' "$*"; red=1; }
expect_rc() { # $1 期望 RC  $2 描述  $3.. 命令
  want="$1"; desc="$2"; shift 2
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" = "$want" ]; then ok "$desc (RC=$rc)"; else fail "$desc: 期望 RC=$want 得到 $rc"; printf '%s\n' "$out" | sed 's/^/     /' | head -20; fi
  LAST_OUT="$out"
}

# ── 1. 建仓 + init ──
WS="$T/ws"; mkdir -p "$WS/src" "$WS/specs"
cd "$WS" && git init -q && git config user.email t@t && git config user.name t
printf 'specs/\n' > .gitignore
printf 'a\n' > src/a.ts; printf 'b\n' > src/b.ts; printf '# p\n' > specs/plan.md
printf '# root\n' > CLAUDE.md
git add -A && git commit -qm init
expect_rc 0 "flow-init" flow-init --ws "$WS" --repo . --main main
[ -f "$WS/.claude/flow.config.sh" ] && ok "config 已写" || fail "config 未写"
grep -q 'FLOW_SPEC_UNTRACKED=1' "$WS/.claude/flow.config.sh" && ok "自动判出规格目录被 gitignore" || fail "未判出 gitignore"
[ -x "$WS/.git/hooks/post-commit" ] && grep -q flow-post-commit "$WS/.git/hooks/post-commit" && ok "shim 已装" || fail "shim 未装"
expect_rc 0 "flow-init 幂等重跑" flow-init --ws "$WS" --repo . --main main

# 门与 fact-lint 配置(smoke 用最小门)
cat >> "$WS/.claude/flow.config.sh" <<'EOF'
flow_gates() {
  printf '%s\n' \
    'lint	true' \
    'unit	sh -c '"'"'echo "Test Files 1 passed (1)"; echo "Tests 3 passed (3)"'"'"'' \
    'dbreset	true'
}
FLOW_FACT_LINT_ROOTS="src specs"
FLOW_GATE_REBUILD=""
EOF
expect_rc 0 "flow-config --check" flow-config --check

# ── 2. 账本 / 路由 / 索引 ──
cat > "$WS/specs/debts.md" <<'EOF'
# 账本
<!-- debt:1 mark:#1 status:open owner:T1 due:T1 touches:src/a.ts title:示例一 -->
> #1 正文一
<!-- debt:2 mark:② status:closed owner:T1 due:T1 touches:src/b.ts title:示例二 -->
> ② 正文二
<!-- debt:3 mark:#3 status:open owner:T2 due:T2 touches:src/b.ts title:示例三 -->
> #3 正文三
EOF
expect_rc 0 "flow-route-debts --lint" flow-route-debts --lint
expect_rc 0 "flow-route-debts T1 src/a.ts" flow-route-debts T1 src/a.ts
printf '%s' "$LAST_OUT" | grep -q '#1' && ok "路由命中 #1" || fail "路由未命中 #1"
printf '%s' "$LAST_OUT" | grep -q '#3' && fail "路由误命中 #3" || ok "路由未误命中 #3"
expect_rc 2 "flow-route-debts 绝对路径 FATAL" flow-route-debts T1 /abs/x
expect_rc 0 "flow-render-index --write" flow-render-index --write
grep -q '<!-- debts-index hash:' "$WS/CLAUDE.md" && ok "索引块已写入" || fail "索引块未写入"
grep -q '触面' "$WS/CLAUDE.md" && fail "索引默认不该带触面列" || ok "索引不带触面列"
printf '<!-- debt:4 mark:#4 status:decided owner:T1 due:T1 touches:src/a.ts title:坏状态 -->\n> #4 x\n' >> "$WS/specs/debts.md"
expect_rc 1 "lint 抓第三种状态" flow-route-debts --lint
sed -i.bak '/debt:4/,$d' "$WS/specs/debts.md" && rm -f "$WS/specs/debts.md.bak"

# ── 3. 冻结 ──
FL="$WS/.flow/smoke"; mkdir -p "$FL"
# 单仓布局:.claude/ 与索引改动都在仓内,先提交成起点,冻结只量之后的实改集
git add -A >/dev/null 2>&1; git commit -qm setup >/dev/null 2>&1
expect_rc 0 "flow-manifest baseline" flow-manifest baseline "$FL/.manifest-baseline.txt"
printf 'd\n' >> src/b.ts; printf 'more\n' >> specs/plan.md
printf 'src/b.ts\nspecs/plan.md\n' > "$FL/.declared.txt"
expect_rc 0 "flow-manifest verify OK" flow-manifest verify "$FL/.manifest-baseline.txt" "$FL/.declared.txt"
printf '%s' "$LAST_OUT" | grep -q 'verify OK' && ok "读到 verify OK" || fail "没读到 verify OK"
# git 轴回归(单仓布局:kit 自有件在仓内 ⟹ 过滤模式多行,曾让 BSD awk 吐空集 ⟹ git 轴恒空恒绿;中文路径曾被 core.quotepath 转义 ⟹ 申报永远对不上)
printf 'n\n' > src/新增.ts
expect_rc 1 "flow-manifest verify git 轴漏申报 RED(中文路径)" flow-manifest verify "$FL/.manifest-baseline.txt" "$FL/.declared.txt"
printf '%s' "$LAST_OUT" | grep -q 'RED 漏申报: src/新增.ts' && ok "点名漏申报的中文路径" || fail "未点名 src/新增.ts"
printf 'src/b.ts\nspecs/plan.md\nsrc/新增.ts\n' > "$FL/.declared.txt"
expect_rc 0 "flow-manifest verify 中文路径申报对得上" flow-manifest verify "$FL/.manifest-baseline.txt" "$FL/.declared.txt"
printf '%s' "$LAST_OUT" | grep -q 'git 2 ' && ok "git 轴计数 2(过滤器活着、kit 自有件已滤)" || fail "git 轴计数不是 2: $LAST_OUT"
printf 'src/b.ts\n' > "$FL/.declared-short.txt"
expect_rc 1 "flow-manifest verify 非空转 RED" flow-manifest verify "$FL/.manifest-baseline.txt" "$FL/.declared-short.txt"
printf '%s' "$LAST_OUT" | grep -q 'RED 漏申报: specs/plan.md' && ok "点名漏申报的 specs 文件" || fail "未点名 specs/plan.md"
expect_rc 0 "flow-freeze" flow-freeze "$FL/.after-hashes.txt"
grep -q 'specs/plan.md' "$FL/.after-hashes.txt" && ok "冻结清单含规格轴" || fail "冻结清单缺规格轴"
grep -q 'src/新增.ts' "$FL/.after-hashes.txt" && ok "冻结清单含中文路径" || fail "冻结清单漏中文路径(quotepath 转义后 [ -f ] 为假被静默丢弃)"

# ── 4. 派单块 / 预算 / 收工 ──
printf '# h\n' > "$FL/01-write-handoff.md"
expect_rc 0 "flow-dispatch" flow-dispatch T1 --tree 快照 --db 禁用 --seq 1 src/a.ts
printf '%s' "$LAST_OUT" | grep -q '#1' && ok "派单块含欠账 #1" || fail "派单块缺欠账"
printf '%s' "$LAST_OUT" | grep -q '边写边落' && ok "派单块含边写边落" || fail "派单块缺边写边落"
printf '%s' "$LAST_OUT" | grep -q '证据源封闭' && ok "派单块含证据源封闭" || fail "派单块缺证据源封闭"
printf '%s' "$LAST_OUT" | grep -q '≤40000 字节' && ok "派单块含自写字节预算" || fail "派单块缺自写字节预算"
printf '%s' "$LAST_OUT" | grep -qF '<!-- flow:gen-begin -->' && printf '%s' "$LAST_OUT" | grep -qF '<!-- flow:gen-end -->' && ok "派单块自带生成段标记" || fail "派单块缺 flow:gen 标记"
expect_rc 2 "flow-dispatch 绝对触面 FATAL" flow-dispatch T1 --tree 快照 --db 禁用 --seq 1 /abs
expect_rc 0 "flow-doc-budget" flow-doc-budget "$FL"
head -c 48000 /dev/zero | tr '\0' x > "$FL/98-fat.md"; printf '\n' >> "$FL/98-fat.md"
expect_rc 1 "flow-doc-budget 自写字节红线(1 行 48001 字节)" flow-doc-budget "$FL"
printf '%s' "$LAST_OUT" | grep -q 'RED .*自写 48001 字节 > 40000' && ok "自写超限点名" || fail "自写超限未点名: $LAST_OUT"
head -c 38000 /dev/zero | tr '\0' y > "$FL/97-near.md"; printf '\n' >> "$FL/97-near.md"
expect_rc 1 "近线件不改红绿(同目录仍有 RED 件)" flow-doc-budget "$FL"
printf '%s' "$LAST_OUT" | grep -q 'WARN 自写 1 行 38001 字节.*97-near.md(自写 > 字节线的 90%' && ok "90% 近线 WARN" || fail "近线未 WARN: $(printf '%s' "$LAST_OUT" | grep 97-near)"
rm -f "$FL/97-near.md"
# 生成段豁免:48 KB 全在 flow:gen 里 ⟹ 自写 0,只按总字节 WARN,不 RED(派单件从前每批都要一句 budget-ok 带过)
{ printf '<!-- flow:gen-begin -->\n'; head -c 48000 /dev/zero | tr '\0' g; printf '\n<!-- flow:gen-end -->\n'; } > "$FL/96-gen.md"
expect_rc 1 "生成段件在 RED 目录里仍逐件判" flow-doc-budget "$FL"
printf '%s' "$LAST_OUT" | grep -q 'WARN 自写 0 行 0 字节(总 3 行 4804[0-9] 字节).*96-gen.md(总字节 > 40000' && ok "生成段不计进自写,只按总字节 WARN" || fail "生成段豁免失效: $(printf '%s' "$LAST_OUT" | grep 96-gen)"
printf '<!-- flow:gen-begin -->\nx\n' > "$FL/95-unbal.md"
flow-doc-budget "$FL" > /dev/null 2>&1 || true
expect_rc 1 "标记不成对仍逐件判" flow-doc-budget "$FL"
printf '%s' "$LAST_OUT" | grep -q 'WARN flow:gen 标记不成对(begin 1 / end 0).*95-unbal.md' && ok "标记不成对 WARN" || fail "标记不成对未 WARN: $(printf '%s' "$LAST_OUT" | grep 95-unbal)"
rm -f "$FL/96-gen.md" "$FL/95-unbal.md"
{ printf 'budget-ok:冒烟\n'; cat "$FL/98-fat.md"; } > "$FL/98-fat.tmp" && mv "$FL/98-fat.tmp" "$FL/98-fat.md"
expect_rc 0 "flow-doc-budget budget-ok 带过字节线" flow-doc-budget "$FL"
rm -f "$FL/98-fat.md"
expect_rc 0 "flow-close OK" flow-close "$FL" "$FL/.manifest-baseline.txt" "$FL/.declared.txt"
printf '%s' "$LAST_OUT" | grep -q 'ROUND-CLOSE OK' && ok "ROUND-CLOSE OK" || fail "未见 ROUND-CLOSE OK"
for i in 1 2 3; do printf -- '- 新规矩 %s\n' "$i" >> "$WS/.claude/flow-local.md"; done
expect_rc 1 "flow-close 规则书变长 RED" flow-close "$FL" "$FL/.manifest-baseline.txt" "$FL/.declared.txt"
printf '%s' "$LAST_OUT" | grep -q '规则书变长' && ok "棘轮点名规则书变长" || fail "棘轮未点名"

# ── 5. 门缓存 ──
git add -A >/dev/null 2>&1; git commit -qm work
expect_rc 0 "flow-gates --reset 首跑" flow-gates --reset
printf '%s' "$LAST_OUT" | grep -q 'SIX-GATES PASS\|GATES PASS' && ok "门 PASS" || fail "门未 PASS"
expect_rc 0 "flow-gates --reset 二跑" flow-gates --reset
printf '%s' "$LAST_OUT" | grep -q 'CACHED' && ok "缓存命中" || fail "缓存未命中"

# ── 6. post-commit → map-debt → clear ──
mkdir -p src/中文目录; printf 'm\n' > src/中文目录/m.ts   # 中文新目录:quotepath 转义时 [ -d ] 为假,结构规则 A 静默落空
printf 'e\n' >> src/a.ts; git add -A; git commit -qm touch-a
C=$(git rev-parse --short HEAD)
[ -f "$WS/.claude/map-debt.md" ] && grep -q "$C" "$WS/.claude/map-debt.md" && ok "post-commit 记了队列" || fail "post-commit 未记队列"
grep -q "$C | 新目录 src/中文目录 |" "$WS/.claude/map-debt.md" && ok "post-commit 认出中文新目录" || fail "post-commit 漏记中文新目录(quotepath)"
cat > "$FL/verdicts.md" <<'EOF'
| 标记 | 判定 | 证据 | 落点 |
|---|---|---|---|
| #1 | 不动 | 只加了一行 | — |
EOF
expect_rc 0 "flow-clear-map-debt --verdicts" flow-clear-map-debt --verdicts "$FL/verdicts.md" "$C"
grep -q "\[x\].*$C.*#1" "$WS/.claude/map-debt.md" && ok "三态表勾掉 #1" || fail "三态表未勾掉 #1"

# ── 7. fact-lint ──
printf '// 本仓从没跑过这个\n' > src/c.ts
expect_rc 1 "flow-fact-lint scan 抓 QCLAIM" flow-fact-lint scan src
expect_rc 0 "flow-fact-lint baseline" flow-fact-lint baseline
expect_rc 0 "flow-fact-lint verify 新增 0" flow-fact-lint verify
printf '// 树里没有第二个\n' >> src/c.ts
expect_rc 1 "flow-fact-lint verify 新增 1" flow-fact-lint verify

# ── 7b. 补充路径:接收位 / 合并模式 / 不重置的门 / 默认清账 / pr-merge 帮助 ──
cat > "$WS/specs/plan.md" <<'EOF'
## T1 · 示例任务
- 接收位:欠账 #1 的闭点
- 普通行
## T2 · 另一个
提到 T1 的行
EOF
expect_rc 0 "flow-receipts" flow-receipts specs/plan.md T1
printf '%s' "$LAST_OUT" | grep -q '接收位' && ok "接收位轴1命中" || fail "接收位轴1未命中"
expect_rc 2 "flow-receipts 找不到节 FATAL" flow-receipts specs/plan.md T9
expect_rc 0 "flow-dispatch --plan 任务节同源摘取" flow-dispatch T1 --tree 快照 --db 禁用 --seq 1 --plan "$WS/specs/plan.md" src/a.ts
printf '%s' "$LAST_OUT" | grep -q '任务书节选.*L1–3' && ok "节选定位 L1–3" || fail "节选定位错: $(printf '%s' "$LAST_OUT" | grep 任务书节选)"
printf '%s' "$LAST_OUT" | grep -q '^- 普通行' && ok "节选含节内正文" || fail "节选缺节内正文"
printf '%s' "$LAST_OUT" | grep -q '^## T2' && fail "节选越界到 T2" || ok "节选止于下一节"
expect_rc 0 "flow-dispatch --plan 找不到节只 WARN" flow-dispatch T9 --tree 快照 --db 禁用 --seq 1 --plan "$WS/specs/plan.md" src/a.ts
printf '%s' "$LAST_OUT" | grep -q '找不到节' && ok "节选缺失点名" || fail "节选缺失未点名"
printf '%s' "$LAST_OUT" | grep -q '未给 --round' && ok "无 --round 时模型行=继承" || fail "缺模型行"
expect_rc 0 "flow-dispatch --round ②A 无配置" flow-dispatch T1 --tree 快照 --db 禁用 --seq 1 --round ②A src/a.ts
printf '%s' "$LAST_OUT" | grep -q '②A · 继承编排方' && ok "--round 未配模型=继承" || fail "--round 模型行错"
printf 'FLOW_ROLE_MODELS="②A=sonnet"\n' >> "$WS/.claude/flow.config.sh"
expect_rc 0 "flow-dispatch --round ②A 有配置" flow-dispatch T1 --tree 快照 --db 禁用 --seq 1 --round ②A src/a.ts
printf '%s' "$LAST_OUT" | grep -q 'model=sonnet' && ok "FLOW_ROLE_MODELS 生效" || fail "FLOW_ROLE_MODELS 未生效"
{ printf '## T5 · 大任务\n'; for i in 1 2 3 4 5 6 7 8 9; do printf 'REQ-T5-0%s [open] 判据 %s\n' "$i" "$i"; done; printf 'REQ-T5-10 [deferred #1] 转账\n## T6 · 尾\n'; } > "$WS/specs/plan-req.md"
expect_rc 3 "flow-dispatch open REQ 9 > 上限 8 RC=3" flow-dispatch T5 --tree 快照 --db 禁用 --seq 1 --plan "$WS/specs/plan-req.md" src/a.ts
expect_rc 0 "flow-dispatch --cap-ok 带过 REQ 上限" flow-dispatch T5 --tree 快照 --db 禁用 --seq 1 --plan "$WS/specs/plan-req.md" --cap-ok 冒烟 src/a.ts
printf '%s' "$LAST_OUT" | grep -q 'REQ open 9 · done 0 · deferred 1' && ok "REQ 计数 open 9 / deferred 1" || fail "REQ 计数错: $(printf '%s' "$LAST_OUT" | grep -o 'REQ open[^;]*')"
printf 'src/a.ts\nsrc/b.ts\n' > "$FL/.lane-paths.txt"
expect_rc 0 "flow-dispatch --lane-merge" flow-dispatch T3 --tree 活树-独占 --db 禁用 --seq 50 --lane-merge "$FL/.lane-paths.txt"
printf '%s' "$LAST_OUT" | grep -q '合并批' && ok "合并批头行" || fail "合并批头行缺失"
expect_rc 2 "flow-dispatch --lane-merge 拒绝 --plan" flow-dispatch T3 --tree 活树-独占 --db 禁用 --seq 50 --lane-merge "$FL/.lane-paths.txt" --plan "$WS/specs/plan.md"
expect_rc 0 "flow-gates 不重置" flow-gates
printf '%s' "$LAST_OUT" | grep -q 'dbreset skipped\|CACHED' && ok "不重置口径:跳过 dbreset 或命中缓存" || fail "不重置口径异常"
printf 'x\n' >> src/b.ts; git add -A; git commit -qm touch-b; C2=$(git rev-parse --short HEAD)
printf '> **%s** 追写:触面变宽\n' "$(date +%F)" >> "$WS/specs/debts.md"
expect_rc 0 "flow-clear-map-debt 默认口径" flow-clear-map-debt "$C2"
printf '%s' "$LAST_OUT" | grep -q '勾掉 1 条' && ok "同日追写勾掉 #3" || fail "默认口径未勾掉: $LAST_OUT"
expect_rc 0 "flow-pr-merge --help" flow-pr-merge --help

# ── 8. freshness ──
out=$(flow-freshness 2>&1); [ -n "$out" ] && ok "freshness 有事就响: $out" || fail "freshness 在有未勾队列时应响"
sed -i.bak 's/^- \[ \]/- [x]/' "$WS/.claude/map-debt.md"; rm -f "$WS/.claude/map-debt.md.bak"
flow-render-index --write >/dev/null 2>&1
head -n "$(cat "$WS/.flow/.rulebook-lines")" "$WS/.claude/flow-local.md" > "$T/fl" && cp "$T/fl" "$WS/.claude/flow-local.md"
out=$(flow-freshness 2>&1); [ -z "$out" ] && ok "freshness 全绿静默" || fail "freshness 应静默,却说: $out"
out=$(cd "$T" && flow-freshness 2>&1); [ -z "$out" ] && ok "freshness 无配置静默" || fail "freshness 无配置应静默"

# ── 9. 多仓布局(工作区根在仓外;StockSteer-Mono 的生产布局)──
WS2="$T/ws2"; mkdir -p "$WS2/repo/src" "$WS2/repo/specs"
in_dir "$WS2/repo" sh -c 'git init -q && git config user.email t@t && git config user.name t && printf "specs/\n" > .gitignore && printf "a\n" > src/a.ts && printf "# s\n" > specs/s.md && printf "# root\n" > CLAUDE.md && git add -A && git commit -qm init'
expect_rc 0 "多仓 flow-init --repo repo" flow-init --ws "$WS2" --repo repo --main main
[ -f "$WS2/.claude/flow.config.sh" ] && grep -q 'FLOW_REPO="repo"' "$WS2/.claude/flow.config.sh" && ok "多仓 config 指向子仓" || fail "多仓 config 未指向子仓"
cat >> "$WS2/.claude/flow.config.sh" <<'EOF'
flow_gates() { printf '%s\n' 'lint	true' 'dbreset	true'; }
FLOW_GATE_REBUILD=""
FLOW_FACT_LINT_ROOTS="src"
EOF
printf '<!-- debt:1 mark:#1 status:open owner:T1 due:T1 touches:src/a.ts title:多仓示例 -->\n> #1 正文\n' > "$WS2/repo/specs/debts.md"
expect_rc 0 "多仓 子目录起跑 lint" in_dir "$WS2/repo/src" flow-route-debts --lint
expect_rc 0 "多仓 工作区根起跑 render-index" in_dir "$WS2" flow-render-index --write
grep -q 'debts-index' "$WS2/repo/CLAUDE.md" && ok "多仓 索引写进子仓根文档" || fail "多仓 索引未写进子仓"
in_dir "$WS2/repo" sh -c 'git add -A && git commit -qm setup' >/dev/null 2>&1
FL2="$WS2/.flow/b1"; mkdir -p "$FL2"
expect_rc 0 "多仓 baseline" in_dir "$WS2/repo" flow-manifest baseline "$FL2/.base.txt"
printf 'z\n' >> "$WS2/repo/src/a.ts"; printf 'more\n' >> "$WS2/repo/specs/s.md"
printf 'src/a.ts\nspecs/s.md\n' > "$FL2/.decl.txt"
expect_rc 0 "多仓 verify OK(工作区文件零泄漏进仓)" in_dir "$WS2" flow-manifest verify "$FL2/.base.txt" "$FL2/.decl.txt"
in_dir "$WS2/repo" sh -c 'git add -A && git commit -qm t1' >/dev/null 2>&1
C3=$(git -C "$WS2/repo" rev-parse --short HEAD)
grep -q "$C3" "$WS2/.claude/map-debt.md" && ok "多仓 post-commit 记进工作区队列" || fail "多仓 post-commit 未记队列"
expect_rc 0 "多仓 flow-gates --reset" in_dir "$WS2/repo" flow-gates --reset
[ -d "$WS2/.claude/flow-gates" ] && ok "多仓 门缓存落在工作区 .claude/" || fail "多仓 门缓存位置错"
# 三态表证据格含转义竖线(照 review-template 的示例)
printf '| 标记 | 判定 | 证据 | 落点 |\n|---|---|---|---|\n| #1 | 还 | `git diff \\| grep -c x` → 1 | debts.md #1 |\n' > "$FL2/verdicts.md"
expect_rc 0 "三态表证据含 \\|" in_dir "$WS2/repo" flow-clear-map-debt --verdicts "$FL2/verdicts.md" "$C3"
grep -q '④三态表:还' "$WS2/.claude/map-debt.md" && ok "转义竖线行被解析" || fail "转义竖线行未解析"

# ── 10. flow-trace(REQ ↔ 测试对账;0.3 起替代 flow-receipts)──
cat > "$WS/specs/plan.md" <<'EOF'
## T5 · 溯源示例
### 需求
- REQ-T5-01 [open] WHEN a THEN b
- REQ-T5-02 [done] WHEN c THEN d
- REQ-T5-03 [deferred #3] WHEN e THEN f
### 设计
- ADR-T5-1 提到 REQ-T5-01 不算第二个定义
## T6 · 空节
### 需求
- 这里没有 REQ 行
## T7 · 缺状态
- REQ-T7-01 WHEN x THEN y
EOF
printf "it('[REQ-T5-01] a→b', () => {})\nit('[REQ-T9-99] 孤儿', () => {})\n" > "$WS/src/t5.test.ts"
expect_rc 1 "flow-trace RED(REQ-T5-02 零测试)" flow-trace specs/plan.md T5
printf '%s' "$LAST_OUT" | grep -q 'RED  REQ-T5-02' && ok "点名零测试的 REQ" || fail "未点名 REQ-T5-02: $LAST_OUT"
printf '%s' "$LAST_OUT" | grep -q 'ok   REQ-T5-01' && ok "未跟踪的新测试文件也算数" || fail "未跟踪测试未被计入"
printf '%s' "$LAST_OUT" | grep -q 'WARN REQ-T9-99' && ok "孤儿测试 WARN" || fail "孤儿未 WARN"
printf '%s' "$LAST_OUT" | grep -q 'info REQ-T5-03 \[deferred' && ok "deferred 不计" || fail "deferred 处理错"
printf '%s' "$LAST_OUT" | grep -q 'REQ 3 条 / 判 3 条' && ok "贴 3 判 3" || fail "计数行错: $LAST_OUT"
printf "it('[REQ-T5-02] c→d', () => {})\n" >> "$WS/src/t5.test.ts"
expect_rc 0 "flow-trace OK" flow-trace specs/plan.md T5
printf '%s' "$LAST_OUT" | grep -q 'TRACE OK: 2/2' && ok "TRACE OK 2/2" || fail "末行不是 TRACE OK 2/2: $LAST_OUT"
expect_rc 2 "flow-trace 零 REQ FATAL" flow-trace specs/plan.md T6
expect_rc 1 "flow-trace 缺状态行 RED" flow-trace specs/plan.md T7
printf '%s' "$LAST_OUT" | grep -q '没有 \[open|done|deferred\] 状态行' && ok "点名缺状态的 REQ" || fail "缺状态未点名: $LAST_OUT"
expect_rc 2 "flow-trace 找不到节 FATAL" flow-trace specs/plan.md T9

# ── 11. flow-settings(会话瘦身:关掉 FLOW_KEEP_* 之外的插件与用户级 MCP;HOME 指到假目录,不碰真设置)──
H="$T/home"; mkdir -p "$H/.claude"
printf '{"enabledPlugins":{"a@m":true,"b@m":true,"c@m":false,"flow-kit@local":true}}\n' > "$H/.claude/settings.json"
printf '{"mcpServers":{"x":{"type":"stdio"},"y":{"type":"http"}}}\n' > "$H/.claude.json"
WS3="$T/ws3"; mkdir -p "$WS3/specs"
( cd "$WS3" && git init -q && git config user.email t@t && git config user.name t && printf '# r\n' > CLAUDE.md && git add -A && git commit -qm init )
expect_rc 0 "ws3 flow-init(不带 keep)" env HOME="$H" flow-init --ws "$WS3" --repo . --main main
printf '%s' "$LAST_OUT" | grep -q '未瘦身' && ok "不带 keep 只提示不猜" || fail "未提示: $LAST_OUT"
expect_rc 2 "flow-settings 未配 FLOW_KEEP_* FATAL" in_dir "$WS3" env HOME="$H" flow-settings --check
printf '%s' "$LAST_OUT" | grep -q '候选插件.*a@m b@m flow-kit@local' && ok "FATAL 时列出候选" || fail "候选未列: $LAST_OUT"
printf 'FLOW_KEEP_PLUGINS="a"\nFLOW_KEEP_MCP="x"\n' >> "$WS3/.claude/flow.config.sh"
expect_rc 1 "flow-settings --check 文件不存在 RED" in_dir "$WS3" env HOME="$H" flow-settings --check
expect_rc 0 "flow-settings --dry-run" in_dir "$WS3" env HOME="$H" flow-settings --dry-run
printf '%s' "$LAST_OUT" | grep -q '"b@m": false' && ok "dry-run 关 b@m" || fail "dry-run 未关 b@m: $LAST_OUT"
[ ! -f "$WS3/.claude/settings.local.json" ] && ok "dry-run 不落盘" || fail "dry-run 写了文件"
expect_rc 0 "flow-settings --write" in_dir "$WS3" env HOME="$H" flow-settings --write
SL="$WS3/.claude/settings.local.json"
grep -q '"b@m": false' "$SL" && ok "b@m 已关" || fail "b@m 未关"
grep -q '"a@m"' "$SL" && fail "留的 a@m 不该出现在 local" || ok "a@m 留(不写键)"
grep -q '"c@m"' "$SL" && fail "用户级本就 false 的 c@m 不该被碰" || ok "c@m 不碰"
grep -q 'flow-kit@local' "$SL" && fail "flow-kit 不该被关" || ok "flow-kit 永远留"
grep -q '"y"' "$SL" && ok "MCP y 已关" || fail "MCP y 未关"
grep -q '"x"' "$SL" && fail "留的 MCP x 不该被关" || ok "MCP x 留"
expect_rc 0 "flow-settings --check 写后全绿" in_dir "$WS3" env HOME="$H" flow-settings --check
expect_rc 0 "flow-settings --write 幂等" in_dir "$WS3" env HOME="$H" flow-settings --write
printf '%s' "$LAST_OUT" | grep -q '无变化' && ok "幂等:无变化" || fail "幂等重写: $LAST_OUT"
expect_rc 0 "flow-config --check 含瘦身核对" in_dir "$WS3" env HOME="$H" flow-config --check
printf '%s' "$LAST_OUT" | grep -q '会话瘦身' && ok "flow-config 核对项含瘦身" || fail "flow-config 未核瘦身: $LAST_OUT"
in_dir "$WS3" flow-render-index --write >/dev/null 2>&1   # 先把欠账索引渲染进根文档,免得 freshness 第 (3) 项抢话
out=$(cd "$WS3" && HOME="$H" flow-freshness); [ -z "$out" ] && ok "freshness 全绿静默" || fail "freshness 有话: $out"
# 漂移:用户又装了新插件 d@m
printf '{"enabledPlugins":{"a@m":true,"b@m":true,"d@m":true,"flow-kit@local":true}}\n' > "$H/.claude/settings.json"
expect_rc 1 "新装插件 → --check RED" in_dir "$WS3" env HOME="$H" flow-settings --check
printf '%s' "$LAST_OUT" | grep -q 'RED: 插件未关: d@m' && ok "点名 d@m" || fail "未点名 d@m: $LAST_OUT"
out=$(cd "$WS3" && HOME="$H" flow-freshness); printf '%s' "$out" | grep -q '会话未瘦身 1 处' && ok "freshness 报漂移" || fail "freshness 未报: $out"
# 改主意:留 b 不留 a → a 关、b 的 false 键删掉
sed -i.bak 's/^FLOW_KEEP_PLUGINS="a"/FLOW_KEEP_PLUGINS="b"/' "$WS3/.claude/flow.config.sh" && rm -f "$WS3/.claude/flow.config.sh.bak"
expect_rc 0 "换 keep 后 --write" in_dir "$WS3" env HOME="$H" flow-settings --write
grep -q '"a@m": false' "$SL" && ok "a@m 改为关" || fail "a@m 未关"
grep -q '"b@m"' "$SL" && fail "b@m 的 false 键该删" || ok "b@m 的 false 键已删"
# flow-init 一次到位 + 已有 local 的别的键不动
WS4="$T/ws4"; mkdir -p "$WS4/specs" "$WS4/.claude"
( cd "$WS4" && git init -q && git config user.email t@t && git config user.name t && printf '# r\n' > CLAUDE.md && git add -A && git commit -qm init )
printf '{"permissions":{"allow":["Bash(ls)"]}}\n' > "$WS4/.claude/settings.local.json"
expect_rc 0 "flow-init --keep-plugins/--keep-mcp 一次到位" env HOME="$H" flow-init --ws "$WS4" --repo . --main main --keep-plugins "a b" --keep-mcp "x y"
grep -q '^FLOW_KEEP_PLUGINS="a b"' "$WS4/.claude/flow.config.sh" && ok "config 写入 FLOW_KEEP_PLUGINS" || fail "config 未写 FLOW_KEEP_PLUGINS"
grep -q '"d@m": false' "$WS4/.claude/settings.local.json" && ok "ws4 关 d@m" || fail "ws4 未关 d@m"
grep -q 'disabledMcpServers' "$WS4/.claude/settings.local.json" && fail "全留时不该有 disabledMcpServers" || ok "全留 MCP 不写键"
grep -q 'Bash(ls)' "$WS4/.claude/settings.local.json" && ok "已有 permissions 键原样保留" || fail "permissions 键丢了"

# ── 9. flow-usage / flow-review-diff ──
TR="$T/transcripts/-ws-enc/sid1"; mkdir -p "$TR/subagents" "$T/emptyflow"
python3 - "$TR" "$FL" <<'PY'
import json, sys, os
tr, fl = sys.argv[1:3]
def asst(mid, ts, blocks, out=10):
    return json.dumps(dict(type='assistant', timestamp=ts, message=dict(id=mid, model='claude-test', usage=dict(input_tokens=5, cache_creation_input_tokens=100, cache_read_input_tokens=1000, output_tokens=out), content=blocks)))
def user(ts, text):
    return json.dumps(dict(type='user', timestamp=ts, message=dict(role='user', content=text)), ensure_ascii=False)
with open(os.path.join(tr, 'subagents', 'agent-1.jsonl'), 'w') as f:
    f.write(user('2026-09-03T01:00:00.000Z', f'你是 p1 的 ①写 agent。派单:{fl}/01-dispatch.md') + '\n')
    # 同一 message.id 的两条分片:首条是 thinking 块(out=2),次条才带真输出(out=10)。
    # 留「第一条」会把输出列低估 3 倍(实测 ①写 60,899 而真值 200,275)⟹ 必须逐字段取 max。
    f.write(asst('m1', '2026-09-03T01:00:10.000Z', [dict(type='thinking', thinking='')], out=2) + '\n')
    f.write(asst('m1', '2026-09-03T01:00:11.000Z', [dict(type='tool_use', id='tu1', name='Bash', input={'command': 'cat src/a.ts src/b.ts'})], out=10) + '\n')
    f.write(asst('m2', '2026-09-03T01:05:00.000Z', [dict(type='text', text='done')], out=20) + '\n')
with open(os.path.join(tr, 'subagents', 'agent-2.jsonl'), 'w') as f:
    f.write(user('2026-09-03T01:00:00.000Z', '别的批次 /nowhere/.flow/x') + '\n')
    f.write(asst('m9', '2026-09-03T01:00:10.000Z', [dict(type='text', text='x')]) + '\n')
with open(os.path.join(os.path.dirname(tr), 'sid1.jsonl'), 'w') as f:
    # 派单装配在第一个 agent 起来之前 —— 只按 sub-agent 时段切窗会把它整段丢掉
    f.write(user('2026-09-03T00:58:00.000Z', f'起一批,派单落 {fl}/01-dispatch.md') + '\n')
    f.write(asst('o1', '2026-09-03T00:59:30.000Z', [dict(type='text', text='ok')], out=7) + '\n')
    f.write(asst('o2', '2026-09-04T09:00:00.000Z', [dict(type='text', text='别批,窗外')], out=7) + '\n')
PY
printf 'FLOW_TRANSCRIPTS_DIR="%s"\nFLOW_TURN_CAP=1\n' "$T/transcripts" >> "$WS/.claude/flow.config.sh"
expect_rc 0 "flow-usage" flow-usage "$FL"
printf '%s' "$LAST_OUT" | grep -q '^| ①写 | 5m | 携带 2.2k · 输出 30 · 当量 [0-9.k]* | 2 轮 · 0.50 调用/轮 · 读批量 2.00 路径/读调用(1 次)· claude-test · 1 会话' && ok "①写行:去重 2 轮、携带 2.2k、输出取 max=30、读批量 2.00" || fail "①写行错: $(printf '%s' "$LAST_OUT" | grep '①写')"
printf '%s' "$LAST_OUT" | grep -q 'WARN ①写:2 请求 > FLOW_TURN_CAP 1' && ok "单轴请求超 FLOW_TURN_CAP 报 WARN" || fail "请求上限未 WARN: $(printf '%s' "$LAST_OUT" | grep WARN)"
printf '%s' "$LAST_OUT" | grep -q '^| 编排方 | .* 1 轮' && ok "父会话记成编排方,窗外那轮已剔除" || fail "编排方行错(应 1 轮): $(printf '%s' "$LAST_OUT" | grep 编排方)"
printf '%s' "$LAST_OUT" | grep -q '窗 09-0.*父会话提到本流程目录' && ok "编排方行带时间窗" || fail "编排方行缺时间窗"
printf '%s' "$LAST_OUT" | grep -q 'USAGE OK: 2 会话 / 3 轮' && ok "USAGE OK 末行" || fail "USAGE 末行错: $(printf '%s' "$LAST_OUT" | tail -1)"
expect_rc 0 "flow-usage --write" flow-usage "$FL" --write
[ -f "$FL/.usage.md" ] && ok ".usage.md 已写" || fail ".usage.md 未写"
expect_rc 0 "flow-doc-budget 不数 .usage.md" flow-doc-budget "$FL"
printf '%s' "$LAST_OUT" | grep -q 'usage.md' && fail "dotfile 进了热路径" || ok "dotfile 不进热路径"
expect_rc 2 "flow-usage 零命中 FATAL" flow-usage "$T/emptyflow"
printf '## 〇\n可合并\n## 丙栏 · 必闭\n- src/a.ts:3 漏判空集\n- src/b.ts 措辞\n## 丁栏\n- src/c.ts 不算\n' > "$FL/02a-orig.md"
printf '## 丙栏 · 必闭\n1. src/a.ts:9 另一种写法\n2. src/d.ts 新发现\n' > "$FL/02a-shadow.md"
expect_rc 0 "flow-review-diff" flow-review-diff "$FL/02a-orig.md" "$FL/02a-shadow.md"
printf '%s' "$LAST_OUT" | grep -q 'REVIEW-DIFF: 原版独有 1 条 · 影子独有 1 条 · 共同文件 1' && ok "丙栏按文件锚分组:1 / 1 / 1" || fail "review-diff 计数错: $(printf '%s' "$LAST_OUT" | tail -1)"
printf '%s' "$LAST_OUT" | grep -q 'src/c.ts' && fail "丁栏混进了丙栏" || ok "只取丙栏"
printf '## 甲栏\n- x\n' > "$FL/02a-bad.md"
expect_rc 2 "flow-review-diff 无丙栏 FATAL" flow-review-diff "$FL/02a-orig.md" "$FL/02a-bad.md"
rm -f "$FL/02a-orig.md" "$FL/02a-shadow.md" "$FL/02a-bad.md"

# ── 11. flow-ledger(账本增删改 + 三态表单一解析器)──
cd "$WS"
expect_rc 0 "flow-ledger add" flow-ledger add --owner T4 --due T4 --touches src/a.ts --title 新立的账 --body 正文四
grep -q '<!-- debt:4 mark:#4 status:open owner:T4 due:T4 touches:src/a.ts title:新立的账 -->' "$WS/specs/debts.md" && ok "add 写出机器头(自动取号 #4)" || fail "add 机器头错: $(grep 'debt:4' "$WS/specs/debts.md")"
grep -q '^> #4 正文四' "$WS/specs/debts.md" && ok "add 写出正文行" || fail "add 正文行缺失"
expect_rc 2 "flow-ledger add 重号 FATAL" flow-ledger add --owner T4 --due T4 --touches src/a.ts --title x --mark '#4'
expect_rc 2 "flow-ledger add 绝对触面 FATAL" flow-ledger add --owner T4 --due T4 --touches /abs/x --title x
expect_rc 0 "flow-ledger append(追写)" flow-ledger append '#4' '追写:触面变宽到 src/b.ts'
grep -q '^>   追写:触面变宽到 src/b.ts' "$WS/specs/debts.md" && ok "append 落在正文尾" || fail "append 未落盘"
expect_rc 0 "flow-ledger close" flow-ledger close '#4' --note 冒烟还账
grep -q '<!-- debt:4 mark:#4 status:closed ' "$WS/specs/debts.md" && ok "close 翻 status" || fail "close 未翻 status"
grep -q "已还 $(date +%F)" "$WS/specs/debts.md" && ok "close 追一行已还" || fail "close 未追已还行"
expect_rc 0 "flow-ledger close 幂等(已 closed 只跳过)" flow-ledger close '#4'
printf '%s' "$LAST_OUT" | grep -q 'skip #4 已是 closed' && ok "重复 close 跳过而非静默改" || fail "重复 close 行为错"
expect_rc 2 "flow-ledger close 标记不存在 FATAL" flow-ledger close '#99'
expect_rc 0 "flow-ledger 落盘后自动 lint" flow-ledger append '#3' '再追一行'
printf '%s' "$LAST_OUT" | grep -q 'LEDGER OK: 已落盘;lint 已过' && ok "末行 LEDGER OK" || fail "末行错: $(printf '%s' "$LAST_OUT" | tail -1)"
cat > "$FL/verdicts2.md" <<'EOF'
| 项 | 判定 | 命令 | RC |
|---|---|---|---|
| #1 | `shasum -c x` | 21 OK | 0 |

## 逐欠账三态表
| 标记 | 判定 | 证据 | 落点 |
|---|---|---|---|
| #3 | **还** | 复跑判据 → 判 5 / RED 0 | debts.md #3 段 |
| #1 | **不动** | numstat 0 | — |
EOF
expect_rc 0 "flow-ledger verdicts(强调号 + 混表)" flow-ledger verdicts "$FL/verdicts2.md"
printf '%s' "$LAST_OUT" | grep -q '^#3	还	' && ok "**还** 归一化成 还" || fail "强调号未归一化: $(printf '%s' "$LAST_OUT" | head -3)"
printf '%s' "$LAST_OUT" | grep -q 'VERDICTS OK: 还 1 · 追写 0 · 不动 1' && ok "三态计数" || fail "三态计数错: $(printf '%s' "$LAST_OUT" | tail -1)"
expect_rc 0 "flow-ledger apply 默认 dry-run" flow-ledger apply "$FL/verdicts2.md"
printf '%s' "$LAST_OUT" | grep -q '\[dry-run\] close #3' && ok "dry-run 只报不写" || fail "dry-run 输出错"
grep -q '<!-- debt:3 mark:#3 status:open ' "$WS/specs/debts.md" && ok "dry-run 未动账本" || fail "dry-run 动了账本"
expect_rc 0 "flow-ledger apply --write" flow-ledger apply "$FL/verdicts2.md" --write
grep -q '<!-- debt:3 mark:#3 status:closed ' "$WS/specs/debts.md" && ok "apply 把「还」翻成 closed" || fail "apply 未翻 #3"
grep -q '<!-- debt:1 mark:#1 status:open ' "$WS/specs/debts.md" && ok "「不动」零动作" || fail "「不动」被误改"
expect_rc 2 "flow-ledger verdicts 零合法行 FATAL" flow-ledger verdicts "$FL/01-write-handoff.md"

# ── 12. flow-close --between(轮间交接口一键)──
flow-render-index --write >/dev/null 2>&1
git add -A >/dev/null 2>&1
git commit -qm ledger >/dev/null 2>&1
expect_rc 0 "between baseline" flow-manifest baseline "$FL/.base-b.txt"
printf 'between\n' >> src/a.ts
printf 'src/a.ts\n' > "$FL/.decl-b.txt"
expect_rc 0 "flow-freeze after-hashes" flow-freeze "$FL/.after-b.txt"
expect_rc 0 "flow-close --between" flow-close --between "$FL" "$FL/.base-b.txt" "$FL/.decl-b.txt" "$FL/.after-b.txt" --task T1
printf '%s' "$LAST_OUT" | grep -q 'BETWEEN OK' && ok "BETWEEN OK" || fail "未见 BETWEEN OK: $(printf '%s' "$LAST_OUT" | tail -3)"
printf '%s' "$LAST_OUT" | grep -q '树读数' && ok "含树读数(HEAD + porcelain)" || fail "缺树读数"
printf '%s' "$LAST_OUT" | grep -q '路由复跑' && ok "含路由复跑" || fail "缺路由复跑"
printf '%s' "$LAST_OUT" | grep -q 'REQ 对账跳过' && ok "未给 --plan 时 REQ 对账显式跳过(不静默)" || fail "REQ 对账跳过未声明"
expect_rc 2 "flow-close --between 缺 after-hashes FATAL" flow-close --between "$FL" "$FL/.base-b.txt" "$FL/.decl-b.txt"
printf 'src/b.ts\n' > "$FL/.decl-wrong.txt"
expect_rc 1 "flow-close --between 漏申报 RED" flow-close --between "$FL" "$FL/.base-b.txt" "$FL/.decl-wrong.txt" "$FL/.after-b.txt"
printf '%s' "$LAST_OUT" | grep -q 'BETWEEN RED' && ok "BETWEEN RED" || fail "漏申报没红"

# ── 13. flow-receipts 表行体例 + 带连字符任务号的 REQ ──
cat > "$WS/specs/plan-table.md" <<'EOF'
# 一期任务表
| 任务 | 内容 | 验收 |
|---|---|---|
| P1.A | 计算规格骨架 | 接收位:骨架落库 |
| P1.B | schema v0 | 依赖 P1.A 的口径 |

落地记录:P1.A 已出口
EOF
expect_rc 2 "表行体例下 section 模式 FATAL(并提示改 config)" flow-receipts specs/plan-table.md P1.A
printf '%s' "$LAST_OUT" | grep -q 'FLOW_RECEIPT_MODE=table' && ok "FATAL 里给出修法" || fail "FATAL 未给修法"
printf 'FLOW_RECEIPT_MODE="table"\n' >> "$WS/.claude/flow.config.sh"
expect_rc 0 "flow-receipts table 体例" flow-receipts specs/plan-table.md P1.A
printf '%s' "$LAST_OUT" | grep -q 'RECEIPTS OK: 轴1 2 · 轴2 1' && ok "表行两轴计数" || fail "表行计数错: $(printf '%s' "$LAST_OUT" | tail -1)"
expect_rc 2 "table 体例零命中 FATAL" flow-receipts specs/plan-table.md P9.Z
sed -i.bak '/FLOW_RECEIPT_MODE/d' "$WS/.claude/flow.config.sh"; rm -f "$WS/.claude/flow.config.sh.bak"
mkdir -p src/t
cat > "$WS/specs/plan-hyphen.md" <<'EOF'
## P4-T2 · 带连字符的任务号
- REQ-P4-T2-01 [open] WHEN a THEN b
- REQ-P4T2-02 [open] 无连字符的写法也要认
EOF
printf "it('[REQ-P4-T2-01] a', () => {});\nit('[REQ-P4T2-02] b', () => {});\n" > src/t/hyphen.test.ts
expect_rc 0 "flow-trace 认带连字符的 REQ 号" flow-trace specs/plan-hyphen.md P4-T2
printf '%s' "$LAST_OUT" | grep -q 'TRACE OK: 2/2' && ok "两种写法都对上" || fail "REQ 对账错: $(printf '%s' "$LAST_OUT" | tail -1)"
expect_rc 0 "flow-dispatch 数带连字符的 REQ" flow-dispatch P4-T2 --tree 快照 --db 禁用 --seq 1 --plan "$WS/specs/plan-hyphen.md" src/a.ts
printf '%s' "$LAST_OUT" | grep -q 'REQ open 2 · done 0' && ok "派单 REQ 计数 2" || fail "派单 REQ 计数错: $(printf '%s' "$LAST_OUT" | grep -o 'REQ open[^;]*')"
expect_rc 0 "flow-dispatch --round ①写 给写模板绝对路径" flow-dispatch T1 --tree 活树-独占 --db 禁用 --seq 1 --round ①写 src/a.ts
printf '%s' "$LAST_OUT" | grep -q '回件模板.*/skills/protocol/references/handoff-template.md' && ok "模板路径由脚本自算(无版本号手打)" || fail "缺回件模板行: $(printf '%s' "$LAST_OUT" | grep 模板)"
expect_rc 0 "flow-dispatch --round ④A 给审模板" flow-dispatch T1 --tree 快照 --db 禁用 --seq 1 --round ④A src/a.ts
printf '%s' "$LAST_OUT" | grep -q '回件模板.*/references/review-template.md' && ok "审轮给复审模板" || fail "审轮模板行错"
rm -rf src/t "$WS/specs/plan-hyphen.md" "$WS/specs/plan-table.md"

# ── 14. flow-merge-lane(并行支三方合并器;空比对守卫)──
git checkout -- src/a.ts 2>/dev/null || true
git add -A >/dev/null 2>&1
git commit -qm pre-lane >/dev/null 2>&1
BASE=$(git rev-parse --short HEAD)
LANE="$T/lane"; mkdir -p "$LANE/src"
cp src/a.ts "$LANE/src/a.ts"; printf 'lane-side\n' >> "$LANE/src/a.ts"
cp src/b.ts "$LANE/src/b.ts"
printf 'src/a.ts\n' > "$FL/.lane-list.txt"
expect_rc 0 "flow-merge-lane plan" flow-merge-lane plan "$BASE" "$LANE" "$FL/.lane-list.txt"
printf '%s' "$LAST_OUT" | grep -q '^FF    src/a.ts' && ok "主树未动 → FF" || fail "merge-lane plan 判定错: $(printf '%s' "$LAST_OUT" | head -2)"
grep -q 'lane-side' src/a.ts && fail "plan 不该写主树" || ok "plan 一个字节不写"
printf 'src/b.ts\n' > "$FL/.lane-empty.txt"
expect_rc 2 "flow-merge-lane 空比对守卫 FATAL" flow-merge-lane plan "$BASE" "$LANE" "$FL/.lane-empty.txt"
printf '%s' "$LAST_OUT" | grep -q '逐字节相同' && ok "点名支树没改它" || fail "空比对守卫未点名"
expect_rc 0 "flow-merge-lane apply" flow-merge-lane apply "$BASE" "$LANE" "$FL/.lane-list.txt"
grep -q 'lane-side' src/a.ts && ok "apply 写进主树" || fail "apply 未写主树"
git checkout -- src/a.ts 2>/dev/null || true

# ── 15. FLOW_INDEX_DOC(欠账索引搬出常驻文件;43 条索引 = 5.5 KB,住根文档就是每轮重付)──
cd "$WS"
mkdir -p docs; printf '# 欠账索引(生成物)\n' > docs/idx.md
printf 'FLOW_INDEX_DOC="docs/idx.md"\n' >> "$WS/.claude/flow.config.sh"
expect_rc 0 "flow-render-index --write 默认落 FLOW_INDEX_DOC" flow-render-index --write
grep -q '<!-- debts-index hash:' docs/idx.md && ok "索引落在 FLOW_INDEX_DOC" || fail "索引未落 FLOW_INDEX_DOC"
out=$(flow-freshness 2>&1)
printf '%s' "$out" | grep -q '两处索引' && ok "根文档留着旧块 → freshness 报两处索引" || fail "两处索引未报: $out"
python3 - "$WS/CLAUDE.md" <<'PYEOF'
import sys, re
p = sys.argv[1]; ls = open(p, encoding='utf-8').read().split('\n')
out = []; skip = False
for l in ls:
    if l.startswith('<!-- debts-index '): skip = True; out.append('欠账索引:见 docs/idx.md(生成物,flow-render-index --write)'); continue
    if l.startswith('<!-- /debts-index'): skip = False; continue
    if not skip: out.append(l)
open(p, 'w', encoding='utf-8').write('\n'.join(out))
PYEOF
out=$(flow-freshness 2>&1); [ -z "$out" ] && ok "删掉旧块后 freshness 静默" || fail "应静默,却说: $out"
grep -q '欠账索引:见 docs/idx.md' "$WS/CLAUDE.md" && ok "根文档只剩一行指针" || fail "指针行缺失"
sed -i.bak '/FLOW_INDEX_DOC/d' "$WS/.claude/flow.config.sh"; rm -f "$WS/.claude/flow.config.sh.bak"
out=$(flow-freshness 2>&1)
printf '%s' "$out" | grep -q '欠账索引漂移' && ok "不设 FLOW_INDEX_DOC 时回落根文档(此时它只剩指针 → 报漂移)" || fail "回落根文档失效: $out"
flow-render-index --write >/dev/null 2>&1

[ "$red" = 0 ] && { echo "SMOKE OK"; exit 0; } || { echo "SMOKE RED"; exit 1; }
