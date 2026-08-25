# Cell War —— 桌游电子化（Godot）

[![tests](https://github.com/Kevinnb66699/SpringSense-2026-2027-Cell-War/actions/workflows/tests.yml/badge.svg)](https://github.com/Kevinnb66699/SpringSense-2026-2027-Cell-War/actions/workflows/tests.yml)

《Cell War》是一款免疫细胞 vs 癌细胞的对抗桌游（ver.0.98）。本仓库是其电子化版本，使用 **Godot 4** 引擎开发。

## 仓库结构

```
├── README.md                  本文件
├── docs/
│   ├── 游戏手册 ver.0.98.pdf   桌游原版规则手册
│   ├── 规则电子化说明.md        规则 → 代码的映射，以及所有规则解释/假设
│   └── obsidian/              由手册生成的细粒度 Obsidian 笔记库（125 篇，一概念一笔记）
├── tools/
│   └── draw_ver0.98/          原有的 Python 抽卡/世界事件脚本（桌面版辅助工具，保留存档）
└── game/                      Godot 4 工程（电子版游戏本体）
```

## 如何运行

1. 安装 [Godot 4.3+](https://godotengine.org/download)（标准版即可，无需 .NET 版）。
2. 打开 Godot → Import → 选择 `game/project.godot`。
3. 按 F5 运行。

## 游戏简介

- 4 或 6 名玩家，分为**免疫细胞**与**癌细胞**两个阵营，在 61 块组织构成的六边形棋盘上对抗。
- 共 20 个世界回合。结束时癌组织数量 ≥ 21（4 人局）/ 31（6 人局）则癌细胞阵营胜利，否则免疫细胞阵营胜利；若所有癌细胞死亡且无法复活，免疫细胞阵营立即胜利。
- 核心机制：掷骰移动、攻击与击退、感染/净化组织、固化、墙壁、卡池抽卡、世界事件、第 10 回合进化。

完整规则见 `docs/游戏手册 ver.0.98.pdf`；电子版对规则的具体实现与所有歧义处的解释见 `docs/规则电子化说明.md`。

## 电子版形态（v1）

- **人机对战**：你选择执免疫或癌症阵营（控制整个阵营），AI 用启发式策略操控对方（追击/逃跑/感染/筑墙）。
- **本地热座**：所有玩家共用一台电脑，按行动顺序轮流操作，与实体桌游体验一致。
- **观战演示**：双方均由 AI 操作，快速了解游戏流程。
- 窗口可任意拉伸/最大化，界面等比缩放。
- 联机对战、美术资源、音效为后续迭代方向。联机采用确定性锁步方案，接口已预留（决策归属字段、答案线格式、局面哈希与确定性测试），详见 `docs/联机设计.md`。

## 开发说明

- 引擎：Godot 4.x，语言：GDScript。
- `game/scripts/core/` 为纯规则逻辑（不依赖场景节点，便于测试与将来联机复用）；`game/scripts/ui/` 为界面层。
- 规则引擎按功能拆分模块：`cw_game.gd` 持有状态与总调度，具体流程分别在 `cw_setup / cw_world / cw_events / cw_turn / cw_movement / cw_combat / cw_cards`，改哪个功能就改对应文件。
