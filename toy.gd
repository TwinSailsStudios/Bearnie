extends Window
## A physics toy living in its own little transparent window.
## Left drag = pick up / throw, middle click = put it away.

const GRAVITY := 1800.0
const PX := 4
const MAX_SPEED := 3200.0

const KINDS := {
	"ball":  {"bounce": 0.75, "friction": 0.6, "spin": true},
	"duck":  {"bounce": 0.55, "friction": 0.3, "spin": false},
	"honey": {"bounce": 0.25, "friction": 0.05, "spin": false},
	"pogo":  {"bounce": 0.2, "friction": 0.05, "spin": false},
}

var kind := "ball"
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var held := false
var attached := false        # pogo stick being ridden by the bear
var resting := false         # sitting still on the floor
var hit_cd := 0.0            # stops one throw from hitting the bear many times
var grab_offset := Vector2.ZERO
var area := Rect2i()
var last_mouse := Vector2.ZERO
var mouse_vel := Vector2.ZERO
var spr := Sprite2D.new()


func setup(toy_kind: String, at: Vector2) -> void:
	kind = toy_kind
	var tex: Texture2D = load("res://sprites/toys/%s.png" % kind)
	size = Vector2i(tex.get_size() * PX)
	borderless = true
	transparent = true
	transparent_bg = true
	always_on_top = true
	unresizable = true
	unfocusable = true
	title = kind
	spr.texture = tex
	spr.scale = Vector2(PX, PX)
	spr.position = Vector2(size) * 0.5
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(spr)
	pos = at - Vector2(size) * 0.5
	position = Vector2i(pos)
	add_to_group("toys")
	window_input.connect(_on_window_input)


func _ready() -> void:
	area = DisplayServer.screen_get_usable_rect(current_screen)
	last_mouse = Vector2(DisplayServer.mouse_get_position())


func rect() -> Rect2:
	return Rect2(pos, Vector2(size))


func floor_y() -> float:
	return float(area.end.y - size.y)


func grab() -> void:
	held = true
	attached = false
	resting = false
	grab_offset = Vector2(size) * 0.5


func _on_window_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			held = true
			attached = false
			resting = false
			grab_offset = Vector2(DisplayServer.mouse_get_position()) - pos
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			queue_free()


func _process(delta: float) -> void:
	hit_cd -= delta
	var m := Vector2(DisplayServer.mouse_get_position())
	mouse_vel = mouse_vel.lerp((m - last_mouse) / maxf(delta, 0.001), 0.5)
	last_mouse = m

	if held:
		pos = m - grab_offset
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			held = false
			vel = mouse_vel.limit_length(MAX_SPEED)
			hit_cd = 0.0
		position = Vector2i(pos.round())
		return
	if attached:
		return   # the bear moves the pogo stick while riding it

	var k: Dictionary = KINDS[kind]
	vel.y += GRAVITY * delta
	pos += vel * delta
	var min_x := float(area.position.x)
	var max_x := float(area.end.x - size.x)
	if pos.x < min_x or pos.x > max_x:
		pos.x = clampf(pos.x, min_x, max_x)
		vel.x = -vel.x * k.bounce
	if pos.y < area.position.y:
		pos.y = area.position.y
		vel.y = -vel.y * k.bounce
	var on_floor := pos.y >= floor_y()
	if on_floor:
		pos.y = floor_y()
		if vel.y > 150.0:
			vel.y = -vel.y * k.bounce
		else:
			vel.y = 0.0
			vel.x *= pow(k.friction, delta)
	if k.spin:
		spr.rotation += vel.x * delta / (size.x * 0.5)
	resting = on_floor and vel.length() < 20.0
	position = Vector2i(pos.round())
