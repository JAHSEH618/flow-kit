# flow.config.sh —— flow-kit 工作区配置(sh 可 source;由 flow-init 生成,之后由人维护)。
# 路径一律相对,不写绝对路径。全字段说明书与实例:plugin 的 examples/stocksteer/flow.config.sh。

# ── 必填 ──
FLOW_REPO="@REPO@"                     # 仓路径,相对工作区根;单仓工作区 = "."

# ── 布局(相对仓根,除非注明)──
FLOW_LEDGER="@LEDGER@"                 # 欠账账本
FLOW_ROOT_DOC="CLAUDE.md"              # 欠账索引块住在哪份文件
FLOW_SPEC_DIRS="@SPEC_DIRS@"           # 规格目录,空格分隔
FLOW_SPEC_UNTRACKED=@UNTRACKED@        # 1 = 规格目录被 gitignore(冻结走双轴);0 = 规格入库(只走 git 轴)
FLOW_FLOW_DIR=".flow"                  # 流程目录根,相对工作区根
FLOW_MAP_DEBT=".claude/map-debt.md"    # 地图欠账队列,相对工作区根
FLOW_LOCAL_DOC=".claude/flow-local.md" # 本项目的本地规矩与实录(规则书棘轮只量它)

# ── git / CI ──
FLOW_MAIN_BRANCH="@MAIN@"
FLOW_DEV_BRANCH="dev"
FLOW_MERGE_STRATEGY="--merge"

# ── 门(有序;每行 name<TAB>command;名字 dbreset 保留给「重置库」,只在 flow-gates --reset 时跑)──
# 没定义 flow_gates 之前 flow-gates 会 FATAL —— 这是故意的:门是项目的事实,不给默认。
# flow_gates() {
#   printf '%s\n' \
#     'lint	<lint 命令>' \
#     'typecheck	<typecheck 命令>' \
#     'build	<build 命令>' \
#     'unit	<单元测试命令>'
# }
FLOW_GATE_SUMMARY_RE='Test Files|Tests '    # 门输出里要抄进 rc.txt 的读数行(ERE)
FLOW_INFRA_FAIL_RE='57P01|Connection terminated|does not exist in the current database'
FLOW_INFRA_FAIL_GATES=''               # 只在这些门的输出里扫守卫(空格分隔;空 = 全部门)
FLOW_GATE_REBUILD='build'              # 缓存命中时仍重跑的门名(空 = 全取缓存)

# ── post-commit 哨兵(每行 路径模式<TAB>该更新的文档段;可不定义)──
# flow_sentinels() {
#   printf '%s\n' \
#     'package.json	CLAUDE.md 命令段'
# }

# ── fact-lint ──
FLOW_FACT_LINT_ROOTS=""                # 扫描根,相对仓根,空格分隔;空 = flow-fact-lint FATAL 提醒配置
FLOW_FACT_LINT_EXCLUDE="@LEDGER@"      # 账本的出处句是内容不是假话
FLOW_FACT_LINT_BASELINE=".claude/fact-lint-baseline.tsv"

# ── 会话瘦身(flow-settings 读;两者都写了才会动 .claude/settings.local.json)──
# 用户级启用的插件里,不在 FLOW_KEEP_PLUGINS 的一律关(flow-kit 自己永远留;写 name@marketplace 或裸 name,空格分隔);
# 用户级 MCP 里,不在 FLOW_KEEP_MCP 的一律关。留什么是项目的事实,不给默认:两行都没写 = flow-settings FATAL 并列候选。
@KEEP_PLUGINS_LINE@
@KEEP_MCP_LINE@

# ── 预算与阈值 ──
FLOW_DOC_BUDGET_FILE=400
FLOW_DOC_BUDGET_BYTES=32000
FLOW_DOC_BUDGET_DIR=4000
FLOW_DOC_BUDGET_RULEBOOK=250
FLOW_DEBT_CAP=8
FLOW_DEBT_WARN=16
FLOW_FIX_BY_WRITER=1                   # 1 = ③改轮回①写轮本人
FLOW_FOLD_MAX=6                        # 不阻塞条 ≤ 此数且全在③写权限面内 ⟹ 不起收尾轮
FLOW_REQ_CAP=8                         # 任务节 open REQ 条数上限(超过 = 拆任务或 flow-dispatch --cap-ok)
FLOW_ROLE_MODELS=""                    # 分角色模型,如 "②A=sonnet";空 = 全部继承编排方;换前先 flow-review-diff 对照
FLOW_TRANSCRIPTS_DIR="$HOME/.claude/projects"   # flow-usage 读 transcripts 的根
