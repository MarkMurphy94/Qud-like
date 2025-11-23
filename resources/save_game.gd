extends Resource
class_name SaveGameResource

# const SAVE_PATH := "user://save_game_file.tres"

# ------------ DATA TO SAVE --------------
@export var player_position: Vector2i
@export var player_current_scene_path: String

const SAVE_GAME_BASE_PATH := "user://save.tres"

# Use this to detect old player saves and update their data.
@export var version := 1

# The next three functions are just thin wrappers around Godot's APIs to keep
# the save API inside of the SaveGameAsResource resource.
func write_savegame() -> void:
	ResourceSaver.save(self, get_save_path())


static func save_exists() -> bool:
	return ResourceLoader.exists(get_save_path())


static func load_savegame() -> Resource:
	var save_path := get_save_path()
	return ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE)

# This function allows us to save and load a text resource in debug builds and a
# binary resource in the released product.
static func get_save_path() -> String:
	var extension := ".tres" if OS.is_debug_build() else ".res"
	return SAVE_GAME_BASE_PATH + extension

static func delete_savegame() -> void:
	var save_path := get_save_path()
	if FileAccess.file_exists(save_path):
		# Delete the save file
		pass
