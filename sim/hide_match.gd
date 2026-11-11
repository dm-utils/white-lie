class_name HideMatch
extends RefCounted
## One session = HideSim + bots + names, with the interface Rollback expects, so Rollback, OnlineClient and
## the replay work unchanged: step(human_command), step_many({seat: cmd}), to_bot(seat), humans, cmd_from/cmd_to.

const CHARACTERS := ["skipper", "fisher", "kid"]
const EMPTY := [-1, -1, -1, -1]

var sim: HideSim
var human := -1
var bot_level := "normal"
var names: Array = []
var replay: Array = []
var humans: Array = []

var _bot_cfg: Dictionary


static func create(seed_value: int, human_character: String, players := 6, level := "normal") -> HideMatch:
	var m := HideMatch.new()
	m.bot_level = level
	m._bot_cfg = HideBrain.level_config(level)
	var pick := SimRng.new(seed_value ^ 0x5BD1E995)
	var entrants: Array = []
	if human_character != "":
		entrants.append(human_character)
		m.human = 0
	while entrants.size() < players:
		entrants.append(CHARACTERS[pick.range_i(CHARACTERS.size())])
	m.sim = HideSim.new(seed_value, entrants)
	m._name_bots(pick)
	return m


static func create_online(seed_value: int, chars: Array, players := 6, level := "normal") -> HideMatch:
	var m := HideMatch.new()
	m.bot_level = level
	m._bot_cfg = HideBrain.level_config(level)
	var pick := SimRng.new(seed_value ^ 0x5BD1E995)
	var entrants: Array = chars.duplicate()
	while entrants.size() < players:
		entrants.append(CHARACTERS[pick.range_i(CHARACTERS.size())])
	m.sim = HideSim.new(seed_value, entrants)
	for i in chars.size():
		m.humans.append(i)
	m._name_bots(pick)
	return m


func _name_bots(pick: SimRng) -> void:
	var bots: Dictionary = Content.load_json("res://data/bots.json")
	for e in sim.ents:
		if e.id == human or humans.has(e.id):
			names.append("")
			continue
		e.is_bot = 1
		var adj: Array = bots.names.adjectives
		var noun: Array = bots.names.nouns
		names.append("%s %s %d" % [adj[pick.range_i(adj.size())], noun[pick.range_i(noun.size())], 1 + pick.range_i(98)])


func step(human_cmd: Dictionary = {}) -> void:
	var cmds: Array = []
	for e in sim.ents:
		cmds.append(human_cmd if e.id == human else HideBrain.think(sim, e, _bot_cfg))
	if human >= 0:
		replay.append(cmd_to(human_cmd))
	sim.step(cmds)


func step_many(cmds: Dictionary) -> void:
	var list: Array = []
	for e in sim.ents:
		list.append(cmd_from(cmds.get(e.id, EMPTY)) if humans.has(e.id) else HideBrain.think(sim, e, _bot_cfg))
	sim.step(list)


func to_bot(slot: int) -> void:
	humans.erase(slot)
	sim.ents[slot].is_bot = 1


static func cmd_from(c: Array) -> Dictionary:
	var d := {"m": int(c[0]), "a": int(c[1]), "s": int(c[2])}
	if int(c[3]) != -1:
		d["sd"] = int(c[3])
	return d


static func cmd_to(d: Dictionary) -> Array:
	return [int(d.get("m", -1)), int(d.get("a", -1)), int(d.get("s", -1)), int(d.get("sd", -1))]


func finished() -> bool:
	return sim.finished == 1


## {mode, place, points, character, seed, players}.
func human_result() -> Dictionary:
	var row: Dictionary = sim.result()[human]
	return {"mode": "hide", "place": int(row.place), "points": int(row.points), "character": str(row.character),
		"seed": sim.seed_value, "players": sim.ents.size()}
