extends Node
## 暂停面板的自测场景（开发期用，不参与正式流程）。
##
## 为什么要单独一个预览场景：battle.tscn 属于 P1，现在还不存在，
## 暂停面板没有一个「战斗界面」可挂。若等 P1 才能验，这一项就只能拖到 D4 之后，
## 而暂停面板恰恰是「树暂停后按钮还能不能点」这种最容易写错的东西。
##
## 用法：F6 单独运行本场景，或 --headless 跑一遍看有没有脚本报错。

## 故意不写类型标注：pause_panel.tscn 的根节点是 CanvasLayer，
## 但 open()/close() 是它挂的脚本提供的，静态类型 CanvasLayer 上并不存在这两个方法，
## 写了类型反而编译不过。这里让它是 Variant，运行时按实际脚本解析。
@onready var _pause_panel = %PausePanel


func _ready() -> void:
	# 等两帧再操作：_ready 时子节点还没进树，grab_focus 会静默失败，
	# 看起来像「打开面板后焦点没设上」。
	await get_tree().process_frame
	await get_tree().process_frame

	print("PREVIEW: 打开前 paused = %s" % get_tree().paused)
	_pause_panel.open()
	print("PREVIEW: 打开后 paused = %s（应为 true）" % get_tree().paused)
	print("PREVIEW: 面板可见 = %s（应为 true）" % _pause_panel.get_node("Overlay").visible)

	# 关掉，证明 close() 能把 paused 复位。这个复位一旦漏了，
	# 下一个场景会以冻结状态加载，日志里却一行错都没有。
	_pause_panel.close()
	print("PREVIEW: 关闭后 paused = %s（应为 false）" % get_tree().paused)

	# 再打开一次，让人工看图 / 截图时能看到面板。
	_pause_panel.open()
