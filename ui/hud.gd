extends CanvasLayer

signal start_requested
signal restart_requested
signal menu_requested

const GREEN := Color(0.3, 1.0, 0.3)
const AMBER := Color(1.0, 0.7, 0.25)

@onready var game: Control = $Game
@onready var start_screen: Control = $StartScreen
@onready var end_screen: Control = $EndScreen
@onready var clock: Label = $Game/Clock/Time
@onready var penalty: Label = $Game/Clock/Penalty
@onready var blocks: Label = $Game/Blocks
@onready var misses: Label = $Game/Misses
@onready var status: Label = $Game/Bottom/Status
@onready var recharge: ProgressBar = $Game/Bottom/Recharge
@onready var prompt: Label = $Game/Bottom/Prompt
@onready var feedback: Label = $Game/Feedback

var feedback_left := 0.0
var penalty_left := 0.0


func _ready() -> void:
	$StartScreen/Frame/Margin/Content/Start.pressed.connect(func(): start_requested.emit())
	$EndScreen/Frame/Margin/Content/Buttons/Again.pressed.connect(func(): restart_requested.emit())
	$EndScreen/Frame/Margin/Content/Buttons/Menu.pressed.connect(func(): menu_requested.emit())


func _process(delta: float) -> void:
	feedback_left = maxf(0.0, feedback_left - delta)
	penalty_left = maxf(0.0, penalty_left - delta)
	feedback.visible = game.visible and feedback_left > 0.0
	penalty.visible = game.visible and penalty_left > 0.0


func show_start() -> void:
	game.hide()
	start_screen.show()
	end_screen.hide()
	$StartScreen/Frame/Margin/Content/Start.grab_focus()


func show_game() -> void:
	start_screen.hide()
	end_screen.hide()
	game.show()
	get_viewport().gui_release_focus()


func show_end(did_win: bool, broken: int, target: int, missed: int, seconds: float) -> void:
	game.hide()
	start_screen.hide()
	end_screen.show()
	var content := $EndScreen/Frame/Margin/Content
	content.get_node("Title").text = "MISSION COMPLETE" if did_win else "TIME UP"
	content.get_node("Title").modulate = GREEN if did_win else AMBER
	content.get_node("Subtitle").text = "All targets cleared. Signal secured." if did_win else "Time expired. Take another shot."
	content.get_node("Results").text = "BLOCKS DESTROYED    %02d / %02d\nMISSED BALLS        %02d\nTIME REMAINING      %s" % [broken, target, missed, format_time(seconds)]
	content.get_node("Buttons/Again").grab_focus()


func update_game(seconds: float, broken: int, target: int, missed: int, active: bool, cooldown: float, cooldown_duration: float, launched: bool) -> void:
	clock.text = format_time(seconds)
	clock.modulate = AMBER if seconds <= 10.0 else GREEN
	blocks.text = "BLOCKS  %02d / %02d" % [broken, target]
	misses.text = "MISSES  %02d" % missed
	status.text = "ACTIVE" if active else ("RECHARGING" if cooldown > 0.0 else "PADDLE READY")
	status.modulate = AMBER if cooldown > 0.0 else GREEN
	recharge.value = 100.0 * (1.0 - clampf(cooldown / cooldown_duration, 0.0, 1.0))
	prompt.text = "SPACE / CLICK TO SWING    •    A / D TO MOVE" if launched else "SPACE / CLICK TO LAUNCH    •    A / D TO MOVE"


func notify_return() -> void:
	feedback.text = "RETURNED"
	feedback.modulate = GREEN
	feedback_left = 0.65


func notify_miss(seconds: float) -> void:
	feedback.text = "MISSED — BALL RESET"
	feedback.modulate = AMBER
	feedback_left = 1.4
	penalty.text = "−%ds" % int(seconds)
	penalty_left = 1.4


func format_time(seconds: float) -> String:
	var total := ceili(maxf(0.0, seconds))
	return "%02d:%02d" % [total / 60, total % 60]
