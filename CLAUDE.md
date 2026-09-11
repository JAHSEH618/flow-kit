# flow-kit

四轮制(写 / 双轴审 / 改 / 复审)多 agent 工作流的 Claude Code plugin。跨项目复用;工作区只留 `.claude/flow.config.sh`(参数)与 `.claude/flow-local.md`(本项目实录)。

## 地图

- `bin/` —— 全部命令,前缀 `flow-`,plugin 启用后进 Bash PATH,按名调用不写路径。每个脚本头注 = 它的说明书。编排方一轮:`flow-dispatch --dir` → `flow-round open` → (agent) → `flow-round close`;② / ④ 后 `flow-micro`;收口 `flow-close --wrap|--ship`;退役 `flow-rulebook`。agent 面向的只有 `flow-ev`(判据命令的唯一通道,1.0.0)、独占轮经它跑的 `flow-gates --reset`、快照轮的 `shasum -c`、①写 的 `flow-step done`。版本记事在 CHANGELOG.md。
- `lib/flow-lib.sh` —— 唯一共享库:找配置(从 cwd 向上找 `.claude/flow.config.sh`,找不到 FATAL)、可移植 sha256、实改集 git 轴枚举(`flow_changed_paths`)、冻结(`flow_freeze_to`)、回件认领 / 〇表解析 / 派生申报(`flow_find_handoff` / `flow_handoff_paths` / `flow_derive_declared`,1.0.0)、欠账标记与 REQ-ID 模式(`flow_mark_re` / `flow_req_re`)、机器头字段提取、kit 自身根目录 `FLOW_KIT_DIR`。
- `skills/protocol/` —— 编排协议 SKILL.md(只留规矩 + `→ why §x`);`references/` 里是照抄用的模板(派单块 + 三行 prompt / 写改回件 / 复审回件 / 收口块 / 三态表 / 轮数账)与 `why.md`(每条规矩的实测与病根,编排方按需读,agent 不读)。
- `skills/init/` —— 把 kit 装进一个工作区:写 config、装 git shim、建流程目录、建账本骨架、按 FLOW_KEEP_* 收窄会话(`flow-settings` 写 `.claude/settings.local.json`:关掉本项目不用的插件与用户级 MCP;实测开局 44k token 里 CLAUDE.md 只占 10k,其余是插件 skill 清单与工具表,sub-agent 每轮重付)。
- `hooks/hooks.json` —— SessionStart 新鲜度检查(`flow-freshness`,全绿静默)。
- `examples/stocksteer/flow.config.sh` —— 配置全字段说明书兼实例。
- `tests/smoke.sh` —— 临时 git 仓上把每条命令跑一遍。

## 移植契约(改任何 bin 脚本都照这个)

