class_name LoadingTips
extends RefCounted
## Tips shown on loading screens and the pure helpers behind them (tested).
## The web shell (html/shell.html) keeps its own copy of the tip list: keep them in sync.

const TIPS: Array[String] = [
	"Water your crops: only wet soil grows.",
	"Slimes go for ripe and growing crops at night. Fence them out.",
	"Sleep in the farmhouse bed to skip to the next morning.",
	"Sell your harvest at the market stall to buy seeds and upgrades.",
	"Chickens and cows give eggs and milk every day.",
	"Gayle waters the crops by day and fights slimes at night.",
	"Press Tab to open your bag and your goals.",
	"Big slimes split in two when they die.",
	"Restoring buildings is how you win. Check the board sign.",
	"Fruit trees take a few days to grow, plant them early.",
]


## Tip for a number (pass randi()). Always valid, even for negative numbers.
static func tip(number: int) -> String:
	return TIPS[posmod(number, TIPS.size())]


## ResourceLoader.load_threaded_get_status fills `progress` with one float 0..1.
static func percent(progress: Array) -> int:
	if progress.is_empty():
		return 0
	return clampi(roundi(float(progress[0]) * 100.0), 0, 100)
