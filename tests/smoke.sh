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
expect_rc 0 "flow-dispatch 两条触面逐条传" flow-dispatch T1 --tree 快照 --db 禁用 --seq 1 src/a.ts src/b.ts
expect_rc 2 "flow-dispatch 同两条塌成一个实参 FATAL" flow-dispatch T1 --tree 快照 --db 禁用 --seq 1 "src/a.ts src/b.ts"
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
printf '%s' "$LAST_OUT" | grep -q '整份 plan 有 .* 行带 REQ' && ok "本节漏写 ≠ 本仓不用 REQ(N/A 只对整份判)" || fail "FATAL 未把不适用与漏写分开: $LAST_OUT"
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
with open(os.path.join(tr, 'subagents', 'agent-3.jsonl'), 'w') as f:
    # 编排方实际写法:「的 **②B · 对内闭包轴**(与 ②A 并行」—— 旧正则被 ** 打败后全文扫先撞 ②A,②B 曾整轴并进错行
    f.write(user('2026-09-03T01:10:00.000Z', f'你是 p1 的 **②B · 对内闭包轴**(与 ②A 并行,零共享推理)。派单:{fl}/02b-dispatch.md') + '\n')
    f.write(asst('m5', '2026-09-03T01:10:10.000Z', [dict(type='tool_use', id='tu5', name='Bash', input={'command': 'flow-manifest verify a b'})], out=10) + '\n')
    # 工具结果 605 s 后才回来 = 卡顿(p4d 实测 600 s 整、两轴同刻放行;输出正常)
    f.write(json.dumps(dict(type='user', timestamp='2026-09-03T01:20:15.000Z', message=dict(role='user', content=[dict(type='tool_result', tool_use_id='tu5', content='verify OK')]))) + '\n')
    f.write(asst('m6', '2026-09-03T01:20:30.000Z', [dict(type='text', text='done')], out=20) + '\n')
with open(os.path.join(os.path.dirname(tr), 'sid1.jsonl'), 'w') as f:
    # 派单装配在第一个 agent 起来之前 —— 只按 sub-agent 时段切窗会把它整段丢掉
    f.write(user('2026-09-03T00:58:00.000Z', f'起一批,派单落 {fl}/01-dispatch.md') + '\n')
    f.write(asst('o1', '2026-09-03T00:59:30.000Z', [dict(type='text', text='ok')], out=7) + '\n')
    f.write(asst('o2', '2026-09-04T09:00:00.000Z', [dict(type='text', text='别批,窗外')], out=7) + '\n')
PY
printf 'FLOW_TRANSCRIPTS_DIR="%s"\nFLOW_TURN_CAP=1\n' "$T/transcripts" >> "$WS/.claude/flow.config.sh"
expect_rc 0 "flow-usage" flow-usage "$FL"
printf '%s' "$LAST_OUT" | grep -q '^| ①写 | 5m | 携带 2.2k · 输出 30 · 当量 [0-9.k]* | 2 轮 · 0.50 调用/轮 · 读批量 2.00 路径/读调用(1 次)· claude-test · 1 会话' && ok "①写行:去重 2 轮、携带 2.2k、输出取 max=30、读批量 2.00" || fail "①写行错: $(printf '%s' "$LAST_OUT" | grep '①写')"
printf '%s' "$LAST_OUT" | grep -q 'WARN ①写:会话 agent-1 2 请求 > FLOW_TURN_CAP 1' && ok "单会话请求超 FLOW_TURN_CAP 报 WARN(按会话)" || fail "请求上限未 WARN: $(printf '%s' "$LAST_OUT" | grep WARN)"
printf '%s' "$LAST_OUT" | grep -q '^| 编排方 | .* 1 轮' && ok "父会话记成编排方,窗外那轮已剔除" || fail "编排方行错(应 1 轮): $(printf '%s' "$LAST_OUT" | grep 编排方)"
printf '%s' "$LAST_OUT" | grep -q '窗 09-0.*父会话提到本流程目录' && ok "编排方行带时间窗" || fail "编排方行缺时间窗"
printf '%s' "$LAST_OUT" | grep -q '^| ②B | 10m | .* 2 轮' && ok "「的 **②B · …**」写法识别成 ②B" || fail "②B 角色识别错: $(printf '%s' "$LAST_OUT" | grep -E '^\| ②')"
printf '%s' "$LAST_OUT" | grep -q '^| ②B | 10m | 0m | 10m | 0m | 1 |' && ok "墙钟归因:②B 工具 10m · 卡顿 1" || fail "墙钟归因行错: $(printf '%s' "$LAST_OUT" | grep -E '^\| ②B \| 10m \| ')"
printf '%s' "$LAST_OUT" | grep -q 'WARN 卡顿 ②B:.* 工具 605s `flow-manifest verify a b`' && ok "卡顿单列 WARN(605 s ≥ FLOW_STALL_SEC)" || fail "卡顿未 WARN: $(printf '%s' "$LAST_OUT" | grep 卡顿)"
printf '%s' "$LAST_OUT" | grep -q '编排方输出去向' && ok "编排方输出去向表" || fail "缺输出去向表"
printf '%s' "$LAST_OUT" | grep -q 'USAGE OK: 3 会话 / 5 轮' && ok "USAGE OK 末行" || fail "USAGE 末行错: $(printf '%s' "$LAST_OUT" | tail -1)"
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
# flow-trace 学 table 体例(0.7.1):节 = 首格恰等于任务号的表行;整份零 REQ ⟹ N/A(RC=3),不是红
expect_rc 3 "flow-trace table 体例 · 整份零 REQ ⟹ N/A" flow-trace specs/plan-table.md P1.A
printf '%s' "$LAST_OUT" | grep -q '^TRACE N/A' && ok "末行 TRACE N/A" || fail "末行不是 TRACE N/A: $(printf '%s' "$LAST_OUT" | tail -1)"
printf '%s' "$LAST_OUT" | grep -q '节命中 1 行' && ok "首格严格:P1.B 那行点名 P1.A,不算进 P1.A 的节(receipts 轴1 全行匹配数 2)" || fail "首格不严格: $(printf '%s' "$LAST_OUT" | tail -1)"
expect_rc 2 "flow-trace table 体例任务号拼错仍 FATAL" flow-trace specs/plan-table.md P9.Z
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
# 0.8.1:主树缺失的两种语义分开 —— 基线也没有 = 支新增件(NEW),基线里有 = 主树删件 vs 支树改件(FATAL)
printf 'lane-new\n' > "$LANE/src/new.ts"
printf 'src/new.ts\n' > "$FL/.lane-new.txt"
expect_rc 0 "flow-merge-lane plan 支新增件" flow-merge-lane plan "$BASE" "$LANE" "$FL/.lane-new.txt"
printf '%s' "$LAST_OUT" | grep -q '^NEW   src/new.ts' && ok "支新增件 → NEW,不再 FATAL" || fail "支新增件判错: $(printf '%s' "$LAST_OUT" | head -3)"
[ -f src/new.ts ] && fail "plan 不该在主树建件" || ok "plan 对新增件也一个字节不写"
expect_rc 0 "flow-merge-lane apply 支新增件" flow-merge-lane apply "$BASE" "$LANE" "$FL/.lane-new.txt"
grep -q 'lane-new' src/new.ts && ok "apply 落下新增件" || fail "apply 没落新增件"
rm -f src/new.ts
# 判据次序:空新增件的 hb 与 ht 都是空文件的哈希 ⟹ NEW 排在空比对守卫之后就成窄误诊(只在空件上现形)
: > "$LANE/src/enew.ts"
printf 'src/enew.ts\n' > "$FL/.lane-enew.txt"
expect_rc 0 "flow-merge-lane plan 空的支新增件" flow-merge-lane plan "$BASE" "$LANE" "$FL/.lane-enew.txt"
printf '%s' "$LAST_OUT" | grep -q '^NEW   src/enew.ts' && ok "空新增件 → NEW,不被空比对守卫误诊" || fail "空新增件判错: $(printf '%s' "$LAST_OUT" | head -3)"
# 阴性对照:同一个空文件基线里**也**有(内容也空)⟹ 守卫照旧 FATAL,证明上一条不是把守卫关了
: > src/eold.ts; git commit -q -m lane-empty-base -- src/eold.ts >/dev/null 2>&1
BASE2=$(git rev-parse --short HEAD)
: > "$LANE/src/eold.ts"
printf 'src/eold.ts\n' > "$FL/.lane-eold.txt"
expect_rc 2 "flow-merge-lane 空文件在基线里也有 ⟹ 仍 FATAL" flow-merge-lane plan "$BASE2" "$LANE" "$FL/.lane-eold.txt"
printf '%s' "$LAST_OUT" | grep -q '逐字节相同' && ok "空比对守卫对空文件照样活着" || fail "阴性对照失守: $(printf '%s' "$LAST_OUT" | head -3)"
rm -f "$LANE/src/enew.ts" "$LANE/src/eold.ts"
mv src/b.ts "$T/b.ts.bak"
printf 'lane-side\n' >> "$LANE/src/b.ts"
printf 'src/b.ts\n' > "$FL/.lane-del.txt"
expect_rc 2 "flow-merge-lane 主树删件 FATAL" flow-merge-lane plan "$BASE" "$LANE" "$FL/.lane-del.txt"
printf '%s' "$LAST_OUT" | grep -q '主树删件 vs 支树改件' && ok "基线里有而主树没有 → 点名真冲突" || fail "未点名主树删件: $(printf '%s' "$LAST_OUT" | head -3)"
mv "$T/b.ts.bak" src/b.ts

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


