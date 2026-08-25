# CLAUDE.md —— Cell War 项目 AI 协作规则

《Cell War》桌游电子化：Godot 4.5 stable + GDScript，61 格六边形棋盘，免疫 vs 癌细胞。
本项目多人协作、大量使用 AI 开发。**你必须遵循既有架构，而不是按自己的偏好开发。**

## 动手前必读

- **改任何代码前**：完整阅读 `docs/架构说明书.md`（模块地图、菜谱、禁止清单都在里面）
- 改游戏规则逻辑前：另读 `docs/规则电子化说明.md`（30 条规则裁决，不可私自推翻）
- 改 `game/scripts/core/` 前：另读 `docs/联机设计.md` 的确定性红线

## 十条铁律

1. `scripts/core/` 是纯逻辑：不挂节点、不碰 UI/输入、不 print（用 `game.log_line`）
2. 一切玩家决策走 `game.ask_option / ask_hex / ask_edge`（问答桥），who 传玩家对象或 `CWData.FACTION_*`
3. 一切游戏随机走 `game.rng`；禁用 `randi()/randf()/randomize()/Time.*/OS.*`（确定性测试会抓）
4. 改哪个功能去哪个文件：数值/文案→`cw_data.gd`；卡牌效果→`cw_cards.gd`；事件→`cw_events.gd`；
   战斗→`cw_combat.gd`；移动→`cw_movement.gd`；回合→`cw_turn.gd`；
   启发式 AI→`hybrid_bridge.gd`；MC 搜索 AI→`mc_bridge.gd`（先读 `docs/AI设计.md`）；
   界面布局/样式→`scenes/*.tscn` + `scenes/ui_theme.tres`（编辑器可视化改；改节点名先搜脚本 `%节点名`）；
   界面逻辑→`scripts/ui/`
5. 选项 value 字符串（"burn"/"roll"/"solidify"…）、卡牌/事件/进化 id、req 的 tag 是**语义键**，
   启发式 AI 靠它们决策——不要改名；部分 prompt 关键词也被 AI 依赖，改文案先搜 `hybrid_bridge.gd`
6. 新增影响规则的状态：`CWGame.state_hash()` 和 `CWSnapshot.capture/restore` **两处都加**；
   丢弃已结束对局前调 `game.dispose()`
7. GDScript 坑：`:=` 不能从 Variant 推断（显式标类型）；`true == 1`（用 `typeof`）；
   新 `class_name` 脚本必须先 `--import` 否则报 Identifier not declared；`.uid` 文件一起提交
8. 每次改动必须验证（`<godot>` = 本机 Godot 4.5 console 可执行文件）：
   ```bash
   <godot> --headless --path game --import
   <godot> --headless --path game -s tests/headless_test.gd   # 必须 ALL TESTS PASSED
   ```
   UI 改动还要真开窗口过一遍。bash 管道取退出码用 `${PIPESTATUS[0]}`
9. 提交：中文信息、一次只做一件事、每行改动可对应到当次任务（不做顺手重构/重命名/格式化）；
   **推送前先 `git pull --rebase`**（队友会直接往 main 推东西）
10. 禁止：引入插件/Autoload/C#、改 `CWData.OFFICIAL_LAYOUT`（对应实体比赛地图）、
    跳过测试推 main、为变绿而改测试、删改 docs 里的既有裁决

有疑问或想改架构：先在 `docs/` 或群里提出讨论，不要直接实现。
