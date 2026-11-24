extends Node3D

const BLOCK_BUDGET := 8
const GRID_COLS := 8
const GRID_ROWS := 4
const CELL_SIZE := Vector2(1.0, 0.7)
const GRID_FRONT_Z := -0.15
# Rows near -> far. Nearer blocks are shorter so the player can see the whole defence.
const ROW_HEIGHTS: Array[float] = [0.8, 1.0, 1.2, 1.4]
const WALL_LIMIT := 2.8
const NO_CELL := Vector2i(-1, -1)
const MAX_BALLS := 3
# Balls travel flat at this height; every block row is tall enough to cover it.
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
var blocks := {}  # Vector2i cell -> StaticBody3D
var placed_total := 0
var building := false
var grid: MeshInstance3D
var hover: MeshInstance3D
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
	make_grid()
	hud.start_requested.connect(start_build)
	hud.defend_requested.connect(start_run)
	hud.restart_requested.connect(restart_run)
	hud.menu_requested.connect(return_to_menu)
	if get_tree().get_meta("prototype2_start_playing", false):
		get_tree().remove_meta("prototype2_start_playing")
		start_build()
	else:
		hud.show_start()
	load_record()
	hud.set_best(best_time)
	update_hud()

func start_build() -> void:
	if building or started:
		return
	building = true
	grid.show()
	hud.show_build()
	hud.update_build(blocks.size(), BLOCK_BUDGET)

func start_run() -> void:
	if started or blocks.is_empty():
		return
	building = false
	started = true
	placed_total = blocks.size()
	grid.hide()
	hover.hide()
	hud.show_game()
	update_hud()

func make_grid() -> void:
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_material.albedo_color = Color(CYAN, 0.9)
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, line_material)
	var left := -GRID_COLS * CELL_SIZE.x / 2
	var back := GRID_FRONT_Z - GRID_ROWS * CELL_SIZE.y
	for c in GRID_COLS + 1:
		lines.surface_add_vertex(Vector3(left + c * CELL_SIZE.x, 0.02, GRID_FRONT_Z))
		lines.surface_add_vertex(Vector3(left + c * CELL_SIZE.x, 0.02, back))
	for r in GRID_ROWS + 1:
		lines.surface_add_vertex(Vector3(left, 0.02, GRID_FRONT_Z - r * CELL_SIZE.y))
		lines.surface_add_vertex(Vector3(-left, 0.02, GRID_FRONT_Z - r * CELL_SIZE.y))
	lines.surface_end()
	grid = MeshInstance3D.new()
	grid.mesh = lines
	grid.visible = false
	wall.add_child(grid)
	var plane := PlaneMesh.new()
	plane.size = CELL_SIZE * 0.94
	hover = MeshInstance3D.new()
	hover.mesh = plane
	hover.material_override = line_material.duplicate()
	hover.visible = false
	wall.add_child(hover)

func cell_center(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5 - GRID_COLS / 2.0) * CELL_SIZE.x, 0, GRID_FRONT_Z - (cell.y + 0.5) * CELL_SIZE.y)

# The floor cell under the cursor; NO_CELL when off the grid.
func cell_at(screen_pos: Vector2) -> Vector2i:
	var hit = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if hit == null:
		return NO_CELL
	var local := wall.to_local(hit)
	var cell := Vector2i(floori(local.x / CELL_SIZE.x + GRID_COLS / 2.0), floori((GRID_FRONT_Z - local.z) / CELL_SIZE.y))
	return cell if cell.x >= 0 and cell.x < GRID_COLS and cell.y >= 0 and cell.y < GRID_ROWS else NO_CELL

# Right click prefers the block actually under the cursor, since tall blocks hide the floor behind them.
func block_cell_at(screen_pos: Vector2) -> Vector2i:
	var origin := camera.project_ray_origin(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen_pos) * 100.0, 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit and hit.collider.has_meta("cell"):
		return hit.collider.get_meta("cell")
	return cell_at(screen_pos)

func place_block(cell: Vector2i) -> bool:
	if cell == NO_CELL or blocks.has(cell) or blocks.size() >= BLOCK_BUDGET:
		return false
	var height: float = ROW_HEIGHTS[cell.y]
	var size := Vector3(CELL_SIZE.x - 0.08, height, CELL_SIZE.y - 0.1)
	var block := $BlockTemplate.duplicate() as StaticBody3D
	block.visible = true
	block.collision_layer = 2
	block.add_to_group("defence_block")
	block.set_meta("cell", cell)
	block.position = cell_center(cell) + Vector3(0, height / 2, 0)
	# Two cubes side by side, one collider: a single hit breaks the whole block.
	var template_size: Vector3 = $BlockTemplate/Mesh.mesh.size
	for part in ["Mesh", "Edges", "Mesh2", "Edges2"]:
		var half := block.get_node(part) as Node3D
		half.scale = Vector3(size.x / 2, size.y, size.z) / template_size
		half.position.x = size.x / 4 * (1 if part.ends_with("2") else -1)
	var shape := BoxShape3D.new()
	shape.size = size
	block.get_node("CollisionShape3D").shape = shape
	wall.add_child(block)
	blocks[cell] = block
	hud.update_build(blocks.size(), BLOCK_BUDGET)
	return true

func remove_block(cell: Vector2i) -> bool:
	if not blocks.has(cell):
		return false
	blocks[cell].queue_free()
	blocks.erase(cell)
	hud.update_build(blocks.size(), BLOCK_BUDGET)
	return true

func update_hover(screen_pos: Vector2) -> void:
	var cell := cell_at(screen_pos)
	hover.visible = cell != NO_CELL
	if hover.visible:
		hover.position = cell_center(cell) + Vector3(0, 0.03, 0)
		var full := blocks.size() >= BLOCK_BUDGET and not blocks.has(cell)
		hover.material_override.albedo_color = Color(ORANGE if full else CYAN, 0.45)

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
	if building:
		if event is InputEventMouseMotion:
			update_hover(event.position)
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				place_block(cell_at(event.position))
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				remove_block(block_cell_at(event.position))
			update_hover(event.position)
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			start_run()
		return
	if started and not finished and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			restart_run()

func _physics_process(delta: float) -> void:
	if not started or finished:
		return
	elapsed += delta
	var direction := float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	wall.position.x = clampf(wall.position.x + direction * WALL_SPEED * delta, -WALL_LIMIT, WALL_LIMIT)
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
	blocks.erase(block.get_meta("cell", NO_CELL))
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
	hud.show_end(intercepted, placed_total, elapsed, best_time, new_record)


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
	hud.update_game(elapsed, intercepted, placed_total, health, BASE_HEALTH, best_time)


func flash_edges(body: Node3D, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	var tween := create_tween().set_parallel(true)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.25)
	# Blocks have two wireframe halves (Edges, Edges2); everything else has one.
	var copies: Array[Node] = []
	for part in ["Edges", "Edges2"]:
		if body.has_node(part):
			var source := body.get_node(part) as Node3D
			var edges := source.duplicate() as MeshInstance3D
			add_child(edges)
			edges.global_transform = source.global_transform
			edges.material_override = material
			tween.tween_property(edges, "scale", edges.scale * 1.2, 0.25)
			copies.append(edges)
	tween.chain()
	for edges in copies:
		tween.tween_callback(edges.queue_free)


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
