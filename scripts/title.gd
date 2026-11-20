extends Node2D
## Title screen: a small farm scene from the Cute Fantasy pack with slimes hopping around,
## the game title, Start / How to Play / Credits / Quit buttons and a developer footer.

const TILE := 16
const GRASS_PLAIN := preload("res://assets/cute_fantasy/Tiles/Grass/Grass_1_Middle.png")
const GRASS_TILES := preload("res://assets/cute_fantasy/Tiles/Grass/Grass_Tiles_1.png")
const GRASS_TUFTS: Array[Vector2i] = [Vector2i(5, 9), Vector2i(6, 9), Vector2i(7, 9)]
const FARMLAND := preload("res://assets/cute_fantasy/Tiles/FarmLand/FarmLand_Tile.png")
const CROPS := preload("res://assets/cute_fantasy/Crops/Crops.png")
const BIG_OAK := preload("res://assets/cute_fantasy/Trees/Big_Oak_Tree.png")
const MEDIUM_OAK := preload("res://assets/cute_fantasy/Trees/Medium_Oak_Tree.png")
const SLIME_GREEN := preload("res://assets/cute_fantasy/Enemies/Slime/Slime_Medium/Slime_Medium_Green.png")
const SLIME_BLUE := preload("res://assets/cute_fantasy/Enemies/Slime/Slime_Medium/Slime_Medium_Blue.png")
const SLIME_PINK := preload("res://assets/cute_fantasy/Enemies/Slime/Slime_Medium/Slime_Medium_Pink.png")

const CARROT_ROW := 2  # Crops.png band (see docs/ASSETS.md)
const RIPE_COLUMN := 5
const PATCH_CELL := Vector2i(3, 11)  # top-left tile of the carrot patch
const PATCH_SIZE := Vector2i(5, 3)
const LOGO := preload("res://assets/generated/logo.png")  # 160x78, see docs/ASSETS.md
const LOGO_TOP := 6.0

var _scenery := Node2D.new()
var _menu := Control.new()
var _how_to_play := HowToPlay.new()
var _credits := Credits.new()
var _footer := UiStyle.make_label(Credits.footer_text(), UiStyle.TEXT_SIZE)
var _new_button := UiStyle.make_button("New Game")
var _continue_button := UiStyle.make_button("Continue")
var _confirm := Control.new()
var _confirm_no_button := UiStyle.make_button("Cancel")


func _ready() -> void:
	get_tree().paused = false
	_scenery.y_sort_enabled = true
	_build_ground()
	_build_carrot_patch()
	add_child(_scenery)
	_place_trees()
	_add_slime(SLIME_GREEN, Vector2(330, 200), 50.0, 0.0)
	_add_slime(SLIME_BLUE, Vector2(390, 236), 36.0, 1.3)
	_add_slime(SLIME_PINK, Vector2(150, 236), 30.0, 2.1)
	_build_ui()


# --- UI ---------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.size = UiStyle.SCREEN
	root.theme = UiStyle.make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.position = Vector2((UiStyle.SCREEN.x - LOGO.get_width()) / 2.0, LOGO_TOP)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(logo)
	var tagline := UiStyle.make_label("Restore the farm. Protect the harvest.", 10)
	tagline.position = Vector2(0, LOGO_TOP + LOGO.get_height() + 2)
	tagline.size = Vector2(UiStyle.SCREEN.x, 14)
	root.add_child(tagline)

	_menu.size = UiStyle.SCREEN
	_menu.position = Vector2(0, 34)  # sit below the title
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_menu)
	var column := UiStyle.make_centered_panel(_menu)
	var how_button := UiStyle.make_button("How to Play")
	var credits_button := UiStyle.make_button("Credits")
	var quit_button := UiStyle.make_button("Quit")
	for button in [_continue_button, _new_button, how_button, credits_button, quit_button]:
		column.add_child(button)
	_continue_button.visible = SaveGame.has_save()
	_continue_button.pressed.connect(_continue_game)
	_new_button.pressed.connect(_on_new_game_pressed)
	how_button.pressed.connect(_open_how_to_play)
	credits_button.pressed.connect(_open_credits)
	quit_button.pressed.connect(get_tree().quit)
	quit_button.visible = not OS.has_feature("web")  # a browser tab can't quit; you close the tab

	# Always-visible credit lines, centred along the bottom edge of the menu.
	root.add_child(_footer)
	_footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.offset_top = -30
	_footer.offset_bottom = -1
	_footer.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

	_how_to_play.closed.connect(_close_how_to_play.bind(how_button))
	root.add_child(_how_to_play)
	_credits.closed.connect(_close_how_to_play.bind(credits_button))
	root.add_child(_credits)
	_build_confirm(root)
	_focus_first_button()


## Continue (only when a save exists) is the default choice, otherwise New Game.
func _focus_first_button() -> void:
	(_continue_button if _continue_button.visible else _new_button).grab_focus()


func _continue_game() -> void:
	Game.reset()
	SaveGame.load_requested = true
	Game.get_tree().change_scene_to_file(Game.MAIN_SCENE)


## With a save on disk, ask before it is thrown away.
func _on_new_game_pressed() -> void:
	if not SaveGame.has_save():
		Game.start_new_game()
		return
	_menu.visible = false
	_footer.visible = false
	_confirm.visible = true
	_confirm_no_button.grab_focus()


