# Authored places

Drop a `MapConfig` `.tres` here to hand-author the location on one overworld tile.
`AuthoredPlaces` scans this folder (no registry to edit). The config claims the tile
named in its `overworld_tile`. When the player enters that tile, `MapGenerator`
builds the config's buildings instead of generating a layout, and
`BespokePlaceProvider` describes it as a `Place` with the usual id
(`settlement_<x>_<y>`), plus the `place.authored` tag.

The overworld still supplies roads, edge exits, culture and ruling faction for the
tile, so an authored town joins up with its neighbours.
