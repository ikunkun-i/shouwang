class_name JsonConfig
extends RefCounted
## `data/` 下 JSON 配置的统一读取入口。
##
## 为什么要有这一层：Godot 的 JSON 解析返回的是 float，直接 `int(dict["hp"])` 散落在
## 各处会漏写；配置改了路径也只改一处。所有 P2 的脚本都通过它读配置，不要自己 FileAccess。
##
## 用法：
##   var cfg := JsonConfig.load_dict("res://data/economy.json")
##   var fee := JsonConfig.get_int(cfg, "fee/initial_fee", 0)

## 按路径缓存解析结果：同一个文件在一次运行里只读一次。
static var _cache: Dictionary = {}


## 读一个 JSON 文件，返回 Dictionary。文件缺失或格式错误时返回空字典并报错。
static func load_dict(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]

	if not FileAccess.file_exists(path):
		push_error("JsonConfig: 配置文件不存在 %s" % path)
		return {}

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("JsonConfig: 配置文件为空 %s" % path)
		return {}

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JsonConfig: %s 不是合法的 JSON 对象" % path)
		return {}

	_cache[path] = parsed
	return parsed


## 丢弃缓存，用于改完配置后热重载。
static func clear_cache() -> void:
	_cache.clear()


## 按 "a/b/c" 路径取子字典，取不到返回空字典。
static func get_dict(source: Dictionary, path: String, fallback: Dictionary = {}) -> Dictionary:
	var value: Variant = _walk(source, path)
	if typeof(value) == TYPE_DICTIONARY:
		return value as Dictionary
	return fallback


## 按路径取整数。JSON 里的数字都是 float，这里统一转 int。
static func get_int(source: Dictionary, path: String, fallback: int = 0) -> int:
	var value: Variant = _walk(source, path)
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return int(value)
		TYPE_STRING:
			var text: String = value
			return text.to_int() if text.is_valid_int() else fallback
		_:
			return fallback


## 按路径取浮点数。
static func get_float(source: Dictionary, path: String, fallback: float = 0.0) -> float:
	var value: Variant = _walk(source, path)
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		TYPE_STRING:
			var text: String = value
			return text.to_float() if text.is_valid_float() else fallback
		_:
			return fallback


## 按路径取布尔值。
static func get_bool(source: Dictionary, path: String, fallback: bool = false) -> bool:
	var value: Variant = _walk(source, path)
	if typeof(value) == TYPE_BOOL:
		return value as bool
	return fallback


## 按路径取字符串。
static func get_string(source: Dictionary, path: String, fallback: String = "") -> String:
	var value: Variant = _walk(source, path)
	if typeof(value) == TYPE_STRING:
		return value as String
	return fallback


## 按路径取数组。
static func get_array(source: Dictionary, path: String, fallback: Array = []) -> Array:
	var value: Variant = _walk(source, path)
	if typeof(value) == TYPE_ARRAY:
		return value as Array
	return fallback


static func _walk(source: Dictionary, path: String) -> Variant:
	if path.is_empty():
		return source
	var current: Variant = source
	for key in path.split("/"):
		if typeof(current) != TYPE_DICTIONARY:
			return null
		var dict: Dictionary = current
		if not dict.has(key):
			return null
		current = dict[key]
	return current
