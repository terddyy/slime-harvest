class_name CameraZoom
extends Camera2D
## The player's camera, with zoom: + / - keys, Ctrl + mouse wheel, or a touchpad pinch.
## The plain mouse wheel is left for switching tools. Zoom is smooth, steps through
## ZOOM_STEPS and is remembered across restarts (static var).

## 1.0 = the normal 480x270 view. Lower = see more of the map, higher = closer.
## The smallest step still fits inside the 768x480 map, so the camera limits keep working.
const ZOOM_STEPS: Array[float] = [0.65, 0.8, 1.0, 1.25, 1.5, 2.0]
const ZOOM_TIME := 0.15
## How much a pinch must grow/shrink before it counts as one zoom step.
const PINCH_STEP := 0.12

static var _step_index := ZOOM_STEPS.find(1.0)

var _pinch := 1.0
var _tween: Tween


func _ready() -> void:
	zoom = Vector2.ONE * ZOOM_STEPS[_step_index]


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event.is_action_pressed("zoom_in"):
		change_zoom(1)
	elif event.is_action_pressed("zoom_out"):
		change_zoom(-1)
	elif event is InputEventMouseButton and event.pressed and event.ctrl_pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			change_zoom(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change_zoom(-1)
	elif event is InputEventMagnifyGesture:
		_pinch *= event.factor
		if _pinch > 1.0 + PINCH_STEP:
			_pinch = 1.0
			change_zoom(1)
		elif _pinch < 1.0 - PINCH_STEP:
			_pinch = 1.0
			change_zoom(-1)


## Moves `steps` zoom levels in (positive) or out (negative), clamped to ZOOM_STEPS.
func change_zoom(steps: int) -> void:
	var index := clampi(_step_index + steps, 0, ZOOM_STEPS.size() - 1)
	if index == _step_index:
		return
	_step_index = index
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "zoom", Vector2.ONE * ZOOM_STEPS[index], ZOOM_TIME)


func zoom_level() -> float:
	return ZOOM_STEPS[_step_index]


func to_save() -> Dictionary:
	return {"zoom": zoom_level()}


## Jumps to the saved zoom (the closest step) without the zoom animation.
func from_save(data: Dictionary) -> void:
	var saved := SaveUtil.number(data, "zoom", 1.0)
	var best := 0
	for i in ZOOM_STEPS.size():
		if absf(ZOOM_STEPS[i] - saved) < absf(ZOOM_STEPS[best] - saved):
			best = i
	_step_index = best
	if _tween != null:
		_tween.kill()
	zoom = Vector2.ONE * ZOOM_STEPS[best]
