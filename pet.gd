extends Node2D
## Bearnie desktop pet.
## Made by Pratik Dash
## Left click = pet, left drag = pick up/throw, right click = menu, middle click = quit.
## Swipe the cursor across him fast to bonk him. Toys live in the right-click "Toy box".
## Watches your cursor, chases it, jumps up and hangs off it (you keep full control —
## the bear only moves its own window), and eats files you drop on it (files are untouched).

const PX := 4                  # sprite scale (32px art -> 128px window)
const SIZE := 32 * PX
const WALK_SPEED := 45.0       # screen px per second
const CHASE_SPEED := 120.0
const GRAVITY := 1800.0
const NAP_AFTER := 150.0       # seconds without attention before napping
const HUNGRY_AFTER := 300.0    # seconds without food before complaining
const DRAG_THRESHOLD := 6.0
const NOTICE_RADIUS := 380.0   # cursor this close -> bear watches it
const JUMP_REACH := 420.0      # how high above its head it can jump
const SHAKE_SPEED := 2600.0    # cursor speed (px/s) that shakes the bear off
const HANG_TIME := Vector2(4.0, 10.0)
const MAX_THROW := 3200.0      # cap on toss speed (px/s)
const WALL_BOUNCE := 0.6       # how much speed survives a wall hit
const FLOOR_BOUNCE := 0.35
const AIR_DRAG := 0.5          # fraction of sideways speed kept per second in the air
const SHAKE_DIZZY := 1400.0    # shake energy needed to make him dizzy while held
const SWAT_SPEED := 2400.0     # cursor speed (px/s) that counts as a bonk
const TOY := preload("res://toy.gd")
const TOY_KINDS := ["ball", "duck", "honey", "pogo"]
const MAX_TOYS := 8

const EMOTES := ["wave", "music", "thinking", "bored", "lookaround", "sneeze", "yawn",
	"cheer", "starry", "shine", "bloom", "talk", "glasses", "cool", "tongue", "smug"]
const PET_REACTIONS := ["happy", "love", "laugh", "kiss", "shy", "wink"]

const SAVE_PATH := "user://bearnie.cfg"

enum MenuItem { STATS, FEED, DANCE, NAP, STAY, QUIT, TOYS }

enum State { IDLE, WALK, EMOTE, NAP, HELD, FALL, CHASE, JUMP, HANG, PLAY, POGO }

@onready var spr: AnimatedSprite2D = $Sprite

var state := State.IDLE
var timer := 0.0
var walk_dir := 1
var pos := Vector2.ZERO          # window position (float, for smooth movement)
var vel := Vector2.ZERO          # velocity while flying / jumping
var fall_start_y := 0.0
var shaken := false
var area := Rect2i()             # usable screen area

var since_attention := 0.0
var since_food := 0.0
var poke_times := []

var pressing := false
var press_mouse := Vector2i.ZERO
var grab_offset := Vector2i.ZERO

var hover_time := 0.0            # how long the cursor has hung around nearby
var interest_cd := 3.0           # cooldown between chase/jump/swipe moves
var last_mouse := Vector2.ZERO
var mouse_speed := 0.0
var mouse_vel := Vector2.ZERO
var shake_energy := 0.0
var wall_hits := 0
var got_hit := false
var hit_cd := 0.0
var play_target = null   # toy the bear is walking over to
var pogo = null          # pogo stick being ridden
var pogo_time := 0.0
var after_pogo := false
var toybox: Window

var stay_put := false            # menu toggle: no wandering/chasing
var menu: PopupMenu
var save := ConfigFile.new()
var times_fed := 0
var times_pet := 0
var save_timer := 60.0


