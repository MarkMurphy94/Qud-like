extends CanvasLayer

@onready var hp_bar: ProgressBar = $MarginContainer/TopContainer/BarsContainer/HPContainer/HPBar
@onready var mp_bar: ProgressBar = $MarginContainer/TopContainer/BarsContainer/MPContainer/MPBar
@onready var sp_bar: ProgressBar = $MarginContainer/TopContainer/BarsContainer/SPContainer/SPBar
@onready var hp_value: Label = $MarginContainer/TopContainer/BarsContainer/HPContainer/HPValue
@onready var mp_value: Label = $MarginContainer/TopContainer/BarsContainer/MPContainer/MPValue
@onready var sp_value: Label = $MarginContainer/TopContainer/BarsContainer/SPContainer/SPValue
@onready var pause_button: Button = $MarginContainer/TopContainer/PauseButton

signal pause_requested

func _ready() -> void:
	pause_button.pressed.connect(_on_pause_button_pressed)
	_style_bars()

func _style_bars() -> void:
	# HP = Red, MP = Blue, SP = Green
	_set_bar_color(hp_bar, Color(0.8, 0.2, 0.2), Color(0.3, 0.1, 0.1))
	_set_bar_color(mp_bar, Color(0.2, 0.4, 0.9), Color(0.1, 0.15, 0.35))
	_set_bar_color(sp_bar, Color(0.2, 0.75, 0.2), Color(0.1, 0.3, 0.1))

func _set_bar_color(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill_style)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = bg_color
	bg_style.corner_radius_top_left = 2
	bg_style.corner_radius_top_right = 2
	bg_style.corner_radius_bottom_left = 2
	bg_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg_style)

func update_hp(current: int, max_value: int) -> void:
	hp_bar.max_value = max_value
	hp_bar.value = current
	hp_value.text = "%d/%d" % [current, max_value]

func update_mp(current: int, max_value: int) -> void:
	mp_bar.max_value = max_value
	mp_bar.value = current
	mp_value.text = "%d/%d" % [current, max_value]

func update_sp(current: int, max_value: int) -> void:
	sp_bar.max_value = max_value
	sp_bar.value = current
	sp_value.text = "%d/%d" % [current, max_value]

func _on_pause_button_pressed() -> void:
	emit_signal("pause_requested")
