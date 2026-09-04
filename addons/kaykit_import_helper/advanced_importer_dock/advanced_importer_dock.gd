@tool
extends PanelContainer

signal reimport_requested(settings: Dictionary[String, bool])

@onready var generate_gridmap_check_box: CheckBox = $MainContainer/GenerateGridmapCheckBox
@onready var reimport_button: Button = $MainContainer/ReimportButton
@onready var selected_files_rich_text_label: RichTextLabel = $MainContainer/SelectedFilesRichTextLabel

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_apply_button_icon()

# Applies the editor "Play" icon to the reimport button.
# This ensures the button visually matches Godot's editor style.
func _apply_button_icon() -> void:
	# Get the current editor theme (only available in editor context)
	var editor_theme: Theme = EditorInterface.get_editor_theme()
	
	# Safely attempt to retrieve the "Play" icon from the EditorIcons set
	var play_icon: Texture2D = editor_theme.get_icon(&"Play", &"EditorIcons")
	
	# Apply the icon
	reimport_button.icon = play_icon

# Build a single settings object
func _get_settings() -> Dictionary[String, bool]:
	return {
		"generate_gridmap": generate_gridmap_check_box.button_pressed
	}

# Called when the reimport button is pressed.
# Emits a custom signal including the current checkbox states so other scripts can handle the reimport logic.
func _on_reimport_button_pressed() -> void:
	var settings: Dictionary[String, bool] = _get_settings()
	
	reimport_requested.emit(settings)
