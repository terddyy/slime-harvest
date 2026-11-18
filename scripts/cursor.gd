extends Node2D
## Outline on the tiles the player will act on. Green = the selected tool can be used there.
## Usually one tile; an upgraded watering can covers several.

const TILE := 16
const OK_COLOR := Color(0.55, 1.0, 0.55, 0.9)
const IDLE_COLOR := Color(1.0, 1.0, 1.0, 0.35)

var _color := IDLE_COLOR
var _cells: Array[Vector2i] = []


func show_cells(cells: Array[Vector2i], can_act: bool) -> void:
	var color := OK_COLOR if can_act else IDLE_COLOR
	if color != _color or cells != _cells:
		_color = color
		_cells = cells
		queue_redraw()


func _draw() -> void:
	for cell in _cells:
		draw_rect(Rect2(Vector2(cell * TILE) + Vector2(0.5, 0.5), Vector2(TILE - 1, TILE - 1)), _color, false, 1.0)
