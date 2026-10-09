extends Node
## Persistent user settings (user://settings.cfg).

const PATH := "user://settings.cfg"

var game_dir: String = ""
var integer_scaling: bool = true
var fullscreen: bool = false
var hires_pack: String = ""  # optional folder of high-resolution replacement art


func _ready() -> void:
	load_settings()
	apply_display()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	game_dir = cfg.get_value("game", "dir", "")
	integer_scaling = cfg.get_value("display", "integer_scaling", true)
	fullscreen = cfg.get_value("display", "fullscreen", false)
	hires_pack = cfg.get_value("display", "hires_pack", "")


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "dir", game_dir)
	cfg.set_value("display", "integer_scaling", integer_scaling)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "hires_pack", hires_pack)
	cfg.save(PATH)


func apply_display() -> void:
	var win := get_window()
	if win == null:
		return
	win.content_scale_stretch = (
		Window.CONTENT_SCALE_STRETCH_INTEGER if integer_scaling
		else Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED
		)


func toggle_integer_scaling() -> void:
	integer_scaling = not integer_scaling
	apply_display()
	save_settings()


func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	apply_display()
	save_settings()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F11:
				toggle_fullscreen()
			KEY_F10:
				toggle_integer_scaling()
