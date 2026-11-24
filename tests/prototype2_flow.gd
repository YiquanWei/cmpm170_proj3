extends SceneTree

var game: Node
var checks := 0
var record_path := "user://prototype2-test-%d.cfg" % OS.get_process_id()

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
		await create_timer(0.7).timeout
		current_scene.queue_free()
		await process_frame
	game = load("res://prototype2.tscn").instantiate()
	game.record_path = record_path
	root.add_child(game)
	current_scene = game
	await frames(3)

# Fresh scene, build the given cells, then start defending with enemy fire held.
func defend(cells: Array) -> void:
	await fresh()
	game.start_build()
	for cell in cells:
		game.place_block(cell)
	game.start_run()
	game.fire_left = 999
	await frames(2)

func screen_of(world: Vector3) -> Vector2:
	return game.camera.unproject_position(world)

func click(button: MouseButton, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = at
	game._unhandled_input(event)

func layout(screen: Control) -> void:
	var frame: Control = screen.get_node("Frame")
	var margin: Control = frame.get_node("Margin")
	check(margin.get_combined_minimum_size().x <= frame.size.x, "menu fits width")
	check(margin.get_combined_minimum_size().y <= frame.size.y, "menu fits height")

func run_checks() -> void:
	root.size = Vector2i(1152, 720)
	await fresh()
	check(get_nodes_in_group("defence_block").is_empty(), "no pre-placed defence before building")
	check(game.hud.start_screen.visible and not game.building, "game opens on the instructions screen")
	layout(game.hud.start_screen)
	check(game.best_time == 0, "missing record starts at zero")
	var ball = game.spawn_ball(Vector3(0, 1.5, -10), Vector3.ZERO)
	check(is_equal_approx(ball.get_node("CollisionShape3D").shape.radius, .09), "ball collider matches visual radius")
	game.remove_ball(ball)

	# Build phase: grid, budget, picking.
	game.start_build()
	check(game.building and game.grid.visible and game.hud.build.visible, "start enters build mode with the grid shown")
	check(game.hud.get_node("Build/Bottom/Defend").disabled, "DEFEND is locked until a block is placed")
	game.start_run()
	check(not game.started, "cannot defend with an empty grid")
	await frames(10)
	check(game.elapsed == 0 and game.projectiles.is_empty(), "no clock and no enemy fire while building")
	var picks_ok := true
	for x in game.GRID_COLS:
		for y in game.GRID_ROWS:
			var cell := Vector2i(x, y)
			picks_ok = picks_ok and game.cell_at(screen_of(game.wall.to_global(game.cell_center(cell)))) == cell
	check(picks_ok, "mouse picking maps every visible grid cell to itself")
	check(game.cell_at(Vector2(4, 4)) == game.NO_CELL, "clicking off the grid selects nothing")
	click(MOUSE_BUTTON_LEFT, screen_of(game.cell_center(Vector2i(0, 0))))
	check(game.blocks.has(Vector2i(0, 0)), "left click places a block")
	check(not game.hud.get_node("Build/Bottom/Defend").disabled, "DEFEND unlocks after the first block")
	check(not game.place_block(Vector2i(0, 0)), "a cell holds only one block")
	for y in game.GRID_ROWS:
		game.place_block(Vector2i(1, y))
	var heights_ok := true
	for y in game.GRID_ROWS:
		var block: StaticBody3D = game.blocks[Vector2i(1, y)]
		var size: Vector3 = block.get_node("CollisionShape3D").shape.size
		heights_ok = heights_ok and is_equal_approx(block.position.y - size.y / 2, 0.0)
		heights_ok = heights_ok and block.position.y + size.y / 2 > game.BALL_Y + .09
		heights_ok = heights_ok and is_equal_approx(size.x, 0.92) and is_equal_approx(block.scale.x, 1.0)
		if y > 0:
			heights_ok = heights_ok and size.y > game.blocks[Vector2i(1, y - 1)].get_node("CollisionShape3D").shape.size.y
	check(heights_ok, "blocks sit on the floor, cover the ball lane, and get taller away from the camera")
	var halves: Node3D = game.blocks[Vector2i(1, 0)]
	check(halves.get_node("Mesh").position.x < 0 and halves.get_node("Mesh2").position.x > 0, "each block is two cubes side by side")
	await frames(2)
	var tall: StaticBody3D = game.blocks[Vector2i(1, 3)]
	click(MOUSE_BUTTON_RIGHT, screen_of(tall.global_position + Vector3(0, .6, 0)))
	check(not game.blocks.has(Vector2i(1, 3)) and game.blocks.size() == 4, "right click removes the block under the cursor")
	for x in range(2, game.GRID_COLS):
		game.place_block(Vector2i(x, 0))
	check(game.blocks.size() == game.BLOCK_BUDGET, "budget fills at 8 blocks")
	check(not game.place_block(Vector2i(7, 3)), "cannot place past the 8-block budget")
	check(game.hud.get_node("Build/Count").text == "BLOCKS  8 / 8", "build HUD shows budget use")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	game._unhandled_input(enter)
	check(game.started and not game.building and not game.grid.visible, "ENTER starts defending and hides the grid")
	check(game.placed_total == 8 and game.hud.get_node("Game/Blocks").text == "BLOCKS LEFT  008", "defend HUD counts placed blocks")
	click(MOUSE_BUTTON_LEFT, screen_of(game.cell_center(Vector2i(7, 3))))
	check(game.blocks.size() == 8, "no building once defending")

	var probe = game.spawn_ball(Vector3(0, 1.5, -10), Vector3(5, 12, 0))
	check(is_equal_approx(probe.position.y, game.BALL_Y) and is_equal_approx(probe.get_meta("velocity").y, 0.0), "balls spawn flat on the lane")
	check(is_equal_approx(probe.get_meta("velocity").length(), Vector3(5, 12, 0).length()), "flattening keeps ball speed")
	var confined := true
	game.set_physics_process(false)
	for i in 360:
		game.move_ball(probe, 1.0 / 60.0)
		confined = confined and is_equal_approx(probe.position.y, game.BALL_Y)
		confined = confined and absf(probe.position.x) <= game.BALL_MAX_X + .005
	check(confined, "repeated side rebounds never move the ball off its lane")
	var shot = game.fire_enemy_ball()
	check(is_equal_approx(shot.get_meta("velocity").y, 0.0) and is_equal_approx(shot.position.y, game.BALL_Y), "emitters fire flat shots")
	game.remove_ball(shot)
	game.remove_ball(probe)
	game.set_physics_process(true)

	# Far-row block at x -1.5, front face z -2.9.
	await defend([Vector2i(2, 3)])
	ball = game.spawn_ball(Vector3(-1.9, .65, -3.6), Vector3(2, 0, 8))
	await frames(6)
	check(game.intercepted == 1 and game.blocks.is_empty(), "one hit breaks the whole two-cube block")
	var v: Vector3 = ball.get_meta("velocity")
	check(v.is_equal_approx(Vector3(2, 0, -8)), "frontal bounce preserves tangential velocity and incident angle")
	check(ball.collision_mask == 7, "ball remains able to hit blocks after bouncing")
	check(ball.get_node("Trail/Dot1").visible, "ball retains readable trail")
	check(game.health == 3, "block impact does not hurt base")
	await defend([Vector2i(2, 3)])
	ball = game.spawn_ball(Vector3(-2.3, .65, -2.6), Vector3(8, 0, 1.2))
	await frames(4)
	v = ball.get_meta("velocity")
	check(v.is_equal_approx(Vector3(-8, 0, 1.2)), "side impact reverses x, without forcing z away from the base")
	# Empty cell 4 between blocks in cells 3 and 5.
	await defend([Vector2i(3, 1), Vector2i(5, 1)])
	ball = game.spawn_ball(Vector3(0.5, game.BALL_Y, -1.2), Vector3(90, 0, .8))
	await frames(2)
	check(game.intercepted == 2, "one ball breaks two blocks through successive side bounces")
	check(is_instance_valid(ball) and not ball.is_queued_for_deletion(), "ricocheting ball stays alive")
	check(game.health == 3, "ricochet channel does not falsely damage base")
	# Wall limits follow the outermost blocks, so a one-sided build can still cover the far side.
	await defend([Vector2i(6, 0), Vector2i(7, 2)])
	var right_side: StaticBody3D = game.blocks[Vector2i(6, 0)]
	game.wall.position.x = -99
	await frames(2)
	check(is_equal_approx(right_side.global_position.x - .46, -game.LANE_EDGE), "a right-side build slides until its leftmost block meets the left rail")
	await frames(60)
	check(absf(game.camera.position.x - game.defence_center()) < .05, "camera follows the centre of the defence")
	game.wall.position.x = 99
	await frames(2)
	var far_right: StaticBody3D = game.blocks[Vector2i(7, 2)]
	check(is_equal_approx(far_right.global_position.x + .46, game.LANE_EDGE), "rightmost block stops at the right rail")
	far_right.queue_free()
	game.blocks.erase(Vector2i(7, 2))
	game.wall.position.x = 99
	await frames(2)
	check(is_equal_approx(right_side.global_position.x + .46, game.LANE_EDGE), "losing the outermost block extends the wall's reach")
	# Long-lived ricochets count toward the cap; emitters must wait for a free slot.
	await defend([Vector2i(0, 0)])
	for i in game.MAX_BALLS:
		game.spawn_ball(Vector3(i, 1.5, -15), Vector3.ZERO)
	game.fire_left = 0
	await frames(2)
	check(game.projectiles.size() == 3, "enemy fire never exceeds three simultaneous balls")
	game.remove_ball(game.projectiles[0])
	game.fire_left = 0
	await frames(2)
	check(game.projectiles.size() == 3, "enemy resumes fire when a ball slot opens")
	# Empty wall is a continuing survival state, never a victory.
	await defend([Vector2i(0, 0)])
	for cell in game.blocks:
		game.blocks[cell].queue_free()
	game.blocks.clear()
	game.intercepted = game.placed_total
	await frames(3)
	check(not game.finished and game.hud.game.visible, "using all blocks does not end survival")
	check(game.hud.get_node("Game/Blocks").text == "BLOCKS LEFT  000", "HUD reports depleted wall")
	game.fire_left = 0
	await frames(2)
	check(game.projectiles.size() == 1, "enemy fire continues with no blocks left")
	for live in game.projectiles.duplicate():
		game.remove_ball(live)
	# Previously bounced balls are still hostile when they reach the base.
	ball = game.spawn_ball(Vector3(6, 1.5, 3.1), Vector3(0, 0, 8))
	ball.set_meta("flash_left", .25)
	await frames(2)
	check(game.health == 2 and not game.finished, "a bounced ball reaching base still costs a life")
	game.fire_left = 999
	game.elapsed = 65.43
	game.spawn_ball(Vector3(6, 1.5, 3.1), Vector3(0, 0, 8))
	game.spawn_ball(Vector3(-6, 1.5, 3.1), Vector3(0, 0, 8))
	await frames(3)
	check(game.finished and game.health == 0, "only base destruction ends the run")
	check(game.new_record and game.best_time >= 65.43, "first survival run sets personal best")
	check(game.projectiles.is_empty(), "ending clears live balls")
	check(game.hud.get_node("EndScreen/Frame/Margin/Content/Title").text == "NEW PERSONAL BEST", "record gets distinct result heading")
	layout(game.hud.end_screen)
	var results: String = game.hud.get_node("EndScreen/Frame/Margin/Content/Results").text
	check(results.contains("01:05.4") and results.contains("001 / 001"), "summary shows time and blocks broken of blocks placed")
	var saved_best: float = game.best_time
	var stopped_time: float = game.elapsed
	await frames(8)
	check(game.elapsed == stopped_time, "clock stops on game over")
	var config := ConfigFile.new()
	check(config.load(record_path) == OK, "record persisted on disk")
	check(is_equal_approx(config.get_value("survival", "best_seconds"), saved_best), "persisted record matches run")
	# Play Again reloads straight into an empty build grid.
	set_meta("prototype2_start_playing", true)
	await fresh()
	check(game.building and game.blocks.is_empty() and game.hud.build.visible, "play again returns to an empty build grid")
	check(is_equal_approx(game.best_time, saved_best), "fresh scene reloads record")
	game.place_block(Vector2i(0, 0))
	game.start_run()
	game.elapsed = 10
	game.damage_base()
	game.damage_base()
	game.damage_base()
	check(not game.new_record and is_equal_approx(game.best_time, saved_best), "shorter run never overwrites best")
	config.load(record_path)
	check(is_equal_approx(config.get_value("survival", "best_seconds"), saved_best), "shorter run leaves stored record intact")
	await create_timer(0.7).timeout
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(record_path)
	print("PASS: %d build-and-defend checks covering grid picking, budget, block heights, ricochets and records" % checks)
	quit()
