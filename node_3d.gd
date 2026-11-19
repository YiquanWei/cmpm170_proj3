extends Node3D

const FIELD_W := 14.0
const FIELD_H := 3.0
const FIELD_NEAR := 6.0
const FIELD_FAR := -22.0
const PADDLE_SIZE := Vector3(3.0, FIELD_H, 0.2)
const BALL_RADIUS := 0.3
const BASE_SPEED := 12.0
const MAX_SPEED := 22.0
const PADDLE_SPEED := 12.0
const TIME_LIMIT := 90.0
const BLOCKS_TO_WIN := 35
const PADDLE_ACTIVE_TIME := 0.2
const PADDLE_COOLDOWN := 0.45

const GREEN := Color(0.3, 1.0, 0.3)
const GREEN_MID := Color(0.17, 0.7, 0.17)
const GREEN_DIM := Color(0.09, 0.4, 0.09)

var paddle: AnimatableBody3D
var ball: CharacterBody3D
var camera: Camera3D
var paddle_shape: CollisionShape3D
var label: Label

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
	build_environment()
	build_arena()
	build_bricks()
	build_paddle()
	build_ball()
	build_hud()


# ---------------------------------------------------------------- building

func build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func make_unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func make_edges(size: Vector3, color: Color) -> MeshInstance3D:
	var h := size * 0.5 * 1.004
	var corners := []
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				corners.append(Vector3(x * h.x, y * h.y, z * h.z))
	var verts := PackedVector3Array()
	for i in 8:
		for bit in [1, 2, 4]:
			var j: int = i ^ bit
			if j > i:
				verts.append(corners[i])
				verts.append(corners[j])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	am.surface_set_material(0, make_unshaded(color))
	var mi := MeshInstance3D.new()
	mi.mesh = am
	return mi


func make_body(body: PhysicsBody3D, size: Vector3, edge_color: Color, fill_alpha := 1.0) -> PhysicsBody3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var fill := Color(edge_color.r * 0.1, edge_color.g * 0.1, edge_color.b * 0.1, fill_alpha)
	mesh.material = make_unshaded(fill)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh

	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box

	body.add_child(mesh_inst)
	body.add_child(make_edges(size, edge_color))
	body.add_child(shape)
	add_child(body)
	return body


func build_arena() -> void:
	var t := 1.0
	var length := FIELD_NEAR - FIELD_FAR
	var mid_z := (FIELD_NEAR + FIELD_FAR) / 2.0
	var col := GREEN_DIM

	var left := make_body(StaticBody3D.new(), Vector3(t, FIELD_H + 2.0 * t, length), col)
	left.position = Vector3(-FIELD_W / 2.0 - t / 2.0, FIELD_H / 2.0, mid_z)

	var right := make_body(StaticBody3D.new(), Vector3(t, FIELD_H + 2.0 * t, length), col)
	right.position = Vector3(FIELD_W / 2.0 + t / 2.0, FIELD_H / 2.0, mid_z)

	var floor_body := make_body(StaticBody3D.new(), Vector3(FIELD_W, t, length), col)
	floor_body.position = Vector3(0.0, -t / 2.0, mid_z)

	var ceiling := make_body(StaticBody3D.new(), Vector3(FIELD_W, t, length), col)
	ceiling.position = Vector3(0.0, FIELD_H + t / 2.0, mid_z)

	var back := make_body(StaticBody3D.new(), Vector3(FIELD_W, FIELD_H, t), col)
	back.position = Vector3(0.0, FIELD_H / 2.0, FIELD_FAR - t / 2.0)

	for z in range(-22, 7, 2):
		add_ring(float(z))


func add_ring(z: float) -> void:
	var mat := make_unshaded(GREEN_DIM)
	var th := 0.04
	var parts := [
		[Vector3(FIELD_W, th, th), Vector3(0.0, 0.0, z)],
		[Vector3(FIELD_W, th, th), Vector3(0.0, FIELD_H, z)],
		[Vector3(th, FIELD_H, th), Vector3(-FIELD_W / 2.0, FIELD_H / 2.0, z)],
		[Vector3(th, FIELD_H, th), Vector3(FIELD_W / 2.0, FIELD_H / 2.0, z)],
	]
	for p in parts:
		var bm := BoxMesh.new()
		bm.size = p[0]
		bm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.position = p[1]
		add_child(mi)


func build_bricks() -> void:
	var colors := [GREEN, GREEN_MID, GREEN_DIM]
	for layer in 3:
		for r in 2:
			for c in 9:
				var b := make_body(StaticBody3D.new(), Vector3(1.3, 1.2, 0.8), colors[layer])
				b.position = Vector3((c - 4) * 1.5, 0.8 + r * 1.4, -14.0 - layer * 1.6)
				b.add_to_group("brick")


func build_paddle() -> void:
	paddle = make_body(AnimatableBody3D.new(), PADDLE_SIZE, GREEN, 0.12) as AnimatableBody3D
	paddle.position = Vector3(paddle_target.x, paddle_target.y, 0.0)

	for child in paddle.get_children():
		if child is CollisionShape3D:
			paddle_shape = child
	set_paddle_enabled(false)

	camera = Camera3D.new()
	camera.fov = 80.0
	camera.position = Vector3(paddle_target.x, paddle_target.y, 5.0)
	add_child(camera)
	camera.make_current()


func build_ball() -> void:
	ball = CharacterBody3D.new()

	var sm := SphereMesh.new()
	sm.radius = BALL_RADIUS
	sm.height = BALL_RADIUS * 2.0
	sm.material = make_unshaded(GREEN)
	var mi := MeshInstance3D.new()
	mi.mesh = sm

	var ss := SphereShape3D.new()
	ss.radius = BALL_RADIUS
	var cs := CollisionShape3D.new()
	cs.shape = ss

	ball.add_child(mi)
	ball.add_child(cs)
	add_child(ball)


func build_hud() -> void:
	var layer := CanvasLayer.new()
	label = Label.new()
	label.position = Vector2(20.0, 20.0)
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", GREEN)
	layer.add_child(label)
	add_child(layer)
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
