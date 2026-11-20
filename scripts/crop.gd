class_name Crop
extends Node2D
## A planted crop. Farm calls tick() on a timer; slimes call bite() while eating it.
## The node's position is the bottom-centre of its tile.

const TEXTURE := preload("res://assets/cute_fantasy/Crops/Crops.png")
const BAND := Vector2i(16, 32)  # every crop in Crops.png is a 16x32 band
const FIRST_STAGE_COLUMN := 2  # columns 2..5 are the growth stages
const STAGES := 4
const BITES_TO_EAT := 3

## Crop id -> data, in shop/hotbar order (cheapest seed first).
##   row: band in Crops.png (see docs/ASSETS.md)
##   grow_ticks: farm ticks the soil must stay wet before each growth stage (bigger = slower)
##   seed_price / sell_price: gold
##   icon / seed_icon: cells in Icons/Outline/Food_Icons_Outline.png
##   requires (optional): id of a restoration project that must be done before the seeds can be bought
const TYPES := {
	"radish": {"name": "Radish", "row": 18, "grow_ticks": 1, "seed_price": 3, "sell_price": 8,
		"icon": Vector2i(2, 8), "seed_icon": Vector2i(3, 8)},
	"carrot": {"name": "Carrot", "row": 2, "grow_ticks": 1, "seed_price": 5, "sell_price": 15,
		"icon": Vector2i(2, 4), "seed_icon": Vector2i(3, 4)},
	"potato": {"name": "Potato", "row": 16, "grow_ticks": 2, "seed_price": 10, "sell_price": 28,
		"icon": Vector2i(0, 10), "seed_icon": Vector2i(1, 10)},
	"tomato": {"name": "Tomato", "row": 1, "grow_ticks": 2, "seed_price": 15, "sell_price": 40,
		"icon": Vector2i(0, 4), "seed_icon": Vector2i(1, 4)},
	"cabbage": {"name": "Cabbage", "row": 7, "grow_ticks": 3, "seed_price": 20, "sell_price": 56,
		"icon": Vector2i(2, 5), "seed_icon": Vector2i(3, 5)},
	"corn": {"name": "Corn", "row": 4, "grow_ticks": 3, "seed_price": 25, "sell_price": 70,
		"icon": Vector2i(0, 7), "seed_icon": Vector2i(1, 7)},
	"eggplant": {"name": "Eggplant", "row": 3, "grow_ticks": 4, "seed_price": 32, "sell_price": 90,
		"icon": Vector2i(4, 7), "seed_icon": Vector2i(5, 7)},
	"pumpkin": {"name": "Pumpkin", "row": 5, "grow_ticks": 4, "seed_price": 40, "sell_price": 120,
		"icon": Vector2i(0, 6), "seed_icon": Vector2i(1, 6)},
	"strawberry": {"name": "Strawberry", "row": 17, "grow_ticks": 5, "seed_price": 55, "sell_price": 170,
		"icon": Vector2i(0, 11), "seed_icon": Vector2i(1, 11), "requires": "greenhouse"},
	"chili": {"name": "Chili", "row": 9, "grow_ticks": 6, "seed_price": 75, "sell_price": 240,
		"icon": Vector2i(4, 6), "seed_icon": Vector2i(5, 6), "requires": "greenhouse"},
}

var cell := Vector2i.ZERO
var stage := 0
var crop_id := "carrot"

var _bites := 0
var _wet_ticks := 0
var _sprite := Sprite2D.new()
var _sparkles: CPUParticles2D  # added once the crop is ripe


func _ready() -> void:
	_sprite.texture = TEXTURE
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.position = Vector2(-8, -30)
	add_child(_sprite)
	_update_sprite()


## Can this crop's seeds be bought? `restored` is Game.restored (project id -> true).
static func is_unlocked(crop_id: String, restored: Dictionary) -> bool:
	var needed: String = Crop.TYPES[crop_id].get("requires", "")
	return needed == "" or restored.has(needed)


func is_ripe() -> bool:
	return stage >= STAGES - 1


## Called by Farm every Farm.GROW_INTERVAL seconds. Counts how long the soil has been wet;
## once it reaches this crop's grow_ticks the crop gets its chance to grow.
## Returns true if the crop used up the water on its tile (Farm then dries the tile).
func tick(is_watered: bool) -> bool:
	if is_watered:
		_wet_ticks += 1
	if _wet_ticks < TYPES[crop_id]["grow_ticks"]:
		return false
	_wet_ticks = 0
	return try_grow(is_watered)


## Grows one stage if watered and not ripe yet.
## Returns true if the crop used up the water on its tile.
func try_grow(is_watered: bool) -> bool:
	if not is_watered or is_ripe():
		return false
	stage += 1
	_update_sprite()
	return true


## Returns true when this bite finished the crop off.
func bite() -> bool:
	_bites += 1
	modulate = Color(1.0, 0.45, 0.45)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.25)
	var eaten := _bites >= BITES_TO_EAT
	if eaten:
		Effects.burst(get_parent(), position + Vector2(0, -6), Effects.LEAVES, 12, 40.0)
	return eaten


func to_save() -> Dictionary:
	return {"id": crop_id, "stage": stage, "bites": _bites, "wet_ticks": _wet_ticks}


## Call after the crop is in the tree (Farm does). `crop_id` is set by the creator.
func from_save(data: Dictionary) -> void:
	stage = clampi(int(SaveUtil.number(data, "stage", 0)), 0, STAGES - 1)
	_bites = clampi(int(SaveUtil.number(data, "bites", 0)), 0, BITES_TO_EAT - 1)
	_wet_ticks = maxi(0, int(SaveUtil.number(data, "wet_ticks", 0)))
	_update_sprite()


func _update_sprite() -> void:
	var column := FIRST_STAGE_COLUMN + stage
	var row: int = TYPES[crop_id]["row"]
	_sprite.region_rect = Rect2(column * BAND.x, row * BAND.y, BAND.x, BAND.y)
	if is_ripe() and _sparkles == null:
		_sparkles = Effects.sparkles(Vector2(14, 10))
		_sparkles.position = Vector2(0, -9)  # over the leaves
		add_child(_sparkles)
