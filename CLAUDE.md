# flow-kit

四轮制(写 / 双轴审 / 改 / 复审)多 agent 工作流的 Claude Code plugin。跨项目复用;工作区只留 `.claude/flow.config.sh`(参数)与 `.claude/flow-local.md`(本项目实录)。

## 地图

- `bin/` —— 全部命令,前缀 `flow-`,plugin 启用后进 Bash PATH,按名调用不写路径。每个脚本头注 = 它的说明书。轮级过渡 `flow-round open|close|state`、步骤账 `flow-step`、收口 `flow-close --wrap|--ship`(0.6.0)、规则书退役 `flow-rulebook`(0.7.0)、微改通道换量法 `flow-micro`(0.8.0)。
- `lib/flow-lib.sh` —— 唯一共享库:找配置(从 cwd 向上找 `.claude/flow.config.sh`,找不到 FATAL)、可移植 sha256、实改集 git 轴枚举(`flow_changed_paths`)、欠账标记与 REQ-ID 模式(`flow_mark_re` / `flow_req_re`)、机器头字段提取、kit 自身根目录 `FLOW_KIT_DIR`(回件模板绝对路径由脚本自算,prompt 里不许手打带版本号的插件缓存路径)。
- `skills/protocol/` —— 编排协议(≤250 行,只留规矩 + 一句为什么 + 最短反例);`references/` 里是照抄用的模板(派单块 + 三行 prompt / 写改回件 / 复审回件 / 收口块 / 三态表 / 轮数账)。
- `skills/init/` —— 把 kit 装进一个工作区:写 config、装 git shim、建流程目录、建账本骨架、按 FLOW_KEEP_* 收窄会话(`flow-settings` 写 `.claude/settings.local.json`:关掉本项目不用的插件与用户级 MCP;实测开局 44k token 里 CLAUDE.md 只占 10k,其余是插件 skill 清单与工具表,sub-agent 每轮重付)。
- `hooks/hooks.json` —— SessionStart 新鲜度检查(`flow-freshness`,全绿静默)。
- `examples/stocksteer/flow.config.sh` —— 配置全字段说明书兼实例。
- `tests/smoke.sh` —— 临时 git 仓上把每条命令跑一遍。

## 移植契约(改任何 bin 脚本都照这个)

1. 头部固定两行:`. "$(cd "$(dirname "$0")/.." && pwd)/lib/flow-lib.sh"` 然后 `flow_load_config`。路径全部从 `FLOW_*` 派生,**脚本里零绝对路径、零项目名**。例外只有四个,都是有意的:`flow-freshness` 与 `flow-post-commit` 先 `flow_find_ws`,找不到静默退出(hook 不许挡会话 / 挡提交);`flow-init` 不 load(它在造 config);`flow-pr-merge` 先处理 `--help`。库会把自己的 `bin/` 前置进 PATH,同胞命令按裸名调用。
2. 必填只有 `FLOW_REPO`;其余有 kit 默认。项目要覆盖的解析串(门输出读数、传输层守卫、哨兵、fact-lint 词表)一律走 config 变量或 config 函数(`flow_gates` / `flow_sentinels`),不留在脚本里。
3. kit 自己定义的枚举与输出词(快照 / 活树-独占 / 禁入,RED / OK / FATAL)保持中文,是协议的一部分,不进 config。生成段标记 `<!-- flow:gen-begin -->` / `<!-- flow:gen-end -->` 同理:`flow-dispatch` 与 `flow-round state` 打、`flow-doc-budget` 认,改一边就要改另一边(预算判的是**自写字节** = 总字节 − 生成段)。轮级约定文件名(`.manifest-baseline-<轮名>.txt` / `.declared-<轮名>.txt` / `.after-<轮名>-hashes.txt` / `.steps-<轮名>.md` / `.face-<轮名>.txt` / `.evidence/<轮名>-*.txt`)由 `flow-dispatch --dir` 印进派单、`flow-round` 按名派生,两侧同源,改一边就要改另一边。**热路径的 md 件(派单 / 回件)不在此列** —— 件名归编排方随手起,所以 `flow-round` 按件里的内容认领(派单看生成段的「轮次 / 模型」行、回件看首行 `# <轮名> 回件`,两份回件模板写死了这个形状),不按件名前缀猜;猜的那条退路要把格子标成 ⚠glob猜。
4. `#!/bin/sh` 的脚本只用 POSIX(不许 `read -d ''`、数组、`PIPESTATUS`、`[[`);真需要 bash 就写 `#!/usr/bin/env bash`。哈希只经 `flow_sha256` / `flow_sha256_check`;临时文件只经 `flow_tmpdir`;解析路径的 git 调用一律 `-c core.quotepath=false`(否则中文路径成八进制转义,静默对不上);多行值不进 `awk -v`(BSD awk 报 newline in string 后吐空集),走 ENVIRON。
5. 判据纪律(协议 §J 的四条硬规矩)脚本自己也守:探测器输出不截断、RC 与命令同层捕获、`&&`/`||` 链里不放判据命令、比对前证明两侧不同源。
6. 欠账标记两种都认(圈码 ①–㊿ 与 `#N`),匹配一律 `LC_ALL=C grep -E "$(flow_mark_re)"`;状态集只有 `open` / `closed`。
7. 出错形态:参数错 RC=2 且 FATAL;判据红 RC=1 且行首 RED;绿 RC=0 且行首 OK / lint OK / PASS。末行固定可 grep。RC=3 是**「这条判据在本仓不适用 / 这个任务过载」**的第三态,不是判据红,调用方按 info 处理:`flow-dispatch` 的 owner 欠账或 open REQ 超上限(拆任务或 `--cap-ok`)· `flow-trace` 整份 plan 零 REQ-ID(末行 `TRACE N/A`,0.7.1)。凡加 RC=3 的地方,「不适用」与「没扫到」必须能分开判(§J0),判据取全局不取局部。
8. kit 自己的记账件(队列 / fact-lint 基线 / 流程目录 / 门缓存)落在仓内时不算任何一轮的实改集:实改集 git 轴一律经 `flow_changed_paths`(内含 `flow_filter_kit_owned`),且调用方同层捕获其 RC,失败不许当空集。