# ── 16. 0.6.0:步骤账 / 派单 --dir --resume / 轮过渡 / 收口机械段 ──
cd "$WS"
FR="$WS/.flow/r1"; mkdir -p "$FR"
expect_rc 0 "flow-step init" flow-step init "$FR" ①写 "REQ-T1-01 写 a" "回件" "收工核对"
printf '%s' "$LAST_OUT" | grep -q 'STEPS OK: 已勾 0 / 共 3 · 下一步 1 · REQ-T1-01 写 a' && ok "步骤账建 3 步" || fail "步骤账末行错: $(printf '%s' "$LAST_OUT" | tail -1)"
expect_rc 2 "flow-step init 已存在 FATAL(进度不许静默覆盖)" flow-step init "$FR" ①写 x
expect_rc 0 "flow-step done 1" flow-step done "$FR" ①写 1 "测绿"
grep -q '^- \[x\] 1 · REQ-T1-01 写 a · .* · 测绿$' "$FR/.steps-①写.md" && ok "勾行带时间与备注" || fail "勾行体例错: $(grep '^- \[x\]' "$FR/.steps-①写.md")"
expect_rc 0 "flow-step done 重复只 WARN" flow-step done "$FR" ①写 1
expect_rc 2 "flow-step done 号不存在 FATAL" flow-step done "$FR" ①写 9
expect_rc 0 "flow-step add" flow-step add "$FR" ①写 "补一步"
printf '%s' "$LAST_OUT" | grep -q '已勾 1 / 共 4 · 下一步 2' && ok "add 后 1/4、下一步 2" || fail "add 计数错: $(printf '%s' "$LAST_OUT" | tail -1)"
rm -f "$FR/.steps-①写.md"
# 派单 --dir:建步骤账(①写按 open REQ)+ 命令连实参 + 节选按轴封顶
{ printf '## T1 · 大节\n'; printf 'REQ-T1-01 [open] 判据甲\nREQ-T1-02 [open] 判据乙\n'; printf '### 第一刀\n'; i=0; while [ $i -lt 400 ]; do i=$((i+1)); printf '正文行 %s 这是一段足够长的规格正文用来把节撑过封顶字节数\n' "$i"; done; printf '### 本刀落位\n落位段最后一行\n## T2 · 尾\n'; } > "$WS/specs/plan-big.md"
expect_rc 0 "flow-dispatch --dir --round ①写 --plan(大节)" flow-dispatch T1 --tree 活树-独占 --db 禁用 --seq 1 --round ①写 --dir "$FR" --plan "$WS/specs/plan-big.md" src/a.ts
printf '%s' "$LAST_OUT" | grep -q '字节 > 封顶' && ok "节选封顶生效" || fail "节选未封顶"
printf '%s' "$LAST_OUT" | grep -q '落位段最后一行' && ok "节尾(落位段)印出" || fail "节尾缺失"
printf '%s' "$LAST_OUT" | grep -q '^L[0-9]*: REQ-T1-02 \[open\]' && ok "REQ 行带 plan 行号" || fail "REQ 行缺失"
printf '%s' "$LAST_OUT" | grep -q '正文行 5 ' && fail "封顶后仍印了节中正文" || ok "节中正文未印"
printf '%s' "$LAST_OUT" | grep -q "flow-manifest verify $FR/.manifest-baseline-①写.txt $FR/.declared-①写.txt" && ok "收工命令连实参(约定名)" || fail "收工命令未带实参"
printf '%s' "$LAST_OUT" | grep -q '变异实测是交付条件' && fail "待填段仍要求①写变异" || ok "①写不再要求变异电池"
grep -q '^- \[ \] 1 · REQ-T1-01 判据甲' "$FR/.steps-①写.md" && [ "$(grep -c '^- \[ \]' "$FR/.steps-①写.md")" = 4 ] && ok "①写步骤账 = 2 REQ + 回件 + 收工核对" || fail "①写步骤账错: $(cat "$FR/.steps-①写.md")"
[ -d "$FR/.evidence" ] && ok ".evidence 已建" || fail ".evidence 未建"
expect_rc 0 "flow-dispatch --dir --round ②A --plan 只给 outline + REQ" flow-dispatch T1 --tree 快照 --db 禁用 --seq 10 --round ②A --dir "$FR" --plan "$WS/specs/plan-big.md" src/a.ts
printf '%s' "$LAST_OUT" | grep -q '只给 outline + REQ 行' && ok "②A 按轴节选" || fail "②A 未按轴节选"
printf '%s' "$LAST_OUT" | grep -q '落位段最后一行' && fail "②A 印了节尾" || ok "②A 零正文"
grep -q '装载:读派单' "$FR/.steps-②A.md" && ok "②A 步骤账四步" || fail "②A 步骤账缺"
expect_rc 2 "flow-dispatch --dir 缺 --round FATAL" flow-dispatch T1 --tree 快照 --db 禁用 --seq 1 --dir "$FR" src/a.ts
# --resume:从步骤账生成续轮派单
flow-dispatch T1 --tree 活树-独占 --db 禁用 --seq 1 --round ①写 --dir "$FR" --plan "$WS/specs/plan-big.md" src/a.ts > "$FR/01-dispatch.md" 2>/dev/null
expect_rc 0 "flow-step done 1(为续轮)" flow-step done "$FR" ①写 1 "写完"
expect_rc 0 "flow-dispatch --resume" flow-dispatch --resume "$FR/01-dispatch.md" --dir "$FR" --round ①写
printf '%s' "$LAST_OUT" | grep -q '①写-续' && ok "续轮派单头" || fail "续轮派单头缺"
printf '%s' "$LAST_OUT" | grep -q '已勾 1 / 共 4 · 下一步 2' && ok "续轮从第 2 步接手" || fail "续轮接手点错: $(printf '%s' "$LAST_OUT" | grep 已勾)"
expect_rc 2 "flow-dispatch --resume 无步骤账 FATAL" flow-dispatch --resume "$FR/01-dispatch.md" --dir "$FR" --round ④B
# flow-round open / close / state
git add -A >/dev/null 2>&1; git commit -qm pre-round >/dev/null 2>&1
expect_rc 1 "flow-round open 撞 fact-lint 新增 RED 先红、不打基线(F-13)" flow-round open "$FR" ①写
[ -f "$FR/.manifest-baseline-①写.txt" ] && fail "fact-lint 红了还打了基线" || ok "fact-lint 红时基线没打"
flow-fact-lint baseline >/dev/null 2>&1
expect_rc 0 "flow-round open ①写" flow-round open "$FR" ①写
printf '%s' "$LAST_OUT" | grep -q 'ROUND-OPEN OK' && ok "ROUND-OPEN OK" || fail "ROUND-OPEN: $(printf '%s' "$LAST_OUT" | tail -3)"
printf '%s' "$LAST_OUT" | grep -q 'flow-fact-lint verify' && ok "open 含 fact-lint verify(F-13)" || fail "open 缺 fact-lint"
[ -f "$FR/.manifest-baseline-①写.txt" ] && ok "open 打了基线(约定名)" || fail "基线未打"
grep -q '<!-- flow:gen-begin -->' "$FR/00-ORCH-STATE.md" && grep -q '| ①写 |' "$FR/00-ORCH-STATE.md" && ok "状态档事实段含 ①写 行" || fail "状态档事实段缺: $(head -12 "$FR/00-ORCH-STATE.md")"
expect_rc 1 "flow-round open 重开 RED(基线已存在)" flow-round open "$FR" ①写
# 模拟 agent 收工:改 a.ts、申报、冻结、回件、勾步骤
printf 'round\n' >> src/a.ts; printf 'src/a.ts\n' > "$FR/.declared-①写.txt"
expect_rc 0 "flow-freeze(约定名)" flow-freeze "$FR/.after-①写-hashes.txt"
printf '# ①写 回件 · 冒烟\n' > "$FR/01-write-handoff.md"
# glob 诱饵:同 01 前缀、mtime 更新、却是别的轮的回件 —— prefix+mtime 那套会取它(P3-1 状态档 14 行行行错就是这个机制)
printf '# ②A 回件 · 诱饵\n' > "$FR/01-review-external.md"
expect_rc 1 "flow-round close 步骤未全勾 RED" flow-round close "$FR" ①写 --task T1
printf '%s' "$LAST_OUT" | grep -q '步骤账未全勾' && ok "close 点名未全勾" || fail "close 未点名步骤账"
i=1; while [ $i -lt 4 ]; do i=$((i+1)); flow-step done "$FR" ①写 $i >/dev/null; done
expect_rc 0 "flow-round close ①写" flow-round close "$FR" ①写 --task T1
printf '%s' "$LAST_OUT" | grep -q 'ROUND-CLOSE OK' && ok "ROUND-CLOSE OK" || fail "ROUND-CLOSE: $(printf '%s' "$LAST_OUT" | tail -4)"
printf '%s' "$LAST_OUT" | grep -q 'BETWEEN OK' && ok "close 内含 between" || fail "close 未跑 between"
printf '%s' "$LAST_OUT" | grep -q '01-write-handoff.md' && ok "回件按首行「# <轮名> 回件」认领" || fail "回件认领错: $(printf '%s' "$LAST_OUT" | grep -A2 '回件')"
printf '%s' "$LAST_OUT" | grep -q '01-review-external.md' && fail "取到了同前缀更新的诱饵件" || ok "诱饵件没被取(不按件名前缀 + mtime 猜)"
grep -q '01-write-handoff.md' "$FR/00-ORCH-STATE.md" && ok "状态档回件列与 close 同源" || fail "状态档回件列错: $(grep '| ①写 |' "$FR/00-ORCH-STATE.md")"
grep -q '01-review-external.md' "$FR/00-ORCH-STATE.md" && fail "状态档回件列取到诱饵件" || ok "状态档回件列没取诱饵"
grep -q '01-dispatch.md' "$FR/00-ORCH-STATE.md" && ok "状态档派单列按「轮次 / 模型」行认领" || fail "状态档派单列错: $(grep '| ①写 |' "$FR/00-ORCH-STATE.md")"
grep -q '已勾 4 / 共 4' "$FR/00-ORCH-STATE.md" && ok "状态档步骤账列 4/4" || fail "状态档步骤账列错: $(grep '| ①写 |' "$FR/00-ORCH-STATE.md")"
printf '\n## 一 · 手写裁决\n保留我\n' >> "$FR/00-ORCH-STATE.md"
expect_rc 0 "flow-round state" flow-round state "$FR"
grep -q '保留我' "$FR/00-ORCH-STATE.md" && ok "state 只刷 gen 段,手写区不动" || fail "state 动了手写区"
[ "$(grep -c 'flow:gen-begin' "$FR/00-ORCH-STATE.md")" = 1 ] && ok "gen 段只有一份" || fail "gen 段重复"
# flow-close --wrap(收口机械段;编排方申报清单含根文档)
printf 'src/a.ts\nCLAUDE.md\n' > "$FR/.declared-close.txt"
expect_rc 0 "flow-close --wrap" flow-close --wrap "$FR" "$FR/.manifest-baseline-①写.txt" "$FR/.declared-close.txt" "$FR/.after-①写-hashes.txt" --task T1
printf '%s' "$LAST_OUT" | grep -q 'WRAP OK' && ok "WRAP OK" || fail "WRAP: $(printf '%s' "$LAST_OUT" | grep -E 'RED|FATAL|WRAP' | head -5)"
printf '%s' "$LAST_OUT" | grep -q 'FLOW-GATES' && ok "wrap 含门整跑" || fail "wrap 缺门"
printf '%s' "$LAST_OUT" | grep -q 'ROUND-STATE OK' && ok "wrap 刷状态档" || fail "wrap 未刷状态档"
printf '%s' "$LAST_OUT" | grep -q '轮数账没生成' && ok "wrap:本目录无 transcripts 只 WARN 不红" || fail "wrap 对无轮数账的处置错"
# 接收位摘录截在字边界(F-9)
printf '## T8 · 长行\n- 接收位:%s\n' "$(i=0; while [ $i -lt 60 ]; do i=$((i+1)); printf '汉字测试'; done)" > "$WS/specs/plan-long.md"
expect_rc 0 "flow-receipts 长汉字行" flow-receipts specs/plan-long.md T8
printf '%s' "$LAST_OUT" > "$T/rcpt.txt"
python3 -c "import sys; open(sys.argv[1],'rb').read().decode('utf-8')" "$T/rcpt.txt" 2>/dev/null && ok "摘录截断后仍是合法 UTF-8(F-9)" || fail "摘录截出非法 UTF-8"
rm -f "$WS/specs/plan-big.md" "$WS/specs/plan-long.md"

