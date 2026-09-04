# 收口块与轮数账(照抄,逐项打勾;顺序固定)

```
0. 收口另起会话:flow-round state <流程目录> 刷完事实段、手写区写完再开新会话做收口(编排方末轮上下文 429k;收口占它一半轮次)
1. flow-close --wrap <流程目录> <基线> <编排方申报清单(含账本 / spec / 根文档)> [after-hashes] [--task] [--plan] [--verdicts <④A 三态表>]
   —— 机械段一条命令:三态表 dry-run · 索引重渲 · 账本 lint · REQ 对账 · 门整跑(收口那一次)· 冻结核对 + 非空转 + 交付态哈希 · 预算 · 规则书棘轮 · 轮数账 --write · 状态档事实段
   末行 WRAP OK 才往下;RED 逐项看,规则书变长即 RED,本批退役的规矩逐字归档到 flow-local-archive.md
2. 账本(判断步):按 dry-run 做 diff 审 → flow-ledger apply <三态表> --write · append <标记> "<一行>" · add --owner … --due … --touches … --title …
   已还条目正文里的开口项单开新条;owner 不锚已收工任务;新条落接收位(flow-receipts 能扫到)
3. spec:任务节写「落地记录 <日期> · 收口」;历史句加注不改原文
4. 根文档:只改门读数数字与批次标签;叙事写项目的编年档
5. commit(消息 = 〇 正面结论 + 裁决号段 + 门 + 账)—— 单独一条命令,前面不串别的
6. flow-close --ship <commit> --subject "<PR 标题>" [--verdicts <④A 三态表>]
   —— clear-map-debt · push dev · gh pr create · flow-pr-merge --background(等 mergeStateStatus CLEAN 才合;日志末行 PR-MERGE DONE|BLOCKED);剩下未勾的 map-debt 人判
7. 与 6 重叠做:memory(号段 / 门 / 进度 / 下一批从 N 起)+ 轮数账固定开销行手填(墙钟归因 / 编排方独占关键路径 / 输出去向 / 卡顿已由 flow-usage 自动出)
```

## 轮数账模板(每批照填;轮次行 = flow-usage 生成,固定开销行手填,固定开销单列才看得出下次该砍哪)

```
| 项 | 时长 | token | 备注 |
|---|---|---|---|
| 开工清账 + 派单装配 | | — | map-debt 未勾条数 / flow-dispatch RC |
| ①写 | | | 起止 |
| ②A ‖ ②B | | | 起止(并行取长者) |
| ③改 | | | 回①本人 / 新起 |
| ④A ‖ ④B | | | 起止(并行取长者) |
| (收尾轮) | | | 起了就说明为何没折进③ |
| 轮间核对 × N | | — | flow-close --between 一键后应 ≤ 3 min/次 |
| 门整跑次数 | | — | 轮内每轮 ≤1 + 收口 1;缓存命中次数另记 |
| 收口 | | — | 账本 / spec / 根文档 / commit / PR |
| 编排固定开销合计 | | — | 判据 ≤ 1 h |
| 本批退役规矩数 | | — | ≥ 1;退役了哪条、做成了什么 |
```

## 检验判据(不达标只许退役规矩或修工具,不许加规矩)

- 编排方独占关键路径 ≤ 30 min(flow-usage 自动出;两批实测 33 / 53 min)
- 轮内门整跑每轮 ≤ 1 次 + 收口 1 次(旧判据「总数 ≤3」的结构下限就是 4,判据本身错了)
- 不起独立收尾轮
- token 列首批记录作基线,之后只比不涨;「调用/轮」低于 1.5 的轴换模型或拆任务,「读批量」低于 2 的轴是没把读合进一个 Bash;单会话请求超 FLOW_TURN_CAP 就拆任务(续轮单算)—— 三条都不加纪律
- 卡顿(单次工具 ≥ FLOW_STALL_SEC,输出正常)从账上扣掉再比:那是 harness 侧,不是 flow 的
