class_name Feedback
extends Node
## Game-feel reactions that don't belong to one object: dirt and water particles on the
## farm, the "Night is coming!" banner, and arrows at
## the screen edge pointing to slimes that are eating crops off-screen.
## Main creates it and calls setup(). The effects themselves are in Effects (effects.gd).

var _farm: Farm
var _player: Player
var _hud: Hud
var _warned_day := 0  # the day we last showed "Night is coming!" on
var _arrows := EdgeArrows.new()


func setup(farm: Farm, player: Player, hud: Hud) -> void:
	_farm = farm
	_player = player
	_hud = hud
	farm.tilled.connect(_on_tilled)
	farm.untilled.connect(_on_tilled)
	farm.watered.connect(_on_watered)

	var layer := CanvasLayer.new()  # screen space, not affected by the night tint
	add_child(layer)
	_arrows.farm = farm
	layer.add_child(_arrows)


func _process(_delta: float) -> void:
	if Game.is_night_coming() and _warned_day != Game.day:
		_warned_day = Game.day
		_hud.show_banner("Night is coming!")


func _on_tilled(cell: Vector2i) -> void:
	# Clumps of soil kick up and fall back down.
	var at := _farm.map_to_local(cell) + Vector2(0, -2)
	Effects.burst(_farm, at, Effects.DIRT, 12, 50.0, 160.0, 0.45)


func _on_watered(cell: Vector2i) -> void:
	# Drops start a little above the soil and fall back onto it.
	var at := _farm.map_to_local(cell) + Vector2(0, -4)
	Effects.burst(_farm, at, Effects.WATER, 6, 30.0, 120.0, 0.4)


## Draws a small red arrow at the screen edge for every slime eating a crop off-screen.
class EdgeArrows extends Control:
	## Arrows stay inside this area so they don't cover the HUD (clock and counters at the
	## top, hotbar at the bottom).
	const ARROW_AREA := Rect2(10, 46, 460, 190)
	const COLOR := Color(1.0, 0.3, 0.25)

	var farm: Farm

	func _ready() -> void:
		size = UiStyle.SCREEN
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not Game.is_night:
			return
		var world_to_screen := get_viewport().get_canvas_transform()
		var screen := Rect2(Vector2.ZERO, size)
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if not _is_eating(enemy):
				continue
			var on_screen: Vector2 = world_to_screen * enemy.global_position
			if not screen.has_point(on_screen):
				var at := Effects.edge_point(ARROW_AREA, on_screen).round()
				var blink := 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / 150.0))
				Effects.draw_arrow(self, at, (on_screen - ARROW_AREA.get_center()).normalized(), Color(COLOR, blink))

	func _is_eating(enemy: Node) -> bool:
		var crop := farm.nearest_crop(enemy.global_position)
		return crop != null and crop.global_position.distance_to(enemy.global_position) <= Slime.EAT_RANGE + 1.0

