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
@onready var _attack_btn: Button = $BottomBar/HBoxContainer/AttackBtn
@onready var _target_select: OptionButton = $BottomBar/HBoxContainer/TargetSelect
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
	_attack_btn.disabled = true
	_target_select.disabled = true
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

	# Populate target selector with enemies and update attack button
	_populate_targets(player_turn, ap)

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
	# Re-evaluate attack button whenever AP changes
	var player_turn := CombatManager.is_player_turn()
	_populate_targets(player_turn, ap)

func _populate_targets(player_turn: bool, ap: int) -> void:
	## Fill the OptionButton with living enemies and update attack-button state.
	var prev_id: int = _target_select.get_selected_id() if _target_select.item_count > 0 else -1
	_target_select.clear()
	if not player_turn:
		_target_select.disabled = true
		_attack_btn.disabled = true
		return
	var enemies: Array = CombatManager.get_enemy_combatants()
	for i in enemies.size():
		var entry: Dictionary = enemies[i]
		var in_range: bool = entry.get("in_range", false)
		var suffix: String = " [near]" if in_range else ""
		_target_select.add_item(entry.label + suffix, i)
		_target_select.set_item_metadata(i, entry.entity)
	var can_select := enemies.size() > 0
	_target_select.disabled = not can_select
	# Restore previously selected index if still valid
	if prev_id >= 0 and prev_id < _target_select.item_count:
		_target_select.select(prev_id)
	_refresh_attack_btn(ap)

func _refresh_attack_btn(ap: int) -> void:
	## Enable Attack only when the player has AP and the selected target is in melee range.
	if _target_select.item_count == 0 or _target_select.disabled:
		_attack_btn.disabled = true
		return
	var target = _target_select.get_selected_metadata()
	var in_range: bool = CombatManager.is_target_in_melee_range(target)
	_attack_btn.disabled = not (ap >= CombatManager.AP_COST_ATTACK and in_range)

func _on_target_selected(_index: int) -> void:
	_refresh_attack_btn(CombatManager.get_current_ap())

func _on_attack_pressed() -> void:
	var target = _target_select.get_selected_metadata()
	if target == null or not is_instance_valid(target):
		return
	CombatManager.player_attack_enemy(target)

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
