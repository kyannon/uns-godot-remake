extends Node
## Root scene: shows the setup screen until a valid game folder is chosen,
## then the lab.
##
## Command-line options (after "--"):
##   --game-dir=PATH      use this Unnatural Selection install folder
##   --demo               start the lab with the demo pens populated
##   --screenshot=FILE    save a PNG after --frames=N frames (default 120) and quit
##   --click=X,Y[;X,Y]    simulate left clicks (logical 320x200 coords) at startup

const LabScene := preload("res://scenes/Lab.tscn")
const SetupScene := preload("res://scenes/Setup.tscn")

var _args := {}
var _frames := 0
var _current: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if _args.has("game-dir"):
		Settings.game_dir = _args["game-dir"]
	if Assets.init_from_settings():
		_show_lab()
	else:
		_show_setup()


func _show_lab() -> void:
	_swap(LabScene.instantiate())
	_current.request_setup.connect(_show_setup)
	if _args.has("demo"):
		_current.call_deferred("_demo_layout")


func _show_setup() -> void:
	_swap(SetupScene.instantiate())
	_current.folder_chosen.connect(_on_folder_chosen)


func _on_folder_chosen(dir: String) -> void:
	Settings.game_dir = dir
	Settings.save_settings()
	if Assets.init_from_settings():
		_show_lab()


func _swap(n: Node) -> void:
	if _current:
		_current.queue_free()
	_current = n
	add_child(n)


func _process(_delta: float) -> void:
	_frames += 1
	if _args.has("click") and _frames == 10:
		for pair in str(_args["click"]).split(";"):
			var xy := pair.split(",")
			if xy.size() == 2 and _current and _current.has_method("_on_press"):
				_current._on_press(Vector2(float(xy[0]), float(xy[1])), MOUSE_BUTTON_LEFT)
	if _args.has("screenshot") and _frames >= int(_args.get("frames", "120")):
		var img := get_viewport().get_texture().get_image()
		img.save_png(_args["screenshot"])
		print("saved screenshot ", _args["screenshot"], " ", img.get_size())
		get_tree().quit()