# ── 17. 0.7.0:F-24 续轮转义 / [done] 不印 / --db 收工段 / ledger --body-file / trace --mark-done / rulebook retire / config 判死 / usage 全窗 + 中断税 ──
cd "$WS"
# F-24:未加引号的 heredoc 里 \\` 留下活反引号,把 flow-manifest verify / git status / ls 真跑了、输出嵌进派单
flow-step init "$FR" ④B "装载" "主活" >/dev/null 2>&1
expect_rc 0 "flow-dispatch --resume(F-24)" flow-dispatch --resume "$FR/01-dispatch.md" --dir "$FR" --round ④B
printf '%s' "$LAST_OUT" | grep -qF '`flow-step done '"$FR"' ④B <N> "<一句>"`' && ok "续轮派单反引号是字面量" || fail "续轮派单反引号仍活着: $(printf '%s' "$LAST_OUT" | grep -n 'flow-step done' | head -2)"
printf '%s' "$LAST_OUT" | grep -qE 'No such file|On branch|申报清单不存在' && fail "续轮派单嵌进了命令输出(F-24)" || ok "续轮派单零命令输出"
# [done] REQ 行不印;--db 禁用 的收工段不给门整跑,独占的给
printf '## T10 · 有 done 的节\n- REQ-T10-01 [done] 老判据\n- REQ-T10-02 [open] 新判据\n## T11 · 尾\n' > "$WS/specs/plan-done.md"
expect_rc 0 "flow-dispatch ②A --db 禁用(plan 含 done)" flow-dispatch T10 --tree 快照 --db 禁用 --seq 1 --round ②A --dir "$FR" --plan "$WS/specs/plan-done.md" src/a.ts
printf '%s' "$LAST_OUT" | grep -q '^L[0-9]*: - REQ-T10-02 \[open\]' && ok "open REQ 行印出" || fail "open REQ 行缺"
printf '%s' "$LAST_OUT" | grep -q 'REQ-T10-01 \[done\]' && fail "[done] REQ 行仍印" || ok "[done] REQ 行不印"
printf '%s' "$LAST_OUT" | grep -q '\[done\] 1 条不印' && ok "REQ 段头报 done 条数" || fail "REQ 段头未报 done 条数"
printf '%s' "$LAST_OUT" | grep -q '门整跑不归你' && ok "--db 禁用:收工段不给 flow-gates(F-22)" || fail "--db 禁用 收工段错"
printf '%s' "$LAST_OUT" | grep -q 'flow-gates --reset >' && fail "--db 禁用 仍印 flow-gates --reset(F-22)" || ok "--db 禁用 零 flow-gates 命令"
grep -q 'flow-gates' "$FR/.steps-②A.md" && fail "②A(禁用)步骤账含门整跑" || ok "②A 步骤账无门整跑"
expect_rc 0 "flow-dispatch ③改 --db 独占" flow-dispatch T10 --tree 活树-独占 --db 独占 --seq 1 --round ③改 --dir "$FR" --plan "$WS/specs/plan-done.md" src/a.ts
printf '%s' "$LAST_OUT" | grep -q "flow-gates --reset > $FR/.evidence/③改-gates.txt" && ok "--db 独占:收工段连实参给门整跑" || fail "--db 独占 收工段缺门"
grep -q '+ flow-gates --reset' "$FR/.steps-③改.md" && ok "③改 步骤账含门整跑" || fail "③改 步骤账缺门"
printf '%s' "$LAST_OUT" | grep -q 'flow-micro <patch>... --face' && ok "待填段:微改通道走换量法(行数由 patch 量)" || fail "待填段微改通道文案未更新: $(printf '%s' "$LAST_OUT" | grep -c 改动估计)"
printf '%s' "$LAST_OUT" | grep -q '改动估计 N 行' && fail "待填段还留着 0.7.0 的自报估计" || ok "待填段不再要自报估计"
printf '%s' "$LAST_OUT" | grep -q '没附 patch 的条目一律不算微改' && ok "待填段写明没 patch 就落回 ③改二" || fail "待填段缺 patch 门槛"
rm -f "$WS/specs/plan-done.md" "$FR/.steps-③改.md" "$FR/.steps-④B.md" "$FR/.face-③改.txt" "$FR/.face-④B.txt"
# flow-ledger add --body-file:多行正文一次落,整块带 > 前缀也认,反引号与 $() 逐字
printf '> #7 首行正文\n>   第二行\n>   第三行 带 `反引号` 与 $(不展开)\n' > "$T/body7.md"
expect_rc 0 "flow-ledger add --body-file(多行、带 > 前缀)" flow-ledger add --owner T7 --due T7 --touches src/b.ts --title 多行正文 --mark '#7' --body-file "$T/body7.md"
grep -q '^> #7 首行正文$' "$WS/specs/debts.md" && grep -q '^>   第三行 带 `反引号` 与 \$(不展开)$' "$WS/specs/debts.md" && ok "多行正文逐字落盘、前缀归一" || fail "多行正文错: $(grep -A3 'mark:#7' "$WS/specs/debts.md")"
printf '%s' "$LAST_OUT" | grep -q '正文 3 行' && ok "add 报正文行数" || fail "add 未报行数: $(printf '%s' "$LAST_OUT" | head -1)"
expect_rc 0 "flow-ledger add --body-file -(stdin)" sh -c "printf 'stdin 正文\n' | flow-ledger add --owner T7 --due T7 --touches src/b.ts --title stdin正文 --mark '#8' --body-file -"
grep -q '^> #8 stdin 正文$' "$WS/specs/debts.md" && ok "stdin 正文落盘" || fail "stdin 正文缺"
expect_rc 2 "flow-ledger add --body 与 --body-file 互斥" flow-ledger add --owner T7 --due T7 --touches src/b.ts --title x --body y --body-file "$T/body7.md"
# flow-trace --mark-done:open 且有测试的翻 done,再跑翻 0
expect_rc 0 "flow-trace --mark-done" flow-trace specs/plan.md T5 --mark-done
printf '%s' "$LAST_OUT" | grep -q '^mark-done: REQ-T5-01 L3 \[open\] → \[done\]' && ok "翻了 REQ-T5-01(带行号)" || fail "mark-done 输出错: $(printf '%s' "$LAST_OUT" | grep mark-done)"
grep -q '^- REQ-T5-01 \[done\] WHEN a THEN b$' "$WS/specs/plan.md" && ok "plan 里 [open] → [done],其余字不动" || fail "plan 未翻或翻坏: $(grep 'REQ-T5-01' "$WS/specs/plan.md")"
expect_rc 0 "flow-trace --mark-done 幂等" flow-trace specs/plan.md T5 --mark-done
printf '%s' "$LAST_OUT" | grep -q '翻了 0 条' && ok "第二次翻 0 条" || fail "幂等错"
expect_rc 2 "flow-trace 未知参数 FATAL" flow-trace specs/plan.md T5 --bogus
# flow-rulebook:逐字搬进归档件、原文件删行;标题 / 越界 FATAL
[ -f "$WS/.claude/flow-local.md" ] || printf '# flow-local\n' > "$WS/.claude/flow-local.md"
printf '\n## 冒烟节\n- 冒烟规矩一 带 `反引号` 与 $(不展开)\n' >> "$WS/.claude/flow-local.md"
n0=$(wc -l < "$WS/.claude/flow-local.md" | tr -d ' ')
hl=$(grep -n '^## 冒烟节' "$WS/.claude/flow-local.md" | cut -d: -f1)
expect_rc 0 "flow-rulebook show" flow-rulebook show
printf '%s' "$LAST_OUT" | grep -q "^ *$((hl+1))  - 冒烟规矩一" && ok "show 带行号" || fail "show 行号错"
expect_rc 0 "flow-rulebook retire" flow-rulebook retire "$((hl+1))" --section "§Z · 冒烟批" --reason "做成了脚本"
[ "$(wc -l < "$WS/.claude/flow-local.md" | tr -d ' ')" = "$((n0-1))" ] && ok "规则书少一行" || fail "规则书行数未降"
grep -q '冒烟规矩一' "$WS/.claude/flow-local.md" && fail "原行没删" || ok "原行已删"
grep -q '^## §Z · 冒烟批 · 退役(' "$WS/.claude/flow-local-archive.md" && grep -q '^- 冒烟规矩一 带 `反引号` 与 \$(不展开)$' "$WS/.claude/flow-local-archive.md" && grep -q '^退役理由:做成了脚本$' "$WS/.claude/flow-local-archive.md" && ok "归档件:新节 + 逐字 + 理由" || fail "归档件错: $(tail -8 "$WS/.claude/flow-local-archive.md")"
grep -q '^\*\*退役件(原 `flow-local.md` 第 [0-9][0-9]* 行,逐字)\*\*:$' "$WS/.claude/flow-local-archive.md" && ok "归档件的文件名进反引号(仓侧纯文本指针棘轮)" || fail "归档件文件名仍是裸的: $(grep 退役件 "$WS/.claude/flow-local-archive.md" | head -2)"
expect_rc 2 "flow-rulebook retire 标题行 FATAL" flow-rulebook retire "$hl" --section x --reason y
expect_rc 2 "flow-rulebook retire 越界 FATAL" flow-rulebook retire 9999 --section x --reason y
expect_rc 2 "flow-rulebook retire 缺 --reason FATAL" flow-rulebook retire "$hl" --section x
# flow-config --check 判死 FLOW_FIX_BY_WRITER=1(宿主无 SendMessage)
flow-config --check >/dev/null 2>&1; base_rc=$?
printf 'FLOW_FIX_BY_WRITER=1\n' >> "$WS/.claude/flow.config.sh"
expect_rc 1 "flow-config --check 判死 FLOW_FIX_BY_WRITER=1" flow-config --check
printf '%s' "$LAST_OUT" | grep -q 'FLOW_FIX_BY_WRITER=1:宿主无 SendMessage' && ok "点名 SendMessage 通路" || fail "未点名 SendMessage"
printf 'FLOW_FIX_BY_WRITER=0\n' >> "$WS/.claude/flow.config.sh"
expect_rc "$base_rc" "flow-config --check 设 0 后回到原读数" flow-config --check
# flow-usage 0.7.0:窗从开工序起到收口末;生成侧断流记卡顿;中断税;固定开销三段自动;--write 保留手填段
FL2="$WS/.flow/p2"; mkdir -p "$FL2"
TR2="$T/transcripts/-ws-enc/sid2"; mkdir -p "$TR2/subagents"
python3 - "$TR2" "$FL2" <<'PY'
import json, sys, os
tr, fl = sys.argv[1:3]
def asst(mid, ts, blocks, out=10):
    return json.dumps(dict(type='assistant', timestamp=ts, message=dict(id=mid, model='claude-test', usage=dict(input_tokens=5, cache_creation_input_tokens=100, cache_read_input_tokens=1000, output_tokens=out), content=blocks)), ensure_ascii=False)
