extends Node
## Sound effects (autoload "Sfx"). Sounds are made by tools/audio/sfx.py from data/sfx.json and turned into Ogg
## Vorbis by CI before the import (assets/audio/sfx/<name>.ogg; build output, not in git). Without the Oggs
## (a fresh checkout) the game is simply silent.
## Buses: Master (hard limiter, styleguide) <- Sfx (volume from settings) and Music (later).
## Every button in the game makes a tap; match code calls play() / play_at().

const FOLDER := "res://assets/audio/sfx/"
const VOICES := 10
const DEFAULT_VOLUME := 80 # percent

var _streams := {} # name -> AudioStream (or null when missing)
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	setup_buses()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_players.append(p)
	apply_volume()
	get_tree().node_added.connect(_on_node_added)


## Master gets a hard limiter; Sfx and Music feed into it. Safe to call twice.
static func setup_buses() -> void:
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(master, limiter)
	for bus in ["Sfx", "Music"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


func volume() -> int:
	return clampi(int(Platform.load_profile().get("settings", {}).get("sfx_volume", DEFAULT_VOLUME)), 0, 100)


func set_volume(percent: int) -> void:
	var p: Dictionary = Platform.load_profile()
	var s: Dictionary = p.get("settings", {})
	s["sfx_volume"] = clampi(percent, 0, 100)
	p["settings"] = s
	Platform.save_profile(p)
	apply_volume()


func apply_volume() -> void:
	var i := AudioServer.get_bus_index("Sfx")
	var v := volume()
	AudioServer.set_bus_mute(i, v == 0)
	AudioServer.set_bus_volume_db(i, linear_to_db(v / 100.0))


func has_sound(sound: String) -> bool:
	return _stream(sound) != null


## Plays a sound; a little pitch variation keeps repeats from sounding mechanical.
func play(sound: String, volume_db := 0.0, pitch_jitter := 0.06) -> void:
	var s := _stream(sound)
	if s == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## A sound in the world: quieter further from the listener (the camera), silent beyond ~1.5 screens.
func play_at(sound: String, pos: Vector2, listener: Vector2, screen := 1920.0) -> void:
	var db := attenuation_db(pos.distance_to(listener), screen)
	if db > -60.0:
		play(sound, db)


static func attenuation_db(distance: float, screen: float) -> float:
	var k := distance / screen
	return -80.0 if k > 1.5 else -18.0 * k * k


func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := FOLDER + sound + ".ogg"
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
	return _streams[sound]


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(func() -> void: play("tap", -4.0, 0.03))
