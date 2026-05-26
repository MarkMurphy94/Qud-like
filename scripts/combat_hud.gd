extends CanvasLayer
## CombatHUD – scene-based UI for turn-based combat.
##
## Edit the visual layout in scenes/combat_hud.tscn.
## This script handles only the dynamic / data-driven parts:
##   • Refreshing the turn-order list
##   • Rebuilding AP / MP pip rows
##   • Appending combat-log entries
##   • Applying the dark StyleBox to each PanelContainer at runtime
##
## Layout (screen space):
##   ┌─────────────────────────────────────────────────────┐
##   │  [TURN BANNER]  "YOUR TURN" / "Enemy Turn"          │  ← top-centre
##   ├─────────────────────────────────────────────────────┤
##   │  Turn order list (top-right)                        │
##   │  ▶ Player                                           │
##   │    Bandit                                           │
##   ├─────────────────────────────────────────────────────┤
##   │  AP: ■ ■ ■   MP: ▲ ▲ ▲        [End Turn]          │  ← bottom
##   └─────────────────────────────────────────────────────┘

# ── Colours ───────────────────────────────────────────────────────────────────
const C_PLAYER := Color(0.35, 0.80, 1.00)
const C_ENEMY := Color(1.00, 0.35, 0.35)
const C_CURRENT := Color(1.00, 0.90, 0.20)
const C_AP := Color(1.00, 0.72, 0.20) # gold
const C_MP := Color(0.35, 0.80, 0.45) # green
const C_PIP_EMPTY := Color(0.25, 0.25, 0.25)
const C_BG := Color(0.05, 0.05, 0.10, 0.82)
const C_BORDER := Color(0.55, 0.55, 0.65)

# ── Log colours by category ───────────────────────────────────────────────────
const C_LOG_INFO := Color(0.80, 0.80, 0.80)
const C_LOG_MOVE := Color(0.55, 0.85, 0.55)
const C_LOG_ATTACK := Color(1.00, 0.55, 0.30)
const C_LOG_SPELL := Color(0.60, 0.75, 1.00)
const C_LOG_DEATH := Color(1.00, 0.30, 0.30)
const MAX_LOG_LINES := 30

# ── Pip layout ────────────────────────────────────────────────────────────────
const PIP_SIZE := 18
const PIP_GAP := 4
const MAX_PIPS := CombatManager.BASE_AP # same for AP and MP

# ── Scene nodes (wired via @onready) ─────────────────────────────────────────
@onready var _banner: Label = $Banner
@onready var _order_panel: PanelContainer = $OrderPanel
@onready var _order_list: VBoxContainer = $OrderPanel/MarginContainer/OrderList
@onready var _bottom_bar: PanelContainer = $BottomBar
@onready var _ap_pips: HBoxContainer = $BottomBar/HBoxContainer/APPips
@onready var _mp_pips: HBoxContainer = $BottomBar/HBoxContainer/MPPips
@onready var _end_btn: Button = $BottomBar/HBoxContainer/EndTurnBtn
@onready var _log_panel: PanelContainer = $LogPanel
@onready var _log_list: VBoxContainer = $LogPanel/MarginContainer/VBoxContainer/LogScroll/LogList
@onready var _log_scroll: ScrollContainer = $LogPanel/MarginContainer/VBoxContainer/LogScroll

var _log_lines: Array = [] # stores Label nodes for capping MAX_LOG_LINES

# ── Ready ──────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Apply the shared dark background style to every panel
	_style_panel(_order_panel)
	_style_panel(_bottom_bar)
	_style_panel(_log_panel)
	# Fill pips to their maximum at startup
	_rebuild_pips(_ap_pips, MAX_PIPS, MAX_PIPS, C_AP)
	_rebuild_pips(_mp_pips, MAX_PIPS, MAX_PIPS, C_MP)
	# Start with an empty banner
	_banner.text = ""
	_connect_signals()

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
	if not CombatManager.combat_event_logged.is_connected(_on_combat_event_logged):
		CombatManager.combat_event_logged.connect(_on_combat_event_logged)
	if not CombatManager.combat_started.is_connected(_on_combat_started):
		CombatManager.combat_started.connect(_on_combat_started)

func _on_end_turn_pressed() -> void:
	CombatManager.end_current_turn()

func _on_resources_changed(ap: int, mp: int) -> void:
	_rebuild_pips(_ap_pips, ap, MAX_PIPS, C_AP)
	_rebuild_pips(_mp_pips, mp, MAX_PIPS, C_MP)

func _on_combatant_added(_entity: Node2D) -> void:
	# Trigger a full refresh when a new combatant joins mid-combat
	CombatManager._refresh_hud()

func _on_combat_started() -> void:
	# Clear the log at the start of each new combat
	for child in _log_list.get_children():
		child.queue_free()
	_log_lines.clear()

func _on_combat_event_logged(message: String, category: String) -> void:
	var lbl := Label.new()
	lbl.text = message
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var col: Color
	match category:
		"move": col = C_LOG_MOVE
		"attack": col = C_LOG_ATTACK
		"spell": col = C_LOG_SPELL
		"death": col = C_LOG_DEATH
		_: col = C_LOG_INFO
	lbl.add_theme_color_override("font_color", col)
	_log_list.add_child(lbl)
	_log_lines.append(lbl)
	# Trim oldest entries when over the cap
	while _log_lines.size() > MAX_LOG_LINES:
		var oldest: Label = _log_lines.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	# Scroll to the bottom on the next frame
	await get_tree().process_frame
	_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)
