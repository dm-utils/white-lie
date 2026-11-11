class_name Mastery
extends RefCounted
## Mastery per animal (FO §7): bronze, silver, gold from matches and wins with that animal (data/mastery.json).
## Badges and looks only, never power. The counters live in profile.mastery (already merged as max with the cloud).

const TIER_KEYS := ["", "MASTERY_BRONZE", "MASTERY_SILVER", "MASTERY_GOLD"]


## 0 = none, 1 = bronze, 2 = silver, 3 = gold.
static func tier(counts: Dictionary) -> int:
	var tiers: Array = Content.load_json("res://data/mastery.json").tiers
	var t := 0
	for i in tiers.size():
		if int(counts.get("matches", 0)) >= int(tiers[i].matches) and int(counts.get("wins", 0)) >= int(tiers[i].wins):
			t = i + 1
	return t


## ["crab:2", "gull:1"]: every animal with a tier, in a stable order (for the public profile).
static func badges(profile: Dictionary) -> Array:
	var out: Array = []
	var m: Dictionary = profile.get("mastery", {})
	var ids := m.keys()
	ids.sort()
	for id in ids:
		var t := tier(m[id])
		if t > 0:
			out.append("%s:%d" % [id, t])
	return out


static func tier_name(t: int) -> String:
	return TranslationServer.translate(TIER_KEYS[clampi(t, 0, 3)]) if t > 0 else ""
