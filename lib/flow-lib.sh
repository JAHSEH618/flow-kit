#!/bin/sh
# flow-lib.sh —— flow-kit 所有 bin/ 脚本共用的库(POSIX sh;被 source,不直接执行)。
# 职责只有四件:找并加载工作区配置 · 可移植的 sha256 · 统一的 die/warn · 欠账标记的模式。
# 用法(每个 bin 脚本头部):
#   . "$(cd "$(dirname "$0")/.." && pwd)/lib/flow-lib.sh"
#   flow_load_config            # 之后 FLOW_WS / FLOW_REPO_DIR / FLOW_LEDGER_PATH … 可用
# 环境覆盖(只给测试与特殊场合):FLOW_CONFIG=<配置文件绝对路径> 跳过向上查找。

flow_die()  { printf 'FATAL: %s\n' "$*" >&2; exit 2; }
flow_warn() { printf 'WARN: %s\n' "$*" >&2; }

# —— sha256:macOS 有 shasum,Linux 常只有 sha256sum;两者 `-c` 认同一种「hash  path」格式 ——
flow_sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"; else sha256sum "$@"; fi
}
flow_sha256_check() {   # 用法: flow_sha256_check <清单文件>   (stdout 逐行 `path: OK|FAILED`,RC 同工具)
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 -c "$1"; else sha256sum -c "$1"; fi
}

flow_tmpdir() { printf '%s' "${TMPDIR:-/tmp}"; }

# —— 找工作区:从 cwd(或 FLOW_START)向上找 .claude/flow.config.sh;找不到 = FATAL(不给默认值,默认值是静默错的来源)——
flow_find_ws() {
  d="${FLOW_START:-$(pwd)}"
  while :; do
    [ -f "$d/.claude/flow.config.sh" ] && { printf '%s' "$d"; return 0; }
    [ "$d" = "/" ] && return 1
    d=$(dirname "$d")
  done
}

