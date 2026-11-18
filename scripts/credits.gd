class_name Credits
extends Control
## "Credits" panel opened from the title screen, plus the one-line footer the title shows
## all the time. All names and course details live in the constants below.

signal closed

const GAME_TITLE := "Slime Harvest"
const DEVELOPER := "Imogen Inocentes"
const COURSE := "BS Computer Science 4"
const PROJECT := "Final Project"
const WEBSITE := "www.imogen.dev"
const WEBSITE_URL := "https://www.imogen.dev"
const INTRO := ("Imogen Inocentes is a Lead Software Engineer at Nexvision Innovations Inc., "
		+ "an AI consultant to Pro Solutions Technology, the founder of Zentari Software, "
		+ "and a Certified Google Gen AI Leader.")
## [role, who]
const LINES := [
	["Game design & programming", DEVELOPER],
	["Characters", "Imogen and Gayle, with Azy at the market stall"],
	["Made for", "%s - %s" % [PROJECT, COURSE]],
	["Website", WEBSITE],
	["Art", "\"Cute Fantasy RPG\" asset pack by Kenmi (kenmi-art.itch.io)"],
	["Engine", "Godot Engine 4.7 (godotengine.org)"],
	["Sound & music", "Generated in code (tools/gen_audio.py)"],
]
const KEY_COLOR := Color(1.0, 0.85, 0.4)

var _back_button := UiStyle.make_button("Back")
var _website_button := UiStyle.make_button("Visit " + WEBSITE)


## The two lines shown at the bottom of the title screen.
static func footer_text() -> String:
	return "Developed by %s  -  %s
%s, %s" % [DEVELOPER, WEBSITE, PROJECT, COURSE]


func _ready() -> void:
	size = UiStyle.SCREEN
	visible = false
	var column := UiStyle.make_centered_panel(self, 6)
	column.add_child(UiStyle.make_label("Credits", 12, KEY_COLOR))
	column.add_child(UiStyle.make_label(GAME_TITLE, 10))

	var about := UiStyle.make_label("About the developer", UiStyle.TEXT_SIZE, KEY_COLOR)
	column.add_child(about)
	var intro := UiStyle.make_label(INTRO)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(330, 0)
	intro.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(intro)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	for row: Array in LINES:
		var role := UiStyle.make_label(row[0], UiStyle.TEXT_SIZE, KEY_COLOR)
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(role)
		var who := UiStyle.make_label(row[1])
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(who)
	column.add_child(grid)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	_website_button.pressed.connect(func() -> void: OS.shell_open(WEBSITE_URL))
	_back_button.pressed.connect(close)
	buttons.add_child(_website_button)
	buttons.add_child(_back_button)
	column.add_child(buttons)


func open() -> void:
	visible = true
	_back_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
