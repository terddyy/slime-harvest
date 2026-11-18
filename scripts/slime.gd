class_name Slime
extends Node2D
## Night enemy. Goes for the nearest crop and eats it (chewing through fences in the way).
## It never hurts the player.
## Hit detection is distance-based (no physics). The node's position is the slime's feet.
## Set `size` before adding it to the tree. A big slime splits into small ones when it dies.
## Enemy contract (group "enemies"): take_hit(), body_center(), vanish(), signal killed.

signal killed(world_pos: Vector2, gold: int)
## Emitted by a big slime when it dies; the Spawner adds the small slimes.
signal split(world_pos: Vector2)

enum Size { SMALL, MEDIUM, BIG }

const SHEET_DIR := "res://assets/cute_fantasy/Enemies/Slime/"
## Every slime sheet is 8 cols x 4 rows; only the frame size differs (see docs/ASSETS.md).
const COLUMNS := 8
const ROWS := 4
## name -> [row, frames, fps]. The big slime's death has 8 frames (see STATS).
const ANIMS := {
	"idle": [0, 4, 6.0],
	"move": [1, 8, 10.0],
	"die": [2, 4, 10.0],
	"hurt": [3, 4, 16.0],
}
## Per-size numbers. sprite_y lifts the frame so the bottom of its shadow sits on the feet;
## body_y is the middle of the body (used for sword hits). fence_damage is one bite on a fence.
const STATS := {
	Size.SMALL: {"sheet": "Slime_Small/Slime_Small_Blue.png", "die_frames": 4,
		"sprite_y": -7.0, "body_y": -4.0, "hp": 1, "speed": 38.0,
		"touch_range": 8.0, "gold": 1, "fence_damage": 1},
	Size.MEDIUM: {"sheet": "Slime_Medium/Slime_Medium_Green.png", "die_frames": 4,
		"sprite_y": -6.0, "body_y": -5.0, "hp": 3, "speed": 26.0,
		"touch_range": 10.0, "gold": 3, "fence_damage": 2},
	Size.BIG: {"sheet": "Slime_Big/Slime_Big_Red.png", "die_frames": 8,
		"sprite_y": -10.0, "body_y": -10.0, "hp": 6, "speed": 17.0,
		"touch_range": 13.0, "gold": 4, "fence_damage": 4},
}

const EAT_RANGE := 6.0
const EAT_INTERVAL := 1.2
const FENCE_BITE_INTERVAL := 1.0
const HURT_TIME := 0.25
const KNOCKBACK_SPEED := 140.0
const SPLIT_COUNT := 2

var farm: Farm
## Fences block the way; the slime chews through them. Can be null (no fences).
var fences: Fences
var size := Size.MEDIUM
var hp := 0

var _stats: Dictionary
var _sprite := Sprite2D.new()
var _anim := "move"
var _anim_time := 0.0
var _knockback := Vector2.ZERO
var _hurt_time := 0.0
var _eat_timer := 0.0
var _dying := false


func _ready() -> void:
	_stats = STATS[size]
	hp = _stats["hp"]
	_sprite.texture = load(SHEET_DIR + _stats["sheet"])
	_sprite.hframes = COLUMNS
	_sprite.vframes = ROWS
	_sprite.position = Vector2(0, _stats["sprite_y"])
	add_child(_sprite)
	add_to_group("enemies")


func _process(delta: float) -> void:
	_anim_time += delta
	if _dying:
		_update_frame()
		if _anim_time >= _stats["die_frames"] / ANIMS["die"][2] + 0.1:
			queue_free()
		return

	_knockback_step(delta)
	_knockback = _knockback.move_toward(Vector2.ZERO, 400.0 * delta)
	_hurt_time = maxf(_hurt_time - delta, 0.0)
	if _hurt_time > 0.0:
		_set_anim("hurt")
	else:
		_think(delta)
	_update_frame()


## Middle of the slime's body, used for sword hits.
func body_center() -> Vector2:
	return global_position + Vector2(0, _stats["body_y"])


func take_hit(damage: int, from: Vector2) -> void:
	if _dying:
		return
	hp -= damage
	Audio.play_sfx("slime_hit", 0.15)
	Effects.flash(self)
	knock_back(from)
	if hp <= 0:
		Audio.play_sfx("slime_die", 0.1)
		var gold: int = _stats["gold"]
		Game.add_gold(gold)
		killed.emit(global_position, gold)
		if size == Size.BIG:
			split.emit(global_position)
		_start_dying()


## Pushes the slime away from `from` and stuns it briefly.
func knock_back(from: Vector2) -> void:
	_knockback = (global_position - from).normalized() * KNOCKBACK_SPEED
	_hurt_time = HURT_TIME


## Disappear without a reward (used at dawn).
func vanish() -> void:
	if not _dying:
		_start_dying()


func _think(delta: float) -> void:
	var crop := farm.nearest_crop(global_position)
	if crop == null:
		_set_anim("idle")
		return
	var target := crop.global_position

	if global_position.distance_to(target) < EAT_RANGE:
		_set_anim("idle")
		_eat_timer += delta
		if _eat_timer >= EAT_INTERVAL:
			_eat_timer = 0.0
			if crop.bite():
				farm.remove_crop(crop.cell)
				Audio.play_sfx("crop_eaten")
		return

	var direction := global_position.direction_to(target)
	_sprite.flip_h = direction.x < 0.0
	var next: Vector2 = global_position + direction * _stats["speed"] * delta
	if fences != null and fences.blocks(global_position, next):
		_chew_fence(fences.cell_at(next), delta)
		return
	_eat_timer = 0.0
	global_position = next
	_set_anim("move")


## A fence is in the way: stay put and bite it until it breaks.
func _chew_fence(cell: Vector2i, delta: float) -> void:
	_set_anim("idle")
	_eat_timer += delta
	if _eat_timer >= FENCE_BITE_INTERVAL:
		_eat_timer = 0.0
		if fences.damage(cell, _stats["fence_damage"]):
			Audio.play_sfx("crop_eaten")


## Knockback can't push a slime through a fence either.
func _knockback_step(delta: float) -> void:
	var next := global_position + _knockback * delta
	if fences != null and fences.blocks(global_position, next):
		_knockback = Vector2.ZERO
	else:
		global_position = next


func _start_dying() -> void:
	_dying = true
	remove_from_group("enemies")
	_set_anim("die")
	Effects.burst(get_parent(), position + Vector2(0, _stats["body_y"]), Effects.SLIME_COLORS[size], 16, 60.0)


func _set_anim(anim_name: String) -> void:
	if anim_name != _anim:
		_anim = anim_name
		_anim_time = 0.0


func _update_frame() -> void:
	var anim: Array = ANIMS[_anim]
	var frame_count: int = _stats["die_frames"] if _anim == "die" else anim[1]
	var index := int(_anim_time * anim[2])
	index = mini(index, frame_count - 1) if _anim == "die" else index % frame_count
	_sprite.frame = anim[0] * COLUMNS + index
