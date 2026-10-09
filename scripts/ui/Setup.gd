extends Control
## First-run screen: asks for the player's own Unnatural Selection folder.

signal folder_chosen(dir: String)

@onready var _status: Label = $Panel/VBox/Status
@onready var _dialog: FileDialog = $FileDialog


func _ready() -> void:
	$Panel/VBox/Choose.pressed.connect(_dialog.popup_centered_ratio.bind(0.8))
	_dialog.dir_selected.connect(_on_dir)
	if not Settings.game_dir.is_empty():
		_status.text = "Not a valid install:\n%s" % Settings.game_dir


func _on_dir(dir: String) -> void:
	if Assets.is_valid_game_dir(dir):
		folder_chosen.emit(dir)
	else:
		_status.text = "That folder doesn't contain the game's data files\n(looked for DATA/AL1.BIN, DATA/5X.PAL ...).\nPick the folder that holds UNS.EXE."
