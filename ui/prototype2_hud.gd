extends CanvasLayer

signal start_requested
signal restart_requested
signal menu_requested

const CYAN := Color(0.2, 0.9, 1.0)
const ORANGE := Color(1.0, 0.3, 0.12)

@onready var game: Control = $Game
@onready var start_screen: Control = $StartScreen
@onready var end_screen: Control = $EndScreen
var feedback_left := 0.0

func _ready() -> void:
	$StartScreen/Frame/Margin/Content/Start.pressed.connect(func(): start_requested.emit())
	$EndScreen/Frame/Margin/Content/Buttons/Again.pressed.connect(func(): restart_requested.emit())
	$EndScreen/Frame/Margin/Content/Buttons/Menu.pressed.connect(func(): menu_requested.emit())
	$Game/Clock/Penalty.hide()

func _process(delta: float) -> void:
	feedback_left = maxf(0, feedback_left - delta)
	$Game/Feedback.visible = game.visible and feedback_left > 0

func show_start() -> void:
	game.hide()
	end_screen.hide()
	start_screen.show()
	$StartScreen/Frame/Margin/Content/Start.grab_focus()

func show_game() -> void:
	start_screen.hide()
	end_screen.hide()
	game.show()
	get_viewport().gui_release_focus()

func update_game(seconds: float, intercepted: int, target: int, health: int, max_health: int) -> void:
	$Game/Clock/Time.text = format_time(seconds)
	$Game/Blocks.text = "INTERCEPTS  %02d / %02d" % [intercepted, target]
	$Game/Misses.text = "WALL BLOCKS  %02d" % (target - intercepted)
	$Game/Bottom/Status.text = "BASE INTEGRITY  %d / %d" % [health, max_health]
	$Game/Bottom/Status.modulate = ORANGE if health == 1 else CYAN
	$Game/Bottom/Recharge.value = 100.0 * health / max_health
	$Game/Bottom/Prompt.text = "A / D OR ARROWS TO MOVE THE WALL"

func notify_intercept() -> void:
	$Game/Feedback.text = "INTERCEPTED — 1 BLOCK USED"
	$Game/Feedback.modulate = CYAN
	feedback_left = 0.8

func notify_base_hit() -> void:
	$Game/Feedback.text = "BASE HIT — INTEGRITY LOST"
	$Game/Feedback.modulate = ORANGE
	feedback_left = 1.3

func show_end(did_win: bool, intercepted: int, target: int, health: int, seconds: float) -> void:
	game.hide()
	start_screen.hide()
	end_screen.show()
	var content := $EndScreen/Frame/Margin/Content
	content.get_node("Title").text = "BASE SECURED" if did_win else "BASE LOST"
	content.get_node("Title").modulate = CYAN if did_win else ORANGE
	content.get_node("Subtitle").text = "Evacuation complete. You held the line." if did_win else "The defence was breached. Try again."
	content.get_node("Results").text = "INTERCEPTIONS      %02d / %02d\nBASE INTEGRITY     %d / 3\nSURVIVAL TIME      %s" % [intercepted, target, health, format_time(seconds)]
	content.get_node("Buttons/Again").grab_focus()

func format_time(seconds: float) -> String:
	var total := int(maxf(0.0, seconds))
	return "%02d:%02d" % [total / 60, total % 60]