func _ready() -> void:
	Engine.max_fps = 30
	randomize()
	var win := get_window()
	win.size = Vector2i(SIZE, SIZE)
	area = DisplayServer.screen_get_usable_rect(win.current_screen)
	pos = Vector2(area.position.x + randi_range(0, area.size.x - SIZE), _floor_y())
	_apply_pos()
	# Only the bear's body catches the mouse; clicks pass through the empty corners.
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([
		Vector2(2, 2) * PX, Vector2(30, 2) * PX, Vector2(30, 32) * PX, Vector2(2, 32) * PX]))
	_make_loop_anim("hang", "cheer", 4.0)
	spr.animation_finished.connect(_on_animation_finished)
	win.files_dropped.connect(_on_files_dropped)
	last_mouse = Vector2(DisplayServer.mouse_get_position())
	get_tree().set_auto_accept_quit(false)
	_build_menu()
	_build_toybox()
	_load_and_greet()


## Builds a looping copy of an existing animation (e.g. arms-up kicking while hanging).
func _make_loop_anim(new_name: String, from: String, fps: float) -> void:
	var sf := spr.sprite_frames
	if sf.has_animation(new_name):
		return
	sf.add_animation(new_name)
	sf.set_animation_loop(new_name, true)
	sf.set_animation_speed(new_name, fps)
	for i in sf.get_frame_count(from):
		sf.add_frame(new_name, sf.get_frame_texture(from, i), sf.get_frame_duration(from, i))


func _floor_y() -> float:
	return float(area.end.y - SIZE)


func _apply_pos() -> void:
	get_window().position = Vector2i(pos.round())


func _center() -> Vector2:
	return pos + Vector2(SIZE, SIZE) * 0.5


func _play(anim: String) -> void:
	if spr.animation != StringName(anim) or not spr.is_playing():
		spr.play(anim)


# ---------------- state changes ----------------

func _go_idle(duration := -1.0) -> void:
	state = State.IDLE
	spr.flip_h = false
	spr.play("idle")
	timer = duration if duration > 0 else randf_range(4.0, 9.0)


func _go_walk() -> void:
	state = State.WALK
	walk_dir = -1 if randf() < 0.5 else 1
	if pos.x < area.position.x + SIZE:
		walk_dir = 1
	elif pos.x > area.end.x - SIZE * 2:
		walk_dir = -1
	spr.flip_h = walk_dir < 0
	_play("walk")
	timer = randf_range(3.0, 8.0)


func _emote(anim: String, face_left := false) -> void:
	state = State.EMOTE
	spr.flip_h = face_left
	spr.play(anim)


func _go_nap() -> void:
	state = State.NAP
	spr.flip_h = false
	spr.play("fall_asleep")
	timer = randf_range(60.0, 180.0)


func _go_chase() -> void:
	state = State.CHASE
	timer = 7.0
	since_attention = 0.0
	_play("walk")


func _go_jump(target: Vector2) -> void:
	state = State.JUMP
	since_attention = 0.0
	interest_cd = randf_range(5.0, 9.0)
	var height := clampf(pos.y - target.y + 20.0, 60.0, JUMP_REACH)
	vel = Vector2(0.0, -sqrt(2.0 * GRAVITY * height))
	fall_start_y = pos.y
	spr.flip_h = false
	spr.play("jump")


func _go_hang() -> void:
	state = State.HANG
	shaken = false
	timer = randf_range(HANG_TIME.x, HANG_TIME.y)
	spr.flip_h = false
	spr.play("hang")


func _go_fall(from_shake := false, start_vel := Vector2.ZERO) -> void:
	state = State.FALL
	shaken = shaken or from_shake
	vel = start_vel.limit_length(MAX_THROW)
	wall_hits = 0
	fall_start_y = pos.y
	spr.play("dizzy" if shaken else "held")


# ---------------- main loop ----------------

