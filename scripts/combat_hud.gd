extends CanvasLayer
## CombatHUD – built entirely in code, attached to a CanvasLayer created by CombatManager.
##
## Layout (screen space):
##   ┌─────────────────────────────────────────────────────┐
##   │  [TURN BANNER]  "YOUR TURN" / "Enemy Turn"          │  ← top-center
##   ├─────────────────────────────────────────────────────┤
##   │  Turn order list (top-right)                        │
##   │  ○ Player                                           │
##   │  ● Bandit                                           │
##   ├─────────────────────────────────────────────────────┤
##   │  AP: ■ ■ ■   MP: ▲ ▲ ▲        [End Turn]          │  ← bottom
##   └─────────────────────────────────────────────────────┘

# ── Colours ───────────────────────────────────────────────────────────────────
const C_PLAYER    := Color(0.35, 0.80, 1.00)
const C_ENEMY     := Color(1.00, 0.35, 0.35)
const C_CURRENT   := Color(1.00, 0.90, 0.20)
const C_AP        := Color(1.00, 0.72, 0.20)   # gold
const C_MP        := Color(0.35, 0.80, 0.45)   # green
const C_PIP_EMPTY := Color(0.25, 0.25, 0.25)
const C_BG        := Color(0.05, 0.05, 0.10, 0.82)
const C_BORDER    := Color(0.55, 0.55, 0.65)

# ── Pip layout ────────────────────────────────────────────────────────────────
const PIP_SIZE    := 18
const PIP_GAP     := 4
const MAX_PIPS    := CombatManager.BASE_AP   # same for AP and MP

# ── Nodes ─────────────────────────────────────────────────────────────────────
var _banner      : Label
var _order_panel : PanelContainer
var _order_list  : VBoxContainer
var _bottom_bar  : PanelContainer
var _ap_label    : Label
var _ap_pips     : HBoxContainer
var _mp_label    : Label
var _mp_pips     : HBoxContainer
var _end_btn     : Button

# ── Build UI ──────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_ui()
	_connect_signals()
	# Hide until refreshed for the first time
	_banner.text = ""

func _build_ui() -> void:
	var vp_size := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
						   ProjectSettings.get_setting("display/window/size/viewport_height"))

	# ── Turn banner (top-centre) ───────────────────────────────────────────
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 20)
	_banner.add_theme_color_override("font_color", C_CURRENT)
	_banner.add_theme_color_override("font_shadow_color", Color.BLACK)
	_banner.add_theme_constant_override("shadow_offset_x", 2)
	_banner.add_theme_constant_override("shadow_offset_y", 2)
	_banner.size = Vector2(vp_size.x, 36)
	_banner.position = Vector2(0, 8)
	add_child(_banner)

	# ── Turn-order panel (top-right) ───────────────────────────────────────
	_order_panel = PanelContainer.new()
	_order_panel.size = Vector2(160, 200)
	_order_panel.position = Vector2(vp_size.x - 168, 48)
	_style_panel(_order_panel)
	add_child(_order_panel)

	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	_order_panel.add_child(margin)

	_order_list = VBoxContainer.new()
	_order_list.add_theme_constant_override("separation", 3)
	margin.add_child(_order_list)

	# ── Bottom bar (AP / MP pips + End Turn button) ────────────────────────
	_bottom_bar = PanelContainer.new()
	_bottom_bar.size = Vector2(vp_size.x, 52)
	_bottom_bar.position = Vector2(0, vp_size.y - 56)
	_style_panel(_bottom_bar)
	add_child(_bottom_bar)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bottom_bar.add_child(hbox)

	# AP label + pips
	_ap_label = _make_label("AP:", C_AP, 14)
	hbox.add_child(_ap_label)
	_ap_pips = HBoxContainer.new()
	_ap_pips.add_theme_constant_override("separation", PIP_GAP)
	hbox.add_child(_ap_pips)
	for _i in MAX_PIPS:
		hbox.add_child(_make_pip())     # placeholder; refreshed each turn

	# Spacer
	var sp1 := Control.new(); sp1.custom_minimum_size = Vector2(20, 1)
	hbox.add_child(sp1)

	# MP label + pips
	_mp_label = _make_label("MP:", C_MP, 14)
	hbox.add_child(_mp_label)
	_mp_pips = HBoxContainer.new()
	_mp_pips.add_theme_constant_override("separation", PIP_GAP)
	hbox.add_child(_mp_pips)

	# Spacer
	var sp2 := Control.new(); sp2.custom_minimum_size = Vector2(24, 1)
	hbox.add_child(sp2)

	# End Turn button
	_end_btn = Button.new()
	_end_btn.text = "End Turn"
	_end_btn.custom_minimum_size = Vector2(90, 34)
	_end_btn.add_theme_font_size_override("font_size", 13)
	_end_btn.pressed.connect(_on_end_turn_pressed)
	hbox.add_child(_end_btn)

	# Populate pip containers
	_rebuild_pips(_ap_pips, MAX_PIPS, MAX_PIPS, C_AP)
	_rebuild_pips(_mp_pips, MAX_PIPS, MAX_PIPS, C_MP)

