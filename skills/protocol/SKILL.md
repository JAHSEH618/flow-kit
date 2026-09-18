---
name: protocol
description: 写 + 双轴审 + 机械复验(③ 改 / ④ 复审按需)的多 agent 工作流编排协议。开一个批次、收任何一轮、收口时都先读本 skill;编排方一批只在三个点动手(flow-batch open · 有 finding 要裁决 · 收口),派单 / 回件模板由 kit 生成(references/dispatch-block.md · handoff-template.md · review-template.md 是它印的骨架),收口照 references/close-block.md;每条规矩的实测与病根在 references/why.md(编排方按需读,agent 不读)。用户说「派单」「起一批」「收口」「复审」「四轮制」「flow-batch」时调用。
---

# flow-kit 编排协议

纪律只写成散文等于没写:派单块由 `flow-dispatch` 生成(回件模板整块印在里面),轮间过渡由 `flow-batch` 串,收口块整块照抄。本文件只放规矩 + 一句为什么;`→ why §x` 指向 `references/why.md` 的实测与病根,编排方按需读。项目实录在工作区 `.claude/flow-local.md`。命令前缀 `flow-`,说明书是头注。

**1.0.0 定型的 agent 面向接口**:收工只写回件;判据命令一律经 `flow-ev`;独占轮另跑一次门整跑、快照轮另跑 `shasum -c`。此后加判据只动 `flow-round close`,不动派单散文、不给 agent 加命令。
**1.1.0 定型的编排方面向接口**:一批只在三个点动手 —— `flow-batch open` 开批 · `flow-batch next` 停在 `待裁决` 时给 `--verdict N` · 末行 `收口` 时照抄它印的 `flow-close --wrap`。其余过渡(close → dispatch → open → prompt)全由 `flow-batch next` 按目录结构判并串起来,零状态文件。

## 0 · 硬不变量(不进 config,装进任何项目都不能关)

1. **写 + 审 + 机械复验**:①写 → ②双轴审(A 对外事实 ‖ B 对内闭包,零共享推理)→ 微改通道(审方的 patch 由 kit 落笔并复跑 oracle)→ **③改 只在有「阻塞」或通道不收(无 patch / 超上限 / 缺头)的 finding 时起,④ 只在树上落了生产改动时起,面 = 那份改动**(③ 〇表 ∪ 微改 prod 行;一轴,形制 = 活树-独占 · 库独占)。档位由 `flow-batch` 从目录结构判(档 A ①② · 档 B ①②④ · 档 C ①②③④)。砍两条 ② 轴与「有生产改动就复验」不行:已记账的失败形态压倒性是「全程没有红」(轴随对象是按对象判不派,不是砍:`FLOW_AXIS_BY_OBJECT=1` 才开,默认关)。
2. **写≠审**:审的 agent 不参与写作、不继承写作时的推理。反例:spec 里「只准三个库」与「要用一个时区库」隔两行,自审绿。
3. **树冻结靠哈希**:`flow-round open` 打基线并核上一轮交付态,`flow-round close` verify(含测试锁)全绿后打交付态哈希;变异走「副本 → 改坏 → 跑 → 复原 → 比 sha」。反例:规格目录被 gitignore,`git status` 单轴枚举漏了一份 spec。
4. **agent 零 git 写,提交归人**。反例:并行支停在基线,`git merge-tree` 比两个相同的东西,空预演恒绿。
5. **判据分级 fail-closed**:不标级的按阻塞;拿不准从阻塞。

## 1 · 轮次与角色

| 轮 | 谁 | 回件(两栏制:实测过的 / 未验推断) |
|---|---|---|
| ①写 | 1 个 agent | `01-write-handoff.md`(首节〇表 = 申报清单;丁栏 = 逐欠账三态表,close 抽成 `.verdicts-①写.md`)+ `.steps-①写.md` |
| ②A ‖ ②B | 2 个 agent,并行 | `02a-review.md` / `02b-review.md`(丙栏每条附 patch,可含生产行) |
| ③改(按需) | 另起 agent;只在 ② 有阻塞或通道不收时起(`FLOW_FIX_BY_WRITER=1` 只在宿主真有 SendMessage 时用,Claude Code 没有) | `03-fix-handoff.md`(〇表每行挂 finding 号) |
| ④(按需) | 1 个 agent,一轴 diff 审(活树-独占 · 库独占);只在树上落了生产改动时起 | `04-review.md`(面 = ③ 〇表 ∪ 微改 prod 行;三态表不归它) |

