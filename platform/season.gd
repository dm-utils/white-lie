class_name Season
extends RefCounted
## Seasons (FO §7): a second free path per season with season looks. Pearls earned during a season count on its path
## (profile.seasons[id].pearls) as well as on the Treasure Path. Dates are UTC; data/seasons.json holds them.


static func all() -> Array:
	return Content.load_json("res://data/seasons.json").get("seasons", [])


## The season running at this unix time, or {}.
static func active(unix: float) -> Dictionary:
	var day := Time.get_date_string_from_unix_time(int(unix))
	for s in all():
		if day >= str(s.start) and day <= str(s.end):
			return s
	return {}


static func days_left(season: Dictionary, unix: float) -> int:
	var end := Time.get_unix_time_from_datetime_string(str(season.end) + "T23:59:59")
	return maxi(0, int(ceil((end - unix) / 86400.0)))


## Adds earned pearls to the active season and grants what was reached: {season, before, after, unlocked, next,
## prev_at} or {} when no season runs.
static func add_pearls(profile: Dictionary, earned: int, unix: float) -> Dictionary:
	var s := active(unix)
	if s.is_empty():
		return {}
	var seasons: Dictionary = profile.get("seasons", {})
	var mine: Dictionary = seasons.get(str(s.id), {})
	var before := int(mine.get("pearls", 0))
	var after := before + earned
	mine["pearls"] = after
	seasons[str(s.id)] = mine
	profile["seasons"] = seasons
	var w := Rewards.walk(s.rewards, before, after)
	for rew in w.unlocked:
		Rewards.grant(profile, rew)
	return {"season": s, "before": before, "after": after, "unlocked": w.unlocked, "next": w.next, "prev_at": w.prev_at}
