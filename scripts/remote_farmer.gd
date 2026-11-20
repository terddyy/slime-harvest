class_name RemoteFarmer
extends Node2D
## Another player's farmer, drawn from the same layered sprites as Player. It has no physics and
## does nothing by itself: CoopSession feeds it the position, facing and animation of the real
## player at about 15 Hz, and it glides toward them. The shirt colour and the name tag tell
## players apart. The node's position is the feet, like Player.

const SHIRT_LAYER := 3  # index in Player.BODY_LAYERS ("Chest/Farmer_Shirt/...")
const SMOOTHING := 14.0  # how quickly the sprite catches up with the last reported position
## Farther than this from the target (e.g. the first report) the farmer jumps instead of gliding.
const SNAP_DISTANCE := 96.0
const NAME_COLOR := Color(1, 1, 1)

var player_id := 0
var player_name := ""
var _target := Vector2.ZERO
var _facing := Vector2.DOWN
var _anim := "idle"
var _anim_time := 0.0
var _has_state := false
var _layers: Array[Sprite2D] = []
var _name_label := Label.new()


func setup(id: int, display_name: String) -> void:
	player_id = id
	player_name = display_name
	name = "Remote%d" % id
	_name_label.text = display_name


func _ready() -> void:
	var body := Node2D.new()
	body.position = Vector2(0, -8)  # feet are 8 px below the frame centre, same as Player
	add_child(body)
	for path: String in Player.BODY_LAYERS:
		var layer := Sprite2D.new()
		layer.texture = load(Player.BODY_DIR + path)
		layer.hframes = Player.COLUMNS
		layer.vframes = Player.ROWS
		body.add_child(layer)
		_layers.append(layer)
	_layers[SHIRT_LAYER].modulate = CoopRules.tint(player_id)

	_name_label.add_theme_font_size_override("font_size", 6)
	_name_label.add_theme_color_override("font_color", NAME_COLOR)
	_name_label.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05))
	_name_label.add_theme_constant_override("outline_size", 3)
	_name_label.custom_minimum_size = Vector2(60, 0)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.position = Vector2(-30, -46)
	add_child(_name_label)
	_draw_frame()


## The newest report from the real player.
func set_state(world_position: Vector2, facing: Vector2, anim: String) -> void:
	_target = world_position
	_facing = facing
	if anim != _anim:
		_anim = anim
		_anim_time = 0.0
	if not _has_state or position.distance_to(_target) > SNAP_DISTANCE:
		position = _target
	_has_state = true


func _process(delta: float) -> void:
	position = position.lerp(_target, 1.0 - exp(-SMOOTHING * delta)) if _has_state else position
	_anim_time += delta
	_draw_frame()


func _draw_frame() -> void:
	var anim: Dictionary = Player.ANIMS[_anim]
	var index := int(_anim_time * anim["fps"])
	index = index % int(anim["frames"]) if anim["loop"] else mini(index, int(anim["frames"]) - 1)
	var facing_index := 0 if _facing.y > 0.0 else (2 if _facing.y < 0.0 else 1)
	var row: int = anim["rows"][facing_index]
	for layer in _layers:
		layer.frame = row * Player.COLUMNS + index
		layer.flip_h = _facing.x < 0.0
