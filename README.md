# flow-kit

四轮制(写 / 双轴审 / 改 / 复审)多 agent 工作流,打包成 Claude Code plugin。工作区只留两份文件:`.claude/flow.config.sh`(参数)与 `.claude/flow-local.md`(本项目实录)。

## 安装(本机,用户级)

```bash
claude plugin marketplace add ~/CodeSpace/flow-kit
```

```bash
claude plugin install flow-kit@flow-kit-local --scope user
```

装进一个工作区:在工作区根跑 `flow-init --repo <仓路径|.>`,或调 `/flow-kit:init` 走引导式。派单 / 复审 / 收口前读 `/flow-kit:protocol`。一轮的编排方三条命令:`flow-dispatch --dir` 派单 → `flow-round open` 开工 → `flow-round close` 收工交接口;中断了 `flow-dispatch --resume`;收口 `flow-close --wrap` 与 `--ship`。

## 升级

改了本仓后:先刷 marketplace,再用**限定名**更新,然后重启会话生效。裸名 `flow-kit` 会 not found。

```bash
claude plugin marketplace update flow-kit-local && claude plugin update flow-kit@flow-kit-local
```

## 布局

`bin/` 命令(前缀 `flow-`,启用后进 PATH)· `lib/` 共享库与模板 · `skills/protocol` 编排协议 · `skills/init` 安装向导 · `hooks/` SessionStart 新鲜度检查 · `examples/` 配置实例 · `tests/smoke.sh` 冒烟。细则见 [CLAUDE.md](CLAUDE.md)。
