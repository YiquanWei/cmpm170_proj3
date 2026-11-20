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


@onready var paddle: AnimatableBody3D = $Paddle
@onready var ball: CharacterBody3D = $Ball
@onready var camera: Camera3D = $Camera3D
@onready var paddle_shape: CollisionShape3D = $Paddle/CollisionShape3D
@onready var label: Label = $HUD/StatusLabel

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
	# The scene owns the layout; this script only initializes gameplay.
	paddle_target = Vector2(paddle.position.x, paddle.position.y)
	ball.position = paddle.position + Vector3(0.0, 0.0, -1.0)
	set_paddle_enabled(false)
	update_hud()


func update_hud() -> void:
	var text := ""
	if timer_started or finished:
		text = "TIME %02d    BLOCKS %d/%d" % [ceili(time_left), blocks_broken, BLOCKS_TO_WIN]
	else:
		text = "BREAK %d BLOCKS IN %d SECONDS" % [BLOCKS_TO_WIN, int(TIME_LIMIT)]
	if finished:
		text += "\n" + ("YOU WIN!" if won else "TIME UP!") + " - click or Space to restart"
	elif not launched:
		text += "\nClick or Space to launch"

	label.text = text


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		launch()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				launch()
			KEY_R:
				get_tree().reload_current_scene()


func launch() -> void:
	if finished:
		get_tree().reload_current_scene()
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
	paddle.visible = on
	paddle_shape.disabled = not on


func swing() -> void:
	if paddle_active or cooldown_left > 0.0:
		return
	paddle_active = true
	active_left = PADDLE_ACTIVE_TIME
	set_paddle_enabled(true)


func _process(_delta: float) -> void:
	camera.position = Vector3(paddle_target.x, paddle_target.y, 5.0)


func _physics_process(delta: float) -> void:
	var dir := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir += 1.0
	paddle_target.x += dir * PADDLE_SPEED * delta
	paddle_target.x = clampf(paddle_target.x, -FIELD_W / 2.0 + PADDLE_SIZE.x / 2.0, FIELD_W / 2.0 - PADDLE_SIZE.x / 2.0)
	paddle.position = Vector3(paddle_target.x, paddle_target.y, 0.0)

	if finished:
		return

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
		else:
			velocity = velocity.bounce(hit.get_normal())
			if collider and collider.is_in_group("brick"):
				collider.queue_free()
				speed = minf(speed + 0.15, MAX_SPEED)
				blocks_broken += 1
				if blocks_broken >= BLOCKS_TO_WIN:
					end_game(true)
					return
		fix_velocity()

	if ball.global_position.z > 2.0:
		respawn_ball()


func fix_velocity() -> void:
	velocity = velocity.normalized() * speed
	var min_z := speed * 0.35
	if absf(velocity.z) < min_z:
		var s := 1.0 if velocity.z >= 0.0 else -1.0
		velocity.z = s * min_z
		velocity = velocity.normalized() * speed


func respawn_ball() -> void:
	launched = false
	velocity = Vector3.ZERO
	speed = BASE_SPEED
	paddle_active = false
	cooldown_left = 0.0
	set_paddle_enabled(false)
	update_hud()


func end_game(did_win: bool) -> void:
	finished = true
	won = did_win
	velocity = Vector3.ZERO
	update_hud()
