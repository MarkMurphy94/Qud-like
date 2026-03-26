extends Area2D
class_name LocalMapTile

## Single source of truth for a local-map entry point on the overworld.
## If scene_path is non-empty a hand-crafted settlement scene is loaded;
## otherwise AreaContainer generates the area from tile_metadata.
@export var scene_path: String = ""
@export var tile_metadata: TileMetadata


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		if tile_metadata:
			print("Player entered tile at position: ", tile_metadata.coords)
		body.current_tile = self

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		if tile_metadata:
			print("Player exited tile at position: ", tile_metadata.coords)
		body.current_tile = null
