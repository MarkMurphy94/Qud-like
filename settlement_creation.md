# Current process for Creating Settlement scenes

1. Open settlement_generator scene, click top SettlementGenerator node and add a new Area Template config
2.  Click Scene>Reload Saved Scene
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
    
5. In the game scene, click the OverworldMap node and add a new entry to the Settlements List
6. add the overworld x, y coordinates for where the settlement should be located and copy+paste the filepath for the settlement scene into the string field and save the game scene