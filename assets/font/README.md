# 字体

| 文件 | 字体 | 许可 | 来源 |
| --- | --- | --- | --- |
| `NotoSansSC-Regular.otf` | Noto Sans SC（思源黑体简体中文子集）Regular | SIL Open Font License 1.1（可随游戏分发、可商用、需保留许可声明） | https://github.com/notofonts/noto-cjk |

## 为什么必须自带字体

Godot 4 的默认字体不含汉字，不显式指定字体时，界面上的中文会渲染成方块（豆腐块）。本项目在 `project.godot` 的 `[gui] theme/custom` 指向 `res://scenes/ui/theme/ui_theme.tres`，该 Theme 的 `default_font` 就是这里的字体，因此所有 Control 默认继承，不需要逐个节点设置。

## 换字体时怎么改

1. 新字体放进本目录
2. 改 `scenes/ui/theme/ui_theme.tres` 的 `ext_resource` 路径，或直接在 Godot 里替换
3. 不要同时留两份中文字体，会让包体无谓变大

## 提交《AI 使用与素材声明》时抄这段

> 字体：Noto Sans SC Regular，采用 SIL Open Font License 1.1，允许在游戏内嵌与分发，已保留原始许可信息。来源 notofonts/noto-cjk。
