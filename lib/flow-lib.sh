#!/bin/sh
# flow-lib.sh —— flow-kit 所有 bin/ 脚本共用的库(POSIX sh;被 source,不直接执行)。
# 职责:找并加载工作区配置 · 可移植 sha256 · 统一 die/warn · 实改集 git 轴 · 标记与 REQ 模式 · 机器头字段(自指的数按 §J 三禁不写)。
# 用法(每个 bin 脚本头部):
#   . "$(cd "$(dirname "$0")/.." && pwd)/lib/flow-lib.sh"
#   flow_load_config            # 之后 FLOW_WS / FLOW_REPO_DIR / FLOW_LEDGER_PATH … 可用
# 环境覆盖(只给测试与特殊场合):FLOW_CONFIG=<配置文件绝对路径> 跳过向上查找。

# 让同胞命令在任何会话里都能按裸名调用(plugin 会话之外 bin 不在 PATH)
_flow_kit_dir=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)
if [ -n "$_flow_kit_dir" ] && [ -d "$_flow_kit_dir/bin" ]; then
  case ":$PATH:" in *":$_flow_kit_dir/bin:"*) ;; *) PATH="$_flow_kit_dir/bin:$PATH"; export PATH ;; esac
fi
# kit 自身根目录:模板路径由脚本自己算,不许任何 prompt 手打插件缓存路径(带版本号,升级即断)
FLOW_KIT_DIR="$_flow_kit_dir"; export FLOW_KIT_DIR

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
  FLOW_INDEX_DOC=""                     # 欠账索引块落点(仓库相对);空 = 跟 FLOW_ROOT_DOC。开放条目多时搬出常驻文件:
                                        # 实测 43 条索引 5.5 KB,住在根 CLAUDE.md 里就是每个会话每一轮都重付
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
  FLOW_INFRA_FAIL_GATES=""
  FLOW_DOC_BUDGET_FILE=400
  FLOW_DOC_BUDGET_BYTES=40000
  FLOW_DOC_BUDGET_SELF=40000            # 自写字节红线(总字节减去 flow:gen 标记段);回件 100% 自写,派单几乎全是生成段
  FLOW_DOC_BUDGET_DIR=4000
  FLOW_DOC_BUDGET_RULEBOOK=250
  FLOW_DEBT_CAP=8
  FLOW_DEBT_WARN=16
  FLOW_FIX_BY_WRITER=1
  FLOW_FOLD_MAX=6
  FLOW_REQ_CAP=8
  FLOW_TURN_CAP=120                     # 单会话请求数上限(flow-usage 只 WARN):携带 ∝ 轮数 × 上下文,上下文又随轮数长 ⟹ 二次;按会话判,续轮单算
  FLOW_DISPATCH_EXCERPT_BYTES=12000     # 派单里 plan 任务节选的字节封顶:超过只印 outline + REQ 行 + 节尾(本刀落位段),其余给「文件 + 行号」指针
                                        # 实测一节 42 KB 横跨三刀,八个 agent 各读一遍 ≈ 该批携带 10%;②③④ 一律不印正文
  FLOW_MICRO_FIX_LINES=3                # ④ 判必闭且改动估计 ≤ 此行数(且在③写权限面内)⟹ 编排方落笔 + 提出轴复验,不起 ③改二(微改通道)
  FLOW_STALL_SEC=300                    # flow-usage 卡顿判据:一次工具调用 ≥ 此秒数单列 WARN(harness 卡顿实测 600 s 整、两轴同刻放行)
  FLOW_RECEIPT_MODE="section"           # plan 体例:section = `## <任务号>` 小节;table = 任务是表行
  FLOW_ROLE_MODELS=""
  FLOW_TRANSCRIPTS_DIR="$HOME/.claude/projects"
  FLOW_MERGE_STRATEGY="--merge"
  # FLOW_KEEP_PLUGINS / FLOW_KEEP_MCP 故意不给默认:留哪些插件与 MCP 是项目的事实,缺了 flow-settings 会 FATAL 并列候选
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
  [ -n "$FLOW_INDEX_DOC" ] || FLOW_INDEX_DOC="$FLOW_ROOT_DOC"
  FLOW_INDEX_DOC_PATH="$FLOW_REPO_DIR/$FLOW_INDEX_DOC"
  FLOW_FLOW_DIR_PATH="$FLOW_WS/$FLOW_FLOW_DIR"
  FLOW_MAP_DEBT_PATH="$FLOW_WS/$FLOW_MAP_DEBT"
  FLOW_LOCAL_DOC_PATH="$FLOW_WS/$FLOW_LOCAL_DOC"
  FLOW_FACT_LINT_BASELINE_PATH="$FLOW_WS/$FLOW_FACT_LINT_BASELINE"
  export FLOW_WS FLOW_REPO FLOW_REPO_DIR FLOW_LEDGER FLOW_LEDGER_PATH FLOW_ROOT_DOC FLOW_ROOT_DOC_PATH \
         FLOW_SPEC_DIRS FLOW_SPEC_UNTRACKED FLOW_FLOW_DIR FLOW_FLOW_DIR_PATH FLOW_MAIN_BRANCH FLOW_DEV_BRANCH \
         FLOW_INDEX_DOC FLOW_INDEX_DOC_PATH FLOW_RECEIPT_MODE \
         FLOW_MAP_DEBT FLOW_MAP_DEBT_PATH FLOW_LOCAL_DOC FLOW_LOCAL_DOC_PATH \
         FLOW_FACT_LINT_BASELINE FLOW_FACT_LINT_BASELINE_PATH FLOW_FACT_LINT_ROOTS FLOW_FACT_LINT_EXCLUDE \
         FLOW_GATE_SUMMARY_RE FLOW_INFRA_FAIL_RE FLOW_INFRA_FAIL_GATES FLOW_DOC_BUDGET_FILE FLOW_DOC_BUDGET_BYTES FLOW_DOC_BUDGET_SELF FLOW_DOC_BUDGET_DIR FLOW_DOC_BUDGET_RULEBOOK \
         FLOW_DEBT_CAP FLOW_DEBT_WARN FLOW_FIX_BY_WRITER FLOW_FOLD_MAX FLOW_MERGE_STRATEGY FLOW_REQ_CAP FLOW_TURN_CAP FLOW_DISPATCH_EXCERPT_BYTES FLOW_MICRO_FIX_LINES FLOW_STALL_SEC FLOW_ROLE_MODELS FLOW_TRANSCRIPTS_DIR \
         FLOW_KEEP_PLUGINS FLOW_KEEP_MCP
}