func _process(delta: float) -> void:
	since_attention += delta
	since_food += delta
	interest_cd -= delta
	hit_cd -= delta
	save_timer -= delta
	if save_timer <= 0.0:
		save_timer = 60.0
		_save()

	var m := Vector2(DisplayServer.mouse_get_position())
	var inst_speed := (m - last_mouse).length() / maxf(delta, 0.001)
	mouse_speed = lerpf(mouse_speed, inst_speed, 0.5)
	mouse_vel = mouse_vel.lerp((m - last_mouse) / maxf(delta, 0.001), 0.5)
	last_mouse = m

	_handle_mouse()
	_check_hits(m)

	match state:
		State.IDLE:
			_notice_toys()
			if state == State.IDLE:
				_watch_cursor(m, delta)
			timer -= delta
			if state == State.IDLE and timer <= 0.0:
				_decide()
		State.WALK:
			pos.x += walk_dir * WALK_SPEED * delta
			var min_x := float(area.position.x)
			var max_x := float(area.end.x - SIZE)
			if pos.x <= min_x or pos.x >= max_x:
				pos.x = clampf(pos.x, min_x, max_x)
				walk_dir = -walk_dir
				spr.flip_h = walk_dir < 0
			_apply_pos()
			timer -= delta
			if timer <= 0.0:
				_go_idle()
		State.CHASE:
			_chase(m, delta)
		State.JUMP:
			_jump_step(m, delta)
		State.HANG:
			_hang_step(m, delta)
		State.NAP:
			timer -= delta
			if timer <= 0.0:
				_wake_up()
		State.HELD:
			pos = m - Vector2(grab_offset)
			_apply_pos()
			_shake_check(delta)
		State.FALL:
			_fall_step(delta)
		State.PLAY:
			_play_step(delta)
		State.POGO:
			_pogo_step(delta)


func _watch_cursor(m: Vector2, delta: float) -> void:
	var d := m - _center()
	var dist := d.length()
	if dist > NOTICE_RADIUS:
		hover_time = 0.0
		if spr.animation != &"idle":
			spr.play("idle")
		return

	hover_time += delta
	# eyes follow the cursor
	var look := ""
	if absf(d.x) > absf(d.y):
		look = "lookL" if d.x < 0 else "lookR"
	else:
		look = "lookUp" if d.y < 0 else "lookDown"
	if spr.animation != StringName(look):
		spr.play(look)

	# cursor on the bear itself (you're about to pet/drag it) -> just watch
	if Rect2(pos, Vector2(SIZE, SIZE)).has_point(m):
		hover_time = 0.0
		return
	if interest_cd > 0.0 or hover_time < 1.0:
		return
	# cursor hovering above its head -> jump for it
	if not stay_put and d.y < -40.0 and absf(d.x) < 90.0 and -d.y < JUMP_REACH + SIZE * 0.5:
		_go_jump(m)
	# cursor right beside it -> swipe at it
	elif absf(d.y) < 90.0 and absf(d.x) < 200.0:
		interest_cd = randf_range(4.0, 7.0)
		_emote("wave", d.x < 0)
	# cursor lingering further along the bottom of the screen -> chase it
	elif not stay_put and hover_time > 2.0 and absf(d.x) > 90.0 and m.y > area.end.y - 500:
		interest_cd = randf_range(4.0, 7.0)
		_go_chase()


func _chase(m: Vector2, delta: float) -> void:
	var dx := m.x - _center().x
	spr.flip_h = dx < 0
	if absf(dx) > 15.0:
		pos.x += signf(dx) * CHASE_SPEED * delta
		pos.x = clampf(pos.x, float(area.position.x), float(area.end.x - SIZE))
		_apply_pos()
	else:
		var dy := m.y - pos.y
		if dy < 0.0 and -dy < JUMP_REACH:
			_go_jump(m)
		else:
			_go_idle()
		return
	timer -= delta
	if timer <= 0.0 or (m - _center()).length() > NOTICE_RADIUS * 2.0:
		_go_idle()


func _jump_step(m: Vector2, delta: float) -> void:
	vel.y += GRAVITY * delta
	pos.y += vel.y * delta
	# drift sideways toward the cursor
	var tx := m.x - SIZE * 0.5
	pos.x = move_toward(pos.x, tx, 260.0 * delta)
	_apply_pos()
	# grab when the cursor is just above the bear's paws
	var grab_zone := Rect2(pos.x + 16.0, pos.y - 40.0, SIZE - 32.0, 56.0)
	if grab_zone.has_point(m):
		_go_hang()
		return
	if vel.y > 0.0:
		# missed — fall back down
		state = State.FALL
		shaken = false
		wall_hits = 0
		vel.x = 0.0
		spr.play("held")


