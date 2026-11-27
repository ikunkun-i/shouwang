# 人员与分工

程序组三人，按系统分域，一人一条分支，互不覆盖。

| 昵称 | 域 | 分支 | 负责范围 | GitHub 账号 |
| --- | --- | --- | --- | --- |
| Siri | P1 战斗域 | `feat/p1-battle` | `scenes/battle/`、`scripts/{track,build_system,tower,enemy,wave_director,base}.gd`、`scripts/data/` | 待补 |
| 星辰 | P2 经济域 | `feat/p2-economy` | `scripts/core/`（状态单例、事件总线、音频总线）、`scripts/economy/`、`scripts/cards/`、`data/`、商店界面 | 1co1co1 |
| 坤坤 | P3 流程与交付 | `feat/p3-flow` | `scenes/boot/`、`scenes/ui/`、`scripts/flow.gd`、`scripts/ui/`、打包交付、仓库维护 | ikunkun-i |

## 职责边界

- P1 只产出“战斗事实”，其他域不得直接改塔、敌、基地的内部状态，只能读信号。
- P2 是唯一状态权威，只有它写 GameState 并广播信号。
- P3 负责从主菜单到退出的完整路径，且是队内唯一打包与出包的人；商店界面的业务逻辑仍归 P2，P3 只做外观与共享控件。
- 仓库所有者是坤坤（P3）：负责合并 PR、维护分支保护、AtomGit 同步。因此除文档类改动外，坤坤自己的代码也走 PR，由 Siri 或星辰批准。

## 非程序角色（来自初期分工稿）

| 角色 | 负责人 | 产出 |
| --- | --- | --- |
| 世界观 / 叙事主笔 | crescent-cat | `docs/worldbuilding-yongzhou.docx` 的定稿与包装文案 |
| 主策划（玩法收口） | 待确认 | 玩法口径维护，冲突时以 `docs/plan-v1.0.pdf` 为准 |

新增或调整分工，改本表并在群里同步，不要只口头说。
