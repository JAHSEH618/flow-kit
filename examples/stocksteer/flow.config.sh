# flow.config.sh —— flow-kit 工作区配置(sh 可 source)。放在工作区根的 .claude/ 下;脚本从 cwd 向上找到它。
# 本文件是 StockSteer-Mono 的实例,同时是所有字段的说明书。路径一律相对,不写绝对路径。
# 生成:flow-init 会按本模板写一份并把 FLOW_REPO 填上;之后由人维护。

# ── 必填 ──────────────────────────────────────────────────────────────────────
FLOW_REPO="StockSteer"                 # 仓路径,相对工作区根;单仓工作区写 "."

# ── 布局(相对仓根,除非注明)────────────────────────────────────────────────
FLOW_LEDGER="specs/debts.md"           # 欠账账本(机器头体例见 skill protocol §账本)
FLOW_ROOT_DOC="CLAUDE.md"              # 欠账索引块住在哪份文件(仓根 CLAUDE.md)
FLOW_SPEC_DIRS="specs"                 # 规格目录,空格分隔;冻结的 shasum 轴与 fact-lint 扫描范围用它
FLOW_SPEC_UNTRACKED=1                  # 1 = 规格目录被 gitignore(真值活在 git 外):冻结走 git+shasum 双轴,grep 要显式带它
                                       # 0 = 规格入库:冻结只走 git 轴
FLOW_FLOW_DIR=".flow"                  # 流程目录根,相对工作区根;每批次一个子目录 .flow/<批次号>/
FLOW_MAP_DEBT=".claude/map-debt.md"    # 地图欠账队列,相对工作区根(post-commit 检测器写、freshness 读、clear-map-debt 清)
FLOW_LOCAL_DOC=".claude/flow-local.md" # 本项目的本地规矩与实录(规则书棘轮只量它),相对工作区根

# ── git / CI ─────────────────────────────────────────────────────────────────
FLOW_MAIN_BRANCH="master"
FLOW_DEV_BRANCH="dev"
FLOW_MERGE_STRATEGY="--merge"          # gh pr merge 的策略参数

# ── 门(有序;每行 name<TAB>command;名字 dbreset 保留给「重置库」步,只在 flow-gates --reset 时跑)──
flow_gates() {
  printf '%s\n' \
    'lint	pnpm lint' \
    'typecheck	pnpm -r typecheck' \
    'build	pnpm -r build' \
    'unit	pnpm test:unit' \
    'dbreset	pnpm db:reset' \
    'integration	pnpm test:integration' \
    'dbverify	pnpm db:verify'
}
FLOW_GATE_SUMMARY_RE='Test Files|Tests |全过|FAIL'   # 门输出里要抄进 rc.txt 的读数行(ERE)
FLOW_INFRA_FAIL_RE='57P01|Connection terminated|does not exist in the current database'  # 传输层守卫:命中 >0 判 INFRA_FAIL 弃读数
FLOW_INFRA_FAIL_GATES='integration'   # 只在这些门的输出里扫守卫(空格分隔;空 = 本次跑过的全部门)
FLOW_GATE_REBUILD='build'              # 缓存命中时仍要重跑的门名(护 dist;空 = 全取缓存)

# ── post-commit 哨兵(每行 路径模式<TAB>该更新的文档段;模式按 sh case 语法)──
flow_sentinels() {
  printf '%s\n' \
    'eslint.config.js	CLAUDE.md 边界段' \
    '.github/workflows/ci.yml	CLAUDE.md 门/CI 段' \
    'prisma/schema.prisma	db/CLAUDE.md DB 段' \
    'db/*.sql	db/CLAUDE.md DB 段' \
    'package.json	CLAUDE.md 钉版/命令段' \
    '*/package.json	CLAUDE.md 钉版/命令段'
}

# ── fact-lint(注释假话族的门)────────────────────────────────────────────────
FLOW_FACT_LINT_ROOTS="apps packages db tools specs"                 # 扫描根,相对仓根,空格分隔
FLOW_FACT_LINT_EXCLUDE="specs/debts.md specs/test-chronicle.md"     # 账本与史册的出处句是内容不是假话
FLOW_FACT_LINT_BASELINE=".claude/fact-lint-baseline.tsv"            # 棘轮基线,相对工作区根
# 模式表:kit 自带默认(中文假话族);项目要加词就在这里覆盖同名变量(ERE,按字节匹配,禁用 CJK 字符类)
# FLOW_FL_QCLAIM='…'  FLOW_FL_QWIDE='…'  FLOW_FL_PROV='…'  FLOW_FL_SELFNUM='…'

# ── 会话瘦身(flow-settings 读)───────────────────────────────────────────────
# 用户级启用的插件里,不在 FLOW_KEEP_PLUGINS 的一律 enabledPlugins:false;用户级 MCP 里,不在 FLOW_KEEP_MCP 的一律进 disabledMcpServers。
# 落在工作区 .claude/settings.local.json(插件 id 与 MCP 名是这台机器的事,不进仓)。flow-kit 自己永远保留。
# 两行都要写(留什么是项目的事实,不给默认;缺任一 flow-settings FATAL 并列出候选)。
FLOW_KEEP_PLUGINS="vtsls claude-hud impeccable"   # 裸 name 或 name@marketplace,空格分隔;写空串 = 只留 flow-kit
FLOW_KEEP_MCP="exa"                                               # 用户级 MCP 名;写空串 = 全关

# ── 预算与阈值 ───────────────────────────────────────────────────────────────
FLOW_DOC_BUDGET_FILE=400               # 单个流程件行数红线
FLOW_DOC_BUDGET_BYTES=32000            # 单个流程件字节红线(token 按字节计;112 KB 的复验件靠长行躲过了行数线)
FLOW_DOC_BUDGET_DIR=4000               # 流程目录热路径合计行数 WARN 线
FLOW_DOC_BUDGET_RULEBOOK=250           # 规则书(flow-local.md)行数上限;棘轮:只许降
FLOW_DEBT_CAP=8                        # owner 归本任务的欠账条数上限(超过 = 拆任务或 --cap-ok)
FLOW_DEBT_WARN=16                      # 必读总条数只 WARN 的线
FLOW_FIX_BY_WRITER=1                   # 1 = ③改轮 SendMessage 回①写轮本人;0 = 另起 agent
FLOW_FOLD_MAX=6                        # 折轮条件:不阻塞条 ≤ 此数且全在③写权限面内 ⟹ 不起收尾轮
FLOW_REQ_CAP=8                         # 任务节 open REQ 条数上限:①写是最长的会话,携带成本随轮数平方长,超了拆任务(或 --cap-ok)
FLOW_ROLE_MODELS=""                    # 分角色模型,如 "②A=sonnet";空 = 继承编排方。换前同一产物两模型各审一次,flow-review-diff 原版独有为空才换
FLOW_TRANSCRIPTS_DIR="$HOME/.claude/projects"   # flow-usage 读 transcripts 的根(收口时 flow-usage <流程目录> --write 自动填轮数账)
