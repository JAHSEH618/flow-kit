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
  FLOW_DOC_BUDGET_HOTPATH=8000          # 回件**热路径节**(〇 索引 / 正面结论 + 丙栏)的字节上限,flow-round close 按本轮自己那份判(0.8.2)
                                        # 为什么不判全文:实测九份回件全文 16–37 KB,按申报件归一落在 609–1498 B/件,排序跟着「这轮要证多少」走,
                                        # 不跟着写作风格走 —— 全文线在数交付面,和 0.8.0 修掉的目录合计线同一种病。真正被下游每一轮重付的只有 〇+丙
                                        # (占全文 9%–35%),甲栏的证据只有复审轴读一次。实测这条线只有 04a 回件破线(11996;它的 〇 节是 `(待收工填)` 占位)
  FLOW_DOC_BUDGET_RULEBOOK=250
  FLOW_DEBT_CAP=8
  FLOW_DEBT_WARN=16
  FLOW_FIX_BY_WRITER=0                  # 1 = ③改轮 SendMessage 回①写轮本人。Claude Code 宿主没有这条通路(p4e 实测 ToolSearch 零命中),默认另起;设 1 时 flow-config --check 判红
  FLOW_FOLD_MAX=6
  FLOW_REQ_CAP=8
  FLOW_TURN_CAP=120                     # 单会话请求数上限(flow-usage 只 WARN):携带 ∝ 轮数 × 上下文,上下文又随轮数长 ⟹ 二次;按会话判,续轮单算
  FLOW_DISPATCH_EXCERPT_BYTES=12000     # 派单里 plan 任务节选的字节封顶:超过只印 outline + REQ 行 + 节尾(本刀落位段),其余给「文件 + 行号」指针
                                        # 实测一节 42 KB 横跨三刀,八个 agent 各读一遍 ≈ 该批携带 10%;②③④ 一律不印正文
  FLOW_MICRO_FIX_LINES=16               # 微改通道:审轮(② 与 ④)必闭里非生产条的**非测试新增行合计**上限(1.0.0 / C2;测试行单列印出不计,删除行不计)。
                                        # 行数由 `flow-micro` 从审方附的 patch `git apply --numstat` 求和,不由审方估:P3-1 实测裁决-700 估 16 行 / 实做 55 行(偏 3.4×)。
                                        # 没附 patch 的条目一律不算微改,自动落回 ③
  FLOW_STALL_SEC=300                    # flow-usage 卡顿判据:一次工具调用 ≥ 此秒数单列 WARN(harness 卡顿实测 600 s 整、两轴同刻放行)
  FLOW_RECEIPT_MODE="section"           # plan 体例:section = `## <任务号>` 小节;table = 任务是表行
  FLOW_TEST_GLOBS='*.test.ts *.test.tsx *.spec.ts *.spec.tsx'   # 测试文件模式(空格分隔的 glob)。两处共用:flow-trace 拿它当 git ls-files 的 pathspec、
                                        # flow-micro 拿它判「性质 = 测试」。别的栈(*_test.go / test_*.py / *Test.java)在 config 里覆盖
  FLOW_ROLE_MODELS=""
  FLOW_BARE_PATH_RE='(^|[^A-Za-z0-9_./`-])[A-Za-z0-9_.-]+\.(md|html|toml|tsx|ts|js|jsx|mjs|cjs|sh|sql|prisma|yml|yaml|json)([^A-Za-z0-9_`]|$)'
                                        # 裸文件名(反引号外):flow-ledger add --title 命中即 FATAL(0.9.0)。title 原样进机器头,再由 flow-render-index 印进根文档,
                                        # 仓侧「纯文本指针」棘轮在 wrap 门整跑才红(P3-4 跑了两遍);入口挡下是秒级,门整跑是分钟级。项目按自己的棘轮式覆盖(ERE)
  FLOW_TEST_SKIP_RE='\.(only|skip|todo)\(|(^|[^A-Za-z0-9_])x(it|test|describe)\('
                                        # 测试文件里的跳过 / 独跑标记(ERE):本轮改过或新增的 FLOW_TEST_GLOBS 件含它 ⟹ flow-manifest verify RED(0.9.0 测试锁)
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
         FLOW_GATE_SUMMARY_RE FLOW_INFRA_FAIL_RE FLOW_INFRA_FAIL_GATES FLOW_DOC_BUDGET_FILE FLOW_DOC_BUDGET_BYTES FLOW_DOC_BUDGET_SELF FLOW_DOC_BUDGET_DIR FLOW_DOC_BUDGET_HOTPATH FLOW_DOC_BUDGET_RULEBOOK \
         FLOW_DEBT_CAP FLOW_DEBT_WARN FLOW_FIX_BY_WRITER FLOW_FOLD_MAX FLOW_MERGE_STRATEGY FLOW_REQ_CAP FLOW_TURN_CAP FLOW_DISPATCH_EXCERPT_BYTES FLOW_MICRO_FIX_LINES FLOW_TEST_GLOBS FLOW_TEST_SKIP_RE FLOW_BARE_PATH_RE FLOW_STALL_SEC FLOW_ROLE_MODELS FLOW_TRANSCRIPTS_DIR \
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

