# flow.config.sh —— flow-kit 工作区配置(sh 可 source)。放在工作区根的 .claude/ 下;脚本从 cwd 向上找到它。
# 本文件是 StockSteer-Mono 的实例,同时是所有字段的说明书。路径一律相对,不写绝对路径。
# 生成:flow-init 会按本模板写一份并把 FLOW_REPO 填上;之后由人维护。

# ── 必填 ──────────────────────────────────────────────────────────────────────
FLOW_REPO="StockSteer"                 # 仓路径,相对工作区根;单仓工作区写 "."

# ── 布局(相对仓根,除非注明)────────────────────────────────────────────────
FLOW_LEDGER="specs/debts.md"           # 欠账账本(机器头体例见 skill protocol §账本)
FLOW_ROOT_DOC="CLAUDE.md"              # 项目地图 / 门读数 / 钉版住在哪份文件(仓根 CLAUDE.md)
#FLOW_INDEX_DOC="docs/debts-index.md"  # 欠账索引块的落点;不设 = 跟 FLOW_ROOT_DOC
#                                        43 条开放索引 = 5.5 KB,住在根文档里就是每个会话每一轮都重付;搬走后根文档留一行指针
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
FLOW_DOC_BUDGET_FILE=400               # 单个流程件**自写**行数红线
FLOW_DOC_BUDGET_SELF=40000             # 单个流程件**自写**字节红线(RED)= 总字节 − <!-- flow:gen-* --> 段。
#                                        为什么改判自写:墙钟拟合 延迟(s) ≈ 1.5 + 1.4×(上下文/100k) + 1.3×(输出/100 token),
#                                        四条复审轴各有 21–34% 的墙钟耗在 `cat >> 回件 <<EOF` 上(单次最慢 144 s);
#                                        而派单件 48 KB 里 46 KB 是 flow-dispatch 生成的,一个字节也不用模型打 —— 从前每批六句 budget-ok 全花在这上面。
#                                        为什么线还是 40000 而不是按墙钟推的 12000:p4c 六份回件逐节量过,没有一节超 14%,
#                                        最大的单条 4.6 KB、中位 0.8–2.8 KB —— 没有胖条目可砍。要砍到 12 KB 只能删必答四组数 /
#                                        事实句三层 / 非空转,而那三项每条后面都挂着一次记过账的假绿(protocol §4)。回件的字节买的是结论本身。
FLOW_DOC_BUDGET_BYTES=40000            # 总字节 WARN 线(不 RED):读取面还是它,一份派单件五个 agent 各读一遍
#                                        实测两份 ④ 回件卡在旧线 32000 的 99% ⟹ 红线在塑造内容;自写超 90% 会先 WARN
FLOW_DOC_BUDGET_DIR=4000               # 流程目录热路径合计行数 WARN 线
FLOW_DOC_BUDGET_RULEBOOK=250           # 规则书(flow-local.md)行数上限;棘轮:只许降
FLOW_DEBT_CAP=8                        # owner 归本任务的欠账条数上限(超过 = 拆任务或 --cap-ok)
FLOW_DEBT_WARN=16                      # 必读总条数只 WARN 的线
FLOW_FIX_BY_WRITER=0                   # 0 = ③改轮另起 agent(派单自带上一轮回件索引表,按表跳读);1 = SendMessage 回①写轮本人 —— Claude Code 宿主没有这条通路
#                                        (p4e 实测 ToolSearch select:SendMessage 零命中),设 1 时 flow-config --check 判红
FLOW_FOLD_MAX=6                        # 折轮条件:不阻塞条 ≤ 此数且全在③写权限面内 ⟹ 不起收尾轮
FLOW_REQ_CAP=8                         # 任务节 open REQ 条数上限:①写是最长的会话,携带成本随轮数平方长,超了拆任务(或 --cap-ok)
FLOW_TURN_CAP=120                      # 单会话请求数上限,flow-usage 只 WARN(不是门);按会话判,续轮单算(按轴合计时有续轮必红)。
#                                        REQ 条数不是长度的代理量:p4c ①写只有 6 条 REQ,却长出 189 个请求、携带 51.8M(全批的 48%)
FLOW_DISPATCH_EXCERPT_BYTES=12000      # 派单里 plan 任务节选的字节封顶。实测 §P4-T3 一节 42 KB 横跨三刀,八个 agent 各读一遍 ≈ 该批携带 10%;
#                                        超过只印 outline + REQ 行 + 节尾(本刀的落位段住在节尾),其余「文件 + 行号」指针;②③④ 一律只给 outline + REQ 行
FLOW_TEST_GLOBS='*.test.ts *.test.tsx *.spec.ts *.spec.tsx'   # 测试文件模式;flow-trace 当 pathspec、flow-micro 判「性质 = 测试」
FLOW_MICRO_FIX_LINES=16                # 微改通道(0.8.0 换量法):行数由 flow-micro 从④附的 patch numstat 量(只数新增行),不由审方估;非生产条合计 ≤ 此行数、且全在③写权限面内
#                                        ⟹ 编排方落笔(占裁决号)+ 复跑 ④ 在丙栏预先写下的复现命令对期望读数,不起 ③改二、不 SendMessage。
#                                        实测 p4d 两条一句话改动走了整整一个周期;p4e 四条非生产项(10–13 行)又走了 ③改二 + ④B定点 46 min —— 单条 ≤3 行的门槛被一条 3–6 行的顶破
FLOW_STALL_SEC=300                     # flow-usage 卡顿判据:一次工具调用 ≥ 此秒数,或 sub-agent 拿到工具结果后 ≥ 此秒数无输出(生成侧断流),单列 WARN
#                                        (p4d 实测 ②A ②B 各挂 600 s 整、同一秒放行;p4e ③改二 改树后 600 s 无请求被 watchdog 中断 —— 都是 harness 的,不是脚本的)
FLOW_RECEIPT_MODE="section"            # plan 体例:section = 任务是 `## <任务号>` 小节;table = 任务是表行
#                                        体例不对时 flow-receipts 恒 FATAL,接收位就退回人眼核 —— 这是装第二个项目才暴露的
FLOW_ROLE_MODELS=""                    # 分角色模型,如 "②A=sonnet";空 = 继承编排方。换前同一产物两模型各审一次,flow-review-diff 原版独有为空才换
FLOW_TRANSCRIPTS_DIR="$HOME/.claude/projects"   # flow-usage 读 transcripts 的根(收口时 flow-usage <流程目录> --write 自动填轮数账)
