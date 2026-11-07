extends Node2D

const CELL := 40
const WIDTH := 19
const HEIGHT := 15
const TEDDY_COUNT := 4
const BEAN := preload("res://mrbean.png")
const WICKET_TEXTURE := preload("res://Mrs_Wicket_Front.webp")
const WICKET_SPEED := 105.0

var open_cells: Array[Array] = []
var maze: Node2D
var player: CharacterBody2D
var wicket: CharacterBody2D
var pathfinder: AStarGrid2D
var wicket_direction := Vector2.ZERO
var path_refresh := 0.0
var ui_layer: CanvasLayer
var collected := 0
var key_collected := false
var seconds := 0.0
var finished := false
var paused := false
var counter_text: Label
var key_text: Label
var timer_text: Label
var notice: Label
var overlay: ColorRect
var pause_panel: PanelContainer

const INK := Color("44372e")
const CREAM := Color("fff3d5")
const GREEN := Color("536d4a")
const BROWN := Color("80563c")

func _ready() -> void:
	maze = $Maze
	player = $Player
	ui_layer = $HUD
	_build_level()
	_build_hud()

func _process(delta: float) -> void:
	if not finished and not paused:
		seconds += delta
		timer_text.text = "TIME  %02d:%02d" % [int(seconds) / 60, int(seconds) % 60]

func _physics_process(delta: float) -> void:
	if not is_instance_valid(wicket) or finished or paused:
		return
	path_refresh -= delta
	if path_refresh <= 0.0:
		path_refresh = 0.22
		_update_wicket_path()
	wicket.velocity = wicket_direction * WICKET_SPEED
	wicket.move_and_slide()
	if wicket.global_position.distance_to(player.global_position) < 30.0:
		_caught_by_wicket()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
		_toggle_pause()

func _build_level() -> void:
	_make_fixed_house()
	_build_pathfinder()
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([Vector2(-18, 12), Vector2(WIDTH * CELL * 0.5, -88), Vector2(WIDTH * CELL + 18, 12)])
	roof.color = Color("a64f43")
	maze.add_child(roof)
	for y in range(HEIGHT):
		for x in range(WIDTH):
			if open_cells[y][x]:
				var floor := ColorRect.new()
				floor.position = Vector2(x, y) * CELL
				floor.size = Vector2(CELL, CELL)
				floor.color = _floor_color(x, y)
				maze.add_child(floor)
				_add_floor_detail(Vector2(x, y) * CELL, x, y)
			else:
				_add_wall(Vector2(x, y) * CELL, x == 0 or y == 0 or x == WIDTH - 1 or y == HEIGHT - 1)
	_add_room_labels()
	_add_furniture()
	_spawn_teddies()
	_spawn_key()
	_add_front_door()
	_add_mrs_wicket()
	_configure_player()
	_update_hud()

func _build_pathfinder() -> void:
	pathfinder = AStarGrid2D.new()
	pathfinder.region = Rect2i(0, 0, WIDTH, HEIGHT)
	pathfinder.cell_size = Vector2(CELL, CELL)
	pathfinder.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	pathfinder.update()
	for y in range(HEIGHT):
		for x in range(WIDTH):
			if not open_cells[y][x]:
				pathfinder.set_point_solid(Vector2i(x, y))

func _make_fixed_house() -> void:
	open_cells.clear()
	for y in range(HEIGHT):
		var row: Array[bool] = []
		for x in range(WIDTH): row.append(false)
		open_cells.append(row)
	# Four rooms, a cross hall, and a front entrance.
	_open_rect(1, 1, 7, 5) # living room
	_open_rect(11, 1, 17, 5) # kitchen
	_open_rect(1, 8, 7, 12) # bedroom
	_open_rect(11, 8, 17, 12) # bathroom
	_open_rect(8, 1, 10, 13) # main hall
	_open_rect(1, 6, 17, 7) # cross hall
	_open_rect(8, 14, 10, 14) # front doorstep
	# Short interior partitions create routes while leaving clear doorways.
	for y in range(1, 5):
		if y != 2: open_cells[y][4] = false
	for x in range(11, 17):
		if x != 14: open_cells[3][x] = false
	for y in range(8, 12):
		if y != 10: open_cells[y][4] = false
	for x in range(12, 18):
		if x != 15: open_cells[10][x] = false
	for x in range(1, 8):
		open_cells[5][x] = x == 3
		open_cells[8][x] = x == 3
	for x in range(11, 18):
		open_cells[5][x] = x == 14
		open_cells[8][x] = x == 14
	# Room walls separate rooms from the hall, with one doorway per room.
	for y in range(1, 6):
		open_cells[y][8] = y == 3
		open_cells[y][10] = y == 3
	for y in range(8, 13):
		open_cells[y][8] = y == 10
		open_cells[y][10] = y == 10
	# The front door is the only opening in the outside wall.
	open_cells[14][9] = true

