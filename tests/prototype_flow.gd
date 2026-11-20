extends SceneTree

var game: Node
var checks := 0


func _initialize() -> void:
	call_deferred("run_checks")


func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAIL: " + message)
		quit(1)
		assert(condition, message)
	checks += 1


func frames(count: int) -> void:
	for i in count:
		await physics_frame


func assert_layout(screen: Control) -> void:
	var frame: Control = screen.get_node("Frame")
	var margin: Control = frame.get_node("Margin")
	check(margin.get_combined_minimum_size().y <= frame.size.y, "menu content fits panel height")
	check(margin.get_combined_minimum_size().x <= frame.size.x, "menu content fits panel width")


func run_checks() -> void:
	root.size = Vector2i(1152, 720)
	game = load("res://prototype1.tscn").instantiate()
	check(game.get_node("Bricks").get_child_count() == 54, "level is authored in scene")
	root.add_child(game)
	current_scene = game
	await frames(20)
	check(game.hud.start_screen.visible and not game.hud.game.visible, "start screen is initial state")
	check(game.time_left == 90.0 and not game.launched, "menu does not start timer or launch")
	assert_layout(game.hud.start_screen)
	var start_button: Button = game.hud.get_node("StartScreen/Frame/Margin/Content/Start")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = start_button.global_position + start_button.size * 0.5
	click.pressed = true
	root.push_input(click)
	var release := click.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release)
	await frames(3)
	check(game.started and not game.timer_started and not game.launched, "start enters ready state without launching")
	check(game.hud.game.visible and not game.hud.start_screen.visible, "start changes UI")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	root.push_input(space)
	check(game.launched and game.timer_started, "first launch starts clock")
	game.ball.position = Vector3(0, 1.5, -0.8)
	game.velocity = Vector3(0, 0, 12)
	game.swing()
	await frames(5)
	check(game.velocity.z < 0, "active paddle physically returns incoming ball")
	check(game.hud.feedback.text == "RETURNED", "successful return has distinct text")
	check(game.return_flash_left > 0.0 and game.trail_positions.size() > 0, "return lights paddle and produces trail")
	check(game.get_node("Audio/Return").stream != null, "return sound is loaded")
	await frames(13)
	check(not game.paddle_active and game.cooldown_left > 0.0, "swing enters cooldown")
	check(game.paddle_shape.disabled, "flash does not extend paddle collision window")
	check(game.hud.status.text == "RECHARGING", "cooldown is visible")
	var before: float = game.time_left
	game.ball.position = Vector3(0, 1.5, 3)
	game.velocity = Vector3(0, 0, 12)
	await frames(2)
	check(game.misses == 1 and not game.launched, "miss resets ball and increments misses")
	check(before - game.time_left >= 3.0 and before - game.time_left < 3.2, "miss deducts exactly three seconds plus elapsed time")
	check(game.hud.feedback.text == "MISSED — BALL RESET" and game.hud.penalty.text == "−3s", "miss and penalty feedback differ from return")
	check(game.ball.position.is_equal_approx(Vector3(0, 1.5, -1)), "miss snaps ball to launch position")
	var misses: int = game.misses
	await frames(10)
	check(game.misses == misses, "waiting to relaunch does not repeat penalty")
	check(game.timer_started and game.time_left < before - 3.0, "timer keeps running after a miss")
	game.time_left = 9.5
	game.update_hud()
	check(game.hud.clock.text == "00:10" and game.hud.clock.modulate == game.hud.AMBER, "last ten seconds use amber MM:SS")
	game.time_left = 2.0
	game.respawn_ball()
	check(game.finished and not game.won and game.time_left == 0.0, "penalty clamps at zero and ends run")
	check(game.hud.end_screen.visible and not game.hud.game.visible, "timeout displays results")
	assert_layout(game.hud.end_screen)
	game.launch()
	check(game.finished and not game.launched, "gameplay input cannot restart results screen")
	game.hud.get_node("EndScreen/Frame/Margin/Content/Buttons/Again").pressed.emit()
	await process_frame
	await frames(3)
	game = current_scene
	check(game.started and not game.finished and not game.timer_started, "play again returns directly to ready state")
	check(game.misses == 0 and game.time_left == 90.0 and get_nodes_in_group("brick").size() == 54, "restart resets stats and restores bricks")
	game.launch()
	game.blocks_broken = 34
	game.ball.position = Vector3(0, 0.8, -12)
	game.velocity = Vector3(0, 0, -12)
	await frames(20)
	check(game.finished and game.won and game.blocks_broken == 35, "brick collision triggers victory")
	check(game.hud.get_node("EndScreen/Frame/Margin/Content/Title").text == "MISSION COMPLETE", "win title differs from timeout")
	check(game.hud.get_node("EndScreen/Frame/Margin/Content/Results").text.contains("35 / 35"), "results contain final stats")
	# Give the audio mixer time to finish the result cue before unloading its scene.
	await create_timer(0.7).timeout
	game.hud.get_node("EndScreen/Frame/Margin/Content/Buttons/Menu").pressed.emit()
	await process_frame
	await frames(3)
	game = current_scene
	check(not game.started and game.hud.start_screen.visible, "main menu button restores start screen")
	print("PASS: %d checks covering menus, physics, feedback, penalty, win, timeout, restart and layout" % checks)
	game.queue_free()
	await process_frame
	await process_frame
	quit()