func _hang_step(m: Vector2, delta: float) -> void:
	# window sits just *below* the cursor so the cursor never covers the bear;
	# your clicks keep going to whatever is under it.
	pos = Vector2(m.x - SIZE * 0.5, m.y + 4.0)
	pos.x = clampf(pos.x, area.position.x - SIZE * 0.5, area.end.x - SIZE * 0.5)
	pos.y = minf(pos.y, _floor_y())
	_apply_pos()
	if pos.y >= _floor_y():
		_go_idle()
		return
	if mouse_speed > SHAKE_SPEED:
		_go_fall(true, mouse_vel * 0.6)
		return
	timer -= delta
	if timer <= 0.0:
		_go_fall(false)


func _fall_step(delta: float) -> void:
	vel.y += GRAVITY * delta
	vel.x *= pow(AIR_DRAG, delta)
	pos += vel * delta
	var min_x := float(area.position.x)
	var max_x := float(area.end.x - SIZE)
	var top := float(area.position.y)
	# bounce off the screen edges
	if pos.x < min_x or pos.x > max_x:
		pos.x = clampf(pos.x, min_x, max_x)
		if absf(vel.x) > 250.0:
			wall_hits += 1
		vel.x = -vel.x * WALL_BOUNCE
	if pos.y < top:
		pos.y = top
		vel.y = -vel.y * 0.5
		wall_hits += 1
	# tilt with sideways speed while flying
	spr.rotation = clampf(vel.x / 4000.0, -0.3, 0.3)
	if pos.y >= _floor_y():
		pos.y = _floor_y()
		if vel.y > 700.0:
			# hit the floor hard -> little bounce
			vel.y = -vel.y * FLOOR_BOUNCE
			vel.x *= 0.7
		else:
			_land()
			return
	_apply_pos()


func _land() -> void:
	vel = Vector2.ZERO
	spr.rotation = 0.0
	_apply_pos()
	var dropped := _floor_y() - fall_start_y
	if after_pogo:
		_emote("laugh")
	elif got_hit:
		if shaken or wall_hits >= 1 or dropped > 300.0:
			_emote("dizzy")
		else:
			_emote(["angry", "surprised", "cry"].pick_random())
	elif shaken or wall_hits >= 2 or dropped > 300.0:
		_emote("dizzy")
	else:
		_emote("land")
	shaken = false
	got_hit = false
	after_pogo = false
	wall_hits = 0


## While held: shaking the mouse back and forth builds up "shake energy".
func _shake_check(delta: float) -> void:
	if mouse_speed > 1200.0:
		shake_energy += mouse_speed * delta
	shake_energy *= pow(0.25, delta)
	if not shaken and shake_energy > SHAKE_DIZZY:
		shaken = true
		spr.play("dizzy")


func _is_night() -> bool:
	var h: int = Time.get_datetime_dict_from_system().hour
	return h >= 22 or h < 6


func _decide() -> void:
	var nap_after := NAP_AFTER * (0.4 if _is_night() else 1.0)
	if since_attention > nap_after and randf() < 0.6:
		_go_nap()
	elif _is_night() and randf() < 0.2:
		_emote("yawn")
	elif since_food > HUNGRY_AFTER and randf() < 0.5:
		_emote("hungry")
	elif since_attention > NAP_AFTER * 0.6 and randf() < 0.15:
		_emote("lonely")
	elif not stay_put and _find_toy(900.0) != null and randf() < 0.6:
		_go_play(_find_toy(900.0))
	else:
		var r := randf()
		if r < 0.45 and not stay_put:
			_go_walk()
		elif r < 0.85:
			_emote(EMOTES.pick_random())
		else:
			_go_idle()


