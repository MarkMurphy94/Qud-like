extends RefCounted
class_name SpawnResult

## One thing a spawn resolve produced: an item, how many, and the stable id it
## is tracked by ("<place_id>/<slot_id>/<index>").

var item: Item
var quantity: int = 1
var spawn_id: String = ""


static func make(result_item: Item, result_quantity: int, result_spawn_id: String) -> SpawnResult:
	var result := SpawnResult.new()
	result.item = result_item
	result.quantity = result_quantity
	result.spawn_id = result_spawn_id
	return result