# ── Public refresh interface (called by CombatManager) ───────────────────────
func refresh(combatant_list: Array, ap: int, mp: int, player_turn: bool) -> void:
	# Banner
	if player_turn:
		_banner.text = "— YOUR TURN —"
		_banner.add_theme_color_override("font_color", C_CURRENT)
	else:
		_banner.text = "— Enemy Turn —"
		_banner.add_theme_color_override("font_color", C_ENEMY)

	# Turn-order list
	for child in _order_list.get_children():
		child.queue_free()
	for entry in combatant_list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var dot := Label.new()
		dot.text = "▶" if entry.is_current else " "
		dot.add_theme_color_override("font_color", C_CURRENT if entry.is_current else Color.TRANSPARENT)
		dot.add_theme_font_size_override("font_size", 11)
		dot.custom_minimum_size = Vector2(14, 0)
		row.add_child(dot)

		var lbl := Label.new()
		lbl.text = entry.label
		lbl.add_theme_font_size_override("font_size", 12)
		var col := C_CURRENT if entry.is_current else (C_PLAYER if entry.is_player else C_ENEMY)
		lbl.add_theme_color_override("font_color", col)
		row.add_child(lbl)
		_order_list.add_child(row)

	# AP / MP pips
	_rebuild_pips(_ap_pips, ap, MAX_PIPS, C_AP)
	_rebuild_pips(_mp_pips, mp, MAX_PIPS, C_MP)

	# End Turn only active on player's turn
	_end_btn.disabled = not player_turn

# ── Helpers ───────────────────────────────────────────────────────────────────
func _rebuild_pips(container: HBoxContainer, filled: int, total: int, color: Color) -> void:
	for child in container.get_children():
		child.queue_free()
	for i in total:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(PIP_SIZE, PIP_SIZE)
		pip.color = color if i < filled else C_PIP_EMPTY
		# Round the pip with a StyleBoxFlat via theme override (not possible for ColorRect,
		# so we nest it in a Panel) – keep it simple: just use ColorRect
		container.add_child(pip)

func _make_label(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l

func _make_pip() -> ColorRect:
	var p := ColorRect.new()
	p.custom_minimum_size = Vector2(PIP_SIZE, PIP_SIZE)
	p.color = C_PIP_EMPTY
	return p

func _style_panel(panel: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BG
	sb.border_color = C_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)

# ── Signals ───────────────────────────────────────────────────────────────────
func _connect_signals() -> void:
	if not CombatManager.resources_changed.is_connected(_on_resources_changed):
		CombatManager.resources_changed.connect(_on_resources_changed)
	if not CombatManager.combatant_added.is_connected(_on_combatant_added):
		CombatManager.combatant_added.connect(_on_combatant_added)

func _on_end_turn_pressed() -> void:
	CombatManager.end_current_turn()

func _on_resources_changed(ap: int, mp: int) -> void:
	_rebuild_pips(_ap_pips, ap, MAX_PIPS, C_AP)
	_rebuild_pips(_mp_pips, mp, MAX_PIPS, C_MP)

func _on_combatant_added(_entity: Node2D) -> void:
	# Trigger a full refresh when a new combatant joins mid-combat
	CombatManager._refresh_hud()