func _open_rect(left: int, top: int, right: int, bottom: int) -> void:
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			open_cells[y][x] = true

func _add_wall(position: Vector2, outside: bool) -> void:
	var wall := StaticBody2D.new()
	wall.position = position + Vector2.ONE * CELL * 0.5
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2.ONE * CELL
	collision.shape = shape
	wall.add_child(collision)
	var fill := Polygon2D.new()
	fill.polygon = PackedVector2Array([Vector2(-20, -20), Vector2(20, -20), Vector2(20, 20), Vector2(-20, 20)])
	fill.color = Color("8c664d") if outside else Color("c3a987")
	wall.add_child(fill)
	var cap := Polygon2D.new()
	cap.polygon = PackedVector2Array([Vector2(-20, -20), Vector2(20, -20), Vector2(20, -14), Vector2(-20, -14)])
	cap.color = Color("d7b88e") if outside else Color("ead4b4")
	wall.add_child(cap)
	maze.add_child(wall)

func _floor_color(x: int, y: int) -> Color:
	if x <= 7 and y <= 5: return Color("dfd5b6") # living room carpet
	if x >= 11 and y <= 5: return Color("e8d6ae") # kitchen tiles
	if x <= 7 and y >= 8: return Color("d7dfc6") # bedroom rug and boards
	if x >= 11 and y >= 8: return Color("dce4df") # bathroom tiles
	return Color("c9c4a0") # hallway

func _add_floor_detail(position: Vector2, x: int, y: int) -> void:
	# Fine tile seams in the kitchen and bathroom.
	if (x >= 11 and y <= 5) or (x >= 11 and y >= 8):
		var seam := Polygon2D.new()
		seam.polygon = PackedVector2Array([Vector2(1, 39), Vector2(39, 39), Vector2(39, 40), Vector2(1, 40)])
		seam.position = position
		seam.color = Color(0.44, 0.36, 0.28, 0.18)
		maze.add_child(seam)

func _add_room_labels() -> void:
	_add_label("LIVING ROOM", Vector2(1.4, 1.1) * CELL, 12)
	_add_label("KITCHEN", Vector2(12.2, 1.1) * CELL, 12)
	_add_label("MR BEAN'S BEDROOM", Vector2(1.1, 8.15) * CELL, 11)
	_add_label("BATHROOM", Vector2(12.0, 8.15) * CELL, 12)
	_add_label("HALL", Vector2(8.7, 6.25) * CELL, 10)
	_add_label("MR BEAN'S HOUSE", Vector2(7.3, -78), 18, CREAM)

func _add_label(text: String, position: Vector2, size: int, color := INK) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	maze.add_child(label)

