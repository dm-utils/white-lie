class_name Daily
extends RefCounted
## The daily challenge (FO §8): one island, the same bots and the same animal for everyone, from one seed per day
## (UTC). The seed comes from the leaderboards service; signed in, the game also gets a run token so the score can
## count (phase 7b). Offline or without the service, a local seed from the date: playable, but it does not count.
## The score formula lives in data/rules.json ("score"), so the server can use the same numbers later.

const BOTS := "normal"


## "2026-11-10" for a unix time (seconds), in UTC like the server.
static func day_of(unix: float) -> String:
	return Time.get_date_string_from_unix_time(int(unix))


static func seconds_left(unix: float) -> int:
	return 86400 - (int(unix) % 86400)


## "10:59:12" for the countdown on the button.
static func countdown(unix: float) -> String:
	var s := seconds_left(unix)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


## Fallback seed from the date alone (FNV-1a over the text, so it is the same on every platform and version).
static func local_seed(day: String) -> int:
	var h := 2166136261
	for b in ("white-lie-daily-" + day).to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h % 2000000000 + 1


## Everyone plays the same animal that day; it follows from the seed.
static func animal_for(seed_value: int) -> String:
	return Match.SLICE_ANIMALS[seed_value % Match.SLICE_ANIMALS.size()]


## Score = points for the place + per knockout + per second survived (rules.json "score").
static func score(result: Dictionary) -> int:
	var s: Dictionary = Content.load_json("res://data/rules.json").score
	var places: Array = s.place
	var place := clampi(int(result.get("place", 6)), 1, places.size())
	return int(places[place - 1]) + int(result.get("kos", 0)) * int(s.per_ko) + int(result.get("survived_s", 0)) * int(s.per_second)


## Keeps today's best in the profile: profile.daily = {day, best, plays}. Returns {profile, best, improved}.
static func record(profile: Dictionary, day: String, points: int) -> Dictionary:
	var p := profile.duplicate(true)
	var d: Dictionary = p.get("daily", {})
	if str(d.get("day", "")) != day:
		d = {"day": day, "best": 0, "plays": 0}
	var improved := points > int(d.best)
	d.best = maxi(int(d.best), points)
	d.plays = int(d.plays) + 1
	p["daily"] = d
	return {"profile": p, "best": int(d.best), "improved": improved}


## Asks the service for today's seed (and a run token when signed in). Always returns a plan:
## {seed, animal, bots, daily: {day, official, why}, run?: {token, board}}.
static func plan(now_unix: float) -> Dictionary:
	var day := day_of(now_unix)
	var seed_value := 0
	var token := ""
	if St33f.client != null:
		var r: Dictionary = await St33f.client.get_daily()
		if r.ok and str(r.data.get("day", "")) == day:
			seed_value = int(r.data.seed)
			if St33f.is_signed_in():
				var run: Dictionary = await St33f.client.start_run("day")
				if run.ok and int(run.data.get("seed", 0)) == seed_value:
					token = str(run.data.token)
	# why it does not count, if it does not: "offline" (no service) or "sign_in"
	var why := "" if token != "" else ("sign_in" if seed_value != 0 else "offline")
	if seed_value == 0:
		seed_value = local_seed(day)
	var plan := {"seed": seed_value, "animal": animal_for(seed_value), "bots": BOTS,
		"daily": {"day": day, "official": why == "", "why": why}}
	if token != "":
		plan["run"] = {"token": token, "board": "day"}
	return plan


## Start a normal match (Play / Again): on the week board when signed in, else a local random seed.
static func start_normal(tree: SceneTree) -> void:
	var animal := str(Platform.load_profile().get("selected_animal", "octopus"))
	var plan: Dictionary = await week_plan(animal)
	if plan.is_empty():
		Boot.args["seed"] = str(randi() % 2000000000 + 1)
	Boot.next_match = plan
	tree.change_scene_to_file(Boot.SCENES["match"])


## A normal match on the week board: signed in, the seed comes with a run token so the score can count.
## Not signed in or no service: a random seed and no run (the match is the same, it just does not count).
static func week_plan(animal: String) -> Dictionary:
	if St33f.client != null and St33f.is_signed_in():
		var run: Dictionary = await St33f.client.start_run("week")
		if run.ok and int(run.data.get("seed", 0)) > 0:
			return {"seed": int(run.data.seed), "animal": animal, "bots": "easy", "run": {"token": str(run.data.token), "board": "week"}}
	return {}
