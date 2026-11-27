# 守望

2026 开源游戏开发大赛参赛作品（Godot 4.7）。塔防骨架 + 牌组构筑：玩家在航路上布置防御塔，战斗内用费用建塔，关间用代币在商店购买塔牌与技能牌。

> 玩法口径以 `docs/plan-v1.0.pdf` 为准；世界观与叙事仅作包装，不作实现依据。

## 运行

1. 安装 **Godot 4.7**（标准版，非 .NET 版）。
2. 用 Godot 打开本目录（选中 `project.godot`）。
3. 首次打开会自动生成 `.godot/`（已在 `.gitignore` 中忽略，不要提交）。

## 目录说明

| 路径 | 内容 | 负责人 |
| --- | --- | --- |
| `scenes/battle/` | 战斗场景、航路、塔、敌船 | P1 |
| `scripts/{track,build_system,tower,enemy,wave_director,base}.gd` | 战斗逻辑 | P1 |
| `scripts/core/` | 状态单例、事件总线、音频总线 | P2 |
| `scripts/economy/` | 费用与商店 | P2 |
| `cards/`、`data/start_decks/` | 塔牌、技能牌、起始牌组 | P2 |
| `scenes/boot/`、`scenes/ui/` | 主菜单、面板、HUD、主题 | P3 |
| `scripts/flow.gd`、`scripts/ui/` | 流程、界面反馈、引导 | P3 |
| `docs/` | 策划案、分工方案、AI 声明、开发者日志 | 全员 |

## 协作

- 分支：`feat/p1-*` / `feat/p2-*` / `feat/p3-*`，缺陷修复 `fix/*`。
- `main` 已设保护，只允许 PR 合并（至少 1 个批准）。
- 里程碑打标签：`v0.1-d4`、`v0.2-d5`、`v1.0-submit`。
- 详细规则见 `docs/仓库搭建与协作规范.md`。

## 许可

- 代码：MIT（见 `LICENSE`）
- 美术、音频等素材：CC BY 4.0；第三方素材来源逐条登记于 `docs/AI使用与素材声明.md`
