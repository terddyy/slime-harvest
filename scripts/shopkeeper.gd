class_name Shopkeeper
extends Node2D
## Azy, who runs the market stall. Plays the front-facing idle loop of a premade NPC sheet
## and shows a name tag. Main opens the shop when the player presses E near Azy.
## `position` is the feet (bottom-centre), like every other character.

const NPC_NAME := "Azy"
const SHEET := preload("res://assets/cute_fantasy/NPCs (Premade)/Chef_Chloe.png")
const CELL := Vector2i(64, 64)
const IDLE_FRAMES := 6  # row 0 of the sheet, facing the camera
const FRAME_TIME := 0.18
const FEET_Y := 41  # where the feet are inside a 64x64 cell
const TALK_RANGE := 30.0

var _sprite := Sprite2D.new()
var _frame := 0
var _timer := 0.0


## Source rectangle of idle frame `index` in the sheet (wraps around).
static func frame_region(index: int) -> Rect2:
	var column := posmod(index, IDLE_FRAMES)
	return Rect2(Vector2(column * CELL.x, 0), Vector2(CELL))


func _ready() -> void:
	_sprite.texture = SHEET
	_sprite.region_enabled = true
	_sprite.region_rect = frame_region(0)
	_sprite.position = Vector2(0, CELL.y / 2.0 - FEET_Y)
	add_child(_sprite)

	var tag := Label.new()
	tag.text = NPC_NAME
	tag.add_theme_font_size_override("font_size", 8)
	tag.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	tag.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05))
	tag.add_theme_constant_override("outline_size", 3)
	tag.position = Vector2(-20, -42)
	tag.size = Vector2(40, 10)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.z_index = 10
	add_child(tag)


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= FRAME_TIME:
		_timer -= FRAME_TIME
		_frame = (_frame + 1) % IDLE_FRAMES
		_sprite.region_rect = frame_region(_frame)
