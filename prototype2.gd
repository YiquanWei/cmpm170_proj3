extends Node3D

const TOTAL_BLOCKS := 32
const MAX_BALLS := 3
# Balls travel flat at the height of the single row of defence blocks.
const BALL_Y := 0.65
const BALL_MAX_X := 6.61

@export var record_path := "user://prototype2_records.cfg"
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
var best_time := 0.0
var new_record := false
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
	load_record()
	hud.set_best(best_time)
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
	wall.position.x = clampf(wall.position.x + direction * WALL_SPEED * delta, -4.8, 4.8)
	camera.position.x = wall.position.x
	fire_left -= delta
	if fire_left <= 0.0:
		if projectiles.size() < MAX_BALLS:
			fire_enemy_ball()
		fire_left = maxf(3.5, 4.5 - elapsed * 0.005)
	for ball in projectiles.duplicate():
		if not is_instance_valid(ball) or ball.is_queued_for_deletion():
			continue
		move_ball(ball, delta)
		if finished:
			return
	update_hud()


func move_ball(ball: CharacterBody3D, delta: float) -> void:
	var motion: Vector3 = ball.get_meta("velocity") * delta
	# Resolve the remaining travel after each impact, including multiple hits in one tick.
	for collision_index in 8:
		if motion.length_squared() < 0.0000001:
			break
		var hit := ball.move_and_collide(motion)
		if not hit:
			break
		var collider := hit.get_collider() as Node3D
		var normal := hit.get_normal()
		var velocity: Vector3 = ball.get_meta("velocity")
		ball.set_meta("velocity", flatten(velocity.bounce(normal)))
		motion = flatten(hit.get_remainder().bounce(normal))
		if collider.is_in_group("defence_block"):
			intercept_ball(ball, collider)
		elif collider.is_in_group("enemy_emitter"):
			flash_edges(collider, CYAN)
	# Edge and corner hits must never push the ball off its lane.
	ball.global_position.y = BALL_Y
	update_ball_trail(ball)
	var flash_left := maxf(0.0, float(ball.get_meta("flash_left")) - delta)
	ball.set_meta("flash_left", flash_left)
	ball.get_node("Mesh").material_override = return_material if flash_left > 0 else incoming_material
	# A ball is always hostile, including after one or more wall rebounds.
	if ball.position.z > 3.0:
		remove_ball(ball)
		damage_base()


func fire_enemy_ball() -> CharacterBody3D:
	var emitter := emitters.get_child(randi_range(0, emitters.get_child_count() - 1)) as Node3D
	var target_x := clampf(wall.position.x + randf_range(-3.4, 3.4), -6.1, 6.1)
	var spawn := emitter.global_position + Vector3(0, 0, 1.3)
	spawn.y = BALL_Y
	var target := Vector3(target_x, BALL_Y, 0)
	var speed := minf(15.0, 7.5 + elapsed * 0.035)
	var ball := spawn_ball(spawn, (target - spawn).normalized() * speed)
	flash_edges(emitter, ORANGE)
	$Audio/Fire.play()
	return ball

func spawn_ball(position_world: Vector3, velocity: Vector3) -> CharacterBody3D:
	var ball := projectile_scene.instantiate() as CharacterBody3D
	projectiles_root.add_child(ball)
	ball.global_position = Vector3(position_world.x, BALL_Y, position_world.z)
	ball.get_node("Mesh").material_override = incoming_material
	ball.set_meta("velocity", flatten(velocity))
	ball.set_meta("flash_left", 0.0)
	ball.set_meta("trail", PackedVector3Array())
	projectiles.append(ball)
	return ball

func intercept_ball(ball: CharacterBody3D, block: Node3D) -> void:
	if block.is_queued_for_deletion():
		return
	block.remove_from_group("defence_block")
	flash_edges(block, CYAN)
	block.queue_free()
	intercepted += 1
	ball.set_meta("flash_left", 0.25)
	hud.notify_intercept()
	$Audio/Return.play()

func damage_base() -> void:
	health = maxi(0, health - 1)
	hud.notify_base_hit()
	flash_edges($Base, ORANGE)
	$Audio/Miss.play()
	if health <= 0:
		end_game()

func remove_ball(ball: CharacterBody3D) -> void:
	projectiles.erase(ball)
	ball.queue_free()

func end_game() -> void:
	if finished:
		return
	finished = true
	new_record = elapsed > best_time
	if new_record:
		best_time = elapsed
		var records := ConfigFile.new()
		records.set_value("survival", "best_seconds", best_time)
		var error := records.save(record_path)
		if error != OK:
			push_warning("Could not save survival record: %s" % error_string(error))
	for ball in projectiles:
		ball.queue_free()
	projectiles.clear()
	$Audio/Lose.play()
	hud.show_end(intercepted, TOTAL_BLOCKS, elapsed, best_time, new_record)


func load_record() -> void:
	var records := ConfigFile.new()
	if records.load(record_path) == OK:
		var value = records.get_value("survival", "best_seconds", 0.0)
		if (value is float or value is int) and is_finite(float(value)):
			best_time = maxf(0.0, float(value))


# Removes vertical movement while keeping the ball's speed.
func flatten(v: Vector3) -> Vector3:
	var speed := v.length()
	v.y = 0.0
	if v.length_squared() < 0.000001:
		return Vector3.ZERO
	return v.normalized() * speed


func update_hud() -> void:
	hud.update_game(elapsed, intercepted, TOTAL_BLOCKS, health, BASE_HEALTH, best_time)


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
		dot.material_override = return_material if float(ball.get_meta("flash_left")) > 0 else incoming_material
		if dot.visible:
			dot.global_position = history[i + 1]