件名归 `flow-batch` 起,认领按件里的内容(回件首行 `# <轮名> 回件`)。收工件只有回件:申报由 `flow-round close` 从〇表派生(〇表路径 ∪ 先前轮清单;例外列 `裁决-N` → 申报行尾),交付态哈希在全部判据绿之后由 kit 打,收工末态落 `.evidence/<轮名>-close.txt`。→ why §1a

- **①写**:测绿;自报三处最没把握;丁栏 = 逐欠账三态表(每条触到的开放欠账一行:还 / 追写 / 不动 + 证据,`flow-ledger apply` 直接吃);不跑变异电池;步骤账第 0 步是整体设计,之后按 open REQ 一条一步。→ why §1b
- **②A 对外事实轴**:只读快照(开工与收工各对上一轮 `.after` 跑一次 `shasum -c`),零变异,不跑 build / db;引证逐字开文件核,数字独立复算。**②B 对内闭包轴**:活树 + 库独占;自洽、依赖闭包、自设变异找 0 红、第二份拼写 grep;build 与集成归它。后轴不读前轴回件。
- **轴随对象**(`FLOW_AXIS_BY_OBJECT=1` 才开,默认关):① 〇表纯代码(零 `*.md`)且 ①写 派单待填段的裁决全带随行判据(零裁决也算)⟹ `flow-batch next` 只派 ②B(②A 的对象 —— 裁决 / 事实句 / 引证 —— 已由 close 机械跑或本批没有);任一不满足照旧两轴,末行点名哪条。先跑几批看 ②A 在裁决机械化之后还抓不抓得到东西,再开。→ why §3f
- **② 后先走微改通道再决定派不派 ③**(`flow-batch next` 自动):两轴 patch 作一个流核(`flow-micro … --face .face-①写.txt --freeze <最新 .after>`),冲突 FATAL 整批落回 ③。`MICRO OK` 停在 `待裁决`,编排方 `--verdict <N>` 落笔,kit 复跑每条 repro oracle(不符整流回退)。两份丙栏零「阻塞」且通道收下 ⟹ 跳 ③:申报有 prod 行 → 派 ④(只审那份 diff),否则直接收口;否则派 ③,③ 从重打后的交付态起,只剩生产项。→ why §1c
- **③改**:拿两份回件 + 用户裁决;每行改动追到 finding 编号;**可带反证顶回**(〇表性质写 顶回,带 `ev:<名>`),判定权在复审。派单必写核心库写权限:「只许 shell」或「核心库限 <文件 / 性质>」。
- **④ diff 审**(一轴;活树 + 库独占;`flow-dispatch --round ④` 自动取面 = ③ 〇表路径 ∪ 申报 prod 行,印「必查行段」):对面内行段自设变异 · 门整跑 · 复跑 ② 丙栏 oracle(kit 已跑的 micro-* 不重跑)· 「做不到」型断言找反例 · 事实句三层 —— 都只对 diff。三态表归 ①写 丁栏(旧 ④A 的两件事分流)。→ why §1d
- **微改通道**(② 后与 ④ 后同一套):审轮丙栏每条必闭附可 `git apply` 的 patch(`.evidence/<轮名>-micro-<裁决号>.patch`,头两行 `# repro: <命令> → RC=<n> [末行含 <子串>]` 与 `# ev:<名>`)。`flow-micro` 从 patch 量:**只数非测试新增行** · 性质由路径与改动行核(测试文件 / `*.md` / 改动行全是注释 ⟹ 非生产)· 面内按 `.face-<写轮名>.txt` · **生产行单列一桶**(上限 `FLOW_MICRO_PROD_LINES`,0 = 不收;收时 repro / ev 头缺一即 RED,申报行尾 `micro prod`)。`MICRO OK` ⟹ `--apply --verdict N` 落笔,kit **复跑每条 repro**(RC / 末行子串不符 ⟹ 整流回退)、重打冻结件(旧件 `.pre-N`)、追加申报;面外 / 非测试新增 > `FLOW_MICRO_FIX_LINES` / 生产超上限或缺头 ⟹ 整批走 ③。**没附 patch 的条目一律不算微改。**→ why §1e
- **折轮**:不阻塞条 ≤ `FLOW_FOLD_MAX` 且全在③写权限面内 ⟹ ③同轮清、④一并验。
- **步骤账与续轮**:只 ①写 有 `.steps-①写.md`;②③④ 的断点是回件已落的节 + `flow-ev` 的账(状态档事实段每个未收工轮印一行接手点,与 `--resume` 同源)。中断后 `flow-dispatch --resume <原派单> --dir <流程目录>`,不手写。**续轮不是新轮**:不再 `flow-round open`,轮名由 `--resume` 从原派单取,收工仍 `flow-batch next`(它 close 原轮名)。→ why §1f
- **判据命令一律经 `flow-ev`**:`flow-ev <流程目录> <轮名> <名> -- <命令>` 落全量、记账(`.evidence/<轮名>-log.tsv`)、屏上只印末 N 行 + RC;甲栏每条一行判词(close 判 判词行数 = log 行数),丙栏每条引 `ev:<名>`(close 判 log 里有行)。一个名一份证据。→ why §1g
- **回件边写边落**,但回件长度就是墙钟:预算判自写字节(`FLOW_DOC_BUDGET_SELF`),真正判红的是热路径节 = 〇 + 丙栏(`FLOW_DOC_BUDGET_HOTPATH`,close 只判本轮那份)。→ why §1h
- **一次响应只发得出一个工具块**:省往返靠一条 Bash 串多条命令;「调用/轮」记在模型上(< 1.5 换模型或拆任务),「读批量」记在纪律上(< 2 是没合并,`flow-usage` WARN)。→ why §1i
- **后续轮按〇表跳读**;整读一个文件要在回件里给一行理由。**编排方只读〇节 + 丙栏**(三态表由 kit 抽、`flow-ledger` 吃,不用读)。
- **换模型先对照,两个方向都要**:`flow-review-diff <原版> <影子>` 比丙栏;原版独有为空才许换便宜的,「原版」可以是存档的 gold,改 review-template 前也对一次;留贵的也要证。→ why §1j
- **轮间交接口一键**:`flow-batch next` 串 `flow-round close`(派生申报 → between → 裁决随行判据(写 / 改轮)→ 步骤账 / 回件六判 / 丁栏 → 全绿冻结 → 状态档 → 收工末态)与 `flow-round open`(①写 才跑 fact-lint / 预算 → 核上一轮 .after → baseline → 状态档)。判据归批两端:路由复跑 / REQ 对账只在写 / 改轮,审轮的 between 只剩树判据,快照轮零判据。
- **闭环转达要交代库的归属**:④B 发回③时写明④B 是否已停;复验归提出那条的轴,在干净窗口跑。
- 「做不到 / 不可达」型断言:复审必须主动找反例并列出找过的路径,并写明射程。

