class_name GameSettings
extends RefCounted

enum Quality { LOW, BALANCED, HIGH }
const RESOLUTIONS: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]

var volume: float = 0.7
var shake: float = 0.35
var effects: float = 0.7
var fullscreen: bool = false
var quality: int = Quality.BALANCED
var resolution: int = 0


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
	quality = _choice(config.get_value("settings", "quality", quality), Quality.HIGH, quality)
	resolution = _choice(config.get_value("settings", "resolution", resolution), RESOLUTIONS.size() - 1, resolution)


func set_value(key: String, value: float) -> void:
	if not is_finite(value):
		return
	match key:
		"volume": volume = clampf(value, 0.0, 1.0)
		"shake": shake = clampf(value, 0.0, 1.0)
		"effects": effects = clampf(value, 0.0, 1.0)
		"fullscreen": fullscreen = value >= 0.5
		"quality": quality = clampi(roundi(value), 0, Quality.HIGH)
		"resolution": resolution = clampi(roundi(value), 0, RESOLUTIONS.size() - 1)


func save_settings(path: String = "user://settings.cfg") -> Error:
	var config := ConfigFile.new()
	config.set_value("settings", "volume", volume)
	config.set_value("settings", "shake", shake)
	config.set_value("settings", "effects", effects)
	config.set_value("settings", "fullscreen", fullscreen)
	config.set_value("settings", "quality", quality)
	config.set_value("settings", "resolution", resolution)
	return config.save(path)


func _number(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		return clampf(float(value), 0.0, 1.0) if is_finite(float(value)) else fallback
	return fallback


func _choice(value: Variant, maximum: int, fallback: int) -> int:
	return clampi(value, 0, maximum) if value is int else fallback
