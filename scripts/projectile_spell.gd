extends Node2D
class_name ProjectileSpell

## Projectile spawned when a player casts a projectile spell.
## Moves in a straight line, hits the first NPC within range,
## then optionally applies AOE damage and destroys itself.

## The Spell resource that created this projectile
var spell: Spell = null
## The node that cast the spell (used to avoid self-damage)
var caster: Node2D = null
## Normalised travel direction
var direction: Vector2 = Vector2.ZERO
## Travel speed in pixels per second
var speed: float = 300.0
## Maximum travel distance in pixels before expiring
var max_range_px: float = 500.0
## Direct-hit damage
var damage: int = 0
## AOE blast radius in pixels (0 = point hit only)
var aoe_radius_px: float = 0.0

var _distance_traveled: float = 0.0
var _hit: bool = false


## Call this after adding the node to the scene tree.
## stop_distance_px: how far to travel before stopping (clamped to max range).
func setup(p_spell: Spell, p_caster: Node2D, p_direction: Vector2, stop_distance_px: float = -1.0) -> void:
	spell         = p_spell
	caster        = p_caster
	direction     = p_direction.normalized()
	speed         = max(p_spell.projectile_speed * 16.0, 80.0)  # tiles/s → px/s, minimum 80
	damage        = p_spell.get_damage()
	aoe_radius_px = p_spell.aoe_radius * 16.0
	max_range_px  = p_spell.spell_range * 16.0

	# Clamp the requested stop distance to the spell's actual maximum range
	if stop_distance_px > 0.0:
		max_range_px = minf(stop_distance_px, max_range_px)

	# Tint the particles to the spell's colour if one is set
	if spell.spell_color != Color.WHITE:
		var particles: GPUParticles2D = get_node_or_null("GPUParticles2D")
		if particles and particles.process_material is ParticleProcessMaterial:
			var mat: ParticleProcessMaterial = particles.process_material.duplicate()
			mat.color = spell.spell_color
			particles.process_material = mat


func _physics_process(delta: float) -> void:
	if _hit:
		return

	var step: Vector2 = direction * speed * delta
	global_position    += step
	_distance_traveled += step.length()

	if _distance_traveled >= max_range_px:
		queue_free()
		return

	_check_npc_collision()


## Check whether the projectile has flown into an NPC this frame.
func _check_npc_collision() -> void:
	var hit_radius: float = 10.0   # pixel radius treated as a direct hit
	for npc in get_tree().get_nodes_in_group("NPCs"):
		if not is_instance_valid(npc):
			continue
		if npc == caster:
			continue
		if npc.global_position.distance_to(global_position) <= hit_radius:
			_on_hit_npc(npc)
			return


## Handle a collision with the first NPC struck.
func _on_hit_npc(primary: Node2D) -> void:
	_hit = true

	if aoe_radius_px > 0.0:
		# Splash damage to every NPC inside the blast radius
		var already_hit: Array = []
		for npc in get_tree().get_nodes_in_group("NPCs"):
			if not is_instance_valid(npc) or npc == caster:
				continue
			if npc.global_position.distance_to(global_position) <= aoe_radius_px:
				if npc not in already_hit:
					already_hit.append(npc)
					if npc.has_method("take_damage"):
						npc.take_damage(damage, caster)
	else:
		# Single-target damage
		if primary.has_method("take_damage"):
			primary.take_damage(damage, caster)

	_explode()


## Stop the projectile and clean up after the particle effect plays out.
func _explode() -> void:
	set_physics_process(false)
	var particles: GPUParticles2D = get_node_or_null("GPUParticles2D")
	if particles:
		particles.emitting = false
	# Give the existing particles a moment to fade before freeing
	get_tree().create_timer(0.6).timeout.connect(queue_free)
