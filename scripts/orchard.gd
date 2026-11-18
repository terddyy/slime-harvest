class_name Orchard
extends Node2D
## Fruit trees in the orchard area. A sapling (bought at the stall) is planted once, grows
## over days (new_day() is called at every dawn) and then gives fruit every FRUIT_DAYS days.
## Slimes ignore the trees. Trees are static bodies, so the player walks around them.

const TILE := 16
const STAGES := preload("res://assets/cute_fantasy/Crops/Fruit_Tree_Stages.png")  # 3 frames of 32x64
const FRAME := Vector2(32, 64)
## Days from planting until a tree is "young" and until it is fully grown.
const YOUNG_DAYS := 1
const MATURE_DAYS := 3
## A grown tree has fruit again this many days after it grew up / after the last picking.
const FRUIT_DAYS := 3
const FRUIT_PER_TREE := 3
## Top-left of the tree sprite relative to the tree's feet (bottom-centre of its cell).
const SPRITE_OFFSET := Vector2(-16, -56)

## Tree id -> data. Keys are in shop order.
##   texture: the tree with fruit on it (32x64). fruit_price is per piece, sapling_price per tree.
const TYPES := {
	"apple": {"name": "Apple", "sapling_price": 60, "fruit_price": 20,
		"texture": preload("res://assets/cute_fantasy/Crops/Apple_Tree.png")},
	"cherry": {"name": "Cherry", "sapling_price": 80, "fruit_price": 28,
		"texture": preload("res://assets/cute_fantasy/Crops/Cherry_Tree.png")},
	"peach": {"name": "Peach", "sapling_price": 100, "fruit_price": 36,
		"texture": preload("res://assets/cute_fantasy/Crops/Peach_Tree.png")},
	"pear": {"name": "Pear", "sapling_price": 120, "fruit_price": 44,
		"texture": preload("res://assets/cute_fantasy/Crops/Pear_Tree.png")},
}

## Where trees may be planted (cells). Set by Main from WorldLayout.
var area := Rect2i()
## The y-sorted node the trees are added to. Set by Main.
var tree_parent: Node2D

var _trees := {}  # Vector2i -> {"id": String, "age": int, "wait": int, "fruit": bool}
var _nodes := {}  # Vector2i -> StaticBody2D whose first child is the Sprite2D


func has_tree(cell: Vector2i) -> bool:
	return _trees.has(cell)


func tree_count() -> int:
	return _trees.size()


## Cell is inside the orchard, free, and has no tree directly left or right (crowns are 2 cells wide).
func can_plant(cell: Vector2i) -> bool:
	return area.has_point(cell) and not _trees.has(cell) \
		and not _trees.has(cell + Vector2i.LEFT) and not _trees.has(cell + Vector2i.RIGHT)


func plant(cell: Vector2i, id: String) -> bool:
	if not TYPES.has(id) or not can_plant(cell):
		return false
	_trees[cell] = {"id": id, "age": 0, "wait": 0, "fruit": false}
	_add_node(cell)
	_refresh(cell)
	return true


## 0 sapling, 1 young, 2 grown. -1 when there is no tree.
func stage(cell: Vector2i) -> int:
	if not _trees.has(cell):
		return -1
	var age: int = _trees[cell]["age"]
	return 0 if age < YOUNG_DAYS else (1 if age < MATURE_DAYS else 2)


func has_fruit(cell: Vector2i) -> bool:
	return _trees.has(cell) and _trees[cell]["fruit"]


## Picks the fruit. Returns the tree id, or "" when there is nothing to pick.
func harvest(cell: Vector2i) -> String:
	if not has_fruit(cell):
		return ""
	_trees[cell]["fruit"] = false
	_trees[cell]["wait"] = 0
	_refresh(cell)
	return _trees[cell]["id"]


## Called at every dawn: trees grow, grown trees count down to their next fruit.
func new_day() -> void:
	for cell: Vector2i in _trees:
		var tree: Dictionary = _trees[cell]
		tree["age"] += 1
		if tree["age"] > MATURE_DAYS and not tree["fruit"]:
			tree["wait"] += 1
			tree["fruit"] = tree["wait"] >= FRUIT_DAYS
		_refresh(cell)


func to_save() -> Dictionary:
	var entries := []
	for cell: Vector2i in _trees:
		var tree: Dictionary = _trees[cell]
		entries.append([cell.x, cell.y, {"id": tree["id"], "age": tree["age"], "wait": tree["wait"], "fruit": tree["fruit"]}])
	return {"trees": entries}


func from_save(data: Dictionary) -> void:
	for cell: Vector2i in _nodes:
		_nodes[cell].queue_free()
	_nodes.clear()
	_trees.clear()
	for entry: Variant in SaveUtil.list(data.get("trees")):
		if not SaveUtil.is_entry(entry, 2) or entry.size() < 3 or not entry[2] is Dictionary:
			continue
		var info: Dictionary = entry[2]
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		if not TYPES.has(info.get("id")) or not plant(cell, info["id"]):
			continue
		var tree: Dictionary = _trees[cell]
		tree["age"] = maxi(0, int(SaveUtil.number(info, "age", 0)))
		tree["wait"] = clampi(int(SaveUtil.number(info, "wait", 0)), 0, FRUIT_DAYS)
		tree["fruit"] = info.get("fruit") == true and tree["age"] >= MATURE_DAYS
		_refresh(cell)


func _add_node(cell: Vector2i) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(cell * TILE) + Vector2(TILE / 2.0, TILE - 2.0)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.position = SPRITE_OFFSET
	sprite.region_enabled = true
	body.add_child(sprite)
	var trunk := CircleShape2D.new()
	trunk.radius = 4.0
	var collider := CollisionShape2D.new()
	collider.shape = trunk
	collider.position = Vector2(0, -3)
	body.add_child(collider)
	(tree_parent if tree_parent != null else self).add_child(body)
	_nodes[cell] = body


## Stage frame while growing, the type's own fruit tree when it has fruit.
func _refresh(cell: Vector2i) -> void:
	var sprite: Sprite2D = _nodes[cell].get_child(0)
	var tree: Dictionary = _trees[cell]
	if tree["fruit"]:
		sprite.texture = TYPES[tree["id"]]["texture"]
		sprite.region_rect = Rect2(Vector2.ZERO, FRAME)
	else:
		sprite.texture = STAGES
		sprite.region_rect = Rect2(Vector2(stage(cell) * FRAME.x, 0), FRAME)