1. 头部固定两行:`. "$(cd "$(dirname "$0")/.." && pwd)/lib/flow-lib.sh"` 然后 `flow_load_config`。路径全部从 `FLOW_*` 派生,**脚本里零绝对路径、零项目名**。例外只有四个,都是有意的:`flow-freshness` 与 `flow-post-commit` 先 `flow_find_ws`,找不到静默退出(hook 不许挡会话 / 挡提交);`flow-init` 不 load(它在造 config);`flow-pr-merge` 先处理 `--help`。库会把自己的 `bin/` 前置进 PATH,同胞命令按裸名调用。
2. 必填只有 `FLOW_REPO`;其余有 kit 默认。项目要覆盖的解析串(门输出读数、传输层守卫、哨兵、fact-lint 词表)一律走 config 变量或 config 函数(`flow_gates` / `flow_sentinels`),不留在脚本里。
3. kit 自己定义的枚举与输出词(快照 / 活树-独占 / 禁入,RED / OK / FATAL)保持中文,是协议的一部分,不进 config。生成段标记 `<!-- flow:gen-begin -->` / `<!-- flow:gen-end -->` 同理:`flow-dispatch` 与 `flow-round state` 打、`flow-doc-budget` 认,改一边就要改另一边(预算判的是**自写字节** = 总字节 − 生成段)。轮级约定文件名(`.manifest-baseline-<轮名>.txt` / `.declared-<轮名>.txt`(1.0.0 起 kit 派生,带 `# declared ·` 头)/ `.after-<轮名>-hashes.txt`(kit 冻结;`flow-micro` 备份件 `<名>.pre-<N>`、`flow-close --wrap` 就地重打前的备份件 `<名>.pre-wrap`,1.0.1)/ `.steps-①写.md` / `.face-<轮名>.txt` / `.evidence/<轮名>-*.txt` / `.evidence/<轮名>-log.tsv`)由 `flow-dispatch --dir` 印进派单、`flow-round` / `flow-ev` / `flow-micro` 按名派生,两侧同源,改一边就要改另一边。**热路径的 md 件(派单 / 回件)不在此列** —— 件名归编排方随手起,所以 `flow-round` 按件里的内容认领(派单看生成段的「轮次 / 模型」行、回件看首行 `# <轮名> 回件`,两份回件模板写死了这个形状),不按件名前缀猜;猜的那条退路要把格子标成 ⚠glob猜。
4. `#!/bin/sh` 的脚本只用 POSIX(不许 `read -d ''`、数组、`PIPESTATUS`、`[[`);真需要 bash 就写 `#!/usr/bin/env bash`。哈希只经 `flow_sha256` / `flow_sha256_check`;临时文件只经 `flow_tmpdir`;解析路径的 git 调用一律 `-c core.quotepath=false`(否则中文路径成八进制转义,静默对不上);多行值不进 `awk -v`(BSD awk 报 newline in string 后吐空集),走 ENVIRON。
5. 判据纪律(协议 §J 的四条硬规矩)脚本自己也守:探测器输出不截断、RC 与命令同层捕获、`&&`/`||` 链里不放判据命令、比对前证明两侧不同源。
6. 欠账标记两种都认(圈码 ①–㊿ 与 `#N`),匹配一律 `LC_ALL=C grep -E "$(flow_mark_re)"`;状态集只有 `open` / `closed`。
7. 出错形态:参数错 RC=2 且 FATAL;判据红 RC=1 且行首 RED;绿 RC=0 且行首 OK / lint OK / PASS。末行固定可 grep。RC=3 是**「这条判据在本仓不适用 / 这个任务过载」**的第三态,不是判据红,调用方按 info 处理:`flow-dispatch` 的 owner 欠账或 open REQ 超上限(拆任务或 `--cap-ok`)· `flow-trace` 整份 plan 零 REQ-ID(末行 `TRACE N/A`,0.7.1)。凡加 RC=3 的地方,「不适用」与「没扫到」必须能分开判(§J0),判据取全局不取局部。
8. kit 自己的记账件(队列 / fact-lint 基线 / 流程目录 / 门缓存)落在仓内时不算任何一轮的实改集:实改集 git 轴一律经 `flow_changed_paths`(内含 `flow_filter_kit_owned`),且调用方同层捕获其 RC,失败不许当空集;门命令里要它就 `flow-changed`,不许自拼 `git status`。
9. **每条质量判据只在一处跑,由不写代码的一方跑**(0.9.0):轮收工的判据全在 `flow-round close`(派生申报 → `flow-close --between`:verify(含树身份 + 测试锁)· 非空转 · 假话门 · 越面 · 路由 · REQ 对账 · 预算 → 全绿冻结 → 回件六判),上一轮交付态在 `flow-round open` 核,收口在 `--wrap`。派单里让 agent 自跑的那些命令是给它自己的提示,不是判据;判据的例外只走一条通道 —— 申报行尾 `# 裁决-N`。**每加一条机械判据就退一段派单散文**:`tests/smoke.sh` 里 `GEN_CAP` 是派单生成段字节的棘轮(量法排除 `flow:tpl` 段),只许往下改。
10. **agent 面向的接口定型于 1.0.0,新判据只加在 close 一侧**:agent 收工只写回件(〇表第二列 = 路径,例外列 = 裁决号);判据命令一律经 `flow-ev`(全量 + 账 + 末行);独占轮另跑一次门整跑、快照轮另跑 `shasum -c`;①写 另有步骤账。申报由 `flow-round close` 从〇表派生、冻结在全绿后由 kit 打、上一轮交付态在 `flow-round open` 核。要加一条质量判据,加在 `flow-round close`(读回件 / log.tsv / 树),**不许**往派单散文里加一句、不许给 agent 加一条命令 —— 三批实测 agent 侧流程开销占请求三成,每一条都是这样长出来的。回件模板改了形状(〇表列、甲栏体例)要同步改 `flow_handoff_paths` 与 close 的判词计数,两侧同源(契约 3 同理)。

## 命令对照(StockSteer-Mono `.claude/scripts/` 旧名 → 新名)

route-debts → `flow-route-debts` · render-debts-index → `flow-render-index` · render-dispatch → `flow-dispatch` · route-receipts → `flow-receipts` · tree-freeze → `flow-freeze`(壳,主体 `flow_freeze_to`)· freeze-manifest → `flow-manifest` · round-close → `flow-close` · six-gates → `flow-gates` · doc-budget → `flow-doc-budget` · fact-lint → `flow-fact-lint` · clear-map-debt → `flow-clear-map-debt` · merge-lane → `flow-merge-lane` · pr-merge-when-green → `flow-pr-merge` · post-commit hook 逻辑 → `flow-post-commit` · 新增 `flow-init` / `flow-config` / `flow-freshness` / `flow-settings` / `flow-trace` / `flow-usage` / `flow-review-diff` / `flow-ledger`(账本增删改,并且是 ④A 三态表的唯一解析器 —— 判定格实际写作 `**还**`,谁再写一份正则谁就 FATAL)/ `flow-step`(①写 步骤账)/ `flow-round`(轮开工 / 收工交接口 / 状态档事实段)/ `flow-rulebook`(规则书退役)/ `flow-micro`(微改通道)/ `flow-changed`(实改集给门命令)/ `flow-ev`(1.0.0,agent 跑判据命令的唯一通道)。
