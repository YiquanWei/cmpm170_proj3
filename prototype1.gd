extends Node3D

const FIELD_W := 14.0
const FIELD_H := 3.0
const PADDLE_SIZE := Vector3(3.0, FIELD_H, 0.2)
const BASE_SPEED := 12.0
const MAX_SPEED := 22.0
const PADDLE_SPEED := 12.0
const TIME_LIMIT := 90.0
const BLOCKS_TO_WIN := 35
const PADDLE_ACTIVE_TIME := 0.2
const PADDLE_COOLDOWN := 0.45
const MISS_PENALTY := 3.0
const GREEN := Color(0.3, 1.0, 0.3)
# Dim outline shown at all times so the player always knows where the paddle is.
const OUTLINE_IDLE := Color(0.12, 0.4, 0.12)
# Ball colour when a swing right now would reach it in time.
const BALL_IN_RANGE := Color(1.0, 0.25, 0.2)
const BALL_RADIUS := 0.3


@onready var paddle: AnimatableBody3D = $Paddle
@onready var ball: CharacterBody3D = $Ball
@onready var camera: Camera3D = $Camera3D
@onready var paddle_shape: CollisionShape3D = $Paddle/CollisionShape3D
@onready var hud = $HUD
@onready var paddle_edges: MeshInstance3D = $Paddle/Edges
@onready var paddle_fill: MeshInstance3D = $Paddle/Mesh
@onready var ball_mesh: MeshInstance3D = $Ball/Mesh
@onready var trail: Node3D = $ReturnTrail

var started := false
var misses := 0
var return_flash_left := 0.0
var trail_positions: Array[Vector3] = []
var paddle_material: StandardMaterial3D
var ball_material: StandardMaterial3D
var velocity := Vector3.ZERO
var speed := BASE_SPEED
var launched := false
var timer_started := false
var finished := false
var won := false
var time_left := TIME_LIMIT
var blocks_broken := 0
var paddle_active := false
var active_left := 0.0
var cooldown_left := 0.0
var paddle_target := Vector2(0.0, FIELD_H / 2.0)


func _ready() -> void:
	paddle_target = Vector2(paddle.position.x, paddle.position.y)
	ball.position = paddle.position + Vector3(0.0, 0.0, -1.0)
	paddle_material = paddle_edges.mesh.surface_get_material(0).duplicate()
	paddle_edges.material_override = paddle_material
	ball_material = ball_mesh.mesh.surface_get_material(0).duplicate()
	ball_mesh.material_override = ball_material
	paddle.visible = true
	set_paddle_enabled(false)
	clear_trail()
	hud.start_requested.connect(start_run)
	hud.restart_requested.connect(restart_run)
	hud.menu_requested.connect(return_to_menu)
	if get_tree().get_meta("prototype1_start_playing", false):
		get_tree().remove_meta("prototype1_start_playing")
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


func _exit_tree() -> void:
	for sound in $Audio.get_children():
		sound.stop()


func restart_run() -> void:
	get_tree().set_meta("prototype1_start_playing", true)
	get_tree().reload_current_scene()


func return_to_menu() -> void:
	get_tree().remove_meta("prototype1_start_playing")
	get_tree().reload_current_scene()


func update_hud() -> void:
	hud.update_game(time_left, blocks_broken, BLOCKS_TO_WIN, misses,
		paddle_active, cooldown_left, PADDLE_COOLDOWN, launched)


func _unhandled_input(event: InputEvent) -> void:
	# Menu buttons consume their own input, so clicking START never launches a ball.
	if not started or finished:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		launch()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				launch()
			KEY_R:
				restart_run()


func launch() -> void:
	if not started or finished:
		return
	if launched:
		swing()
		return
	launched = true
	timer_started = true
	velocity = Vector3(randf_range(-0.3, 0.3), randf_range(-0.1, 0.1), -1.0).normalized() * speed
	update_hud()


# ---------------------------------------------------------------- gameplay

func set_paddle_enabled(on: bool) -> void:
	# The outline (Edges) always stays visible; only the filled box shows during a swing.
	paddle_fill.visible = on
	paddle_shape.disabled = not on


func swing() -> void:
	if paddle_active or cooldown_left > 0.0:
		return
	paddle_active = true
	active_left = PADDLE_ACTIVE_TIME
	set_paddle_enabled(true)


func _process(delta: float) -> void:
	camera.position = Vector3(paddle_target.x, paddle_target.y, 5.0)
	return_flash_left = maxf(0.0, return_flash_left - delta)
	var lit := paddle_active or return_flash_left > 0.0
	if lit:
		paddle_material.albedo_color = GREEN.lerp(Color(0.9, 1.0, 0.9), clampf(return_flash_left / 0.35, 0.0, 1.0))
	else:
		paddle_material.albedo_color = OUTLINE_IDLE
	# Keep a successful return visible beyond the very short active swing window.
	paddle_fill.visible = lit
	ball_material.albedo_color = BALL_IN_RANGE if ball_in_range() else GREEN
	if return_flash_left <= 0.0:
		clear_trail()