def user(ts, text):
    return json.dumps(dict(type='user', timestamp=ts, message=dict(role='user', content=text)), ensure_ascii=False)
def result(ts, tid, text='ok'):
    return json.dumps(dict(type='user', timestamp=ts, message=dict(role='user', content=[dict(type='tool_result', tool_use_id=tid, content=text)])))
def bash(tid, cmd): return dict(type='tool_use', id=tid, name='Bash', input={'command': cmd})
D = '2026-09-05T'
with open(os.path.join(tr, 'subagents', 'agent-s1.jsonl'), 'w') as f:      # ③改:改树后 600 s 无输出,被 watchdog 中断
    f.write(user(D + '01:00:00.000Z', f'你是 p2 的 ③改 agent。派单:{fl}/03-dispatch.md') + '\n')
    f.write(asst('s1m1', D + '01:00:10.000Z', [bash('s1t1', 'cat src/a.ts')]) + '\n')
    f.write(result(D + '01:00:12.000Z', 's1t1') + '\n')
    f.write(asst('s1m2', D + '01:00:20.000Z', [bash('s1t2', "python3 - <<'PY'\nprint(1)\nPY")]) + '\n')
    f.write(result(D + '01:00:25.000Z', 's1t2') + '\n')
    f.write(user(D + '01:10:25.000Z', '[Request interrupted by user]') + '\n')
