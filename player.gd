extends CharacterBody2D

## Top-down movement for the maze. Walls are handled by CharacterBody2D collisions.
@export var speed := 185.0

var _last_facing := Vector2.DOWN
var _walk_time := 0.0
var _sprite: Sprite2D

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_sprite = get_node_or_null("BeanSprite") as Sprite2D

func _physics_process(delta: float) -> void:
	var direction := Input.get_vector("Left", "Right", "Up", "Down")
	direction += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	velocity = direction * speed
	if direction.length_squared() > 0.01:
		_last_facing = direction
		_walk_time += delta * 12.0
	else:
		_walk_time = 0.0
	move_and_slide()
	if is_instance_valid(_sprite):
		if absf(_last_facing.x) > absf(_last_facing.y):
			_sprite.rotation = 0.0
			_sprite.flip_h = _last_facing.x < 0.0
		else:
			_sprite.flip_h = false
			_sprite.rotation = -PI / 2.0 if _last_facing.y < 0.0 else PI / 2.0
		_sprite.position.y = -5.0 + (sin(_walk_time) * 2.0 if direction.length_squared() > 0.01 else 0.0)