## 2 · 分级

| 级 | 什么 | 处置 |
|---|---|---|
| 阻塞 | 缺门 / 门假绿 / 生产行为错 / 违反用户裁决 / 合并会破坏树 | 挡合并,当轮闭 |
| 不阻塞 | 树上注释说了假话(自指数 / 出处句 / 全称句)· 措辞 · 引文面 | 不挡合并、不单独起轮;微改通道或折轮清完;**收口前必须清完** |
| 记账 | 边界外同族残留 · 触面外发现 | 立账,本批不做 |

「不阻塞」≠「不做」,= 不单独起轮;清不完的只能显式改判记账,不许静默滚下批。→ why §2

## 3 · 派单(照抄 `references/dispatch-block.md`)

- **树权限**三选一:快照 / 活树-独占 / 禁入(只读 agent 一律快照)。**库权限**三选一:独占 / 只读 / 禁用(库是单点)。→ why §3a
- **写权限面**:许写 = 触面,由 `flow-dispatch` 印(close 判 本轮〇表路径 ⊆ 面,例外走〇表「例外」列);**禁写 / 严重级 / 边界 / ③ 核心库权限由 kit 印默认**(禁写 = 许写之外全部;严重级三档;边界 = `git ls-files -- <触面…>`;③ 只许 shell),改档才在待填段追加;**裁决号段**跨批累加,`flow-batch` 按代 +100 错开(并行的 ②A ‖ ②B 不撞号)。
- **欠账必读与必读骨架由 `flow-dispatch` 生成**(上一轮回件按首行认领、账本行区间、flow-local);欠账必读只给改树的轮(①③),审轮只印账本路径一行;手写段只加裁决与必查,不复述。触面参数仓库相对。owner 欠账 > `FLOW_DEBT_CAP` ⟹ 拆任务或 `--cap-ok <理由>`。→ why §3b
- **裁决带随行命令**:待填段一条一行 `【裁决 N】<文> → 判据 <命令> → RC=<n> [末行含 <子串>]`;写 / 改轮 `flow-round close` 经 `flow-ev` 跑(不符 RED;无判据只 WARN,仍归审方核);①写 之后的派单由 kit 同源抄入 ①写 那份的裁决行,只写一次。→ why §3f
- **边界给「类的枚举命令」,不给「实例清单」**;实例清单只当已知阳性用。
- **派单前顺序固定**:清账 → spec 落位 → `flow-batch open <目录> <任务号> --seq <N> --plan <plan> <触面…>`(它跑 lint → receipts → dispatch → open,印 prompt);之后每轮回件落了就 `flow-batch next`。baseline 之后编排方对仓内文件零编辑。→ why §3c
- **CARRY 进派单前对树核一次**,或显式标「未核线索,先核再做」。
- **收工件全是 dotfile**,「流程目录里没有冻结件」先 `ls -a`。`.after-<轮>-hashes.txt` 只覆盖该轮申报的文件,两份做差集不是实改集。快照轮 close 不冻、不核活树(状态档印 `⊘快照不冻`),②A ‖ ②B 谁先收都行;`.evidence/<轮>-close.txt` 末行是该轮收工末态,`flow-batch` 按它判已收、不重收。
- **接收位**:任务书声称「已覆盖」之前跑 `flow-receipts <plan> <任务号>`(三轴:节内 · 节外 · 跨件 —— 别的 plan 落给它的账也列;`RECEIPTS N/A` 是本任务零标记,不是错)。
- **派单落文件,编排方零 heredoc**;生成段自带 plan 任务节选(①写正文按 `FLOW_DISPATCH_EXCERPT_BYTES` 封顶,②③④ 只 outline + REQ 行)、回件模板全文、门名、flow-ev 写法、必读骨架。→ why §3d
- **并行支**四条隔离缺一不可:gitignore 件手工拷进去;引证一律读主树;第二支零 DB 面;文件层不相交,账本归主树支。支合并单独成批(`--lane-merge`),用 `flow-merge-lane plan|apply`,不用 `git merge-tree`。