# —— 加载配置并派生绝对路径;缺必填项当场 FATAL ——
flow_load_config() {
  if [ -n "${FLOW_CONFIG:-}" ]; then
    [ -f "$FLOW_CONFIG" ] || flow_die "FLOW_CONFIG 指向的文件不存在: $FLOW_CONFIG"
    FLOW_WS=$(cd "$(dirname "$FLOW_CONFIG")/.." && pwd)
    cfg="$FLOW_CONFIG"
  else
    FLOW_WS=$(flow_find_ws) || flow_die "从 $(pwd) 向上找不到 .claude/flow.config.sh —— 先跑 flow-init"
    cfg="$FLOW_WS/.claude/flow.config.sh"
  fi
  # 默认值(config 可覆盖);必填项不给默认
  FLOW_LEDGER="specs/debts.md"
  FLOW_ROOT_DOC="CLAUDE.md"
  FLOW_SPEC_DIRS="specs"
  FLOW_SPEC_UNTRACKED=0
  FLOW_FLOW_DIR=".flow"
  FLOW_MAIN_BRANCH="master"
  FLOW_DEV_BRANCH="dev"
  FLOW_MAP_DEBT=".claude/map-debt.md"
  FLOW_LOCAL_DOC=".claude/flow-local.md"
  FLOW_FACT_LINT_BASELINE=".claude/fact-lint-baseline.tsv"
  FLOW_FACT_LINT_ROOTS=""
  FLOW_FACT_LINT_EXCLUDE=""
  FLOW_GATE_SUMMARY_RE='Test Files|Tests '
  FLOW_INFRA_FAIL_RE='57P01|Connection terminated|does not exist in the current database'
  FLOW_DOC_BUDGET_FILE=400
  FLOW_DOC_BUDGET_DIR=4000
  FLOW_DOC_BUDGET_RULEBOOK=250
  FLOW_DEBT_CAP=8
  FLOW_DEBT_WARN=16
  FLOW_FIX_BY_WRITER=1
  FLOW_FOLD_MAX=6
  FLOW_MERGE_STRATEGY="--merge"
  # shellcheck disable=SC1090
  . "$cfg"
  [ -n "${FLOW_REPO:-}" ] || flow_die "flow.config.sh 缺 FLOW_REPO(仓路径,相对工作区;单仓写 .)"
  case "$FLOW_REPO" in
    /*) flow_die "FLOW_REPO 必须相对工作区,不许绝对路径: $FLOW_REPO" ;;
    .)  FLOW_REPO_DIR="$FLOW_WS" ;;
    *)  FLOW_REPO_DIR="$FLOW_WS/$FLOW_REPO" ;;
  esac
  [ -d "$FLOW_REPO_DIR/.git" ] || [ -f "$FLOW_REPO_DIR/.git" ] || flow_die "FLOW_REPO 不是 git 仓: $FLOW_REPO_DIR"
  FLOW_LEDGER_PATH="$FLOW_REPO_DIR/$FLOW_LEDGER"
  FLOW_ROOT_DOC_PATH="$FLOW_REPO_DIR/$FLOW_ROOT_DOC"
  FLOW_FLOW_DIR_PATH="$FLOW_WS/$FLOW_FLOW_DIR"
  FLOW_MAP_DEBT_PATH="$FLOW_WS/$FLOW_MAP_DEBT"
  FLOW_LOCAL_DOC_PATH="$FLOW_WS/$FLOW_LOCAL_DOC"
  FLOW_FACT_LINT_BASELINE_PATH="$FLOW_WS/$FLOW_FACT_LINT_BASELINE"
  export FLOW_WS FLOW_REPO FLOW_REPO_DIR FLOW_LEDGER FLOW_LEDGER_PATH FLOW_ROOT_DOC FLOW_ROOT_DOC_PATH \
         FLOW_SPEC_DIRS FLOW_SPEC_UNTRACKED FLOW_FLOW_DIR FLOW_FLOW_DIR_PATH FLOW_MAIN_BRANCH FLOW_DEV_BRANCH \
         FLOW_MAP_DEBT FLOW_MAP_DEBT_PATH FLOW_LOCAL_DOC FLOW_LOCAL_DOC_PATH \
         FLOW_FACT_LINT_BASELINE FLOW_FACT_LINT_BASELINE_PATH FLOW_FACT_LINT_ROOTS FLOW_FACT_LINT_EXCLUDE \
         FLOW_GATE_SUMMARY_RE FLOW_INFRA_FAIL_RE FLOW_DOC_BUDGET_FILE FLOW_DOC_BUDGET_DIR FLOW_DOC_BUDGET_RULEBOOK \
         FLOW_DEBT_CAP FLOW_DEBT_WARN FLOW_FIX_BY_WRITER FLOW_FOLD_MAX FLOW_MERGE_STRATEGY
}

# —— 门与哨兵:config 里以函数给出(sh 原生,免解析分隔符)。没定义就给空实现,调用方自判「零门」——
command -v flow_gates     >/dev/null 2>&1 || flow_gates()     { :; }   # 每行: name<TAB>command ;名 dbreset 保留给「重置库」
command -v flow_sentinels >/dev/null 2>&1 || flow_sentinels() { :; }   # 每行: 路径模式<TAB>该更新的文档段

# —— 欠账标记:圈码 ①–㊿(UTF-8 前两字节 E2 91 / E3 89 / E3 8A)与纯数字 #N 两种都认;调用方一律 LC_ALL=C grep -E ——
flow_mark_re() { printf '(\342\221.|\343\211.|\343\212.|#[0-9]+)'; }
flow_entry_re() { printf '^> %s' "$(flow_mark_re)"; }          # 账本条目行
flow_is_mark() {                                                # 用法: flow_is_mark <串> ;RC 0 = 是合法标记
  printf '%s' "$1" | LC_ALL=C grep -qE "^$(flow_mark_re)$"
}

# —— 机器头字段提取(一行一头:<!-- debt:N mark:.. status:.. owner:.. due:.. touches:a,b title:.. -->)——
flow_head_field() {   # 用法: flow_head_field <行> <字段名>
  case "$2" in
    title) printf '%s' "$1" | sed -n 's/.* title:\(.*\) -->/\1/p' ;;
    *)     printf '%s' "$1" | sed -n "s/.* $2:\([^ ]*\) .*/\1/p" ;;
  esac
}
flow_open_heads() {   # 账本里 status:open 的机器头行
  grep '^<!-- debt:' "$FLOW_LEDGER_PATH" | grep ' status:open '
}
