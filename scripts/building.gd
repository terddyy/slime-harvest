class_name Building
extends Node2D
## One restorable building. `position` is its foot (see BuildingData); the farmhouse door is there.
## Not restored: a sign with the name and price, some rubble and a faint blue ghost of the
## building. Restored: the full sprite with walls to bump into (and spinning sails on the windmill).
## Set `id` and `ghost_parent` before adding it to the tree. Buildings (buildings.gd) does that.

const RUBBLE := [Rect2(16, 96, 16, 16), Rect2(48, 96, 16, 16), Rect2(64, 96, 16, 16)]  # in Outdoor_Decor.png
const DECOR := preload("res://assets/cute_fantasy/Outdoor decoration/Outdoor_Decor.png")
const SIGNS := preload("res://assets/cute_fantasy/Outdoor decoration/Signs.png")
const SIGN_REGION := Rect2(0, 16, 16, 32)
const GHOST_COLOR := Color(0.6, 0.8, 1.0, 0.22)
const SAIL_FPS := 6.0

var id := ""
var restored := false
## Flat things drawn under the y-sorted entities (the ghost), so the player never hides behind them.
var ghost_parent: Node2D

var _ghost: Sprite2D
var _ruin := Node2D.new()
var _built := Node2D.new()
var _collider := CollisionShape2D.new()
var _sails: Sprite2D


func _ready() -> void:
	var data := BuildingData.spec(id)
	position = BuildingData.foot_position(id)
	_make_ghost(data)
	_make_ruin(data)
	_make_built(data)
	add_child(_ruin)
	add_child(_built)
	set_restored(Game.is_restored(id), false)
	set_process(_sails != null)


func _process(_delta: float) -> void:
	_sails.frame = int(Time.get_ticks_msec() / 1000.0 * SAIL_FPS) % _sails.hframes


## Switches between ruin and building. `animate` adds a puff of sparkles (not used when loading).
func set_restored(done: bool, animate: bool) -> void:
	restored = done
	_ruin.visible = not done
	_ghost.visible = not done
	_built.visible = done
	_collider.set_deferred("disabled", not done)
	if done and animate:
		Effects.burst(get_parent(), position + Vector2(0, -24), Effects.SPARKLE, 30, 60.0)
		Effects.burst(get_parent(), position + Vector2(0, -6), Effects.DIRT, 16, 40.0)


func _sprite(data: Dictionary) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = load(data["texture"])
	sprite.region_enabled = true
	sprite.region_rect = data["region"]
	sprite.centered = false
	sprite.position = -(data["foot"] as Vector2)
	return sprite


func _make_ghost(data: Dictionary) -> void:
	_ghost = _sprite(data)
	_ghost.modulate = GHOST_COLOR
	_ghost.position += position
	ghost_parent.add_child(_ghost)


func _make_built(data: Dictionary) -> void:
	_built.add_child(_sprite(data))
	if data.has("sails"):
		var sails_data: Dictionary = data["sails"]
		_sails = Sprite2D.new()
		_sails.texture = load(sails_data["texture"])
		_sails.hframes = sails_data["frames"]
		_sails.position = sails_data["hub"]
		_built.add_child(_sails)
	var body := StaticBody2D.new()
	var shape := RectangleShape2D.new()
	var walls: Rect2 = data["collision"]
	shape.size = walls.size
	_collider.shape = shape
	_collider.position = walls.get_center()
	body.add_child(_collider)
	_built.add_child(body)


## Sign (with the name and price), then a few rocks and stumps spread over the plot.
func _make_ruin(data: Dictionary) -> void:
	var plot := WorldLayout.area(data["plot"])
	var half_width := plot.size.x * BuildingData.TILE / 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = id.hash()
	for i in 3 + plot.size.x / 4:
		var piece := Sprite2D.new()
		piece.texture = DECOR
		piece.centered = false
		piece.region_enabled = true
		piece.region_rect = RUBBLE[rng.randi() % RUBBLE.size()]
		var spot := Vector2(
			rng.randf_range(-half_width + 24.0, half_width - 12.0),
			rng.randf_range(-plot.size.y * BuildingData.TILE * 0.4, -4.0))
		piece.position = spot + Vector2(-8, -16)
		_ruin.add_child(piece)

	var sign_spot := Vector2(-half_width + 12.0, 0)
	var board := Sprite2D.new()
	board.texture = SIGNS
	board.centered = false
	board.region_enabled = true
	board.region_rect = SIGN_REGION
	board.position = sign_spot + Vector2(-8, -30)
	_ruin.add_child(board)
	var project := Restoration.project(id)
	var label := Label.new()
	label.text = "%s
%dg at the board" % [project["name"], project["cost"]]
	label.custom_minimum_size = Vector2(70, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05))
	label.add_theme_constant_override("outline_size", 3)
	label.position = sign_spot + Vector2(-35, -49)
	_ruin.add_child(label)