## 4 · 判据纪律

**四条硬规矩(照做,不解释)**:① 探测器输出不许截断,不许 `| tail / head / grep` 之后据此下结论;② 退出码与命令同层捕获,不隔管道取 `$?`;③ `&&` / `||` 链里不放判据命令;④ 比对前先证明两侧不同源,空比对恒绿。一句话:下结论前问「我看的是被测对象,还是我这条命令的产物?」`flow-ev` 把 ①② 做成了结构性事实。

- **非空转**:凡拿「零命中 / 全绿」下结论的扫描,先在一个**另造的**已知阳性上跑一次,必须出非零;锚类的头词,不锚那一句。
- **算了 ≠ 判了**:甲栏判词行数 = log 行数(close 判);两个本该相等的数同一行写差值,差 ≠ 0 未解释 = 红。
- **六个假绿轴**逐个过:参数 · 模式 · 字形(中文数字)· 措辞 · 范围(全仓要 `command grep` 或显式带规格目录)· 增量状态(清产物连 tsbuildinfo 一起清)。
- **变异六守卫**(②B / ④B;config 有 `mutate` 门的仓审轴只判幸存变异体,六守卫不适用)见 dispatch-block「变异纪律」。传输层:`FLOW_INFRA_FAIL_RE` 命中 > 0 判 INFRA_FAIL 弃读数。
- **行为断言的载体是门不是注释**:能变成断言的变成一道会红的门;变不成的写成可一跳验证的指针;只剩数字的每个数挂它的命令。→ why §4a
- **事实句 == 随行命令**,三层:存在性 · 等价性 · 相关性。被数集合 = 该段全部句子,先枚举再分类。→ why §4b
- **证据源封闭**:只认树、上游 spec、本批流程目录。flow-* 与门的末行固定可 grep:判读 = 末行 + 同层 RC,全量落 `.evidence/`。→ why §4c
- **门定义变了要重打基线**,差值分两个方向写。
- **写文档 / 注释的轮次三禁**:自指的数 · 出处句 · 全称句。改法**只删不写**。→ why §4d

