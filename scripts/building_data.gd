class_name BuildingData
extends RefCounted
## Art and placement of every restorable building (pure data, no nodes, so tests can check it).
## One entry per id in Restoration.PROJECTS. See docs/ASSETS.md for the sheets.
##   plot       the WorldLayout area the building stands in
##   texture    sprite sheet, region = the part of it that is the building
##   foot       pixel in the region where the building meets the ground (the door for houses);
##              it is put on the bottom-middle of the plot
##   collision  walls the player can't walk through, relative to the foot
##   sails      (windmill only) animated sheet of 4 frames + the hub position relative to the foot

const TILE := 16
const BUILDINGS := "res://assets/cute_fantasy/Buildings/Buildings/"
## The foot sits this many pixels above the bottom edge of the plot.
const FOOT_MARGIN := 3

const SPECS := {
	"well": {
		"plot": &"well_plot",
		"texture": "res://assets/cute_fantasy/Outdoor decoration/Well.png",
		"region": Rect2(0, 0, 32, 48),
		"foot": Vector2(16, 47),
		"collision": Rect2(-10, -10, 20, 10),
	},
	"farmhouse": {
		"plot": &"farmhouse_plot",
		"texture": BUILDINGS + "Houses/Wood/House_3_Wood_Base_Red.png",
		"region": Rect2(0, 0, 144, 128),
		"foot": Vector2(89, 112),
		"collision": Rect2(-76, -24, 118, 24),
	},
	"chicken_coop": {
		"plot": &"coop_plot",
		"texture": BUILDINGS + "Unique_Buildings/Coop/Coop_Red_Red.png",
		"region": Rect2(0, 0, 80, 128),
		"foot": Vector2(40, 126),
		"collision": Rect2(-26, -16, 52, 16),
	},
	"barn": {
		"plot": &"barn_plot",
		"texture": BUILDINGS + "Unique_Buildings/Barn/Barn_Red_Red.png",
		"region": Rect2(0, 0, 128, 144),
		"foot": Vector2(64, 131),
		"collision": Rect2(-50, -20, 100, 20),
	},
	"windmill": {
		"plot": &"windmill_plot",
		"texture": BUILDINGS + "Unique_Buildings/Windmill/Windmill.png",
		"region": Rect2(0, 0, 64, 112),
		"foot": Vector2(32, 108),
		"collision": Rect2(-20, -14, 40, 14),
		"sails": {
			"texture": BUILDINGS + "Unique_Buildings/Windmill/Windmill_Sail_Anim.png",
			"frames": 4,
			"hub": Vector2(0, -64),
		},
	},
	"greenhouse": {
		"plot": &"greenhouse_plot",
		"texture": BUILDINGS + "Unique_Buildings/Greenhouse/GreenHouse_Wood.png",
		"region": Rect2(96, 0, 96, 128),
		"foot": Vector2(48, 116),
		"collision": Rect2(-44, -14, 88, 14),
	},
}


static func spec(id: String) -> Dictionary:
	return SPECS.get(id, {})


## Where the building stands: bottom-middle of its plot (a world position, in pixels).
## For the farmhouse and barn this is right in front of the door.
static func foot_position(id: String) -> Vector2:
	var plot := WorldLayout.area(spec(id).get("plot", &""))
	return Vector2(
		(plot.position.x + plot.size.x / 2.0) * TILE,
		plot.end.y * TILE - FOOT_MARGIN)