with open(os.path.join(tr, 'subagents', 'agent-s2.jsonl'), 'w') as f:      # ③改续:读 45 s 后第一个非读调用
    f.write(user(D + '01:12:45.000Z', f'你是 p2 的 ③改续 agent。派单:{fl}/03c-dispatch.md') + '\n')
    f.write(asst('s2m1', D + '01:13:00.000Z', [bash('s2t1', f'cat {fl}/03c-dispatch.md')]) + '\n')
    f.write(result(D + '01:13:01.000Z', 's2t1') + '\n')
    f.write(asst('s2m2', D + '01:13:45.000Z', [bash('s2t2', f'flow-step done {fl} ③改 2 "接上"')]) + '\n')
    f.write(result(D + '01:13:46.000Z', 's2t2') + '\n')
    f.write(asst('s2m3', D + '01:20:00.000Z', [dict(type='text', text='done')]) + '\n')
with open(os.path.join(os.path.dirname(tr), 'sid2.jsonl'), 'w') as f:      # 编排方:开工序在首次提到目录之前;收口在最后一次提到目录之后
    f.write(asst('o1', D + '00:40:00.000Z', [bash('o1t', 'flow-freshness')]) + '\n')
    f.write(result(D + '00:40:01.000Z', 'o1t') + '\n')
    f.write(asst('o2', D + '00:50:00.000Z', [bash('o2t', f'cat {fl}/00-ORCH-STATE.md')]) + '\n')
    f.write(result(D + '00:50:01.000Z', 'o2t') + '\n')
    f.write(asst('o3', D + '00:55:00.000Z', [dict(type='tool_use', id='o3t', name='Agent', input={'prompt': f'你是 p2 的 ③改 agent。派单:{fl}/03-dispatch.md'})]) + '\n')
    f.write(result(D + '00:55:01.000Z', 'o3t') + '\n')
    f.write(asst('o4', D + '01:12:00.000Z', [bash('o4t', f'flow-dispatch --resume {fl}/03-dispatch.md --dir {fl} --round ③改')]) + '\n')
    f.write(result(D + '01:12:01.000Z', 'o4t') + '\n')
    f.write(asst('o5', D + '01:12:30.000Z', [dict(type='tool_use', id='o5t', name='Agent', input={'prompt': f'你是 p2 的 ③改续 agent。派单:{fl}/03c-dispatch.md'})]) + '\n')
    f.write(result(D + '01:12:31.000Z', 'o5t') + '\n')
    f.write(asst('o6', D + '01:25:00.000Z', [bash('o6t', f'flow-round close {fl} ③改续')]) + '\n')
    f.write(result(D + '01:25:01.000Z', 'o6t') + '\n')
    f.write(asst('o7', D + '01:26:00.000Z', [bash('o7t', 'git commit -F -')]) + '\n')
    f.write(result(D + '01:26:01.000Z', 'o7t') + '\n')
    f.write(asst('o8', D + '01:27:00.000Z', [bash('o8t', 'flow-close --ship abc --subject x')]) + '\n')
    f.write(result(D + '01:27:01.000Z', 'o8t') + '\n')
    f.write(asst('o9', D + '01:50:00.000Z', [bash('o9t', 'echo 与本批无关,间隔 23 min')]) + '\n')
    f.write(result(D + '01:50:01.000Z', 'o9t') + '\n')