## 命令对照(StockSteer-Mono `.claude/scripts/` 旧名 → 新名)

route-debts → `flow-route-debts` · render-debts-index → `flow-render-index` · render-dispatch → `flow-dispatch` · route-receipts → `flow-receipts` · tree-freeze → `flow-freeze` · freeze-manifest → `flow-manifest` · round-close → `flow-close` · six-gates → `flow-gates` · doc-budget → `flow-doc-budget` · fact-lint → `flow-fact-lint` · clear-map-debt → `flow-clear-map-debt` · merge-lane → `flow-merge-lane` · pr-merge-when-green → `flow-pr-merge` · post-commit hook 逻辑 → `flow-post-commit` · 新增 `flow-init` / `flow-config` / `flow-freshness` / `flow-settings` / `flow-trace` / `flow-usage` / `flow-review-diff` / `flow-ledger`(账本增删改,并且是 ④A 三态表的唯一解析器 —— 判定格实际写作 `**还**`,谁再写一份正则谁就 FATAL)· 0.6.0 新增 `flow-step`(步骤账,断点续跑的真值源)/ `flow-round`(轮开工 / 收工交接口 / 状态档事实段)· 0.7.0 新增 `flow-rulebook`(规则书退役,逐字搬进归档件)与 `flow-trace --mark-done` / `flow-ledger add --body-file` / `flow-close --ship --dir`;`flow-usage` 的 `.usage.md` 也用 `flow:gen-*` 标记括生成段,重跑保留手填段。

0.7.1(工具修):`flow-trace` 学 table 体例(节 = **首格恰等于任务号**的表行,不用 `flow-receipts` 轴1 的全行 `index()`)+ 整份 plan 零 REQ-ID 出 `RC=3 / TRACE N/A`,`flow-close` 的两处对账按 info 处理不判红;`flow-round` 的派单 / 回件两列改**按件里的内容认领**。

0.8.0(微改通道换量法):新 `flow-micro <patch>... --face <写权限面清单> [--freeze] [--apply]` —— 行数由 `git apply --numstat` 的**新增行**求和给,性质由路径(`FLOW_TEST_GLOBS` / `*.md`)与 patch 改动行核,面内按 `flow-dispatch --dir` 落的 `.face-<轮名>.txt` 判;`flow-doc-budget` 的目录合计线按轮数归一(轮数 > 6 时线 = DIR × 轮数 / 6)。