func _physics_process(delta: float) -> void:
	if not started or finished:
		return
	var dir := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir += 1.0
	paddle_target.x += dir * PADDLE_SPEED * delta
	paddle_target.x = clampf(paddle_target.x, -FIELD_W / 2.0 + PADDLE_SIZE.x / 2.0, FIELD_W / 2.0 - PADDLE_SIZE.x / 2.0)
	paddle.position = Vector3(paddle_target.x, paddle_target.y, 0.0)

	if paddle_active:
		active_left -= delta
		if active_left <= 0.0:
			paddle_active = false
			cooldown_left = PADDLE_COOLDOWN
			set_paddle_enabled(false)
	elif cooldown_left > 0.0:
		cooldown_left -= delta

	if timer_started:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			end_game(false)
			return
	update_hud()

	if not launched:
		ball.global_position = paddle.global_position + Vector3(0.0, 0.0, -1.0)
		return

	var hit := ball.move_and_collide(velocity * delta)
	if hit:
		var collider := hit.get_collider() as Node
		if collider == paddle:
			var off := ball.global_position - paddle.global_position
			velocity = Vector3(off.x * 0.5, off.y * 0.2, -1.0)
			return_flash_left = 0.45
			trail_positions.clear()
			hud.notify_return()
			$Audio/Return.play()
		else:
			velocity = velocity.bounce(hit.get_normal())
			if collider and collider.is_in_group("brick"):
				flash_brick(collider)
				collider.queue_free()
				$Audio/Brick.play()
				speed = minf(speed + 0.15, MAX_SPEED)
				blocks_broken += 1
				if blocks_broken >= BLOCKS_TO_WIN:
					end_game(true)
					return
		fix_velocity()

	if return_flash_left > 0.0:
		update_trail()
	if ball.global_position.z > 2.0:
		respawn_ball()


# True when pressing space now would put the active paddle in the ball's path
# before the swing window closes.
func ball_in_range() -> bool:
	if not launched or finished or velocity.z <= 0.0:
		return false
	var front := paddle.global_position.z - PADDLE_SIZE.z / 2.0
	var gap := front - (ball.global_position.z + BALL_RADIUS)
	if gap > velocity.z * PADDLE_ACTIVE_TIME or gap < -(PADDLE_SIZE.z + BALL_RADIUS * 2.0):
		return false
	var at := ball.global_position + velocity * (maxf(gap, 0.0) / velocity.z)
	var off := at - paddle.global_position
	return absf(off.x) <= PADDLE_SIZE.x / 2.0 + BALL_RADIUS \
		and absf(off.y) <= PADDLE_SIZE.y / 2.0 + BALL_RADIUS


func fix_velocity() -> void:
	velocity = velocity.normalized() * speed
	var min_z := speed * 0.35
	if absf(velocity.z) < min_z:
		var s := 1.0 if velocity.z >= 0.0 else -1.0
		velocity.z = s * min_z
		velocity = velocity.normalized() * speed


func respawn_ball() -> void:
	misses += 1
	time_left = maxf(0.0, time_left - MISS_PENALTY)
	launched = false
	velocity = Vector3.ZERO
	speed = BASE_SPEED
	paddle_active = false
	active_left = 0.0
	cooldown_left = 0.0
	return_flash_left = 0.0
	clear_trail()
	set_paddle_enabled(false)
	ball.global_position = paddle.global_position + Vector3(0.0, 0.0, -1.0)
	hud.notify_miss(MISS_PENALTY)
	$Audio/Miss.play()
	if time_left <= 0.0:
		end_game(false)
	update_hud()


func end_game(did_win: bool) -> void:
	if finished:
		return
	finished = true
	won = did_win
	velocity = Vector3.ZERO
	paddle_active = false
	return_flash_left = 0.0
	clear_trail()
	set_paddle_enabled(false)
	if won:
		$Audio/Win.play()
	else:
		$Audio/Lose.play()
	hud.show_end(won, blocks_broken, BLOCKS_TO_WIN, misses, time_left)
	update_hud()


func update_trail() -> void:
	trail_positions.push_front(ball.global_position)
	if trail_positions.size() > trail.get_child_count() + 1:
		trail_positions.pop_back()
	for i in trail.get_child_count():
		var dot := trail.get_child(i) as MeshInstance3D
		dot.visible = i + 1 < trail_positions.size()
		if dot.visible:
			dot.global_position = trail_positions[i + 1]


func clear_trail() -> void:
	trail_positions.clear()
	for dot in trail.get_children():
		dot.hide()


func flash_brick(brick: Node3D) -> void:
	# Only the brief destruction effect is transient; the level lives in the scene.
	var flash := brick.get_node("Edges").duplicate() as MeshInstance3D
	add_child(flash)
	flash.global_transform = brick.global_transform
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.85, 1.0, 0.85)
	flash.material_override = material
	var tween := create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 1.3, 0.18)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.18)
	tween.chain().tween_callback(flash.queue_free)
