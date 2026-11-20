extends Node3D

const TOTAL_BLOCKS := 20
const BASE_HEALTH := 3
const WALL_SPEED := 10.0
const CYAN := Color(0.2, 0.9, 1.0)
const ORANGE := Color(1.0, 0.3, 0.12)

@onready var wall: Node3D = $Wall
@onready var camera: Camera3D = $Camera3D
@onready var hud = $HUD
@onready var emitters: Node3D = $Emitters
@onready var projectiles_root: Node3D = $Projectiles

var projectile_scene := preload("res://prototype2_ball.tscn")
var projectiles: Array[CharacterBody3D] = []
var started := false
var finished := false
var won := false
var health := BASE_HEALTH
var intercepted := 0
var elapsed := 0.0
var fire_left := 1.5
var incoming_material: StandardMaterial3D
var return_material: StandardMaterial3D

func _ready() -> void:
	incoming_material = StandardMaterial3D.new()
	incoming_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	incoming_material.albedo_color = ORANGE
	return_material = incoming_material.duplicate()
	return_material.albedo_color = CYAN
	hud.start_requested.connect(start_run)
	hud.restart_requested.connect(restart_run)
	hud.menu_requested.connect(return_to_menu)
	if get_tree().get_meta("prototype2_start_playing", false):
		get_tree().remove_meta("prototype2_start_playing")
		start_run()
	else:
		hud.show_start()
	update_hud()

func start_run() -> void:
	if started:
		return
	started = true
	hud.show_game()
	update_hud()

func restart_run() -> void:
	get_tree().set_meta("prototype2_start_playing", true)
	get_tree().reload_current_scene()

func return_to_menu() -> void:
	get_tree().remove_meta("prototype2_start_playing")
	get_tree().reload_current_scene()

func _exit_tree() -> void:
	for sound in $Audio.get_children():
		sound.stop()

func _unhandled_input(event: InputEvent) -> void:
	if started and not finished and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			restart_run()

func _physics_process(delta: float) -> void:
	if not started or finished:
		return
	elapsed += delta
	var direction := float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	wall.position.x = clampf(wall.position.x + direction * WALL_SPEED * delta, -5.1, 5.1)
	camera.position.x = wall.position.x
	fire_left -= delta
	if fire_left <= 0.0:
		fire_enemy_ball()
		fire_left = maxf(1.3, 2.7 - intercepted * 0.055)
	for ball in projectiles.duplicate():
		if not is_instance_valid(ball) or ball.is_queued_for_deletion():
			continue
		var age: float = ball.get_meta("age") + delta
		ball.set_meta("age", age)
		var velocity: Vector3 = ball.get_meta("velocity")
		var hit: KinematicCollision3D = ball.move_and_collide(velocity * delta)
		update_ball_trail(ball)
		if hit:
			var collider := hit.get_collider() as Node3D
			if collider.is_in_group("defence_block") and not ball.get_meta("returned"):
				intercept_ball(ball, collider, hit.get_normal())
				if finished:
					return
			elif collider.is_in_group("enemy_emitter"):
				flash_edges(collider, CYAN)
				remove_ball(ball)
			else:
				ball.set_meta("velocity", velocity.bounce(hit.get_normal()))
		if ball.is_queued_for_deletion():
			continue
		if not ball.get_meta("returned") and ball.position.z > 3.0:
			remove_ball(ball)
			damage_base()
			if finished:
				return
		elif ball.position.z < -29.0 or age > 12.0:
			remove_ball(ball)
	update_hud()

func fire_enemy_ball() -> CharacterBody3D:
	var emitter := emitters.get_child(randi_range(0, emitters.get_child_count() - 1)) as Node3D
	var target_x := clampf(wall.position.x + randf_range(-3.4, 3.4), -6.3, 6.3)
	var spawn := emitter.global_position + Vector3(0, 0, 1.3)
	var target := Vector3(target_x, 1.5, 0)
	var speed := minf(11.5, 8.0 + intercepted * 0.12)
	var ball := spawn_ball(spawn, (target - spawn).normalized() * speed)
	flash_edges(emitter, ORANGE)
	$Audio/Fire.play()
	return ball

func spawn_ball(position_world: Vector3, velocity: Vector3) -> CharacterBody3D:
	var ball := projectile_scene.instantiate() as CharacterBody3D
	projectiles_root.add_child(ball)
	ball.global_position = position_world
	ball.get_node("Mesh").material_override = incoming_material
	ball.set_meta("velocity", velocity)
	ball.set_meta("returned", false)
	ball.set_meta("age", 0.0)
	ball.set_meta("trail", PackedVector3Array())
	projectiles.append(ball)
	return ball

func intercept_ball(ball: CharacterBody3D, block: Node3D, normal: Vector3) -> void:
	if block.is_queued_for_deletion():
		return
	block.remove_from_group("defence_block")
	flash_edges(block, CYAN)
	block.queue_free()
	intercepted += 1
	var velocity: Vector3 = ball.get_meta("velocity")
	var reflected := velocity.bounce(normal)
	reflected.z = -maxf(absf(reflected.z), velocity.length() * 0.8)
	ball.set_meta("velocity", reflected.normalized() * velocity.length())
	ball.set_meta("returned", true)
	ball.collision_mask = 5
	ball.get_node("Mesh").material_override = return_material
	hud.notify_intercept()
	$Audio/Return.play()
	if intercepted >= TOTAL_BLOCKS:
		end_game(true)

func damage_base() -> void:
	health = maxi(0, health - 1)
	hud.notify_base_hit()
	flash_edges($Base, ORANGE)
	$Audio/Miss.play()
	if health <= 0:
		end_game(false)

func remove_ball(ball: CharacterBody3D) -> void:
	projectiles.erase(ball)
	ball.queue_free()

func end_game(did_win: bool) -> void:
	if finished:
		return
	finished = true
	won = did_win
	for ball in projectiles:
		ball.queue_free()
	projectiles.clear()
	if won:
		$Audio/Win.play()
	else:
		$Audio/Lose.play()
	hud.show_end(won, intercepted, TOTAL_BLOCKS, health, elapsed)

func update_hud() -> void:
	hud.update_game(elapsed, intercepted, TOTAL_BLOCKS, health, BASE_HEALTH)

func flash_edges(body: Node3D, color: Color) -> void:
	var edges := body.get_node("Edges").duplicate() as MeshInstance3D
	add_child(edges)
	edges.global_transform = body.global_transform
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	edges.material_override = material
	var tween := create_tween().set_parallel(true)
	tween.tween_property(edges, "scale", Vector3.ONE * 1.2, 0.25)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.25)
	tween.chain().tween_callback(edges.queue_free)


func update_ball_trail(ball: CharacterBody3D) -> void:
	var history: PackedVector3Array = ball.get_meta("trail")
	history.insert(0, ball.global_position)
	if history.size() > 7:
		history.resize(7)
	ball.set_meta("trail", history)
	var dots := ball.get_node("Trail").get_children()
	for i in dots.size():
		var dot := dots[i] as MeshInstance3D
		dot.visible = history.size() > i + 1
		dot.material_override = return_material if ball.get_meta("returned") else incoming_material
		if dot.visible:
			dot.global_position = history[i + 1]
