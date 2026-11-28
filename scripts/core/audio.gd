extends Node
## 音频总线挂点：播放音效与背景音，统一音量档位。
##
## 由 P3 维护；P1、P2 只调用，不直接操作 AudioStreamPlayer 节点。
##
## 两条设计约束，写之前先说清：
## 1. 不自带音频资源。assets/audio/ 现在是空的，调用方（P1 的战斗、P2 的商店）
##    把 AudioStream 传进来，这里只负责「怎么播」，不负责「播什么」。
##    一旦这里写死路径，资源一改名，报错点就跑到音频层，很难查。
## 2. 总线在运行时创建，不依赖 project.godot 的 bus layout。
##    仓库里没有 default_bus_layout.tres，AudioServer 里根本没有 SFX/BGM 两条总线，
##    直接 get_bus_index("SFX") 会返回 -1，再 set_bus_volume_db(-1, x) 就是静默无效。
##    在 _ready 里按需补建，谁把这个 autoload 装到哪个工程里都能用。

const BUS_SFX := "SFX"
const BUS_BGM := "BGM"

## 音效播放器池大小。8 个够「一次命中叠三四个音效」的场景；
## 池子满了就抢最早那个，宁可截断一个旧音效，也不在战斗中途 new 节点（会卡帧）。
const SFX_POOL_SIZE := 8

## BGM 交叉淡入淡出的默认时长（秒）。0 就是硬切。
const BGM_FADE_TIME := 0.6

## 音效池。元素可能是 null 之前的占位——用 _make_player 统一创建。
var _sfx_players: Array[AudioStreamPlayer] = []
## 下一个要用的池位，轮转使用，天然分散「谁在响」。
var _sfx_cursor := 0

## 两路 BGM 播放器：一路在响、一路在等。交叉淡入淡出靠它俩互换。
var _bgm_players: Array[AudioStreamPlayer] = []
## 当前在响的那一路下标（0 或 1）。_bgm_players 为空时无意义。
var _bgm_active := 0
## 当前在响的 BGM 流，用于「同一首别重头再来」的判断。
var _bgm_stream: AudioStream = null
## 正在跑的淡出/淡入 tween。切换时先 kill 掉，否则两次切换的 tween 会互相拉扯音量。
var _bgm_tween: Tween = null


func _ready() -> void:
	# 暂停时 BGM 不该断，淡入淡出也该继续跑完；
	# 本节点不做任何轮询，设 ALWAYS 只是让 tween 在暂停时仍然推进。
	process_mode = Node.PROCESS_MODE_ALWAYS

	_ensure_bus(BUS_SFX)
	_ensure_bus(BUS_BGM)

	for i in SFX_POOL_SIZE:
		_sfx_players.append(_make_player(BUS_SFX, "SfxPlayer%d" % i))
	for i in 2:
		_bgm_players.append(_make_player(BUS_BGM, "BgmPlayer%d" % i))


# ---------------------------------------------------------------- 对外接口


## 播放一次性音效。
##
## stream 为空时 push_error 而不是静默 return：
## 「点了没声」是最难查的一类问题，宁可控制台红一行，也不要让人以为是音量没开。
func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		push_error("Audio.play_sfx: stream 为空，未播放")
		return
	if _sfx_players.is_empty():
		push_error("Audio.play_sfx: 播放器池尚未初始化（_ready 没跑？）")
		return

	var player := _pick_sfx_player()
	player.stream = stream
	player.volume_db = volume_db
	player.play()


## 切换背景音乐。
##
## 传进来的 stream 和当前在响的是同一个时直接返回：
## 场景切换会重跑 _ready，若不判重，每进一次战斗背景音乐就从头来一遍。
func play_bgm(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		push_error("Audio.play_bgm: stream 为空，未播放")
		return
	if _bgm_players.size() < 2:
		push_error("Audio.play_bgm: 播放器尚未初始化（_ready 没跑？）")
		return
	if stream == _bgm_stream and _bgm_players[_bgm_active].playing:
		return

	_bgm_stream = stream
	var from := _bgm_players[_bgm_active]
	var to := _bgm_players[1 - _bgm_active]
	_bgm_active = 1 - _bgm_active

	to.stream = stream
	to.volume_db = _fade_start_db(volume_db)
	to.play()

	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	_bgm_tween = create_tween()
	_bgm_tween.set_parallel(true)
	# 旧的一路淡到静音再停：直接 stop 会「咔」一声。
	_bgm_tween.tween_property(from, "volume_db", -60.0, BGM_FADE_TIME)
	_bgm_tween.tween_property(to, "volume_db", volume_db, BGM_FADE_TIME)
	_bgm_tween.chain().tween_callback(from.stop)


## 停掉背景音乐。
func stop_bgm(fade_time: float = BGM_FADE_TIME) -> void:
	_bgm_stream = null
	if _bgm_players.is_empty():
		return
	var from := _bgm_players[_bgm_active]
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	if fade_time <= 0.0:
		from.stop()
		return
	_bgm_tween = create_tween()
	_bgm_tween.tween_property(from, "volume_db", -60.0, fade_time)
	_bgm_tween.tween_callback(from.stop)


## 设置一条总线的音量（分贝）。供未来的设置界面调用。
## 总线不存在时返回 false，让调用方能区分「设成功了」和「总线名写错了」。
func set_bus_volume_db(bus_name: String, volume_db: float) -> bool:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		push_error("Audio.set_bus_volume_db: 总线上没有 %s" % bus_name)
		return false
	AudioServer.set_bus_volume_db(idx, volume_db)
	return true


# ---------------------------------------------------------------- 内部


## 轮流取一个音效播放器；池子全在响时抢当前游标那个（即最早分配出去的）。
func _pick_sfx_player() -> AudioStreamPlayer:
	var player := _sfx_players[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	return player


## 新建一个播放器并挂到本节点下。
## 为什么挂在 Audio 而不是场景里：autoload 不会随场景切换被释放，
## 音效播到一半切场景也不会被硬截断。
func _make_player(bus_name: String, node_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = bus_name
	add_child(player)
	return player


## 补建总线。已存在就跳过，不覆盖别人调好的音量。
func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	# 默认送到 Master。不写这一行，新建总线会挂在 Master 上但名字对不上，
	# 未来做「音效 70%、音乐 40%」的滑条时会发现调了没反应。
	AudioServer.set_bus_send(idx, &"Master")


## 淡入起始音量。-60dB 约等于听不见，从它开始升上来。
func _fade_start_db(target_db: float) -> float:
	# 目标本来就比 -60 还小（几乎静音）时，从 0 开始反而会先响一下。
	return -60.0 if target_db > -60.0 else 0.0
