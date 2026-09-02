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
printf 'src/b.ts\n' > "$FL/.declared-short.txt"
expect_rc 1 "flow-manifest verify 非空转 RED" flow-manifest verify "$FL/.manifest-baseline.txt" "$FL/.declared-short.txt"
printf '%s' "$LAST_OUT" | grep -q 'RED 漏申报: specs/plan.md' && ok "点名漏申报的 specs 文件" || fail "未点名 specs/plan.md"
expect_rc 0 "flow-freeze" flow-freeze "$FL/.after-hashes.txt"
grep -q 'specs/plan.md' "$FL/.after-hashes.txt" && ok "冻结清单含规格轴" || fail "冻结清单缺规格轴"

# ── 4. 派单块 / 预算 / 收工 ──
printf '# h\n' > "$FL/01-write-handoff.md"
expect_rc 0 "flow-dispatch" flow-dispatch T1 --tree 快照 --db 禁用 --seq 1 src/a.ts
printf '%s' "$LAST_OUT" | grep -q '#1' && ok "派单块含欠账 #1" || fail "派单块缺欠账"
printf '%s' "$LAST_OUT" | grep -q '边写边落' && ok "派单块含边写边落" || fail "派单块缺边写边落"
expect_rc 2 "flow-dispatch 绝对触面 FATAL" flow-dispatch T1 --tree 快照 --db 禁用 --seq 1 /abs
expect_rc 0 "flow-doc-budget" flow-doc-budget "$FL"
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
printf 'e\n' >> src/a.ts; git add -A; git commit -qm touch-a
C=$(git rev-parse --short HEAD)
[ -f "$WS/.claude/map-debt.md" ] && grep -q "$C" "$WS/.claude/map-debt.md" && ok "post-commit 记了队列" || fail "post-commit 未记队列"
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

[ "$red" = 0 ] && { echo "SMOKE OK"; exit 0; } || { echo "SMOKE RED"; exit 1; }
