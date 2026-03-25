extends Area2D
class_name LocalMapTile

## Single source of truth for a local-map entry point on the overworld.
## If scene_path is non-empty a hand-crafted settlement scene is loaded;
## otherwise AreaContainer generates the area from tile_metadata.
@export var scene_path: String = ""
@export var tile_metadata: TileMetadata

func _on_area_entered(area: Area2D) -> void:
	var player = area.get_parent()
	if player and player.is_in_group("Player"):
		player.current_tile = self


func _on_area_exited(area: Area2D) -> void:
	var player = area.get_parent()
	if player and player.is_in_group("Player"):
		player.current_tile = null