func _confirm_new_game() -> void:
	SaveGame.delete()
	Game.start_new_game()


func _cancel_new_game() -> void:
	_confirm.visible = false
	_menu.visible = true
	_footer.visible = true
	_new_button.grab_focus()


func _build_confirm(root: Control) -> void:
	_confirm.size = UiStyle.SCREEN
	_confirm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.visible = false
	root.add_child(_confirm)
	var column := UiStyle.make_centered_panel(_confirm)
	column.add_child(UiStyle.make_label("Delete your saved game\nand start over?", UiStyle.TEXT_SIZE, UiStyle.HIGHLIGHT))
	var yes_button := UiStyle.make_button("Yes, start over")
	column.add_child(yes_button)
	column.add_child(_confirm_no_button)
	yes_button.pressed.connect(_confirm_new_game)
	_confirm_no_button.pressed.connect(_cancel_new_game)


func _open_how_to_play() -> void:
	_menu.visible = false
	_footer.visible = false
	_how_to_play.open()


func _open_credits() -> void:
	_menu.visible = false
	_footer.visible = false
	_credits.open()


## Back from How to Play or Credits: show the menu again, focused on `focus_button`.
func _close_how_to_play(focus_button: Button) -> void:
	_menu.visible = true
	_footer.visible = true
	focus_button.grab_focus()


# --- Scenery ----------------------------------------------------------------

func _build_ground() -> void:
	var grass := Sprite2D.new()
	grass.texture = GRASS_PLAIN
	grass.centered = false
	grass.region_enabled = true
	grass.region_rect = Rect2(Vector2.ZERO, UiStyle.SCREEN)
	grass.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(grass)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 40:
		var cell := Vector2i(rng.randi_range(0, 29), rng.randi_range(0, 16))
		var tuft := GRASS_TUFTS[rng.randi() % GRASS_TUFTS.size()]
		add_child(_tile_sprite(GRASS_TILES, tuft, cell))


## A block of tilled soil (3x3 autotile block in FarmLand_Tile.png) with ripe carrots.
func _build_carrot_patch() -> void:
	for x in PATCH_SIZE.x:
		for y in PATCH_SIZE.y:
			var piece := Vector2i(2, 1)  # centre piece
			piece.x = 1 if x == 0 else (3 if x == PATCH_SIZE.x - 1 else 2)
			piece.y = 0 if y == 0 else (2 if y == PATCH_SIZE.y - 1 else 1)
			add_child(_tile_sprite(FARMLAND, piece, PATCH_CELL + Vector2i(x, y)))

			var carrot := Sprite2D.new()
			carrot.texture = CROPS
			carrot.centered = false
			carrot.region_enabled = true
			carrot.region_rect = Rect2(RIPE_COLUMN * 16, CARROT_ROW * 32, 16, 32)
			carrot.offset = Vector2(-8, -30)  # same as Crop: node position is the tile's bottom-centre
			carrot.position = Vector2((PATCH_CELL + Vector2i(x, y)) * TILE) + Vector2(8, TILE)
			_scenery.add_child(carrot)


func _place_trees() -> void:
	for x in range(-8, 500, 48):
		_add_tree(BIG_OAK, Vector2(x, 26))
		_add_tree(BIG_OAK, Vector2(x + 24, 290))
	for spot in [Vector2(14, 120), Vector2(466, 110), Vector2(440, 180), Vector2(110, 160), Vector2(36, 210)]:
		_add_tree(MEDIUM_OAK, spot)


## `feet` is where the trunk meets the ground (frame 1 = tree with shadow).
func _add_tree(texture: Texture2D, feet: Vector2) -> void:
	var big := texture == BIG_OAK
	var tree := Sprite2D.new()
	tree.texture = texture
	tree.centered = false
	tree.region_enabled = true
	tree.region_rect = Rect2(64, 0, 64, 80) if big else Rect2(32, 0, 32, 48)
	tree.offset = Vector2(-32, -62) if big else Vector2(-16, -31)
	tree.position = feet
	_scenery.add_child(tree)


func _add_slime(texture: Texture2D, home: Vector2, wander: float, phase: float) -> void:
	var slime := TitleSlime.new()
	slime.texture = texture
	slime.home = home
	slime.wander = wander
	slime.time = phase
	_scenery.add_child(slime)


func _tile_sprite(texture: Texture2D, atlas_cell: Vector2i, cell: Vector2i) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(atlas_cell * TILE, Vector2(TILE, TILE))
	sprite.position = Vector2(cell * TILE)
	return sprite


## A slime that hops left and right around `home` (Slime_Medium sheet: row 1 = hop, 8 frames).
class TitleSlime extends Sprite2D:
	const HOP_ROW := 1
	const FRAMES := 8
	const FPS := 10.0
	const SPEED := 0.35  # how fast it wanders, in sine cycles per second

	var home := Vector2.ZERO
	var wander := 40.0
	var time := 0.0

	func _ready() -> void:
		hframes = 8
		vframes = 4
		offset = Vector2(0, -6)

	func _process(delta: float) -> void:
		time += delta
		var x := sin(time * SPEED * TAU)
		position = home + Vector2(x * wander, 0)
		flip_h = cos(time * SPEED * TAU) < 0.0  # facing the way it's moving
		frame = HOP_ROW * FRAMES + int(time * FPS) % FRAMES
