class_name Effects
extends RefCounted
## Small "game feel" helpers: particle puffs, a white hit flash and screen shake.
## Only static functions, so any script can call e.g. Effects.flash(self).
## Particles are plain square pixels (no texture), coloured from the art pack's palette.

## Palettes picked from the pack's sprites (see docs/ASSETS.md for the sheets).
const DIRT := [Color("e4a672"), Color("d99359"), Color("8a4836")]
const WATER := [Color("0cf1ff"), Color("00cdf9"), Color("ffffff")]
const LEAVES := [Color("5ac54f"), Color("33984b"), Color("e69c69")]
const SPARKLE := [Color("ffffff"), Color("f9e6cf"), Color(1.0, 0.85, 0.3)]
const BONES := [Color("e6e0d6"), Color("cdcbd2"), Color("aeaab6")]
## Indexed by Slime.Size (SMALL, MEDIUM, BIG).
const SLIME_COLORS := [
	[Color("0cf1ff"), Color("00cdf9"), Color("0069aa"), Color("ffffff")],
	[Color("5ac54f"), Color("33984b"), Color("1e6f50"), Color("ffffff")],
	[Color("f5555d"), Color("c42430"), Color("891e2b"), Color("ffffff")],
]

const PARTICLE_Z := 5  # above the y-sorted entities, below popup text (10)
## Modulate above 1.0 brightens a sprite towards white.
const FLASH_COLOR := Color(4.0, 4.0, 4.0)
const FLASH_TIME := 0.15
const SHAKE_STRENGTH := 3.0  # pixels
const SHAKE_TIME := 0.25
const SHAKE_STEPS := 5
const ARROW_OUTLINE := Color(0.1, 0.07, 0.05)


## A one-shot puff of `amount` pixels flying out of `at` (a position in `parent`).
## `gravity` pulls them down (water drops), 0 makes a puff. The node frees itself.
static func burst(parent: Node, at: Vector2, colors: Array, amount := 10, speed := 35.0,
		gravity := 0.0, lifetime := 0.45) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.position = at
	particles.z_index = PARTICLE_Z
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = amount
	particles.lifetime = lifetime
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.initial_velocity_min = speed * 0.4
	particles.initial_velocity_max = speed
	particles.damping_min = speed * 0.5
	particles.damping_max = speed
	particles.gravity = Vector2(0, gravity)
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.5
	particles.color_initial_ramp = _palette(colors)
	particles.color_ramp = _fade(1.0, 0.6)
	particles.finished.connect(particles.queue_free)
	parent.add_child(particles)
	particles.emitting = true
	return particles


## A looping, gentle twinkle (used on ripe crops). Add it as a child of the thing to sparkle.
static func sparkles(area: Vector2) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.amount = 5
	particles.lifetime = 1.2
	particles.preprocess = particles.lifetime  # already twinkling on the first frame
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = area / 2.0
	particles.direction = Vector2.UP
	particles.spread = 0.0
	particles.initial_velocity_min = 4.0
	particles.initial_velocity_max = 8.0
	particles.gravity = Vector2.ZERO
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.0
	particles.color_initial_ramp = _palette(SPARKLE)
	particles.color_ramp = _fade(0.0, 0.3)  # fades in, then out
	return particles


## Flashes a sprite (or any CanvasItem) white for a moment, e.g. when an enemy is hit.
static func flash(node: CanvasItem) -> void:
	node.modulate = FLASH_COLOR
	node.create_tween().tween_property(node, "modulate", Color.WHITE, FLASH_TIME)


## Shakes the camera by moving its offset a few times, getting weaker, then back to zero.
static func shake(camera: Camera2D, strength := SHAKE_STRENGTH) -> void:
	if camera == null:
		return
	var tween := camera.create_tween()
	var step_time := SHAKE_TIME / SHAKE_STEPS
	for i in SHAKE_STEPS:
		var power := strength * (1.0 - float(i) / SHAKE_STEPS)
		var offset := Vector2(randf_range(-power, power), randf_range(-power, power)).round()
		tween.tween_property(camera, "offset", offset, step_time)
	tween.tween_property(camera, "offset", Vector2.ZERO, step_time)


## Where an arrow to `target` goes: `target` itself if it is inside `area`, otherwise the point
## where the line from the middle of `area` to `target` leaves `area`. Screen coordinates.
static func edge_point(area: Rect2, target: Vector2) -> Vector2:
	var center := area.get_center()
	var offset := target - center
	var half := area.size / 2.0
	var scale_x := half.x / maxf(absf(offset.x), 0.001)
	var scale_y := half.y / maxf(absf(offset.y), 0.001)
	return center + offset * minf(minf(scale_x, scale_y), 1.0)


## Draws a long, narrow triangle with a dark outline; its tip is 7 * size px from `at` along `direction`.
static func draw_arrow(canvas: CanvasItem, at: Vector2, direction: Vector2, color: Color, size := 1.0) -> void:
	var forward := direction * size
	var side := direction.orthogonal() * size
	var tip := at + forward * 7.0
	var back := at - forward * 5.0
	var points := PackedVector2Array([tip, back + side * 3.5, back - side * 3.5])
	var outline := PackedVector2Array([tip + forward * 2.0, back - forward + side * 5.0, back - forward - side * 5.0])
	canvas.draw_colored_polygon(outline, ARROW_OUTLINE)
	canvas.draw_colored_polygon(points, color)


## Each particle picks one of `colors` at random (a gradient with hard steps).
static func _palette(colors: Array) -> Gradient:
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / colors.size())
	gradient.offsets = offsets
	gradient.colors = PackedColorArray(colors)
	return gradient


## Alpha over a particle's life: starts at `start_alpha`, is fully visible at `peak`, ends at 0.
static func _fade(start_alpha: float, peak: float) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, peak, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, start_alpha), Color.WHITE, Color(1, 1, 1, 0)])
	return gradient
