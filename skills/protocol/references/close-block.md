# 收口块与轮数账(照抄,逐项打勾;顺序固定)

```
0. 收口另起会话:flow-round state <流程目录> 刷完事实段、手写区写完再开新会话做收口(编排方末轮上下文 429k;收口占它一半轮次)
1. flow-close --wrap <流程目录> <基线> <编排方申报清单(含账本 / spec plan / 根文档)> [after-hashes] [--task] [--plan] [--verdicts <④A 三态表>]
   —— 机械段一条命令:三态表 dry-run · 索引重渲 · 账本 lint · REQ 对账 · REQ 翻 done(对账绿才翻,plan 须在申报清单里)· 门整跑(收口那一次;印一行可照抄的门读数)
      · 冻结核对 + 非空转 + 交付态哈希 · 预算 · 规则书棘轮 · 轮数账 --write · 状态档事实段
   末行 WRAP OK 才往下,它后面印的就是剩余手工步(2–7),照它做;RED 逐项看,规则书变长即 RED
2. 账本(判断步):按 dry-run 做 diff 审 → flow-ledger apply <三态表> --write · append <标记> "<一行>" · add --owner … --due … --touches … --title … --body-file <正文文件>
   (正文多行一次落,整块带 `> ` 前缀也认;p4e 曾 add 只落机器头、正文再五次 python)已还条目正文里的开口项单开新条;owner 不锚已收工任务;新条落接收位(flow-receipts 能扫到)
3. spec:任务节写「落地记录 <日期> · 收口」+ 下一刀接收位;历史句加注不改原文;REQ 状态已由 --mark-done 翻好,不手改
4. 根文档:只改门读数与批次标签 —— wrap 印的「门读数(照抄进根文档…)」那一行照抄;叙事写项目的编年档
5. 规则书:flow-rulebook show 看行号 → flow-rulebook retire <行号> --section "<§X · 批次>" --reason "<一句>"(每批 ≥ 1 条;逐字搬,不经 shell)
6. commit(消息 = 〇 正面结论 + 裁决号段 + 门 + 账)—— 单独一条命令,前面不串别的
7. flow-close --ship <commit> --subject "<PR 标题>" [--verdicts <④A 三态表>] --dir <流程目录>
   —— clear-map-debt · push dev · gh pr create · flow-pr-merge --background(等 mergeStateStatus CLEAN 才合;日志末行 PR-MERGE DONE|BLOCKED)· flow-usage --write 重跑(窗含收口);剩下未勾的 map-debt 人判
8. 与 7 重叠做:memory(号段 / 门 / 进度 / 下一批从 N 起)+ 轮数账手填段填「本批退役规矩数」
```

## 轮数账(每批;全由 flow-usage 生成,手填段只剩一行)

轮次行(轮数 / 携带 / 输出 / 当量 / 调用每轮 / 读批量 / 模型)+ 墙钟归因(生成 / 工具 / 空等 / 卡顿)+ 固定开销(开工 / 轮间 × N / 收口 / 门整跑 · 缓存命中 / 独占合计)+ 编排方输出去向 + WARN(请求上限 / 读批量 / 卡顿 / 中断税 / 独占超线)
—— 都从 transcripts 算,窗从开工序起到收口末(--ship --dir 之后重跑才含 commit / PR)。手填曾把开工 11 min 估成 35、收口 16 估成 40,所以退役。
`.usage.md` 的生成段由 `<!-- flow:gen-* -->` 括起,重跑保留标记之后的手填段:

```
| 项 | 读数 | 备注 |
|---|---|---|
| 本批退役规矩数 | | ≥ 1;退役了哪条、做成了什么(flow-rulebook retire N 或 N.k) |
```

## 检验判据(不达标只许退役规矩或修工具,不许加规矩)

- 编排方独占关键路径 = 开工 + 轮间 + 收口 ≤ 30 min(flow-usage 全窗算;p4e 实测 35 = 9 + 11 + 13。旧窗只盖住编排方 46% 的请求,曾报 14 ✅)
- 轮内门整跑每轮 ≤ 1 次 + 收口 1 次(旧判据「总数 ≤3」的结构下限就是 4,判据本身错了)
- 不起独立收尾轮;④ 判零阻塞后的非生产尾巴走微改通道 `flow-micro <patch>... --face … --apply --freeze …`,不起 ③改二(p4e 那条尾巴 46 min)
- token 列首批记录作基线,之后只比不涨;「调用/轮」低于 1.5 的轴换模型或拆任务,「读批量」低于 2 的轴是没把读合进一个 Bash;单会话请求超 FLOW_TURN_CAP 就拆任务(续轮单算)—— 三条都不加纪律
- 卡顿(单次工具 ≥ FLOW_STALL_SEC,或 sub-agent 拿到工具结果后 ≥ 它无输出;上下文与输出都正常)从账上扣掉再比:那是 harness 侧,不是 flow 的;中断税行里只有「编排方接手 + 续轮装载」两段归 flow
