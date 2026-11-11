class_name ScoreCheck
extends RefCounted
## The replay check for the leaderboards (phase 7c), run by .github/workflows/verify-scores.yml.
## Input: the service's GET /pending answer. Output: {verdicts: [{id, ok, reason}]} for POST /verdicts.
## Per score: the board's rules (day: the animal of the day against "normal" bots; week: "easy" bots, any animal
## in the game), then Replay.check plays the whole match again and compares the result with the claim.

static func verdict(s: Dictionary) -> Dictionary:
	var id := str(s.get("id", ""))
	var board := str(s.get("board", ""))
	var seed_value := int(s.get("seed", 0))
	var animal := str(s.get("animal", ""))
	var bots := str(s.get("bots", ""))
	if board.begins_with("day:"):
		if animal != Daily.animal_for(seed_value):
			return {"id": id, "ok": false, "reason": "not_the_animal_of_the_day"}
		if bots != Daily.BOTS:
			return {"id": id, "ok": false, "reason": "wrong_bots_for_daily"}
	elif board.begins_with("week:"):
		if bots != "easy":
			return {"id": id, "ok": false, "reason": "wrong_bots_for_week"}
	else:
		return {"id": id, "ok": false, "reason": "unknown_board"}
	var r := Replay.check(seed_value, animal, bots, s.get("replay", {}), s.get("claimed", {}))
	return {"id": id, "ok": bool(r.ok), "reason": str(r.reason)}


## All verdicts for one batch from the service.
static func run(pending: Dictionary) -> Dictionary:
	var out: Array = []
	for s in pending.get("scores", []):
		if s is Dictionary:
			out.append(verdict(s))
	return {"verdicts": out}
