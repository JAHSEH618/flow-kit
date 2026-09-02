---
name: init
description: 把 flow-kit 装进当前工作区(单仓或多仓并排工作区都行):先无声体检,一次提问定范围,出一张提案确认后连续执行 flow-init,再帮用户把门命令填进 flow.config.sh。用户说「装 flow-kit」「这个项目也用四轮制」「初始化工作流」时调用。
---

# flow-kit 安装(引导式)

每一步都动真实文件,所以先看清现状、一次问清范围、提案确认后连续执行,不让确认变成十几次打断。全程幂等:`flow-init` 已有的不覆盖,重跑就是断点续跑。

## Phase 0 · 无声体检(不问)

从 cwd 向上找 `.claude/flow.config.sh`;记录:配置有无 · `flow-local.md` 有无 · 账本有无 · 各仓 `.git/hooks/post-commit` 是否含 `flow-post-commit` · 规格目录在不在、是否被 gitignore(`git check-ignore`)· 项目的门候选(`package.json` scripts / Makefile / `pyproject` / `pom.xml` / `build.gradle` 里 lint / typecheck / test 一类目标)· 主干分支名(`git symbolic-ref refs/remotes/origin/HEAD`,取不到默认 master)· 用户级已启用的插件与 MCP(`flow-settings` 没配时会把候选列出来;或读 `~/.claude/settings.json` 的 `enabledPlugins`、`~/.claude.json` 的 `mcpServers`)与项目语言(TS → typescript-lsp / vtsls;Java → jdtls-lsp;LSP 插件不占上下文,按语言留)。
全部就绪 → 报「已装好,无事可做」,建议 `flow-config --check`,结束。

## Phase 1 · 一次提问

用 AskUserQuestion 问(能同轮问的一起问):
- 布局:单仓(工作区根 = 仓根)还是多仓并排(工作区根在仓外)?多仓时哪一个仓是 `FLOW_REPO`?
- 账本路径与规格目录(给体检到的默认值)。
- 门:把体检到的候选列成有序清单让用户勾选、改命令(门是项目的事实,不替用户猜)。
- 会话瘦身:把用户级插件与 MCP 列成清单让用户勾「留」(默认勾:flow-kit、本项目语言的 LSP 插件、无上下文成本的 statusline 类;其余默认不勾)。为什么必问:开局上下文里插件 skill 清单与 MCP 工具表每个 sub-agent 每轮都付,而哪些用得上只有人知道。

## Phase 2 · 提案(普通文本,一次确认)

按行列出将写的文件与将执行的命令:`flow-init --ws … --repo … --ledger … --spec-dirs … --untracked … --main … --keep-plugins "…" --keep-mcp "…"`(两个 keep 都给,flow-init 才会写 `.claude/settings.local.json`),然后 `flow.config.sh` 里将填入的 `flow_gates` 与 `FLOW_FACT_LINT_ROOTS`,以及 git shim 落点(已有 hook 则追加一行)。一次 AskUserQuestion:照这个执行 / 去掉部分 / 只存档不执行。

## Phase 3 · 执行

1. `flow-init …`(打印每项 已有/已写)。
2. 把用户确认的门写进 `flow.config.sh` 的 `flow_gates`(用 Edit 改注释块为真实函数),填 `FLOW_FACT_LINT_ROOTS`。
3. `flow-config --check` 必须 RC=0(含 `flow-settings --check`);`flow-route-debts --lint` 必须 OK。
4. 若仓已有提交:提示下一次 commit 起 `flow-post-commit` 会记地图欠账队列;零提交的仓首个 commit 会跳过,属正常。
5. 在工作区根 CLAUDE.md 加一行指针(如无):「多 agent 批次:派单 / 复审 / 收口先调 `/flow-kit:protocol`;本地规矩在 `.claude/flow-local.md`」。这是唯一常驻上下文的一行,别多写。

## Phase 4 · 收尾

输出:写入 / 修改文件清单 · `flow-config` 的解析结果 · 下一步(第一批派单前读 `/flow-kit:protocol`,`flow-gates` 先手跑一次确认门都活)。