PY
expect_rc 0 "flow-usage(0.7.0 全窗)" flow-usage "$FL2"
printf '%s' "$LAST_OUT" | grep -q '^| 编排方 | .* 8 轮 .*开工序起 → 收口末' && ok "窗从开工标记起到收口标记止(8 轮;23 min 后那轮在窗外)" || fail "编排方窗错: $(printf '%s' "$LAST_OUT" | grep '^| 编排方')"
printf '%s' "$LAST_OUT" | grep -q '^| 开工清账 + 派单装配 | 14m |' && ok "开工 14m 自动出(区间 = 上一事件末 → 本请求末,含 1 s 的工具结果)" || fail "开工行错: $(printf '%s' "$LAST_OUT" | grep '开工清账')"
printf '%s' "$LAST_OUT" | grep -q '^| 收口 | 1m |' && ok "收口 1m 自动出" || fail "收口行错: $(printf '%s' "$LAST_OUT" | grep '^| 收口')"
printf '%s' "$LAST_OUT" | grep -q '独占关键路径 17m(开工 14m · 轮间 0m · 收口 1m)' && ok "独占关键路径 = 三段之和" || fail "独占行错: $(printf '%s' "$LAST_OUT" | grep '独占关键路径' | head -1)"
printf '%s' "$LAST_OUT" | grep -q 'WARN 卡顿 ③改:.*生成侧断流:工具结果之后无输出,以中断收场 600s' && ok "生成侧断流记卡顿" || fail "生成侧断流未记: $(printf '%s' "$LAST_OUT" | grep 卡顿)"
printf '%s' "$LAST_OUT" | grep -q '^| ③改 | 10m | 0m | 0m | 10m | 1 |' && ok "③改 墙钟行:空等 10m · 卡顿 1" || fail "③改 墙钟行错: $(printf '%s' "$LAST_OUT" | grep -E '^\| ③改 \| 10m')"
printf '%s' "$LAST_OUT" | grep -q '中断税 ③改→③改续:卡顿 10m00s + 编排方接手 2m20s + 续轮装载 1m00s = 13m20s' && ok "中断税 = 卡顿 + 接手 + 装载" || fail "中断税错: $(printf '%s' "$LAST_OUT" | grep 中断)"
expect_rc 0 "flow-usage --write(带标记)" flow-usage "$FL2" --write
grep -q '<!-- flow:gen-begin -->' "$FL2/.usage.md" && grep -q '^## 手填' "$FL2/.usage.md" && ok ".usage.md 生成段带标记 + 手填段" || fail ".usage.md 缺标记或手填段"
printf '| 本批退役规矩数 | 1 | 冒烟 |\n' >> "$FL2/.usage.md"
expect_rc 0 "flow-usage --write 重跑" flow-usage "$FL2" --write
grep -q '^| 本批退役规矩数 | 1 | 冒烟 |$' "$FL2/.usage.md" && [ "$(grep -c 'flow:gen-begin' "$FL2/.usage.md")" = 1 ] && ok "重跑保留手填行、生成段只有一份" || fail "重跑丢了手填行或标记重复"