func _on_animation_finished() -> void:
	match state:
		State.EMOTE:
			_go_idle()
		State.NAP:
			if spr.animation == &"fall_asleep":
				spr.play("nap")
			elif spr.animation == &"wake":
				_go_idle()


func _wake_up() -> void:
	state = State.NAP
	timer = 999.0
	spr.play("wake")


# ---------------- files ----------------

## Files dropped on the bear get "eaten" — purely an animation, the files are never touched.
func _on_files_dropped(_files: PackedStringArray) -> void:
	since_attention = 0.0
	since_food = 0.0
	times_fed += 1
	if state in [State.HELD, State.FALL, State.JUMP, State.HANG]:
		return
	if state == State.NAP:
		_wake_up()
		return
	_emote("eat")


# ---------------- mouse ----------------

func _handle_mouse() -> void:
	var left := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var m := DisplayServer.mouse_get_position()
	if pressing and left and state != State.HELD:
		if Vector2(m - press_mouse).length() > DRAG_THRESHOLD:
			_drop_pogo()
			state = State.HELD
			shaken = false
			shake_energy = 0.0
			spr.flip_h = false
			spr.rotation = 0.0
			spr.play("held")
	elif pressing and not left:
		pressing = false
		if state == State.HELD:
			_go_fall(false, mouse_vel)
		else:
			_poke()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				pressing = true
				press_mouse = DisplayServer.mouse_get_position()
				grab_offset = press_mouse - get_window().position
			MOUSE_BUTTON_RIGHT:
				_open_menu()
			MOUSE_BUTTON_MIDDLE:
				_quit()


func _poke() -> void:
	since_attention = 0.0
	if state in [State.HELD, State.FALL, State.JUMP, State.HANG]:
		return
	if state == State.NAP:
		_wake_up()
		return
	times_pet += 1
	var now := Time.get_ticks_msec() / 1000.0
	poke_times.append(now)
	poke_times = poke_times.filter(func(t): return now - t < 3.0)
	if poke_times.size() >= 6:
		poke_times.clear()
		_emote("angry")
	elif poke_times.size() >= 4:
		_emote("dizzy")
	else:
		_emote(PET_REACTIONS.pick_random())


func _feed() -> void:
	since_attention = 0.0
	since_food = 0.0
	times_fed += 1
	if state == State.NAP:
		_wake_up()
		return
	if state in [State.HELD, State.FALL, State.JUMP, State.HANG]:
		return
	_emote("eat")


# ---------------- menu ----------------

func _build_menu() -> void:
	# let the popup open as its own window instead of being clipped to the 128px pet window
	get_viewport().gui_embed_subwindows = false
	menu = PopupMenu.new()
	add_child(menu)
	menu.add_item("", MenuItem.STATS)
	menu.set_item_disabled(menu.get_item_index(MenuItem.STATS), true)
	menu.add_separator()
	menu.add_item("Feed", MenuItem.FEED)
	menu.add_item("Dance", MenuItem.DANCE)
	menu.add_item("Nap", MenuItem.NAP)
	menu.add_check_item("Stay put", MenuItem.STAY)
	menu.add_item("Toy box", MenuItem.TOYS)
	menu.add_separator()
	menu.add_item("Quit", MenuItem.QUIT)
	menu.id_pressed.connect(_on_menu)


func _open_menu() -> void:
	var idx := menu.get_item_index(MenuItem.STATS)
	menu.set_item_text(idx, "Fed %d x  /  Pet %d x" % [times_fed, times_pet])
	menu.set_item_checked(menu.get_item_index(MenuItem.STAY), stay_put)
	menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _on_menu(id: int) -> void:
	match id:
		MenuItem.FEED:
			_feed()
		MenuItem.DANCE:
			if state not in [State.HELD, State.FALL, State.JUMP, State.HANG]:
				since_attention = 0.0
				_emote("music")
		MenuItem.NAP:
			if state not in [State.HELD, State.FALL, State.JUMP, State.HANG]:
				_go_nap()
		MenuItem.STAY:
			stay_put = not stay_put
			if stay_put and state in [State.WALK, State.CHASE]:
				_go_idle()
		MenuItem.TOYS:
			_open_toybox()
		MenuItem.QUIT:
			_quit()


