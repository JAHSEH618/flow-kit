# flow-kit

[![smoke](https://github.com/JAHSEH618/flow-kit/actions/workflows/smoke.yml/badge.svg)](https://github.com/JAHSEH618/flow-kit/actions/workflows/smoke.yml) —— `tests/smoke.sh` 在 ubuntu(dash)/ macOS × C / UTF-8 四格跑,PR 红了不合。

四轮制(写 / 双轴审 / 改 / 复审)多 agent 工作流,打包成 Claude Code plugin。工作区只留两份文件:`.claude/flow.config.sh`(参数)与 `.claude/flow-local.md`(本项目实录)。

## 安装(本机,用户级)

```bash
claude plugin marketplace add ~/CodeSpace/flow-kit
```

```bash
claude plugin install flow-kit@flow-kit-local --scope user
```

装进一个工作区:在工作区根跑 `flow-init --repo <仓路径|.>`,或调 `/flow-kit:init` 走引导式。派单 / 复审 / 收口前读 `/flow-kit:protocol`。一批的编排方只在三个点动手(1.1.0):`flow-batch open <流程目录> <任务号> --seq <N> --plan <plan> <触面…>` 开批 → 每轮回件落了就 `flow-batch next <流程目录>`(它收上一轮、派开下一轮、印 Agent prompt;② 后收审方的 patch 跑微改通道,停在 `待裁决` 等你给 `--verdict N` 落笔;③④ 按需 —— 零阻塞零生产改动就直接收口)→ 末行 `收口` 时照抄它印的 `flow-close --wrap`,再 `flow-close --ship`。中断了 `flow-dispatch --resume`。agent 侧只剩:写回件、判据命令经 `flow-ev` 跑(1.0.0)。

## 升级

改了本仓后:先刷 marketplace,再用**限定名**更新,然后重启会话生效。裸名 `flow-kit` 会 not found。

```bash
claude plugin marketplace update flow-kit-local && claude plugin update flow-kit@flow-kit-local
```

## 布局

`bin/` 命令(前缀 `flow-`,启用后进 PATH)· `lib/` 共享库与模板 · `skills/protocol` 编排协议 · `skills/init` 安装向导 · `hooks/` SessionStart 新鲜度检查 · `examples/` 配置实例 · `tests/smoke.sh` 冒烟。细则见 [CLAUDE.md](CLAUDE.md)。
