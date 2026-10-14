extends RefCounted

# Dictionaries are exported GDScript resources, so packaged builds need no
# loose files. Numeric HUD formatting uses cached templates, not file reads.
const EN: Dictionary = preload("res://localization/en.gd").TEXT
const RO: Dictionary = preload("res://localization/ro.gd").TEXT
static var _language: String = "en"
static var _reverse: Dictionary = {}


static func dictionary(language: String) -> Dictionary:
	return RO if language == "ro" else EN


static func set_language(language: String) -> void:
	_language = "ro" if language == "ro" else "en"
	TranslationServer.set_locale(_language)
	_reverse.clear()
	for key in dictionary(_language):
		_reverse[dictionary(_language)[key]] = key


static func language_index() -> int:
	return 1 if _language == "ro" else 0


static func text(key: String, values: Array = []) -> String:
	var template: String = dictionary(_language).get(key, EN.get(key, key))
	return template if values.is_empty() else template % values


static func bind(node: Node, property: String, value: String) -> void:
	if _reverse.is_empty():
		set_language(_language)
	node.set(property, value)
	if _reverse.has(value):
		node.set_meta("locale_" + property, [_reverse[value], value])


static func refresh(node: Node) -> void:
	# Only untouched static captions are refreshed here. Dynamic text is replayed
	# from the owning UI's current state, preserving score, modal and run state.
	for property in ["text", "placeholder_text", "tooltip_text"]:
		var metadata: String = "locale_" + property
		if node.has_meta(metadata):
			var binding: Array = node.get_meta(metadata)
			if node.get(property) == binding[1]:
				var translated := text(binding[0])
				node.set(property, translated)
				node.set_meta(metadata, [binding[0], translated])
	for child in node.get_children():
		refresh(child)


static func key_for_text(value: String) -> String:
	if _reverse.is_empty():
		set_language(_language)
	return _reverse.get(value, value)



static func translate_message(english: String) -> String:
	# Compatibility for status/error text stored by existing persistence services.
	# This runs only when a dialog/error opens, never in gameplay's frame loop.
	var key: Variant = EN.find_key(english)
	if key == null:
		key = RO.find_key(english)
	if key != null:
		return text(str(key))
	if "\n" in english:
		var lines := english.split("\n")
		for index in range(lines.size()):
			lines[index] = translate_message(lines[index])
		return "\n".join(lines)
	return english
