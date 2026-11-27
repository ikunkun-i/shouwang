extends Control
## 主菜单。只把「点了哪个按钮」转交给 Flow，自己不做任何流程判断。
## 为什么菜单不判断「能不能开局」：能不能开局取决于牌组与解锁状态（P2），
## 菜单判断一次、Flow 再判断一次，两边迟早不一致；所以这里只转交。

func _ready() -> void:
	%StartButton.pressed.connect(_on_start_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	# 给键盘/手柄用户一个默认焦点，否则这套界面只能拿鼠标点。
	%StartButton.grab_focus()


func _on_start_pressed() -> void:
	# 具体去哪个场景由 Flow 决定，菜单不认识任何路径。
	Flow.start_new_run()


func _on_quit_pressed() -> void:
	# 直接退出。当前阶段没有需要落盘的进度，GameState 随进程结束丢弃是预期行为。
	get_tree().quit()
