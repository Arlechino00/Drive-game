class_name GameSettings
extends RefCounted

var volume: float = 0.7
var shake: float = 0.35
var effects: float = 0.7
var fullscreen: bool = false


func load_settings(path: String = "user://settings.cfg") -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	volume = _number(config.get_value("settings", "volume", volume), volume)
	shake = _number(config.get_value("settings", "shake", shake), shake)
	effects = _number(config.get_value("settings", "effects", effects), effects)
	var saved_fullscreen: Variant = config.get_value("settings", "fullscreen", fullscreen)
	if saved_fullscreen is bool:
		fullscreen = saved_fullscreen


func set_value(key: String, value: float) -> void:
	match key:
		"volume": volume = clampf(value, 0.0, 1.0)
		"shake": shake = clampf(value, 0.0, 1.0)
		"effects": effects = clampf(value, 0.0, 1.0)
		"fullscreen": fullscreen = value >= 0.5


func save_settings(path: String = "user://settings.cfg") -> Error:
	var config := ConfigFile.new()
	config.set_value("settings", "volume", volume)
	config.set_value("settings", "shake", shake)
	config.set_value("settings", "effects", effects)
	config.set_value("settings", "fullscreen", fullscreen)
	return config.save(path)


func _number(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		return clampf(float(value), 0.0, 1.0) if is_finite(float(value)) else fallback
	return fallback
