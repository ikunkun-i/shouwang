extends CanvasLayer
## 暂停面板 + 退出确认。
##
## 为什么根节点是 CanvasLayer 而不是 Control：暂停时要盖住整个战斗画面，
## 包括 HUD 自己的 layer=10。用一个更高的 layer（100）就不用跟任何人的层级吵架。
##
## 为什么 process_mode 必须是 ALWAYS：暂停的本质是 get_tree().paused = true，
## 这会把树上所有节点一起冻住——包括这个面板自己。不设 ALWAYS，暂停之后就
## 再也点不动「继续」，玩家只能 Alt+F4。这是暂停面板最容易犯的错。
##
## 本面板不写任何游戏状态，也不碰 GameState；「回主菜单」「重开」都只是转交 Flow，
## 让 Flow 决定该 reset 还是该保留。面板自己判断进度去留，就会和 Flow 各判一次。

## 盖在所有战斗 UI 之上的层号。HUD 是 10，这里留足余量。
const PAUSE_LAYER := 100

## 打开时的淡入秒数。设为 0 可关掉动画（低配机上淡入反而显得卡）。
const FADE_TIME := 0.12

## 面板当前是否打开。用它做守卫，避免 ESC 连按时 open/close 反复切。
var _is_open := false

## 确认框点「确定」之后要执行的动作。用 StringName 而不是 Callable，
## 是因为 Callable 存下来后如果目标节点被释放，调用时会报「已释放对象」，
## 而字符串只会走到 match 的 default 分支，可控。
var _pending_action: StringName = &""

@onready var _overlay: Control = %Overlay
@onready var _confirm: Control = %Confirm
@onready var _resume_button: Button = %ResumeButton
@onready var _restart_button: Button = %RestartButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _quit_game_button: Button = %QuitGameButton
@onready var _confirm_yes: Button = %ConfirmYes
@onready var _confirm_no: Button = %ConfirmNo


func _ready() -> void:
	layer = PAUSE_LAYER
	# 再设一次：场景文件里已经写了，但这里写死可以防止有人复制本场景后
	# 忘了改 process_mode，导致暂停后按钮点不动这类「看起来像引擎 bug」的问题。
	process_mode = Node.PROCESS_MODE_ALWAYS

	_overlay.visible = false
	_confirm.visible = false

	_resume_button.pressed.connect(_on_resume_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_quit_game_button.pressed.connect(_on_quit_game_pressed)
	_confirm_yes.pressed.connect(_on_confirm_yes_pressed)
	_confirm_no.pressed.connect(_on_confirm_no_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# 确认框开着时，ESC 先关确认框，而不是直接把游戏恢复起来：
	# 玩家按 ESC 的意图多半是「我刚点错了」，不该顺手让游戏跑起来。
	if _confirm.visible:
		_close_confirm()
	else:
		if _is_open:
			close()
		else:
			open()
	# 吃掉这次 ESC，避免战斗里别人再拿它做一件事（比如取消建塔）。
	get_viewport().set_input_as_handled()


## 打开暂停面板。public 是为了让「暂停按钮」或调试脚本也能直接调。
func open() -> void:
	if _is_open:
		return
	_is_open = true
	_overlay.visible = true
	_confirm.visible = false
	# 先暂停再抢焦点：顺序反过来的话，焦点可能在暂停生效前被别的节点抢走，
	# 结果就是「暂停了但键盘按不到任何按钮」。
	get_tree().paused = true
	_resume_button.grab_focus()
	if FADE_TIME > 0.0:
		_overlay.modulate.a = 0.0
		# 不加 set_pause_mode：tween 默认绑定在创建它的节点上，
		# 本节点是 ALWAYS，所以树暂停时它照常跑。
		create_tween().tween_property(_overlay, "modulate:a", 1.0, FADE_TIME)


## 关闭并恢复游戏。
func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_overlay.visible = false
	_confirm.visible = false
	_pending_action = &""
	# 无条件置 false：本面板是唯一有权暂停的节点（没有别的 autoload 会暂停），
	# 所以这里不需要「记住进来之前是不是暂停的」。
	get_tree().paused = false


# ---------------------------------------------------------------- 按钮回调


func _on_resume_pressed() -> void:
	close()


func _on_restart_pressed() -> void:
	# 「重新开始本局」按 plan v2.0 的「一次失败会结束本轮挑战」，
	# 是整局清零回到选牌组，不是重开这一关。清零的职责在 Flow.restart_run()。
	_leave_tree_to(func() -> void: Flow.restart_run())


func _on_main_menu_pressed() -> void:
	_ask_confirm(&"main_menu")


func _on_quit_game_pressed() -> void:
	_ask_confirm(&"quit_game")


func _on_confirm_no_pressed() -> void:
	_close_confirm()
	# 焦点还给「回到主菜单」而不是「继续」：玩家刚否掉的是这一个操作，
	# 接着多半是想改选另一项，而不是直接开打。
	_main_menu_button.grab_focus()


func _on_confirm_yes_pressed() -> void:
	var action := _pending_action
	_pending_action = &""
	_close_confirm()
	match action:
		&"main_menu":
			_leave_tree_to(func() -> void: Flow.go_to_main_menu())
		&"quit_game":
			# 退出整局游戏不需要先解除暂停，进程直接结束。
			get_tree().quit()
		_:
			push_error("PausePanel: 确认动作未知（%s），什么也没做" % action)


# ---------------------------------------------------------------- 内部


## 清掉暂停状态并把界面藏起来，然后执行跳转。
##
## 为什么要单独一个函数：change_scene 会把本节点一起释放，如果在释放前
## 忘了把 get_tree().paused 置回 false，新场景会以「冻结」状态加载——
## 表现为「回主菜单后点不动任何按钮」，而且日志里一行错都没有。
func _leave_tree_to(action: Callable) -> void:
	_is_open = false
	_overlay.visible = false
	_confirm.visible = false
	get_tree().paused = false
	action.call()


func _ask_confirm(action: StringName) -> void:
	_pending_action = action
	_confirm.visible = true
	# 默认焦点放在「取消」上：误触 ESC 或连按回车时，代价小的一侧应该是默认。
	_confirm_no.grab_focus()


func _close_confirm() -> void:
	_confirm.visible = false
	_pending_action = &""
