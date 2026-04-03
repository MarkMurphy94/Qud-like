# Current process for Creating Settlement scenes

_Note: This is not a great process, and lot of it should be optimized soon..._

1. Open location_generator scene, click top SettlementGenerator node and add a new Area Template config
2.  Click Scene>Reload Saved Scene to run the tool script
3. Create a new scene and copy+paste the tilemap nodes from the generator scene to the new scene with a node2d parent
4. In the new scene, add a script to the parent node2d and copy+paste in this code and save the new settlement scene
    
    ```jsx
    @onready var tilemaps = {
    	"GROUND": $ground,
    	"INTERIOR_FLOOR": $interior_floor,
    	"WALLS": $walls,
    	"FURNITURE": $furniture,
    	"ITEMS": $items,
    	"DOORS": $doors,
    	"ROOF": $roof
    }
    ```
    
5. Add a new Config to the scene and set the Building Density and Map Type fields accordingly
6. In the game scene, under an appropriate category node (town_tiles, city_tiles, etc.), add a new local_map_tile scene node, paste the new map scene's filepath from res://, and add a new Tile Metadata config
7. In the tile metadata config, add the overworld vector2i(x, y) coordinates for where the map scene will be. Find this by opening the OverworldMap scene, clicking one of the tilemap nodes, and scrolling over the map until you see the right coords in the bottom left corner
8. Click the OverworldMap node and add optionally add a new entry to the Settlements List
