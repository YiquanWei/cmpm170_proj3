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

func fresh() -> void:
	if current_scene:
		current_scene.queue_free()
		await process_frame
	game = load("res://prototype2.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(3)

func layout(screen: Control) -> void:
	var frame: Control = screen.get_node("Frame")
	var margin: Control = frame.get_node("Margin")
	check(margin.get_combined_minimum_size().x <= frame.size.x, "menu fits panel width")
	check(margin.get_combined_minimum_size().y <= frame.size.y, "menu fits panel height")

func run_checks() -> void:
	root.size = Vector2i(1152, 720)
	await fresh()
	check(game.get_node("Wall").get_child_count() == 20, "20 authored wall blocks")
	check(get_nodes_in_group("defence_block").size() == 20, "all blocks have saved collision group")
	check(game.emitters.get_child_count() == 3, "3 enemy emitters")
	await frames(12)
	check(game.elapsed == 0 and game.projectiles.is_empty(), "menu pauses clock and fire")
	layout(game.hud.start_screen)
	var button: Button = game.hud.get_node("StartScreen/Frame/Margin/Content/Start")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = button.global_position + button.size * 0.5
	click.pressed = true
	root.push_input(click)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click)
	check(game.started and game.hud.game.visible, "start button begins defence")
	var key := InputEventKey.new()
	key.keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	await frames(40)
	check(is_equal_approx(game.wall.position.x, 5.1), "right movement clamps to arena")
	check(is_equal_approx(game.camera.position.x, game.wall.position.x), "first person camera follows defence")
	key.pressed = false
	Input.parse_input_event(key)
	key = InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	Input.parse_input_event(key)
	await frames(70)
	check(is_equal_approx(game.wall.position.x, -5.1), "left movement clamps to arena")
	key.pressed = false
	Input.parse_input_event(key)
	game.wall.position.x = 0
	await frames(100)
	check(game.elapsed > 1 and game.projectiles.size() >= 1, "enemies fire automatically")
	for ball in game.projectiles.duplicate():
		game.remove_ball(ball)
	game.fire_left = 999.0
	await frames(2)
	var incoming = game.spawn_ball(Vector3(-1.35, 1.5, -4), Vector3(0, 0, 9))
	await frames(18)
	check(game.intercepted == 1 and get_nodes_in_group("defence_block").size() == 19, "one collision consumes exactly one block")
	check(incoming.get_meta("returned") and incoming.get_meta("velocity").z < 0, "ball reflects toward enemies")
	check(incoming.get_node("Trail/Dot1").visible, "moving projectile has a visible trail")
	check(incoming.collision_mask == 5, "returned ball cannot consume more wall blocks")
	check(game.health == 3, "successful interception protects base")
	await frames(15)
	check(game.intercepted == 1, "same reflected ball never consumes a second block")
	game.spawn_ball(Vector3(6, 1.5, 3.1), Vector3(0, 0, 9))
	await frames(2)
	check(game.health == 2 and game.intercepted == 1, "miss costs one base life and no blocks")
	check(game.hud.get_node("Game/Feedback").text.contains("BASE HIT"), "miss has distinct feedback")
	game.spawn_ball(Vector3(6, 1.5, 3.1), Vector3(0, 0, 9))
	game.spawn_ball(Vector3(-6, 1.5, 3.1), Vector3(0, 0, 9))
	await frames(3)
	check(game.finished and not game.won and game.health == 0, "third base hit loses")
	check(game.projectiles.is_empty() and game.hud.end_screen.visible, "ending clears live projectiles")
	layout(game.hud.end_screen)
	game.hud.get_node("EndScreen/Frame/Margin/Content/Buttons/Again").pressed.emit()
	await process_frame
	await frames(3)
	game = current_scene
	check(game.started and not game.finished and game.health == 3 and game.intercepted == 0, "restart resets all stats")
	check(get_nodes_in_group("defence_block").size() == 20, "restart restores wall")
	game.fire_left = 999
	# Exercise real collision for every block, including deeper wall layers.
	for i in 20:
		for ball in game.projectiles.duplicate():
			game.remove_ball(ball)
		var block: Node3D = get_nodes_in_group("defence_block")[0]
		var p := block.global_position + Vector3(0, 0, -1)
		game.spawn_ball(p, Vector3(0, 0, 9))
		await frames(15)
		check(game.intercepted == i + 1, "wall block %d is reachable" % (i + 1))
	check(game.finished and game.won and game.health == 3, "last block wins with living base")
	check(game.projectiles.is_empty(), "last block ends fire immediately")
	check(game.hud.get_node("EndScreen/Frame/Margin/Content/Title").text == "BASE SECURED", "victory summary is distinct")
	var time: float = game.elapsed
	await frames(10)
	check(game.elapsed == time, "survival clock stops at ending")
	await create_timer(0.7).timeout
	game.hud.get_node("EndScreen/Frame/Margin/Content/Buttons/Menu").pressed.emit()
	await process_frame
	await frames(3)
	game = current_scene
	check(not game.started and game.hud.start_screen.visible, "main menu resets prototype2")
	game.queue_free()
	await process_frame
	print("PASS: %d prototype2 checks, including real collisions for all 20 blocks" % checks)
	quit()
