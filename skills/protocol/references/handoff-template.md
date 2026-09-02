# 写 / 改回件模板(①写 `01-write-handoff.md` · ③改 `03-fix-handoff.md`;整块照抄,逐项填;缺项 = 回件不合格)

边写边落。件内只贴末行读数 / 摘录 + `.evidence/` 路径,命令全量输出不进件(行与字节两条红线,`flow-doc-budget` 量)。

```
## 〇 · 改动索引表(首节;②③④ 按它跳读,不整读文件)
| 符号 / 文件 | 文件:行段 | 性质 | 对应 |
|---|---|---|---|
| `allocate()` | src/engine/alloc.ts:120–188 | 改 | REQ-P4-T2-03 |
| src/engine/alloc.test.ts | 1–96 | 新增 | REQ-P4-T2-03 |
| `legacyRound()` | src/engine/round.ts:40–71 | 删 | finding B-3 |
每个实改文件 ≥ 1 行;新增文件写整文件行段;性质只许 新增 / 改 / 删。③改轮「对应」列一律 finding 编号,反证顶回也占一行并带命令。

## 一 · 结论一行
交付 / 未交付;关键判据改坏跑过 N / M 条,0 红自报

## 甲栏 · 实测过的(每条:命令 + RC + 末行读数 / 摘录 + .evidence 路径;命令与 RC 同层捕获)
## 乙栏 · 未验推断(没有命令佐证的,一条都不许当结论用;核不了就写「核不了」)
## 丙栏 · 自报三处最没把握(①写必填;两条审查轴按它排优先级)
## 丁栏 · 账本追写草稿(每条触到的开放欠账一行:标记 · 还 / 追写 / 不动 · 一行证据;flow-route-debts 按实改集复跑的输出即行集)
## 戊栏 · 给 flow-local.md 的新实录(踩到就写)

## 收工读数(缺一即回件不合格)
flow-manifest verify 末行 + RC · flow-fact-lint verify 末行 + RC(新增 RED 零)· .after-<轮名>-hashes.txt 与 .declared-<轮名>.txt 的路径
整读过的文件清单(每个一行理由;没有就写「零整读」)
```