# —— 冻结一棵树(1.0.0 入库;flow-freeze 命令只剩壳):实改集(git 轴 + 规格目录轴)逐件 sha256 → <out>,shasum -c 体例 ——
#   为什么入库:1.0.0 起冻结归 `flow-round close`(全绿之后打 .after)与 `flow-micro --apply`(落笔后重打),agent 不再自跑。
#   规格目录轴:git 看不见 gitignore 区,FLOW_SPEC_UNTRACKED=1 时规格目录整个无条件纳入(不做选择就漏不掉)。
#   两条守卫都 FATAL 不静默:枚举结果里出现目录(它下面的文件会漏)· 路径含空白(喂给 flow-manifest 会判格式错)。
#   RC:0 = 清单已出(stdout 一行 `冻结清单已出: <out>(N 行)`);2 = 枚举失败 / 守卫红,清单不写。
flow_freeze_to() {   # 用法: flow_freeze_to <输出文件(绝对)>
  _fz_out="$1"
  case "$_fz_out" in /*) ;; *) flow_die "冻结输出文件必须绝对路径: $_fz_out" ;; esac
  [ -d "$(dirname "$_fz_out")" ] || flow_die "冻结输出目录不存在: $(dirname "$_fz_out")"
  _fz_tmp=$(mktemp "$(flow_tmpdir)/flow-freeze.XXXXXX") || return 2
  ( cd "$FLOW_REPO_DIR" || exit 2
    # 枚举失败不许当空集(空集到 [ -f ] 那关就静默成空清单)—— RC 同层捕获
    flow_changed_paths > "$_fz_tmp" || { echo "FATAL: 实改集枚举失败(flow_changed_paths RC≠0),拒绝出清单" >&2; exit 2; }
    if [ "$FLOW_SPEC_UNTRACKED" = 1 ]; then
      for d in $FLOW_SPEC_DIRS; do [ -d "$d" ] && find "$d" -type f -name '*.md'; done >> "$_fz_tmp"
    fi
    sort -u "$_fz_tmp" > "$_fz_tmp.u"
    _fz_bad=$(while IFS= read -r f; do [ -n "$f" ] && [ -d "$f" ] && printf '%s\n' "$f"; done < "$_fz_tmp.u")
    if [ -n "$_fz_bad" ]; then
      echo "FATAL: 枚举结果里出现目录,它下面的文件会被漏掉:" >&2; printf '  %s\n' $_fz_bad >&2; exit 2
    fi
    _fz_ws=$(grep '[[:space:]]' "$_fz_tmp.u" || true)
    if [ -n "$_fz_ws" ]; then
      echo "FATAL: 枚举结果里有含空白的路径,拒绝出清单:" >&2; printf '%s\n' "$_fz_ws" | sed 's/^/  /' >&2; exit 2
    fi
    while IFS= read -r f; do [ -n "$f" ] && [ -f "$f" ] && flow_sha256 "$f"; done < "$_fz_tmp.u" > "$_fz_out"
    echo "冻结清单已出: $_fz_out($(grep -c . "$_fz_out" || true) 行)"
  ); _fz_rc=$?
  rm -f "$_fz_tmp" "$_fz_tmp.u"
  return $_fz_rc
}

# —— 回件认领(1.0.0 入库,flow-round / flow-dispatch 共用):按**件里的首行**认,不按件名猜 ——
#   回件首行逐字 `# <轮名> 回件 …`(两份回件模板的契约)。件名归编排方随手起,两批实测按件名前缀 + mtime 猜过 14 行行行错。
#   stdout 印文件名(相对 <流程目录>),没有就空;RC 恒 0(认不出由调用方判)。
flow_find_handoff() {   # 用法: flow_find_handoff <流程目录(绝对)> <轮名>
  ( cd "$1" 2>/dev/null || exit 0
    for m in *.md; do
      [ -f "$m" ] || continue
      case "$(head -1 "$m")" in "# $2 回件"*) printf '%s\n' "$m"; break ;; esac
    done )
}

# —— 〇表解析(1.0.0 / A1):回件〇节索引表 → 申报行(`path` 或 `path  # 裁决-N`)——
#   表列:`| 符号 | 文件:行段 | 性质 | 对应 | 例外 |`。第二列 = 路径[:行段](反引号可有可无);性质 新增 / 改 / 删 才算实改,
#   顶回 / 核过 之类不进申报;例外列写 `裁决-N` ⟹ 行尾 `# 裁决-N`(越面与测试锁的例外通道,与 flow-manifest verify 同一条)。
#   审轮的〇是正面结论不是表 ⟹ 零行(视为零改动)。只读 `## 〇` 节;表头行与分隔行跳过。
flow_handoff_paths() {   # 用法: flow_handoff_paths <回件(绝对)>
  LC_ALL=C awk -F'|' '
    /^## /{ on = ($0 ~ /^## 〇/); next }
    !on || $0 !~ /^\|/ || NF < 5 { next }
    { for (i = 1; i <= NF; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
      f = $3; k = $4; e = (NF >= 6 ? $6 : "")
      if (k != "新增" && k != "改" && k != "删") next          # 表头行(性质)与分隔行(---)也在这里被跳过
      gsub(/`/, "", f); sub(/:[0-9][^\/]*$/, "", f)
      if (f == "" || f ~ /[ \t]/ || f ~ /^[0-9][0-9,–-]*$/) next   # 纯行段(旧四列体例把路径写在第一列)不是路径:跳过,让 verify 报漏申报
      if (e ~ /裁决[- ]*[0-9]+/) { sub(/.*裁决[- ]*/, "", e); sub(/[^0-9].*/, "", e); printf "%s  # 裁决-%s\n", f, e }
      else print f }' "$1"
}