# ── 20. flow-micro(微改通道换量法:行数由 patch 量,不由审方估)──
cd "$WS"
git checkout -- . >/dev/null 2>&1 || true
printf 'export const x = 1;\n' > src/x.test.ts
git add -A >/dev/null 2>&1; git commit -qm micro-base >/dev/null 2>&1
MC="$T/micro"; mkdir -p "$MC"
printf '# 写权限面\nsrc\n' > "$FL/.face-③改.txt"
mkpatch() {   # mkpatch <出件> <文件> <追加内容>;出完就还原,树保持干净
  printf '%s\n' "$3" >> "$2"; git -c core.quotepath=false diff > "$1"; git checkout -- "$2"
}
mkpatch "$MC/ok.patch"      src/x.test.ts 'export const y = 2;'
mkpatch "$MC/prod.patch"    src/a.ts      'export const prod = 3;'
mkpatch "$MC/comment.patch" src/b.ts      '// 只加一行注释'
mkpatch "$MC/out.patch"     CLAUDE.md     '面外一行'
i=0; while [ $i -lt 20 ]; do i=$((i+1)); printf 'export const n%d = %d;\n' "$i" "$i" >> src/x.test.ts; done
git -c core.quotepath=false diff > "$MC/big.patch"; git checkout -- src/x.test.ts
printf 'diff --git a/src/nope.ts b/src/nope.ts\n--- a/src/nope.ts\n+++ b/src/nope.ts\n@@ -1 +1 @@\n-x\n+y\n' > "$MC/bad.patch"

expect_rc 0 "flow-micro 测试文件 · 面内 · 1 行 ⟹ MICRO OK" flow-micro "$MC/ok.patch" --face "$FL/.face-③改.txt"
printf '%s' "$LAST_OUT" | grep -q '^MICRO OK: 新增 1 行 / 上限 16' && ok "行数从 numstat 来,不从自陈来" || fail "MICRO OK 读数错: $(printf '%s' "$LAST_OUT" | tail -1)"
expect_rc 0 "flow-micro .ts 里只加注释行 ⟹ 非生产(只按路径判会误杀真注释条)" flow-micro "$MC/comment.patch" --face "$FL/.face-③改.txt"
printf '%s' "$LAST_OUT" | grep -q 'src/b.ts.*注释 · 面内' && ok "改动行核性质:零非注释行 ⟹ 注释" || fail "性质判错: $(printf '%s' "$LAST_OUT" | grep 'src/b.ts')"
expect_rc 1 "flow-micro 生产文件 ⟹ RED(整批走 ③改二)" flow-micro "$MC/prod.patch" --face "$FL/.face-③改.txt"
printf '%s' "$LAST_OUT" | grep -q '生产 · 面内(patch 里有 1 条非注释改动行)' && ok "点名非注释行数" || fail "生产判据未点名: $(printf '%s' "$LAST_OUT" | grep 'src/a.ts')"
printf '%s' "$LAST_OUT" | grep -q '整批起 ③改二' && ok "RED 说清是「通道不收」不是「改错了」" || fail "RED 措辞缺去向"
expect_rc 1 "flow-micro 面外 ⟹ RED(注释也不行)" flow-micro "$MC/out.patch" --face "$FL/.face-③改.txt"
printf '%s' "$LAST_OUT" | grep -q 'CLAUDE.md.*注释 · 面外' && ok "面外与性质分开判" || fail "面外未点名: $(printf '%s' "$LAST_OUT" | grep CLAUDE)"
expect_rc 1 "flow-micro 合计新增 20 > 上限 16 ⟹ RED" flow-micro "$MC/big.patch" --face "$FL/.face-③改.txt"
printf '%s' "$LAST_OUT" | grep -q '合计新增 20 行 > 上限 16' && ok "判的是合计不是单条" || fail "合计判错: $(printf '%s' "$LAST_OUT" | grep 合计)"
expect_rc 2 "flow-micro patch 落不下 ⟹ FATAL(不许猜着改)" flow-micro "$MC/bad.patch" --face "$FL/.face-③改.txt"
expect_rc 2 "flow-micro --apply 不给 --freeze ⟹ FATAL" flow-micro "$MC/ok.patch" --face "$FL/.face-③改.txt" --apply
expect_rc 2 "flow-micro 不给 --face ⟹ FATAL" flow-micro "$MC/ok.patch"
# --apply:先对冻结件核树(patch 在哪棵树上量的就落在哪棵树上)
printf 'dirty\n' >> src/b.ts
expect_rc 0 "flow-freeze(微改前的交付态)" flow-freeze "$FL/.after-micro-hashes.txt"
printf 'tamper\n' >> src/b.ts
expect_rc 1 "flow-micro --apply 树已不是量它的那棵 ⟹ RED,不落笔" flow-micro "$MC/ok.patch" --face "$FL/.face-③改.txt" --freeze "$FL/.after-micro-hashes.txt" --apply
grep -q 'export const y = 2;' src/x.test.ts && fail "冻结不符却落了笔" || ok "冻结不符时零落笔"
git checkout -- src/b.ts; printf 'dirty\n' >> src/b.ts
expect_rc 0 "flow-micro --apply 落笔" flow-micro "$MC/ok.patch" --face "$FL/.face-③改.txt" --freeze "$FL/.after-micro-hashes.txt" --apply
grep -q 'export const y = 2;' src/x.test.ts && ok "patch 真落到了树上" || fail "patch 没落"
git checkout -- src/x.test.ts src/b.ts
# flow-dispatch --dir 落写权限面清单(与 flow-micro --face 两侧同源)
expect_rc 0 "flow-dispatch --dir 落 .face-<轮名>.txt" flow-dispatch T1 --tree 活树-独占 --db 独占 --seq 1 --round ③改 --dir "$FR" src/a.ts src/b.ts
grep -qx 'src/a.ts' "$FR/.face-③改.txt" && grep -qx 'src/b.ts' "$FR/.face-③改.txt" && ok "面清单 = 派单触面,一行一条" || fail "面清单错: $(cat "$FR/.face-③改.txt")"

