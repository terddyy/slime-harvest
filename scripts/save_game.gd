extends Node
## Autoload "SaveGame": the one save file (user://save.json, JSON with a "version" field).
## Systems that have state (Game, Farm, Fences, Player, camera) register with a key and
## provide `to_save() -> Dictionary` and `from_save(data: Dictionary)`. Main registers them
## when the world is built. Saves at dawn, from the pause menu and when the window closes
## (web build: when the tab loses focus).
## A missing, damaged or other-version file counts as "no save": nothing is loaded.

const VERSION := 1
const DEFAULT_PATH := "user://save.json"

## Where the file lives. Tests point this somewhere else so they never touch the real save.
var path := DEFAULT_PATH
## Set by the title's Continue button; Main loads the save once the world is built.
var load_requested := false
## False for a co-op joiner: the farm belongs to the host, so a joiner never writes the file.
var write_enabled := true

var _systems := {}  # key -> Node (insertion order = load order)


func register(key: String, system: Node) -> void:
	_systems[key] = system


## Main calls this when it leaves the tree, so the title screen never saves.
func unregister_all() -> void:
	_systems.clear()
	write_enabled = true


func has_save() -> bool:
	return not read().is_empty()


func delete() -> void:
	DirAccess.remove_absolute(path)


## Writes every registered system. Returns false if nothing is registered or the write fails.
func save() -> bool:
	if _systems.is_empty() or not write_enabled:
		return false
	var sections := snapshot()
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": VERSION, "sections": sections}))
	file.close()
	return DirAccess.rename_absolute(temp_path, path) == OK


## The current state of every registered system (key -> Dictionary). Co-op sends this
## to a joiner; save() writes it to the file.
func snapshot() -> Dictionary:
	var sections := {}
	for key: String in _systems:
		sections[key] = (_systems[key] as Object).call("to_save")
	return sections


## The saved sections (key -> Dictionary), or {} when there is no usable save.
func read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()  # parse() instead of parse_string(): no error print for a damaged file
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary or parsed.get("version") != VERSION:
		return {}
	return SaveUtil.dict(parsed.get("sections"))


## Gives every registered system its saved data. Returns false when there is no save.
func load_game() -> bool:
	var sections := read()
	if sections.is_empty():
		return false
	apply(sections)
	return true


## Gives every registered system its data from `sections` (a saved file or a co-op snapshot).
func apply(sections: Dictionary) -> void:
	for key: String in _systems:
		if sections.has(key) and sections[key] is Dictionary:
			(_systems[key] as Object).call("from_save", sections[key])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()
	# A browser never sends the close request when the tab closes, so the web build also
	# saves whenever the tab loses focus or is hidden.
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and OS.has_feature("web"):
		save()