## 5 · 收口(照抄 `references/close-block.md`)

- `flow-close --wrap` 一条命令做机械段(WRAP OK 后印剩余手工步),`flow-close --ship <commit> --subject <标题> --dir <流程目录>` 做提交后四步并重跑轮数账。判断步归编排方。→ why §5a
- **账本**:①写 丁栏的三态表(kit 抽成 `.verdicts-①写.md`,`--wrap` 默认取它)⟹ 编排方只做 diff 审;落笔一律走 `flow-ledger`。已还条目里的开口项单开新条;owner 不锚已收工任务;新条落接收位。→ why §5b
- **收口同会话**:请求数超 `FLOW_TURN_CAP`(`flow-usage` WARN)才另起会话;`flow-batch` 之后编排方一批 ≤12 请求,「末轮上下文 429k」的病根不再成立。→ why §5c
- **轮数账**全由 `flow-usage --write` 生成,零手填;token 当量批间只比不涨。输出列是唯一指向墙钟的那一列。→ why §5d
- **检验判据**:编排方独占关键路径 ≤ 30 min · 轮内门整跑每轮 ≤ 1 次 + 收口 1 次 · 不起独立收尾轮 · 单会话请求 ≤ `FLOW_TURN_CAP` · 读批量 ≥ 2 · sub-agent 开销请求(仪式 / 读 kit / 打回件)≤ 15% · 卡顿扣掉再比。不达标只许退役规矩或修工具,不许加规矩。→ why §5e
- **规矩棘轮反向**:`flow-local.md` 字节只许降(变长即 RED)—— 棘轮才是判据,退役是条件触发:`--wrap` 报规则书变长才 `flow-rulebook retire <行号>[.<子句号>] --section "<§X · 批次>" --reason "<一句>"`,不再每批仪式性退一条。→ why §5f

## 6 · 中断、恢复、影子时间

- 中断优先 graceful drain:发「立刻把状态写进状态档后停」。硬杀后 = 只读账目重建员跑快照:路由复跑 + 接收位复跑 + 冻结 verify + 状态档第一栏逐条对树。
- 状态档 `00-ORCH-STATE.md` 是中断点专用件;事实段由 `flow-round` 生成在 `<!-- flow:gen-* -->` 段里(轮表 · 轮次计划 · 每个未收工轮的接手点 · 下一步 `flow-batch next`),**手写区只放裁决**(号段 / 改档 / 扩面理由)—— 派单与接手点由 kit 生成,不抄。
- 续轮派单不手写:`flow-dispatch --resume`。先对树核:通知的 result 只带首句,watchdog 判 failed 也不代表没干活。→ why §6
- 影子时间只做依赖已封闭的活;瓶颈轮的正确姿势是等。任何「唤回」通路先探针,拿到回音才许写「推荐」。

## 7 · 账本体例

