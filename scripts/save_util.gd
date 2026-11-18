class_name SaveUtil
extends RefCounted
## Small helpers for reading save data safely. A save file can be hand-edited or damaged,
## so every system reads its values through these instead of trusting the types.


static func is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


## A number from `data[key]`, or `fallback` when it is missing or not a number.
static func number(data: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = data.get(key)
	return float(value) if is_number(value) else fallback


## An Array from a saved value, or an empty one.
static func list(value: Variant) -> Array:
	return value if value is Array else []


## A Dictionary from a saved value, or an empty one.
static func dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


## True when `entry` is an Array that starts with `numbers` numbers (e.g. 2 for [x, y]).
static func is_entry(entry: Variant, numbers: int) -> bool:
	if not entry is Array or entry.size() < numbers:
		return false
	for i in numbers:
		if not is_number(entry[i]):
			return false
	return true


## "id -> count" dictionary keeping only known ids with a count above 0.
static func counts(value: Variant, valid_ids: Array) -> Dictionary:
	var result := {}
	for id: Variant in dict(value):
		var count: Variant = value[id]
		if valid_ids.has(id) and is_number(count) and int(count) > 0:
			result[id] = int(count)
	return result