func _add_furniture() -> void:
	# Living room: sofa, television, and rug.
	_add_rect(Vector2(1.4, 2.0) * CELL, Vector2(2.3, 0.75) * CELL, Color("76523f"))
	_add_rect(Vector2(1.55, 2.08) * CELL, Vector2(2.0, 0.24) * CELL, Color("a87958"))
	_add_rect(Vector2(5.7, 1.9) * CELL, Vector2(1.0, 0.36) * CELL, BROWN)
	_add_rect(Vector2(5.92, 1.48) * CELL, Vector2(0.56, 0.36) * CELL, Color("423b36"))
	_add_rect(Vector2(3.0, 4.15) * CELL, Vector2(2.7, 0.55) * CELL, Color("d5bd87"))
	# Kitchen counters and a small dining table.
	_add_rect(Vector2(11.4, 1.8) * CELL, Vector2(1.0, 2.6) * CELL, Color("c99b68"))
	_add_rect(Vector2(13.0, 4.1) * CELL, Vector2(2.0, 0.65) * CELL, Color("946848"))
	# Bedroom: bed with cream pillow and a soft yellow blanket.
	_add_rect(Vector2(1.35, 9.0) * CELL, Vector2(2.3, 1.8) * CELL, Color("76523f"))
	_add_rect(Vector2(1.48, 9.12) * CELL, Vector2(2.04, 1.55) * CELL, Color("f4e8cc"))
	_add_rect(Vector2(1.55, 9.65) * CELL, Vector2(1.9, 0.95) * CELL, Color("d5b95f"))
	# Bathroom: bath and sink; all furniture is visual-only, with no collision.
	_add_rect(Vector2(12.0, 9.0) * CELL, Vector2(2.5, 1.1) * CELL, Color("f6f0df"))
	_add_rect(Vector2(12.16, 9.12) * CELL, Vector2(2.18, 0.72) * CELL, Color("bad3cf"))
	_add_rect(Vector2(15.4, 9.0) * CELL, Vector2(1.0, 0.7) * CELL, Color("f6f0df"))
	# Plants add a little green to the house corners.
	_add_plant(Vector2(6.2, 4.4) * CELL)
	_add_plant(Vector2(16.1, 4.4) * CELL)
	_add_plant(Vector2(6.2, 11.3) * CELL)

func _add_rect(position: Vector2, size: Vector2, color: Color) -> void:
	var shape := Polygon2D.new()
	shape.position = position
	shape.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	shape.color = color
	maze.add_child(shape)

func _add_plant(position: Vector2) -> void:
	_add_rect(position + Vector2(-7, 3), Vector2(14, 12), Color("a66e4d"))
	for leaf_offset in [Vector2(-7, -3), Vector2(0, -10), Vector2(7, -3)]:
		var leaf := Polygon2D.new()
		leaf.polygon = _circle(7)
		leaf.position = position + leaf_offset
		leaf.color = Color("71845b")
		maze.add_child(leaf)

func _spawn_teddies() -> void:
	# One teddy stays in each room, but its exact spot changes on every retry.
	var living_spots: Array[Vector2i] = [Vector2i(3, 3), Vector2i(5, 3), Vector2i(6, 3), Vector2i(2, 4), Vector2i(3, 4), Vector2i(5, 4), Vector2i(6, 4)]
	var kitchen_spots: Array[Vector2i] = [Vector2i(15, 2), Vector2i(16, 2), Vector2i(17, 2), Vector2i(15, 4), Vector2i(16, 4), Vector2i(17, 4)]
	var bedroom_spots: Array[Vector2i] = [Vector2i(5, 9), Vector2i(6, 9), Vector2i(5, 11), Vector2i(6, 11), Vector2i(2, 11), Vector2i(6, 10)]
	var bathroom_spots: Array[Vector2i] = [Vector2i(15, 11), Vector2i(16, 11), Vector2i(17, 11), Vector2i(11, 11), Vector2i(14, 11)]
	living_spots.shuffle()
	kitchen_spots.shuffle()
	bedroom_spots.shuffle()
	bathroom_spots.shuffle()
	var teddy_cells: Array[Vector2i] = [living_spots[0], kitchen_spots[0], bedroom_spots[0], bathroom_spots[0]]
	for cell in teddy_cells:
		var teddy := Area2D.new()
		teddy.position = (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
		var collision := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 14
		collision.shape = shape
		teddy.add_child(collision)
		var body := Polygon2D.new()
		body.polygon = _circle(11)
		body.color = Color("e5b84e")
		teddy.add_child(body)
		for ear_x in [-7.0, 7.0]:
			var ear := Polygon2D.new()
			ear.polygon = _circle(4)
			ear.position = Vector2(ear_x, -8)
			ear.color = BROWN
			teddy.add_child(ear)
		teddy.body_entered.connect(_collect.bind(teddy))
		maze.add_child(teddy)

func _spawn_key() -> void:
	var key := Area2D.new()
	key.name = "HouseKey"
	var key_spots: Array[Vector2i] = [Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 5), Vector2i(9, 8), Vector2i(9, 9), Vector2i(9, 11), Vector2i(9, 12)]
	key_spots.shuffle()
	key.position = (Vector2(key_spots[0]) + Vector2(0.5, 0.5)) * CELL
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 15
	collision.shape = shape
	key.add_child(collision)
	var ring := Polygon2D.new()
	ring.polygon = _circle(9)
	ring.color = Color("e7b936")
	key.add_child(ring)
	var hole := Polygon2D.new()
	hole.polygon = _circle(4)
	hole.color = Color("d7dfc6")
	key.add_child(hole)
	_add_rect_to(key, Vector2(5, -2), Vector2(17, 4), Color("e7b936"))
	_add_rect_to(key, Vector2(16, 1), Vector2(4, 5), Color("e7b936"))
	key.body_entered.connect(_collect_key)
	maze.add_child(key)

