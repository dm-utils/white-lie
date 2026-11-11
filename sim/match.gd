class_name Match
extends RefCounted
## One match = MatchSim + bots + presentation data (names). The view and the tests drive it the same way:
## step(human_command) once per tick. With human_animal "" every entrant is a bot (tests, balance runs).

const SLICE_ANIMALS := ["crab", "octopus", "gull"]

var sim: MatchSim
var human := -1
var bot_level := "easy"
var names: Array = []
var replay: Array = [] # human commands per tick (compact), for replays and server checks later
var humans: Array = [] # online: the player slots (the rest are bots)

var _bot_cfg: Dictionary


## mode "" = the normal match (last one dry wins); "ball" = Strandbal, 3 against 3 (phase 14).
static func create(seed_value: int, human_animal: String, players := 6, level := "easy", mode := "") -> Match:
	var m := Match.new()
	m.bot_level = level
	m._bot_cfg = BotBrain.level_config(level)
	# bots' animals and names come from their own stream, so they never shift the sim's RNG
	var pick := SimRng.new(seed_value ^ 0x5BD1E995)
	var entrants: Array = []
	if human_animal != "":
		entrants.append(human_animal)
		m.human = 0
	while entrants.size() < players:
		entrants.append(SLICE_ANIMALS[pick.range_i(SLICE_ANIMALS.size())])
	m.sim = MatchSim.new(seed_value, entrants, mode)
	var bots: Dictionary = Content.load_json("res://data/bots.json")
	for e in m.sim.ents:
		if e.id == m.human:
			m.names.append("")
			continue
		e.is_bot = 1
		e.damage_pct = int(m._bot_cfg.damage_pct)
		var adj: Array = bots.names.adjectives
		var noun: Array = bots.names.nouns
		m.names.append("%s %s %d" % [adj[pick.range_i(adj.size())], noun[pick.range_i(noun.size())], 1 + pick.range_i(98)])
	return m


func step(human_cmd: Dictionary = {}) -> void:
	var cmds: Array = []
	for e in sim.ents:
		if not e.alive:
			cmds.append({})
		elif e.id == human:
			cmds.append(human_cmd)
		else:
			cmds.append(BotBrain.think(sim, e, _bot_cfg))
	if human >= 0:
		replay.append([int(human_cmd.get("m", -1)), int(human_cmd.get("a", -1)), int(human_cmd.get("s", -1)), int(human_cmd.get("sd", -1))])
	sim.step(cmds)


## Online (phase 12): several players in slots 0..n-1 (their animals in order), bots fill the rest. Everyone in the
## match builds it the same way from the same seed, so bots act the same on every screen.
static func create_online(seed_value: int, animals: Array, players := 6, level := "normal", mode := "") -> Match:
	var m := create(seed_value, "", players, level, mode)
	# rebuild with the players first: create() with "" made all bots; redo with fixed entrants
	var pick := SimRng.new(seed_value ^ 0x5BD1E995)
	var entrants: Array = animals.duplicate()
	while entrants.size() < players:
		entrants.append(SLICE_ANIMALS[pick.range_i(SLICE_ANIMALS.size())])
	m.sim = MatchSim.new(seed_value, entrants, mode)
	m.humans = []
	for i in animals.size():
		m.humans.append(i)
	for e in m.sim.ents:
		if e.id >= animals.size():
			e.is_bot = 1
			e.damage_pct = int(m._bot_cfg.damage_pct)
	m.human = -1
	return m


## One tick for an online match: cmds = {slot: [m, a, s, sd]} for every player slot (missing = standing still).
func step_many(cmds: Dictionary) -> void:
	var list: Array = []
	for e in sim.ents:
		if not e.alive:
			list.append({})
		elif humans.has(e.id):
			list.append(cmd_from(cmds.get(e.id, EMPTY)))
		else:
			list.append(BotBrain.think(sim, e, _bot_cfg))
	sim.step(list)


## A player who left: from now on a bot plays that slot (every screen does it at the same tick).
func to_bot(slot: int) -> void:
	humans.erase(slot)
	sim.ents[slot].is_bot = 1


const EMPTY := [-1, -1, -1, -1]


static func cmd_from(c: Array) -> Dictionary:
	var d := {"m": int(c[0]), "a": int(c[1]), "s": int(c[2])}
	if int(c[3]) != -1:
		d["sd"] = int(c[3])
	return d


static func cmd_to(d: Dictionary) -> Array:
	return [int(d.get("m", -1)), int(d.get("a", -1)), int(d.get("s", -1)), int(d.get("sd", -1))]


func finished() -> bool:
	return sim.finished == 1


## The player's result, the same for the screen and for the replay check: {place, kos, animal, seed, survived_s, players}.
func human_result() -> Dictionary:
	var me: MatchSim.Ent = sim.ents[human]
	if sim.mode == "ball": # won / draw / lost count like 1st / 2nd / 4th place for pearls; no leaderboard (yet)
		var place: int = [1, 1, 2, 4][clampi(me.place, 0, 3)]
		return {
			"mode": "ball", "place": place, "outcome": ["won", "won", "draw", "lost"][clampi(me.place, 0, 3)],
			"kos": me.kos, "goals": me.goals, "team": me.team, "score": [sim.score_0, sim.score_1],
			"animal": str(sim.animals[me.id].id), "seed": sim.seed_value, "survived_s": sim.tick / 30, "players": sim.ents.size(),
		}
	return {
		"place": me.place if me.place > 0 else 1, "kos": me.kos, "animal": str(sim.animals[me.id].id), "seed": sim.seed_value,
		"survived_s": (me.died_tick if me.died_tick >= 0 else sim.tick) / 30, "players": sim.ents.size(),
	}


func human_out() -> bool:
	return human >= 0 and not sim.ents[human].alive and sim.mode == "" # Strandbal: you come back
