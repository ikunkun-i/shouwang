extends Node
## 音频总线挂点：播放音效与背景音，统一音量档位。
##
## 由 P3 维护；P1、P2 只调用，不直接操作 AudioStreamPlayer 节点。

const BUS_SFX := "SFX"
const BUS_BGM := "BGM"


## 播放一次性音效。
func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	# TODO(P3): 用对象池复用 AudioStreamPlayer，避免每次分配。
	pass


## 切换背景音乐。
func play_bgm(stream: AudioStream, volume_db: float = 0.0) -> void:
	# TODO(P3): 交叉淡入淡出。
	pass