# —— 派生申报清单(1.0.0 / A1):本轮 = 〇表路径 ∪ 目录里**所有先前轮**的派生清单 ——
#   git 轴比的是 HEAD 不是基线:一批里前几轮未提交的改动全在实改集里,所以要并上前几轮(取并集而不取「上一轮」:
#   ②A ‖ ②B 谁后收工不定,flow-micro 追写的是 ①写 那份,按 mtime 取单份都会漏)。同一路径多行取带裁决号的那行,本轮优先。
#   自己那份(.declared-<轮名>.txt)不并入(重跑 close 幂等);带 kit 头的先前清单头行跳过。写进 <out>,首行 kit 头。
flow_derive_declared() {   # 用法: flow_derive_declared <流程目录(绝对)> <轮名> <回件(绝对,可空)> <输出(绝对)>
  _dd_dir="$1"; _dd_round="$2"; _dd_h="$3"; _dd_out="$4"
  _dd_tmp=$(mktemp "$(flow_tmpdir)/flow-declared.XXXXXX") || return 2
  { [ -n "$_dd_h" ] && [ -f "$_dd_h" ] && flow_handoff_paths "$_dd_h" | sed 's/^/0\t/'
    for f in "$_dd_dir"/.declared-*.txt; do
      [ -f "$f" ] || continue
      [ "$f" = "$_dd_dir/.declared-$_dd_round.txt" ] && continue
      grep -v '^[[:space:]]*#' "$f" | sed -e 's/^[0-9a-f]\{40,\}  //' -e 's/^git \(..\) //' -e 's/^git //' -e 's/.* -> //' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep . | sed 's/^/1\t/'
    done; } > "$_dd_tmp"
  { echo "# declared · $_dd_round(flow-round close 派生 $(date +%F\ %H:%M):〇表路径 ∪ 先前轮清单;勿手改,重跑 close 重生)"
    LC_ALL=C awk -F'\t' '{ line = $2; p = line; sub(/[ \t][ \t]*#.*$/, "", p); sub(/[ \t]*$/, "", p); if (p == "") next
        has = (line ~ /#/)
        if (!(p in best)) { best[p] = line; rank[p] = $1 * 2 + (has ? 0 : 1); ord[++n] = p }
        else { r = $1 * 2 + (has ? 0 : 1); if (r < rank[p]) { best[p] = line; rank[p] = r } } }
      END { for (i = 1; i <= n; i++) print best[ord[i]] }' "$_dd_tmp"
  } > "$_dd_out"
  rm -f "$_dd_tmp"
}

# —— 路径实参的词分割守卫(0.8.2):单个实参含空白 ⟹ 多半是把整份清单塞进一个变量喂进来了 ——
#   zsh 不对 `$VAR` 做词分割(bash 的 IFS 分词在 zsh 里默认关着),于是 `cmd $PATHS` 把 N 条路径塌成 1 条实参,
#   而每个消费者都拿它做前缀 / 精确匹配 ⟹ 路径轴静默失效、命令照样 RC=0。两处实测:
#     · flow-dispatch 触面 N 条塌成 1 条,派单块照样生成(StockSteer P4-T4-2G,0.8.1 已在本地挡下)
#     · flow-route-debts 实改集 15 条塌成 3 条(ShipLedger P3-3 的 ④A / ④B 各踩一次)
#   让路径轴静默失效的输入,要在入口红,不能靠人记得 —— 所以守卫归库,不归某一个脚本。
#   ⚠ flow-manifest 的扫描区**故意不用**这条:那批实参在每一个消费者那里都是不带引号展开的
#   (`sha_scan $areas` / 基线头 `areas:` / flow-close 的 `for a in $areas`),塌成一条再分开是等价的,加守卫会把能用的用法判死。
flow_check_ws_args() {   # 用法: flow_check_ws_args <参数名(报错用)> <实参>...
  _flow_ws_name="$1"; shift
  for _flow_ws_a in "$@"; do
    case "$_flow_ws_a" in
      *[[:space:]]*) flow_die "单个${_flow_ws_name}实参含空白 —— 多半是把整份清单塞进一个变量喂进来了(zsh 不对 \$VAR 做词分割),于是 N 条塌成 1 条、按它走的路径轴跟着静默塌:改用数组或 xargs 逐条传: $_flow_ws_a" ;;
    esac
  done
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