# ---------------- memory ----------------

func _load_and_greet() -> void:
	var first_time := save.load(SAVE_PATH) != OK
	times_fed = save.get_value("stats", "fed", 0)
	times_pet = save.get_value("stats", "pet", 0)
	stay_put = save.get_value("settings", "stay_put", false)
	var last_seen: int = save.get_value("stats", "last_seen", 0)
	var away := int(Time.get_unix_time_from_system()) - last_seen
	if first_time:
		_emote("wave")          # nice to meet you
	elif away > 6 * 3600:
		_emote("cheer")         # missed you!
	elif _is_night():
		_emote("yawn")
	else:
		_emote("happy")


func _save() -> void:
	save.set_value("stats", "fed", times_fed)
	save.set_value("stats", "pet", times_pet)
	save.set_value("stats", "last_seen", int(Time.get_unix_time_from_system()))
	save.set_value("settings", "stay_put", stay_put)
	save.save(SAVE_PATH)


func _quit() -> void:
	_save()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


# ---------------- getting hit ----------------

## Bonks from a fast cursor swipe or a thrown toy.
func _check_hits(m: Vector2) -> void:
	if hit_cd > 0.0 or state in [State.HELD, State.HANG]:
		return
	var body := Rect2(pos + Vector2(12, 8), Vector2(SIZE - 24, SIZE - 8))
	if not pressing and mouse_speed > SWAT_SPEED and body.has_point(m):
		_knock(mouse_vel * 0.45 + Vector2(0, -350))
		return
	var toys: Array = get_tree().get_nodes_in_group("toys")
	for t in toys:
		if t.held or t.attached or t.hit_cd > 0.0:
			continue
		if t.vel.length() < 450.0 or not body.intersects(t.rect()):
			continue
		t.hit_cd = 0.6
		if t.kind == "honey" and state != State.FALL:
			t.queue_free()      # caught it — snack time
			_feed()
			return
		var push: Vector2 = t.vel * 0.35 + Vector2(0, -300)
		t.vel = Vector2(-t.vel.x * 0.4, -absf(t.vel.y) * 0.3 - 200.0)
		_knock(push)
		return


func _knock(v: Vector2) -> void:
	hit_cd = 0.6
	since_attention = 0.0
	_drop_pogo()
	got_hit = true
	after_pogo = false
	state = State.FALL
	vel = v.limit_length(MAX_THROW)
	wall_hits = 0
	fall_start_y = pos.y
	spr.flip_h = false
	spr.play("scared")


# ---------------- toys ----------------

func _find_toy(max_dist: float):
	var best = null
	var best_d := max_dist
	var toys: Array = get_tree().get_nodes_in_group("toys")
	for t in toys:
		if t.held or t.attached or not t.resting:
			continue
		var d: float = absf(t.rect().get_center().x - _center().x)
		if d < best_d:
			best_d = d
			best = t
	return best


func _notice_toys() -> void:
	if stay_put or interest_cd > 0.0:
		return
	var t = _find_toy(500.0)
	if t != null:
		interest_cd = randf_range(3.0, 6.0)
		_go_play(t)


func _go_play(t) -> void:
	state = State.PLAY
	play_target = t
	timer = 8.0
	since_attention = 0.0
	_play("walk")


