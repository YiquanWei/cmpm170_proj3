extends SceneTree

var game: Node
var checks := 0
var record_path := "/tmp/prototype2-test-%d.cfg" % OS.get_process_id()

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

func layout(screen: Control) -> void:
	var frame: Control = screen.get_node("Frame")
	var margin: Control = frame.get_node("Margin")
	check(margin.get_combined_minimum_size().x <= frame.size.x, "menu fits width")
	check(margin.get_combined_minimum_size().y <= frame.size.y, "menu fits height")

func run_checks() -> void:
	root.size = Vector2i(1152, 720)
	await fresh()
	check(get_nodes_in_group("defence_block").size() == game.TOTAL_BLOCKS and game.TOTAL_BLOCKS == 32, "32 bricks in a single row")
	for brick in game.wall.get_children():
		check(is_equal_approx(brick.position.y, game.BALL_Y), "every brick sits on the ball lane")
	var block: StaticBody3D = game.wall.get_child(0)
	check(block.get_node("CollisionShape3D").shape.size.is_equal_approx(Vector3(.42, .44, .42)), "individual bricks are smaller in all main face dimensions")
	var ball = game.spawn_ball(Vector3(0, 1.5, -10), Vector3.ZERO)
	check(is_equal_approx(ball.get_node("CollisionShape3D").shape.radius, .09), "smaller ball collider matches visual radius")
	game.remove_ball(ball)
	check(game.best_time == 0, "missing record starts at zero")
	await frames(10)
	check(game.elapsed == 0, "menu pauses survival clock")
	layout(game.hud.start_screen)
	# The player only moves horizontally: every legal ball x must be coverable by the row.
	var covered := true
	for xi in 21:
		var x := lerpf(-game.BALL_MAX_X, game.BALL_MAX_X, xi / 20.0)
		var reachable := false
		for brick in game.wall.get_children():
			var shift := clampf(x - brick.position.x, -4.8, 4.8)
			if absf(x - brick.position.x - shift) <= 0.30:
				reachable = true
				break
		covered = covered and reachable
	check(covered, "every point on the ball lane is coverable by horizontal wall movement")
	var probe = game.spawn_ball(Vector3(0, 1.5, -10), Vector3(5, 12, 0))
	check(is_equal_approx(probe.position.y, game.BALL_Y) and is_equal_approx(probe.get_meta("velocity").y, 0.0), "balls spawn flat on the lane")
	check(is_equal_approx(probe.get_meta("velocity").length(), Vector3(5, 12, 0).length()), "flattening keeps ball speed")
	var confined := true
	game.set_physics_process(false)
	for i in 360:
		game.move_ball(probe, 1.0 / 60.0)
		confined = confined and is_equal_approx(probe.position.y, game.BALL_Y)
		confined = confined and absf(probe.position.x) <= game.BALL_MAX_X + .005
	check(confined, "repeated side rebounds never move the ball up or down or out of the defence area")
	var shot = game.fire_enemy_ball()
	check(is_equal_approx(shot.get_meta("velocity").y, 0.0) and is_equal_approx(shot.position.y, game.BALL_Y), "emitters fire flat shots")
	game.remove_ball(shot)
	game.remove_ball(probe)
	game.set_physics_process(true)
	game.start_run()
	game.fire_left = 999
	ball = game.spawn_ball(Vector3(-1.9, .65, -3.4), Vector3(2, 0, 8))
	await frames(6)
	check(game.intercepted == 1, "oblique frontal impact breaks a brick")
	var v: Vector3 = ball.get_meta("velocity")
	check(v.is_equal_approx(Vector3(2, 0, -8)), "frontal bounce preserves tangential velocity and incident angle")
	check(ball.collision_mask == 7, "ball remains able to hit blocks after bouncing")
	check(ball.get_node("Trail/Dot1").visible, "smaller ball retains readable trail")
	check(game.health == 3, "block impact does not hurt base")
	await fresh()
	game.start_run()
	game.fire_left = 999
	ball = game.spawn_ball(Vector3(-2.3, .65, -2.6), Vector3(8, 0, 1.2))
	await frames(4)
	v = ball.get_meta("velocity")
	check(v.is_equal_approx(Vector3(-8, 0, 1.2)), "side impact reverses x, without forcing z away from the base")
	# Put two real brick colliders either side of a small empty channel.
	await fresh()
	game.start_run()
	game.fire_left = 999
	game.wall.position.x = 4.8
	for x in [-0.45, 0.45]:
		var fixture: StaticBody3D = game.wall.get_child(0).duplicate()
		game.add_child(fixture)
		fixture.position = Vector3(x, game.BALL_Y, -7)
	await frames(2)
	ball = game.spawn_ball(Vector3(0, game.BALL_Y, -7), Vector3(90, 0, .8))
	await frames(2)
	check(game.intercepted == 2, "one ball breaks two bricks through successive real side bounces")
	check(is_instance_valid(ball) and not ball.is_queued_for_deletion(), "ricocheting ball stays alive")
	check(game.health == 3, "ricochet channel does not falsely damage base")
	# Long-lived ricochets count toward the cap; emitters must wait for a free slot.
	await fresh()
	game.start_run()
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
	await fresh()
	game.start_run()
	game.fire_left = 999
	for brick in game.wall.get_children():
		brick.queue_free()
	game.intercepted = game.TOTAL_BLOCKS
	await frames(3)
	check(not game.finished and game.hud.game.visible, "using all blocks does not end survival")
	check(game.hud.get_node("Game/Blocks").text == "BLOCKS LEFT  000", "HUD reports depleted wall")
	game.fire_left = 0
	await frames(2)
	check(game.projectiles.size() == 1, "enemy fire continues with no bricks left")
	for shot in game.projectiles.duplicate():
		game.remove_ball(shot)
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
	check(game.hud.get_node("EndScreen/Frame/Margin/Content/Results").text.contains("01:05.4"), "summary displays tenths of seconds")
	var saved_best: float = game.best_time
	var stopped_time: float = game.elapsed
	await frames(8)
	check(game.elapsed == stopped_time, "clock stops on game over")
	var config := ConfigFile.new()
	check(config.load(record_path) == OK, "record persisted on disk")
	check(is_equal_approx(config.get_value("survival", "best_seconds"), saved_best), "persisted record matches run")
	await fresh()
	check(is_equal_approx(game.best_time, saved_best), "fresh scene reloads record")
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
	print("PASS: %d endless-survival checks covering angle reflection, multi-hit ricochet, small geometry and persistent records" % checks)
	quit()