# ── 21. flow-doc-budget 目录合计按轮数归一 ──
DB7="$T/dirnorm"; mkdir -p "$DB7"
{ echo "# 冒烟件"; echo "budget-ok: 冒烟造的长件,单件线不是本例要判的"; awk 'BEGIN{for(i=1;i<=4100;i++) print "行 " i}'; } > "$DB7/01-dispatch.md"
expect_rc 0 "flow-doc-budget 六轮以内仍按原线" flow-doc-budget "$DB7"
printf '%s' "$LAST_OUT" | grep -q 'WARN 目录热路径合计' && ok "0 轮 → 线仍是 4000,合计超线照 WARN" || fail "未按原线判: $(printf '%s' "$LAST_OUT" | tail -2)"
i=0; while [ $i -lt 7 ]; do i=$((i+1)); : > "$DB7/.manifest-baseline-r$i.txt"; done
expect_rc 0 "flow-doc-budget 七轮按轮数归一" flow-doc-budget "$DB7"
printf '%s' "$LAST_OUT" | grep -q 'WARN 目录热路径合计' && fail "七轮仍按 4000 判(线在数轮数不在数膨胀)" || ok "七轮归一后不再 WARN"
printf '%s' "$LAST_OUT" | grep -q '轮 7 · 合计线 4666' && ok "合计线印出归一读数" || fail "归一读数错: $(printf '%s' "$LAST_OUT" | grep '^—— ')"

# ── 22. flow-close --ship 的队列落笔(0.8.1;三支都在 push 之前判完 ⟹ 不需要 gh、不需要网络)──
# 病根:clear-map-debt 只写工作树,而下一步直接 push ⟹ 中间零提交,队列的清空**按定义**进不了本批自己的 PR。
# 冒烟仓没有 remote ⟹ push 失败 → is-ancestor 失败 → sred=1 → 在 gh 被调用之前 `SHIP RED: 未开 PR` 退出,所以三支都 RC=1。
cd "$WS"
printf '| 标记 | 判定 | 证据 | 落点 |\n|---|---|---|---|\n| #99 | 不动 | 冒烟:队列里没有这个标记 | — |\n' > "$FL/ship-none.md"
# 支 a:队列件不在跟踪集(.git/info/exclude 挡着,git add -A 从没收过它)
git ls-files --error-unmatch -- "$WS/.claude/map-debt.md" >/dev/null 2>&1 && fail "支a 夹具错:队列件本该未跟踪" || ok "支a 夹具:队列件未跟踪"
SH0=$(git rev-parse --short HEAD)
expect_rc 1 "flow-close --ship 支a(队列件未跟踪)" flow-close --ship "$SH0" --subject 冒烟 --verdicts "$FL/ship-none.md"
printf '%s' "$LAST_OUT" | grep -q 'info 队列件不在本仓的跟踪集里' && ok "未跟踪 ⟹ info,不落笔" || fail "支a 读数错: $(printf '%s' "$LAST_OUT" | grep -A2 '队列落笔')"
printf '%s' "$LAST_OUT" | grep -q 'SHIP RED: 未开 PR' && ok "无 remote ⟹ push 后短路,gh 没被调用" || fail "支a 没在 push 后短路"
# 支 b:队列件已跟踪,但本次一条都没勾 ⟹ 与 HEAD 逐字节相同,不许落空笔
git add -f .claude/map-debt.md >/dev/null 2>&1
git commit -q -m ship-track-queue -- .claude/map-debt.md >/dev/null 2>&1
TQ=$(git rev-parse --short HEAD)
git ls-files --error-unmatch -- "$WS/.claude/map-debt.md" >/dev/null 2>&1 && ok "支b 夹具:队列件已进跟踪集" || fail "支b 夹具:队列件没跟上"
expect_rc 1 "flow-close --ship 支b(队列与 HEAD 相同)" flow-close --ship "$TQ" --subject 冒烟 --verdicts "$FL/ship-none.md"
printf '%s' "$LAST_OUT" | grep -q 'info 队列件与 HEAD 逐字节相同' && ok "一条都没勾 ⟹ info,不落空笔" || fail "支b 读数错: $(printf '%s' "$LAST_OUT" | grep -A2 'map-debt 队列落笔')"
[ "$(git rev-parse --short HEAD)" = "$TQ" ] && ok "支b 零新增 commit" || fail "支b 落了空笔"
# 支 c:真勾掉一条 ⟹ 按 pathspec 落一笔,且不 amend 收口 commit
printf 'ship\n' >> src/a.ts
git commit -q -m ship-touch-a -- src/a.ts >/dev/null 2>&1
SC=$(git rev-parse --short HEAD)
SM=$(LC_ALL=C sed -n "s/^- \[ \] [^|]*| $SC | 触欠账\(.*\) 的触面 |.*/\1/p" "$WS/.claude/map-debt.md" | head -1)
[ -n "$SM" ] && ok "支c 夹具:post-commit 给 $SC 记了未勾行(标记 $SM)" || fail "支c 夹具:队列里没有 $SC 的未勾行"
printf '| 标记 | 判定 | 证据 | 落点 |\n|---|---|---|---|\n| %s | 不动 | 冒烟 | — |\n' "$SM" > "$FL/ship-verdicts.md"
printf 'dirty\n' >> src/b.ts     # 工作树里的别的脏东西:落笔只许按 pathspec 收队列件
expect_rc 1 "flow-close --ship 支c(真勾掉一条)" flow-close --ship "$SC" --subject 冒烟 --verdicts "$FL/ship-verdicts.md"
printf '%s' "$LAST_OUT" | grep -q '队列落笔 ' && ok "勾掉后真落一笔" || fail "支c 没落笔: $(printf '%s' "$LAST_OUT" | grep -A3 'map-debt 队列落笔')"
[ "$(git rev-parse --short 'HEAD~1')" = "$SC" ] && ok "落笔是 $SC 之上的新 commit(没 amend 收口 commit)" || fail "落笔 amend 了收口 commit"
[ "$(git -c core.quotepath=false diff-tree --no-commit-id --name-only -r HEAD)" = ".claude/map-debt.md" ] && ok "落笔只收队列件(pathspec 没扫脏工作树)" || fail "落笔扫进了别的件: $(git diff-tree --no-commit-id --name-only -r HEAD | tr '\n' ' ')"
git diff --quiet -- src/b.ts && fail "落笔把 src/b.ts 的脏改动也带走了" || ok "src/b.ts 的脏改动还留在工作树里"
# 非空转对照:同一条命令重跑,读数必须从「队列落笔」退回「逐字节相同」,且零新增 commit
HC=$(git rev-parse --short HEAD)
expect_rc 1 "flow-close --ship 支c 重跑(非空转对照)" flow-close --ship "$SC" --subject 冒烟 --verdicts "$FL/ship-verdicts.md"
printf '%s' "$LAST_OUT" | grep -q 'info 队列件与 HEAD 逐字节相同' && ok "重跑退回「逐字节相同」—— 落笔那支不是恒真分支" || fail "重跑读数没变(落笔支恒真)"
[ "$(git rev-parse --short HEAD)" = "$HC" ] && ok "重跑零新增 commit" || fail "重跑又落了一笔"
git checkout -- src/b.ts

[ "$red" = 0 ] && { echo "SMOKE OK"; exit 0; } || { echo "SMOKE RED"; exit 1; }