func _play_step(delta: float) -> void:
	if not is_instance_valid(play_target) or play_target.held or play_target.attached:
		_go_idle()
		return
	var dx: float = play_target.rect().get_center().x - _center().x
	spr.flip_h = dx < 0
	if absf(dx) > 40.0:
		pos.x += signf(dx) * CHASE_SPEED * delta
		pos.x = clampf(pos.x, float(area.position.x), float(area.end.x - SIZE))
		_apply_pos()
		timer -= delta
		if timer <= 0.0:
			_go_idle()
		return
	match play_target.kind:
		"pogo":
			_go_pogo(play_target)
		"honey":
			play_target.queue_free()
			_feed()
		_:
			# kick it!
			var dir := signf(dx) if dx != 0.0 else 1.0
			play_target.vel = Vector2(dir * randf_range(600.0, 1100.0), -randf_range(500.0, 950.0))
			play_target.resting = false
			_emote(["cheer", "happy", "laugh"].pick_random(), dx < 0)
	play_target = null


func _go_pogo(t) -> void:
	state = State.POGO
	pogo = t
	pogo.attached = true
	pogo.resting = false
	pogo_time = randf_range(7.0, 12.0)
	vel = Vector2(randf_range(-220.0, 220.0), -850.0)
	spr.play("hang")


func _pogo_floor() -> float:
	# bear stands on the pegs, ~60px down the stick
	return _floor_y() - (pogo.size.y - 60)


func _pogo_step(delta: float) -> void:
	if not is_instance_valid(pogo) or pogo.held:
		pogo = null
		_go_fall(false, vel)
		return
	pogo_time -= delta
	vel.y += GRAVITY * delta
	pos += vel * delta
	var min_x := float(area.position.x)
	var max_x := float(area.end.x - SIZE)
	if pos.x < min_x or pos.x > max_x:
		pos.x = clampf(pos.x, min_x, max_x)
		vel.x = -vel.x
	if pos.y < area.position.y:
		pos.y = area.position.y
		vel.y = absf(vel.y) * 0.3
	var fy: float = _pogo_floor()
	if pos.y >= fy:
		pos.y = fy
		if pogo_time <= 0.0:
			_drop_pogo()
			after_pogo = true
			_go_fall(false, Vector2(0.0, -250.0))
			return
		vel.y = -randf_range(700.0, 950.0)     # boing
		if randf() < 0.3:
			vel.x = randf_range(-260.0, 260.0)
	spr.flip_h = vel.x < 0
	_apply_pos()
	pogo.pos = Vector2(_center().x - pogo.size.x * 0.5, pos.y + SIZE - 60)
	pogo.position = Vector2i(pogo.pos.round())


func _drop_pogo() -> void:
	if pogo != null and is_instance_valid(pogo):
		pogo.attached = false
		pogo.vel = Vector2(randf_range(-150.0, 150.0), -250.0)
	pogo = null


func _build_toybox() -> void:
	toybox = Window.new()
	toybox.title = "Bearnie's toys"
	toybox.size = Vector2i(320, 130)
	toybox.unresizable = true
	toybox.always_on_top = true
	toybox.visible = false
	toybox.close_requested.connect(toybox.hide)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	toybox.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	var hint := Label.new()
	hint.text = "drag a toy out, throw it at him!"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	col.add_child(row)
	for k in TOY_KINDS:
		var icon := TextureRect.new()
		icon.texture = load("res://sprites/toys/%s.png" % k)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(56, 84)
		icon.tooltip_text = k
		icon.mouse_default_cursor_shape = Control.CURSOR_DRAG
		icon.gui_input.connect(_on_toybox_input.bind(k))
		row.add_child(icon)
	add_child(toybox)


func _open_toybox() -> void:
	var x := clampi(int(pos.x) - 96, area.position.x, area.end.x - toybox.size.x)
	var y := maxi(int(pos.y) - toybox.size.y - 40, area.position.y)
	toybox.position = Vector2i(x, y)
	toybox.show()


func _on_toybox_input(event: InputEvent, kind: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_spawn_toy(kind)


func _spawn_toy(kind: String) -> void:
	var toys: Array = get_tree().get_nodes_in_group("toys")
	if toys.size() >= MAX_TOYS:
		toys[0].queue_free()
	var t = TOY.new()
	t.setup(kind, Vector2(DisplayServer.mouse_get_position()))
	add_child(t)
	t.grab()