# —— kit 自己的记账件(队列 / 基线 / 流程目录 / 门缓存)落在仓内(单仓布局)时,不算任何一轮的实改集 ——
flow_kit_owned_rel() {   # 打印仓库相对路径;目录带尾斜杠
  for p in "$FLOW_MAP_DEBT_PATH" "$FLOW_FACT_LINT_BASELINE_PATH" "$FLOW_FLOW_DIR_PATH/" "$FLOW_WS/.claude/flow-gates/"; do
    case "$p" in "$FLOW_REPO_DIR"/*) printf '%s\n' "${p#"$FLOW_REPO_DIR"/}" ;; esac
  done
}
flow_filter_kit_owned() {   # stdin 一行一路径 → 去掉 kit 自有件(精确匹配或目录前缀)
  pats=$(flow_kit_owned_rel)
  if [ -z "$pats" ]; then cat; return 0; fi
  # ⚠ 模式多行(单仓布局下必然多行)只能走 ENVIRON 递给 awk:BSD awk 对 `-v 变量=<含换行串>` 报「newline in string」
  #   RC=2 且一行不吐 ⟹ 三条命令的 git 轴恒空 ⟹ verify 恒绿(实测:申报 1 件、实改 15 件照 OK)。`-v` 还会对值做转义处理,ENVIRON 原样透传。
  FLOW_KIT_OWNED="$pats" awk 'BEGIN{n=split(ENVIRON["FLOW_KIT_OWNED"],a,"\n")} { keep=1; for(i=1;i<=n;i++){ p=a[i]; if(p=="") continue; if(substr(p,length(p),1)=="/"){ if(index($0,p)==1) keep=0 } else if($0==p) keep=0 } if(keep) print }'
}

# —— 实改集 git 轴:manifest verify / close 非空转 / freeze 三处共用这一条枚举,别再各自手拼 ——
#   -c core.quotepath=false:不带它 git 把非 ASCII 路径转成八进制转义并加引号(`"\344\270\255.md"`)
#     ⟹ 申报行永远对不上(verify 假红)、`[ -f ]` 永远为假(freeze 静默漏出清单)。
#   -uall:不带它未跟踪**目录**折成一行目录名,藏在里面的未申报文件 verify 照绿。
#   剥状态位按固定 3 字符前缀 + 显式处理 rename 的 ` -> `;`awk '{print $NF}'` 对含空格的路径会截断。
#   porcelain 路径恒相对仓根,故 -C 后与调用方 cwd 无关。RC = 末段过滤器的 RC(POSIX sh 无 pipefail):
#   枚举失败吐的是空集,而空集在三个调用方那里都是绿 —— 调用方必须按 §J 同层捕获,RC≠0 不许当空集用。
flow_changed_paths() {
  git -C "$FLOW_REPO_DIR" -c core.quotepath=false status --porcelain -uall | sed 's/^...//' | sed 's/.* -> //' | flow_filter_kit_owned
}

# —— UTF-8 字边界截断(awk 函数源码;调用方 `LC_ALL=C awk "$(flow_awk_utrunc)"'… utrunc($0, N) …'`,length/substr 按字节)——
#   按字节截会劈开多字节汉字产出非法 UTF-8(F-9,三批复发:派单件五份全中,编排方每批 iconv -c 清);
#   截完往回退到字边界:前导字节 ≥ \300、续字节 \200–\277,最多退 3 字节。flow-receipts 的摘录与 flow-dispatch 的节头共用。
flow_awk_utrunc() {
  cat <<'AWK'
function utrunc(s, n,   t, i, c, k) {
  if (length(s) <= n) return s
  t = substr(s, 1, n)
  for (i = n; i > n - 4 && i > 0; i--) {
    c = substr(t, i, 1)
    if (c < "\200") return t
    if (c >= "\300") { k = (c >= "\360") ? 4 : ((c >= "\340") ? 3 : 2); return (i + k - 1 > n) ? substr(t, 1, i - 1) : t }
  }
  return t
}
AWK
}

# —— 门与哨兵:config 里以函数给出(sh 原生,免解析分隔符)。没定义就给空实现,调用方自判「零门」——
command -v flow_gates     >/dev/null 2>&1 || flow_gates()     { :; }   # 每行: name<TAB>command ;名 dbreset 保留给「重置库」
command -v flow_sentinels >/dev/null 2>&1 || flow_sentinels() { :; }   # 每行: 路径模式<TAB>该更新的文档段

# —— 欠账标记:圈码 ①–㊿(UTF-8 前两字节 E2 91 / E3 89 / E3 8A)与纯数字 #N 两种都认;调用方一律 LC_ALL=C grep -E ——
flow_mark_re() { printf '(\342\221.|\343\211.|\343\212.|#[0-9]+)'; }
# REQ-ID:REQ-<任务号(可含连字符)>-<序号>。ERE 最左最长 ⟹ REQ-P4-T2-01 整条命中,REQ-P4T2-01 也命中。
flow_req_re() { printf 'REQ-[A-Z0-9]+(-[A-Z0-9]+)*-[0-9]+'; }
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
