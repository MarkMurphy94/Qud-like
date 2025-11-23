extends Node2D

var scene_loading = false
var scene_path: String
var time_elapsed: int
var scene_to_be_loaded

func load_screen():
	var scene = scene_path
	time_elapsed = Time.get_ticks_msec()
	ResourceLoader.load_threaded_request(scene)
	scene_loading = true

func _process(delta: float) -> void:
	if scene_loading:
		var progress = []
		var status = ResourceLoader.load_threaded_get_status(scene_path, progress)
		if status == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_IN_PROGRESS:
			print_rich("[color=pink]Loading Progress: [color=yellow]%s" % (progress[0]* 100))
		if status == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED:
			scene_to_be_loaded = ResourceLoader.load_threaded_get(scene_path)
			print_rich("[color=pink]Loading Progress: [color=green]%s" % (progress[0]* 100))
			time_elapsed = Time.get_ticks_msec() - time_elapsed
			print_rich("[color=lime]Progress finished in: [color=green]%s" % (time_elapsed))
			
