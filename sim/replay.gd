class_name Replay
extends RefCounted
## A replay = the player's commands per tick, run-length encoded: {v: 1, ticks, rle: [[count, m, a, s, sd], ...]}.
## With the seed, the animal and the bot level it plays the whole match again: the sim and the bots are
## deterministic, so the same commands give the same result. The replay check (tools/verify_scores) uses this to
## accept or reject a score; the leaderboards service only checks the shape.

const VERSION := 1
const MAX_TICKS := 600 * 30 + 300 # rules.json limits.max_seconds, plus a margin


## From Match.replay ([[m, a, s, sd] per tick]) to the compact form.
static func encode(ticks: Array) -> Dictionary:
	var rle: Array = []
	for t in ticks:
		if not rle.is_empty() and rle[-1][1] == t[0] and rle[-1][2] == t[1] and rle[-1][3] == t[2] and rle[-1][4] == t[3]:
			rle[-1][0] += 1
		else:
			rle.append([1, int(t[0]), int(t[1]), int(t[2]), int(t[3])])
	return {"v": VERSION, "ticks": ticks.size(), "rle": rle}


## Back to one command per tick, or [] when the replay is malformed.
static func decode(replay: Dictionary) -> Array:
	if int(replay.get("v", 0)) != VERSION or not replay.get("rle") is Array:
		return []
	var out: Array = []
	for run in replay.rle:
		if not run is Array or run.size() != 5 or int(run[0]) < 1 or out.size() + int(run[0]) > MAX_TICKS:
			return []
		var cmd := {"m": int(run[1]), "a": int(run[2]), "s": int(run[3])}
		if int(run[4]) != -1:
			cmd["sd"] = int(run[4])
		for i in int(run[0]):
			out.append(cmd)
	return out if out.size() == int(replay.get("ticks", -1)) else []


## Plays the match again. Returns {ok, reason, result, hash}: ok when the replay is well-formed, the match ended
## (finished, or the player was washed away) exactly at the last tick, and the result matches the claim.
static func check(seed_value: int, animal: String, bots: String, replay: Dictionary, claimed: Dictionary) -> Dictionary:
	if not Match.SLICE_ANIMALS.has(animal) or not ["easy", "normal", "hard"].has(bots):
		return {"ok": false, "reason": "bad_setup", "result": {}, "hash": 0}
	var cmds := decode(replay)
	if cmds.is_empty():
		return {"ok": false, "reason": "bad_replay", "result": {}, "hash": 0}
	var m := Match.create(seed_value, animal, 6, bots)
	for i in cmds.size():
		if m.finished() or m.human_out():
			return {"ok": false, "reason": "replay_after_end", "result": m.human_result(), "hash": m.sim.state_hash()}
		m.step(cmds[i])
	if not (m.finished() or m.human_out()):
		return {"ok": false, "reason": "match_not_over", "result": m.human_result(), "hash": m.sim.state_hash()}
	var r := m.human_result()
	for k in ["place", "kos", "survived_s"]:
		if int(r[k]) != int(claimed.get(k, -1)):
			return {"ok": false, "reason": "result_mismatch", "result": r, "hash": m.sim.state_hash()}
	return {"ok": true, "reason": "", "result": r, "hash": m.sim.state_hash()}
