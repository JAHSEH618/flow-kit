# 收口块与轮数账(照抄,逐项打勾;顺序固定)

```
0. 收口另起会话:状态档写完再开新会话做收口(编排方末轮上下文 429k;收口占它一半轮次)
1. 账本:①的追写草稿 + ④A 的三态表做 diff 审,落笔走 flow-ledger,不手写补丁:
   flow-ledger apply <④A回件> → 看 dry-run → flow-ledger apply <④A回件> --write   (「还」批量翻 closed)
   flow-ledger append <标记> "<一行>"   (追写:正文是人写的散文,机器不代笔)
   flow-ledger add --owner … --due … --touches … --title …   (立新条;号自动取)
   已还条目正文里的开口项单开新条;owner 不锚已收工任务;新条落接收位(flow-receipts 能扫到)
2. flow-render-index --write · flow-route-debts --lint
3. spec:任务节写「落地记录 <日期> · 收口」;历史句加注不改原文
4. 根文档:只改门读数数字与批次标签;叙事写项目的编年档
5. flow-gates --reset(命中缓存就别整跑)
6. flow-close <流程目录> <基线> <编排方申报清单(含账本 / spec / 根文档)> [after-hashes]
   —— 含规则书棘轮:flow-local.md 变长即 RED;本批退役的规矩逐字归档到 flow-local-archive.md
7. commit(消息 = 〇 正面结论 + 裁决号段 + 门 + 账)—— 单独一条命令,前面不串别的
8. flow-clear-map-debt --verdicts <④A 三态表文件> <commit>;剩下未勾的人判
9. push → gh pr create → flow-pr-merge <PR> --background(日志路径打印出来,合并结果最后核一眼)
10. 与 9 重叠做:memory(号段 / 门 / 进度 / 下一批从 N 起)+ flow-usage <流程目录> --write(轮数账轮次行自动填进 .usage.md)+ 固定开销行手填
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

- 编排固定开销 ≤ 1 h
- 轮内门整跑每轮 ≤ 1 次 + 收口 1 次(旧判据「总数 ≤3」的结构下限就是 4,判据本身错了)
- 不起独立收尾轮
- token 列首批记录作基线,之后只比不涨;「调用/轮」低于 1.5 的轴换模型或拆任务,「读批量」低于 2 的轴是没把读合进一个 Bash;单轴请求超 FLOW_TURN_CAP 就拆任务 —— 三条都不加纪律
