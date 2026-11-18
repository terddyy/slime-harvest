class_name Animal
extends Node2D
## One chicken or cow. Wanders inside its pen and gives one product per day: it is ready
## when Game.day is past the day it was last collected, and shows a bubble until then.
## `position` is its feet. Slimes never target animals (they are not in group "enemies").

const FRAME := 32
const FRAMES_PER_SECOND := 8.0
const ICONS := preload("res://assets/cute_fantasy/Icons/Outline/Food_Icons_Outline.png")

var type_id := "chicken"
var pen := Rect2()  # in pixels; feet stay inside
## Last day the product was taken. A new animal starts at today, so it gives its first one tomorrow.
var collected_day := 1

var _data: Dictionary
var _sprite := Sprite2D.new()
var _bubble := Sprite2D.new()
var _target := Vector2.ZERO
var _wait := 0.0
var _time := 0.0
var _bubble_y := 0.0


func _ready() -> void:
	_data = AnimalTypes.TYPES[type_id]
	_sprite.texture = load(_data["sheet"])
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.position = -(_data["feet"] as Vector2)
	add_child(_sprite)
	var icon := AtlasTexture.new()
	icon.atlas = ICONS
	icon.region = Rect2(Vector2(AnimalTypes.PRODUCTS[_data["product"]]["icon"]) * 16, Vector2(16, 16))
	_bubble.texture = icon
	_bubble.visible = false
	_bubble.z_index = 5
	_bubble_y = -(_data["feet"] as Vector2).y - 6
	add_child(_bubble)
	_target = position
	_wait = randf_range(0.2, 2.0)
	_update_frame(false)


func _process(delta: float) -> void:
	_time += delta
	var moving := false
	if _wait > 0.0:
		_wait -= delta
	elif position.distance_to(_target) < 1.0:
		_wait = randf_range(1.5, 4.0)
		_target = _random_point()
	else:
		var step: Vector2 = (_target - position).limit_length(float(_data["speed"]) * delta)
		position += step
		_sprite.flip_h = (step.x > 0.0) == bool(_data["faces_left"])
		moving = true
	_update_frame(moving)
	_bubble.visible = has_product()
	_bubble.position = Vector2(-8, _bubble_y + sin(_time * 4.0) * 1.5)


func has_product() -> bool:
	return Game.day > collected_day


## Takes today's product. Returns its id, or "" when there is none yet.
func collect() -> String:
	if not has_product():
		return ""
	collected_day = Game.day
	return _data["product"]


func body_center() -> Vector2:
	return global_position + Vector2(0, -8)


func to_save() -> Dictionary:
	return {"type": type_id, "x": position.x, "y": position.y, "day": collected_day}


func _random_point() -> Vector2:
	return Vector2(randf_range(pen.position.x, pen.end.x), randf_range(pen.position.y, pen.end.y))


func _update_frame(moving: bool) -> void:
	var row: int = _data["walk_row"] if moving else _data["idle_row"]
	var count: int = _data["walk_frames"] if moving else _data["idle_frames"]
	var column := int(_time * FRAMES_PER_SECOND) % count
	_sprite.region_rect = Rect2(column * FRAME, row * FRAME, FRAME, FRAME)
