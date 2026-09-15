extends CharacterBody3D

## Movement speed in meters per second.
@export var speed: float = 5.0
## Jump velocity applied on jump input.
@export var jump_velocity: float = 4.5
## Gravity (positive value; applied downward).
@export var gravity: float = 9.8

## Optional camera used for input-relative movement.
@export var camera: Camera3D

func _physics_process(delta: float) -> void:
	# Apply gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# Input direction (WASD / arrow keys via ui_* actions).
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := Vector3.ZERO
	if camera:
		# Move relative to the camera's facing direction.
		var forward := -camera.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := camera.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		direction = (forward * input_dir.y + right * input_dir.x).normalized()
	else:
		direction = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()