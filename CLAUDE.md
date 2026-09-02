# flow-kit

四轮制(写 / 双轴审 / 改 / 复审)多 agent 工作流的 Claude Code plugin。跨项目复用;工作区只留 `.claude/flow.config.sh`(参数)与 `.claude/flow-local.md`(本项目实录)。

## 地图

- `bin/` —— 全部命令,前缀 `flow-`,plugin 启用后进 Bash PATH,按名调用不写路径。每个脚本头注 = 它的说明书。
- `lib/flow-lib.sh` —— 唯一共享库:找配置(从 cwd 向上找 `.claude/flow.config.sh`,找不到 FATAL)、可移植 sha256、欠账标记模式、机器头字段提取。
- `skills/protocol/` —— 编排协议(≤250 行,只留规矩 + 一句为什么 + 最短反例);`references/` 里是照抄用的模板(派单块 / 复审回件 / 收口块 / 三态表 / 轮数账)。
- `skills/init/` —— 把 kit 装进一个工作区:写 config、装 git shim、建流程目录、建账本骨架。
- `hooks/hooks.json` —— SessionStart 新鲜度检查(`flow-freshness`,全绿静默)。
- `examples/stocksteer/flow.config.sh` —— 配置全字段说明书兼实例。
- `tests/smoke.sh` —— 临时 git 仓上把每条命令跑一遍。

## 移植契约(改任何 bin 脚本都照这个)

1. 头部固定两行:`. "$(cd "$(dirname "$0")/.." && pwd)/lib/flow-lib.sh"` 然后 `flow_load_config`。路径全部从 `FLOW_*` 派生,**脚本里零绝对路径、零项目名**。
2. 必填只有 `FLOW_REPO`;其余有 kit 默认。项目要覆盖的解析串(门输出读数、传输层守卫、哨兵、fact-lint 词表)一律走 config 变量或 config 函数(`flow_gates` / `flow_sentinels`),不留在脚本里。
3. kit 自己定义的枚举与输出词(快照 / 活树-独占 / 禁入,RED / OK / FATAL)保持中文,是协议的一部分,不进 config。
4. `#!/bin/sh` 的脚本只用 POSIX(不许 `read -d ''`、数组、`PIPESTATUS`、`[[`);真需要 bash 就写 `#!/usr/bin/env bash`。哈希只经 `flow_sha256` / `flow_sha256_check`;临时文件只经 `flow_tmpdir`。
5. 判据纪律(协议 §J 的四条硬规矩)脚本自己也守:探测器输出不截断、RC 与命令同层捕获、`&&`/`||` 链里不放判据命令、比对前证明两侧不同源。
6. 欠账标记两种都认(圈码 ①–㊿ 与 `#N`),匹配一律 `LC_ALL=C grep -E "$(flow_mark_re)"`;状态集只有 `open` / `closed`。
7. 出错形态:参数错 RC=2 且 FATAL;判据红 RC=1 且行首 RED;绿 RC=0 且行首 OK / lint OK / PASS。末行固定可 grep。

## 命令对照(StockSteer-Mono `.claude/scripts/` 旧名 → 新名)

route-debts → `flow-route-debts` · render-debts-index → `flow-render-index` · render-dispatch → `flow-dispatch` · route-receipts → `flow-receipts` · tree-freeze → `flow-freeze` · freeze-manifest → `flow-manifest` · round-close → `flow-close` · six-gates → `flow-gates` · doc-budget → `flow-doc-budget` · fact-lint → `flow-fact-lint` · clear-map-debt → `flow-clear-map-debt` · merge-lane → `flow-merge-lane` · pr-merge-when-green → `flow-pr-merge` · post-commit hook 逻辑 → `flow-post-commit` · 新增 `flow-init` / `flow-config` / `flow-freshness`。
