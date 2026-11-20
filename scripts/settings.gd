class_name Settings
extends RefCounted
## Player settings: volumes, fullscreen and key bindings, saved in user://settings.cfg.
## Pure data + rules (no nodes, no autoloads) so tests/run_tests.gd can check it.
## Game owns the one instance (Game.settings); SettingsMenu edits it.

const PATH := "user://settings.cfg"

## Action name -> default keys. A key slot is a position in this list (slot 0 = main key).
const DEFAULT_BINDINGS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"use_tool": [KEY_SPACE, KEY_J],
	"interact": [KEY_E],
	"cycle_seed": [KEY_Q],
	"tool_1": [KEY_1],
	"tool_2": [KEY_2],
	"tool_3": [KEY_3],
	"tool_4": [KEY_4],
	"tool_5": [KEY_5],
	"tool_6": [KEY_6],
	"restart": [KEY_R],
	"skip_phase": [KEY_N],
	"zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
	"pause": [KEY_ESCAPE],
	"to_title": [KEY_T],
	"hide_tips": [KEY_F1],
	"goals": [KEY_G],
	"inventory": [KEY_TAB],
}
## Actions the player can rebind, in the order the settings menu lists them.
## "pause" is missing on purpose: Esc must always open the menu.
const ACTION_LABELS := {
	"move_up": "Move up",
	"move_down": "Move down",
	"move_left": "Move left",
	"move_right": "Move right",
	"use_tool": "Use tool",
	"interact": "Interact",
	"cycle_seed": "Next seed",
	"tool_1": "Hoe",
	"tool_2": "Watering can",
	"tool_3": "Seeds",
	"tool_4": "Sword",
	"tool_5": "Fence",
	"tool_6": "Sprinkler",
	"inventory": "Inventory",
	"goals": "Farm goals",
	"hide_tips": "Hide tips",
	"zoom_in": "Zoom in",
	"zoom_out": "Zoom out",
	"restart": "Restart",
	"to_title": "To title",
	"skip_phase": "Skip phase (debug)",
}
## Keys that can't be bound: Esc cancels/pauses, Enter confirms menu buttons.
const RESERVED_KEYS := [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]
## Short names for keys whose Godot name is long or unclear.
const KEY_NAMES := {
	KEY_EQUAL: "=",
	KEY_MINUS: "-",
	KEY_KP_ADD: "Num +",
	KEY_KP_SUBTRACT: "Num -",
	KEY_ESCAPE: "Esc",
	KEY_UP: "Up",
	KEY_DOWN: "Down",
	KEY_LEFT: "Left",
	KEY_RIGHT: "Right",
}
const VOLUME_BUSES := ["master", "music", "sfx"]

var master := 1.0  # 0.0 - 1.0 each
var music := 1.0
var sfx := 1.0
var fullscreen := false
## Action -> Array[int] of keys, same slots as DEFAULT_BINDINGS.
var bindings: Dictionary = {}


func _init() -> void:
	reset_bindings()


func reset_bindings() -> void:
	bindings = {}
	for action: String in DEFAULT_BINDINGS:
		bindings[action] = (DEFAULT_BINDINGS[action] as Array).duplicate()


func volume(bus: String) -> float:
	return get(bus)


func set_volume(bus: String, value: float) -> void:
	if bus in VOLUME_BUSES:
		set(bus, clampf(value, 0.0, 1.0))


## Key of an action in a slot, or -1 when there is none.
func key_for(action: String, slot := 0) -> int:
	var keys: Array = bindings.get(action, [])
	return keys[slot] if slot >= 0 and slot < keys.size() else -1


## The action (and slot) that uses a key, or {} when it is free.
func owner_of(key: int) -> Dictionary:
	for action: String in bindings:
		var slot := (bindings[action] as Array).find(key)
		if slot != -1:
			return {"action": action, "slot": slot}
	return {}


## Binds `key` to a slot of an action. Returns {"ok": bool, "message": String}.
## A key that another slot already uses is swapped: that slot gets this slot's old key.
func rebind(action: String, slot: int, key: int) -> Dictionary:
	if not ACTION_LABELS.has(action) or slot < 0 or slot >= (bindings[action] as Array).size():
		return {"ok": false, "message": "That key can't be changed."}
	if key in RESERVED_KEYS:
		return {"ok": false, "message": "%s is reserved." % key_label(key)}
	var old_key := key_for(action, slot)
	if key == old_key:
		return {"ok": true, "message": ""}
	var other := owner_of(key)
	if other.is_empty():
		bindings[action][slot] = key
		return {"ok": true, "message": ""}
	var other_action: String = other["action"]
	if not ACTION_LABELS.has(other_action):
		return {"ok": false, "message": "%s is used by %s." % [key_label(key), other_action]}
	bindings[other_action][other["slot"]] = old_key
	bindings[action][slot] = key
	return {"ok": true, "message": "%s swapped with %s." % [key_label(key), ACTION_LABELS[other_action]]}


## Replaces the {action} placeholders of a text with the current main keys, and {move}
## with the four move keys (used by How to Play).
func fill_keys(template: String) -> String:
	var names := {"move": " ".join([
		key_label(key_for("move_up")),
		key_label(key_for("move_left")),
		key_label(key_for("move_down")),
		key_label(key_for("move_right")),
	])}
	for action: String in bindings:
		names[action] = key_label(key_for(action))
	return template.format(names)


static func key_label(key: int) -> String:
	if key < 0:
		return "-"
	if KEY_NAMES.has(key):
		return KEY_NAMES[key]
	return OS.get_keycode_string(key as Key)


## Saves to `path`. Returns true when the file was written.
func save_file(path := PATH) -> bool:
	var config := ConfigFile.new()
	for bus in VOLUME_BUSES:
		config.set_value("audio", bus, volume(bus))
	config.set_value("display", "fullscreen", fullscreen)
	for action: String in bindings:
		config.set_value("keys", action, bindings[action])
	return config.save(path) == OK


## Loads from `path`. A missing or damaged file (or value) leaves the defaults.
func load_file(path := PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for bus in VOLUME_BUSES:
		var value: Variant = config.get_value("audio", bus, 1.0)
		set_volume(bus, float(value) if typeof(value) in [TYPE_FLOAT, TYPE_INT] else 1.0)
	fullscreen = config.get_value("display", "fullscreen", false) == true
	var loaded := {}
	for action: String in DEFAULT_BINDINGS:
		var keys: Variant = config.get_value("keys", action, [])  # [] = missing, fails the check
		if ACTION_LABELS.has(action) and _valid_keys(keys, (DEFAULT_BINDINGS[action] as Array).size()):
			loaded[action] = (keys as Array).duplicate()
		else:
			loaded[action] = (DEFAULT_BINDINGS[action] as Array).duplicate()
	if _has_duplicate_keys(loaded):
		return  # a hand-edited file with clashing keys: keep the defaults
	bindings = loaded


func _valid_keys(keys: Variant, size: int) -> bool:
	if typeof(keys) != TYPE_ARRAY or (keys as Array).size() != size:
		return false
	for key: Variant in keys:
		if typeof(key) != TYPE_INT or key < 0 or key in RESERVED_KEYS:
			return false
	return true


func _has_duplicate_keys(all_bindings: Dictionary) -> bool:
	var seen := {}
	for action: String in all_bindings:
		for key: int in all_bindings[action]:
			if seen.has(key):
				return true
			seen[key] = true
	return false