- 每条欠账 = 一行机器头 + 条目正文:`<!-- debt:N mark:#N status:open|closed owner:<任务号> due:<任务号或日期> touches:<仓库相对路径前缀,逗号分隔> title:<一句> -->`,下一行 `> #N <正文>`。标记新号一律 `#N`;历史圈码 ①–㊿ 兼容。状态只有 open / closed。
- 索引块是生成物(`flow-render-index --write`),勿手改;`flow-freshness` 核索引 hash 与账本开放集一致。开放条目多到几 KB 时用 `FLOW_INDEX_DOC` 把它搬出常驻文件。
- 改账本后 `flow-route-debts --lint`。

## 8 · 工具速查

编排方一批的命令就这几条,`<>` 内的文件参数一律绝对路径;其余命令(`flow-dispatch` / `flow-round` / `flow-micro` / `flow-freeze` / `flow-manifest` / `flow-changed` / `flow-gates` / `flow-fact-lint` / `flow-doc-budget` / `flow-render-index` / `flow-clear-map-debt` / `flow-pr-merge` / `flow-merge-lane` / `flow-post-commit` / `flow-init` / `flow-config` / `flow-freshness`)由 `flow-batch` / `flow-close` 内部调用或只在排障与非标批次时手跑,说明书是各自的头注。agent 面向的只有 `flow-ev`、独占轮经它跑的 `flow-gates --reset`、快照轮的 `shasum -c`、①写 的 `flow-step done`。

| 命令 | 用法 | 何时 |
|---|---|---|
| `flow-batch` | `open <流程目录> <任务号> --seq <N> [--plan <plan>] [--db 独占\|只读\|禁用] [--core <面>] [--cap-ok <理由>] <触面…>` · `next <流程目录> [--verdict <N>] [--task] [--plan] [--seq] [--core]` | 开批;每轮回件落了就 next(末行 `BATCH NEXT: <轮…>\|待裁决\|收口`) |
| `flow-dispatch` | `--resume <原派单> --dir <流程目录>`(单步派单:`<任务号> --tree … --db … --seq <N> --round <轮名> --dir <目录> [--face-from] … <触面…>`) | 续轮;非标批次手派 |
| `flow-round` | `state <流程目录>`(单步:`open\|close <流程目录> <轮名> [--task] [--plan]`) | 刷状态档;排障时单步开工 / 收工 |
| `flow-ev` | `flow-ev <流程目录> <轮名> <名> [--show N\|all] -- <命令…>` | agent 跑任何判据命令 |
| `flow-micro` | `flow-micro <patch…> --face <.face-<写轮名>.txt> [--freeze <最新 .after> --apply --verdict <N>]` | `flow-batch next` 自动跑;手跑只在排障 |
| `flow-step` | `flow-step init\|add\|done\|show <流程目录> ①写 …` | ①写 轮内每步 |
| `flow-route-debts` | `flow-route-debts <任务号或触面…>` · `--lint` | 派单 / 改账本后 |
| `flow-receipts` · `flow-trace` | `flow-receipts <plan> <任务号>` · `flow-trace <plan> <任务号> [--mark-done]` | 任务书覆盖声明前;收口(`--wrap` 自动跑) |
| `flow-close` | `--wrap <流程目录> <基线> <申报> [after] [--task] [--plan] [--verdicts <表>]` · `--ship <commit> --subject <标题> [--verdicts] --dir <流程目录>` | 收口机械段 / 提交后四步 |
| `flow-ledger` | `apply <三态表> [--write]` · `close <标记> [--note]` · `append <标记> <行>` · `touches <标记> <a,b>` · `add --owner --due --touches --title [--body-file <正文\|->]` | 收口改账本;三态表的唯一解析器 |
| `flow-usage` | `flow-usage <流程目录> [--write]` | 收口(`--wrap` 与 `--ship --dir` 自动跑) |
| `flow-rulebook` | `show [行号]` · `retire <行号>[.<子句号>] --section "<§X · 批次>" --reason "<一句>"` | `--wrap` 报规则书变长时退役(条件触发) |
| `flow-review-diff` | `flow-review-diff <原版回件> <影子回件>` | 改任一轴的模型前 |
