# flow-kit

四轮制(写 / 双轴审 / 改 / 复审)多 agent 工作流的 Claude Code plugin。跨项目复用;工作区只留 `.claude/flow.config.sh`(参数)与 `.claude/flow-local.md`(本项目实录)。

## 地图

- `bin/` —— 全部命令,前缀 `flow-`,plugin 启用后进 Bash PATH,按名调用不写路径。每个脚本头注 = 它的说明书。轮级过渡 `flow-round open|close|state`、步骤账 `flow-step`、收口 `flow-close --wrap|--ship`(0.6.0)。
- `lib/flow-lib.sh` —— 唯一共享库:找配置(从 cwd 向上找 `.claude/flow.config.sh`,找不到 FATAL)、可移植 sha256、实改集 git 轴枚举(`flow_changed_paths`)、欠账标记与 REQ-ID 模式(`flow_mark_re` / `flow_req_re`)、机器头字段提取、kit 自身根目录 `FLOW_KIT_DIR`(回件模板绝对路径由脚本自算,prompt 里不许手打带版本号的插件缓存路径)。
- `skills/protocol/` —— 编排协议(≤250 行,只留规矩 + 一句为什么 + 最短反例);`references/` 里是照抄用的模板(派单块 + 三行 prompt / 写改回件 / 复审回件 / 收口块 / 三态表 / 轮数账)。
- `skills/init/` —— 把 kit 装进一个工作区:写 config、装 git shim、建流程目录、建账本骨架、按 FLOW_KEEP_* 收窄会话(`flow-settings` 写 `.claude/settings.local.json`:关掉本项目不用的插件与用户级 MCP;实测开局 44k token 里 CLAUDE.md 只占 10k,其余是插件 skill 清单与工具表,sub-agent 每轮重付)。
- `hooks/hooks.json` —— SessionStart 新鲜度检查(`flow-freshness`,全绿静默)。
- `examples/stocksteer/flow.config.sh` —— 配置全字段说明书兼实例。
- `tests/smoke.sh` —— 临时 git 仓上把每条命令跑一遍。

## 移植契约(改任何 bin 脚本都照这个)

1. 头部固定两行:`. "$(cd "$(dirname "$0")/.." && pwd)/lib/flow-lib.sh"` 然后 `flow_load_config`。路径全部从 `FLOW_*` 派生,**脚本里零绝对路径、零项目名**。例外只有四个,都是有意的:`flow-freshness` 与 `flow-post-commit` 先 `flow_find_ws`,找不到静默退出(hook 不许挡会话 / 挡提交);`flow-init` 不 load(它在造 config);`flow-pr-merge` 先处理 `--help`。库会把自己的 `bin/` 前置进 PATH,同胞命令按裸名调用。
2. 必填只有 `FLOW_REPO`;其余有 kit 默认。项目要覆盖的解析串(门输出读数、传输层守卫、哨兵、fact-lint 词表)一律走 config 变量或 config 函数(`flow_gates` / `flow_sentinels`),不留在脚本里。
3. kit 自己定义的枚举与输出词(快照 / 活树-独占 / 禁入,RED / OK / FATAL)保持中文,是协议的一部分,不进 config。生成段标记 `<!-- flow:gen-begin -->` / `<!-- flow:gen-end -->` 同理:`flow-dispatch` 与 `flow-round state` 打、`flow-doc-budget` 认,改一边就要改另一边(预算判的是**自写字节** = 总字节 − 生成段)。轮级约定文件名(`.manifest-baseline-<轮名>.txt` / `.declared-<轮名>.txt` / `.after-<轮名>-hashes.txt` / `.steps-<轮名>.md` / `.evidence/<轮名>-*.txt`)由 `flow-dispatch --dir` 印进派单、`flow-round` 按名派生,两侧同源,改一边就要改另一边。
4. `#!/bin/sh` 的脚本只用 POSIX(不许 `read -d ''`、数组、`PIPESTATUS`、`[[`);真需要 bash 就写 `#!/usr/bin/env bash`。哈希只经 `flow_sha256` / `flow_sha256_check`;临时文件只经 `flow_tmpdir`;解析路径的 git 调用一律 `-c core.quotepath=false`(否则中文路径成八进制转义,静默对不上);多行值不进 `awk -v`(BSD awk 报 newline in string 后吐空集),走 ENVIRON。
5. 判据纪律(协议 §J 的四条硬规矩)脚本自己也守:探测器输出不截断、RC 与命令同层捕获、`&&`/`||` 链里不放判据命令、比对前证明两侧不同源。
6. 欠账标记两种都认(圈码 ①–㊿ 与 `#N`),匹配一律 `LC_ALL=C grep -E "$(flow_mark_re)"`;状态集只有 `open` / `closed`。
7. 出错形态:参数错 RC=2 且 FATAL;判据红 RC=1 且行首 RED;绿 RC=0 且行首 OK / lint OK / PASS。末行固定可 grep。唯一例外:`flow-dispatch` 的 owner 欠账超上限 RC=3(不是判据红,是任务过载,要拆任务或 `--cap-ok`)。
8. kit 自己的记账件(队列 / fact-lint 基线 / 流程目录 / 门缓存)落在仓内时不算任何一轮的实改集:实改集 git 轴一律经 `flow_changed_paths`(内含 `flow_filter_kit_owned`),且调用方同层捕获其 RC,失败不许当空集。

## 命令对照(StockSteer-Mono `.claude/scripts/` 旧名 → 新名)

route-debts → `flow-route-debts` · render-debts-index → `flow-render-index` · render-dispatch → `flow-dispatch` · route-receipts → `flow-receipts` · tree-freeze → `flow-freeze` · freeze-manifest → `flow-manifest` · round-close → `flow-close` · six-gates → `flow-gates` · doc-budget → `flow-doc-budget` · fact-lint → `flow-fact-lint` · clear-map-debt → `flow-clear-map-debt` · merge-lane → `flow-merge-lane` · pr-merge-when-green → `flow-pr-merge` · post-commit hook 逻辑 → `flow-post-commit` · 新增 `flow-init` / `flow-config` / `flow-freshness` / `flow-settings` / `flow-trace` / `flow-usage` / `flow-review-diff` / `flow-ledger`(账本增删改,并且是 ④A 三态表的唯一解析器 —— 判定格实际写作 `**还**`,谁再写一份正则谁就 FATAL)· 0.6.0 新增 `flow-step`(步骤账,断点续跑的真值源)/ `flow-round`(轮开工 / 收工交接口 / 状态档事实段)。