func _add_rect_to(parent: Node2D, position: Vector2, size: Vector2, color: Color) -> void:
	var shape := Polygon2D.new()
	shape.position = position
	shape.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	shape.color = color
	parent.add_child(shape)

func _add_front_door() -> void:
	var exit := Area2D.new()
	exit.name = "FrontDoor"
	exit.position = (Vector2(9, 14) + Vector2(0.5, 0.5)) * CELL
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(34, 38)
	collision.shape = shape
	exit.add_child(collision)
	_add_rect_to(exit, Vector2(-18, -20), Vector2(36, 40), Color("70432f"))
	_add_rect_to(exit, Vector2(-13, -16), Vector2(28, 34), Color("a66c43"))
	_add_rect_to(exit, Vector2(7, 1), Vector2(4, 4), Color("f3cf6c"))
	var sign := Label.new()
	sign.text = "FRONT DOOR"
	sign.position = Vector2(-42, -37)
	sign.add_theme_font_size_override("font_size", 9)
	sign.add_theme_color_override("font_color", INK)
	exit.add_child(sign)
	exit.body_entered.connect(_try_exit)
	maze.add_child(exit)

func _configure_player() -> void:
	player.position = Vector2(2.5, 3.5) * CELL
	var sprite: Sprite2D = player.get_node("BeanSprite")
	sprite.texture = BEAN
	sprite.scale = Vector2(0.12, 0.12)
	var camera: Camera2D = player.get_node("Camera2D")
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	var zoom_level := 1.7
	camera.zoom = Vector2(zoom_level, zoom_level)
	var half_view := get_viewport_rect().size / (2.0 * zoom_level)
	camera.limit_left = int(half_view.x)
	camera.limit_top = 0
	camera.limit_right = int(WIDTH * CELL - half_view.x)
	camera.limit_bottom = HEIGHT * CELL

func _add_mrs_wicket() -> void:
	wicket = CharacterBody2D.new()
	wicket.name = "MrsWicket"
	wicket.position = Vector2(16.5, 4.5) * CELL
	wicket.collision_layer = 1
	wicket.collision_mask = 1
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 15
	collision.shape = shape
	wicket.add_child(collision)
	var sprite := Sprite2D.new()
	sprite.texture = WICKET_TEXTURE
	sprite.scale = Vector2(0.14, 0.14)
	sprite.position.y = -5
	wicket.add_child(sprite)
	var name_tag := Label.new()
	name_tag.text = "MRS WICKET"
	name_tag.position = Vector2(-38, -37)
	name_tag.add_theme_font_size_override("font_size", 9)
	name_tag.add_theme_color_override("font_color", INK)
	wicket.add_child(name_tag)
	maze.add_child(wicket)

func _update_wicket_path() -> void:
	var start := Vector2i(int(wicket.position.x / CELL), int(wicket.position.y / CELL))
	var goal := Vector2i(int(player.position.x / CELL), int(player.position.y / CELL))
	if not pathfinder.is_in_boundsv(start) or not pathfinder.is_in_boundsv(goal):
		wicket_direction = Vector2.ZERO
		return
	var path: PackedVector2Array = pathfinder.get_id_path(start, goal)
	if path.size() > 1:
		var next_center := (path[1] + Vector2(0.5, 0.5)) * CELL
		wicket_direction = (next_center - wicket.position).normalized()
	else:
		wicket_direction = Vector2.ZERO

