class_name GoalsList
extends VBoxContainer
## Every farm goal on one list: done ones dimmed with [x], the current one highlighted with ">".
## A plain Control so a panel (the inventory's Goals tab) can hold it.
## It rebuilds its rows from Game whenever the stats change or it is shown.

const DONE_COLOR := Color(0.55, 0.9, 0.55, 0.65)
const TODO_COLOR := Color(0.85, 0.8, 0.7)
const ROW_WIDTH := 230.0

var _rows: Array[Label] = []
var _current_row: Label  # row of the current goal, null when all are done


func _ready() -> void:
	add_theme_constant_override("separation", 1)
	Game.stats_changed.connect(refresh)
	visibility_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		return
	var goals := FarmGoals.build(Game.goal_state())
	var current := FarmGoals.current(goals)
	_current_row = null
	while _rows.size() < goals.size():
		var row := Label.new()
		row.custom_minimum_size.x = ROW_WIDTH
		add_child(row)
		_rows.append(row)
	for i in goals.size():
		var goal: Dictionary = goals[i]
		var row := _rows[i]
		var is_current: bool = goal["id"] == current.get("id", "")
		if is_current:
			_current_row = row
		var mark := "[x] " if goal["done"] else ("> " if is_current else "[ ] ")
		row.text = mark + String(goal["text"])
		row.add_theme_color_override("font_color", DONE_COLOR if goal["done"] else (UiStyle.HIGHLIGHT if is_current else TODO_COLOR))


## The row of the goal to do next (so a scroll box can show it), or null.
func current_row() -> Label:
	return _current_row
