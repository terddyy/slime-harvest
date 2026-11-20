class_name GuideArrow
extends CanvasLayer
## The tutorial's "go here" arrow. When the tip on screen sends the player somewhere (Azy, the
## restoration board, Gayle, the farmhouse), a yellow arrow bounces above that place; when the
## place is off-screen, the arrow sits at the screen edge and points the way.
## Once the tips are over (Tutorial.is_finished) it points at the current farm goal instead,
## by day only. Main sets `tutorial`, `goal_target` (returns the goal's "where" name, "" = none)
## and `locate` (target name -> world position, Vector2.INF = none).

## The arrow stays inside this screen area so the HUD never hides it: below the tip box and the
## gold/seed/crop counters (top right), above the hint text and hotbar.
const ARROW_AREA := Rect2(16, 60, 448, 166)
const BOUNCE_HEIGHT := 3.0  # pixels
const BOUNCE_SPEED := 6.0
const SIZE := 1.6  # bigger than the slime arrows so it is easy to spot

var tutorial: Tutorial
var locate: Callable
var goal_target: Callable

var _canvas := Control.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps checking, so the arrow hides while a menu pauses
	_canvas.size = UiStyle.SCREEN
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_guide)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


func _draw_guide() -> void:
	if tutorial == null or Game.is_paused():
		return
	var target := tutorial.guide_target()
	if target.is_empty() and Tutorial.is_finished and not Game.is_night and goal_target.is_valid():
		target = goal_target.call()
	if target.is_empty():
		return
	var world_pos: Vector2 = locate.call(target)
	if world_pos == Vector2.INF:
		return
	var on_screen := _canvas.get_viewport().get_canvas_transform() * world_pos
	var bounce := absf(sin(Time.get_ticks_msec() / 1000.0 * BOUNCE_SPEED)) * BOUNCE_HEIGHT
	if Rect2(Vector2.ZERO, UiStyle.SCREEN).has_point(on_screen):
		# Visible: a down-arrow bouncing just above the target. Near the top of the screen it is
		# held below the tip box, so it still points down at the target.
		var tip := on_screen.clamp(ARROW_AREA.position, ARROW_AREA.end)
		var at := (tip - Vector2(0, 7.0 * SIZE + bounce)).round()
		Effects.draw_arrow(_canvas, at, Vector2.DOWN, UiStyle.HIGHLIGHT, SIZE)
	else:
		# Off-screen: an arrow at the screen edge, nudging towards the target.
		var direction := (on_screen - ARROW_AREA.get_center()).normalized()
		var at := (Effects.edge_point(ARROW_AREA, on_screen) - direction * bounce).round()
		Effects.draw_arrow(_canvas, at, direction, UiStyle.HIGHLIGHT, SIZE)
