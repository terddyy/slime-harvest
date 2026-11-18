class_name UiStyle
extends RefCounted
## Shared look for menus (title, pause, how-to-play, end screen):
## dark-brown panels with a light border, small pixel-friendly text.
## Only static helpers, so any script can call e.g. UiStyle.make_button("Start").

const SCREEN := Vector2(480, 270)

const PANEL_COLOR := Color(0.22, 0.14, 0.09)
const PANEL_BORDER := Color(0.86, 0.72, 0.5)
const BUTTON_COLOR := Color(0.36, 0.24, 0.15)
const BUTTON_BORDER := Color(0.55, 0.4, 0.27)
const BUTTON_HOVER_COLOR := Color(0.5, 0.33, 0.19)
const HIGHLIGHT := Color(1.0, 0.85, 0.4)
const TEXT_COLOR := Color(0.98, 0.92, 0.8)
const OUTLINE_COLOR := Color(0.1, 0.07, 0.05)

const TEXT_SIZE := 8
const BUTTON_TEXT_SIZE := 10
const BUTTON_SIZE := Vector2(96, 18)


## Theme to put on the root Control of a menu. Children inherit it.
static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = TEXT_SIZE
	theme.set_color("font_color", "Label", TEXT_COLOR)
	theme.set_color("font_outline_color", "Label", OUTLINE_COLOR)
	theme.set_constant("outline_size", "Label", 3)

	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_stylebox("panel", "Panel", panel_style())

	theme.set_font_size("font_size", "Button", BUTTON_TEXT_SIZE)
	theme.set_stylebox("normal", "Button", _box(BUTTON_COLOR, BUTTON_BORDER))
	theme.set_stylebox("hover", "Button", _box(BUTTON_HOVER_COLOR, HIGHLIGHT))
	theme.set_stylebox("pressed", "Button", _box(BUTTON_COLOR.darkened(0.3), HIGHLIGHT))
	theme.set_stylebox("hover_pressed", "Button", _box(BUTTON_COLOR.darkened(0.3), HIGHLIGHT))
	# Focus is drawn on top of "normal": a bright border shows which button Enter will press.
	var focus := _box(BUTTON_HOVER_COLOR, HIGHLIGHT)
	theme.set_stylebox("focus", "Button", focus)
	for color_name in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(color_name, "Button", TEXT_COLOR)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	return theme


static func panel_style() -> StyleBoxFlat:
	var style := _box(PANEL_COLOR, PANEL_BORDER)
	style.set_content_margin_all(8)
	return style


## A menu button. Hovering with the mouse also moves keyboard focus,
## so only one button is ever highlighted.
static func make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.mouse_entered.connect(button.grab_focus)
	return button


static func make_label(text: String, font_size := TEXT_SIZE, color := TEXT_COLOR) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## A vertical stack of widgets inside a bordered panel, centred on the screen.
## Returns the VBoxContainer to add widgets to; the panel is its parent.
static func make_centered_panel(parent: Control, separation := 4) -> VBoxContainer:
	var center := CenterContainer.new()
	center.size = SCREEN
	parent.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)
	return column


static func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.anti_aliasing = false
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style