func _caught_by_wicket() -> void:
	if finished: return
	finished = true
	player.set_physics_process(false)
	wicket.velocity = Vector2.ZERO
	_show_panel("MRS WICKET CAUGHT YOU!", "Mr. Bean has to try escaping again.", "TRY AGAIN", _restart)

func _build_hud() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 16
	panel.offset_right = -16
	panel.offset_top = 12
	panel.offset_bottom = 92
	panel.add_theme_stylebox_override("panel", _panel_style(CREAM, BROWN, 2, 14))
	ui_layer.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	panel.add_child(stack)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	stack.add_child(row)
	var title := _ui_label("MR. BEAN'S HOUSE", 18, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	counter_text = _ui_label("TEDDIES  0 / %d" % TEDDY_COUNT, 15, BROWN)
	row.add_child(counter_text)
	key_text = _ui_label("KEY  MISSING", 15, BROWN)
	row.add_child(key_text)
	timer_text = _ui_label("TIME  00:00", 15, INK)
	row.add_child(timer_text)
	var pause_button := _ui_button("Pause", _toggle_pause)
	row.add_child(pause_button)
	var restart_button := _ui_button("Restart", _restart)
	row.add_child(restart_button)
	var objective := _ui_label("Find all 4 teddy bears and the house key, then escape through the front door.", 12, GREEN)
	stack.add_child(objective)
	notice = _ui_label("", 14, Color("a64f43"))
	notice.position = Vector2(20, 108)
	ui_layer.add_child(notice)

func _collect(body: Node2D, teddy: Area2D) -> void:
	if body != player: return
	collected += 1
	teddy.queue_free()
	_update_hud()

func _collect_key(body: Node2D) -> void:
	if body != player: return
	key_collected = true
	var key := maze.get_node_or_null("HouseKey")
	if is_instance_valid(key): key.queue_free()
	_update_hud()

func _try_exit(body: Node2D) -> void:
	if body != player: return
	if collected < TEDDY_COUNT or not key_collected:
		var missing := ""
		if collected < TEDDY_COUNT: missing += "%d teddy bear(s)" % (TEDDY_COUNT - collected)
		if not key_collected:
			if not missing.is_empty(): missing += " and "
			missing += "the house key"
		notice.text = "Still need %s." % missing
		return
	finished = true
	player.set_physics_process(false)
	var time_string := "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
	_show_panel("MR. BEAN ESCAPED!", "All teddy bears and the house key collected.\nCompletion time: %s" % time_string, "PLAY AGAIN", _restart)

func _toggle_pause() -> void:
	if finished: return
	paused = not paused
	get_tree().paused = paused
	if paused:
		_show_panel("PAUSED", "Take a little break.", "RESUME", _toggle_pause)
	else:
		if is_instance_valid(overlay): overlay.queue_free()

func _show_panel(title_text: String, detail_text: String, button_text: String, action: Callable) -> void:
	if is_instance_valid(overlay): overlay.queue_free()
	overlay = ColorRect.new()
	overlay.color = Color(0.12, 0.1, 0.08, 0.58)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	ui_layer.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	pause_panel = PanelContainer.new()
	pause_panel.custom_minimum_size = Vector2(500, 270)
	pause_panel.add_theme_stylebox_override("panel", _panel_style(CREAM, BROWN, 4, 20))
	center.add_child(pause_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	pause_panel.add_child(box)
	var title := _ui_label(title_text, 30, INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var detail := _ui_label(detail_text, 17, BROWN)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)
	var button := _ui_button(button_text, action)
	box.add_child(button)
	if paused and not finished:
		var restart := _ui_button("RESTART LEVEL", _restart)
		box.add_child(restart)

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _update_hud() -> void:
	if is_instance_valid(counter_text): counter_text.text = "TEDDIES  %d / %d" % [collected, TEDDY_COUNT]
	if is_instance_valid(key_text): key_text.text = "KEY  FOUND" if key_collected else "KEY  MISSING"

func _ui_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _ui_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(110, 38)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_stylebox_override("normal", _panel_style(GREEN, BROWN, 1, 9))
	button.add_theme_stylebox_override("hover", _panel_style(Color("6b855e"), BROWN, 1, 9))
	button.pressed.connect(action)
	return button

func _panel_style(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _circle(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * i / 20.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
