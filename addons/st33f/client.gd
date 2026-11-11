class_name St33fClient
extends RefCounted
## Thin client for the St33f Engine API. Every call returns
##   {"ok": bool, "status": int, "data": Dictionary, "error": St33fError or null}
## and never throws. Calls are coroutines: `var r := await client.me()`.
## Each service (accounts, feedback, leaderboards, ...) has its own host; tests can point all services at one base URL.

const URLS := {
	"dev": {
		"accounts": "https://st33f-accounts-dev.st33fd3v.workers.dev",
		"feedback": "https://st33f-feedback-dev.st33fd3v.workers.dev",
		"leaderboards": "https://st33f-leaderboards-dev.st33fd3v.workers.dev",
		"pvp": "https://st33f-pvp-dev.st33fd3v.workers.dev",
	},
	"acc": {},
	"prod": {
		"accounts": "https://api.steefbeest.nl",
		"feedback": "https://feedback-api.steefbeest.nl",
		"leaderboards": "https://scores.steefbeest.nl",
		"pvp": "https://pvp.steefbeest.nl",
	},
}

var bases: Dictionary = {}
var game: String
var transport: St33fTransport
var token := ""
var user_agent := ""


## base: a URL used for every service, or a {service: url} dictionary.
func _init(p_game: String, base: Variant, p_transport: St33fTransport) -> void:
	game = p_game
	transport = p_transport
	if base is Dictionary:
		for k in base:
			bases[k] = str(base[k]).trim_suffix("/")
	else:
		bases["*"] = str(base).trim_suffix("/")
	# Browsers forbid setting User-Agent; native builds identify game, version and OS.
	if not OS.has_feature("web"):
		user_agent = "%s/%s (%s)" % [game.capitalize(), str(ProjectSettings.get_setting("application/config/version", "0")), OS.get_name()]


func base_for(service: String) -> String:
	return str(bases.get(service, bases.get("*", "")))


func call_api(method: int, path: String, body: Variant = null, auth := false, service := "accounts", extra_headers := PackedStringArray()) -> Dictionary:
	var headers := _headers(extra_headers)
	var text := ""
	if body != null:
		headers.append("Content-Type: application/json")
		# full precision: never round numbers the server or a sim will read
		text = JSON.stringify(body, "", false, true)
	if auth:
		if token == "":
			return _result(401, {"error": "signed_out", "message": "sign in first"})
		headers.append("Authorization: Bearer " + token)
	var base := base_for(service)
	if base == "":
		return _result(0, {"error": "network", "message": "no address for " + service})
	var r: Dictionary = await transport.request(method, base + path, headers, text)
	return _parse(r)


func call_raw(method: int, path: String, body: PackedByteArray, content_type: String, service: String, extra_headers := PackedStringArray()) -> Dictionary:
	var headers := _headers(extra_headers)
	headers.append("Content-Type: " + content_type)
	var r: Dictionary = await transport.request_raw(method, base_for(service) + path, headers, body)
	return _parse(r)


func _headers(extra: PackedStringArray) -> PackedStringArray:
	var headers := PackedStringArray()
	if user_agent != "":
		headers.append("User-Agent: " + user_agent)
	headers.append_array(extra)
	return headers


func _parse(r: Dictionary) -> Dictionary:
	var data: Variant = JSON.parse_string(str(r.get("body", ""))) if str(r.get("body", "")) != "" else {}
	return _result(int(r.get("status", 0)), data if typeof(data) == TYPE_DICTIONARY else {})


func _result(status: int, data: Dictionary) -> Dictionary:
	if status >= 200 and status < 300:
		return {"ok": true, "status": status, "data": data, "error": null}
	var code := "network" if status == 0 else str(data.get("error", "http_%d" % status))
	var err := St33fError.new(status, code, str(data.get("message", "")), data)
	return {"ok": false, "status": status, "data": data, "error": err}


# --- accounts ---

func health(service := "accounts") -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/health", null, false, service)


func auth_start(email: String) -> Dictionary:
	return await call_api(HTTPClient.METHOD_POST, "/auth/start", {"email": email, "game": game})


func auth_verify(email: String, challenges: PackedStringArray, code: String) -> Dictionary:
	return await call_api(HTTPClient.METHOD_POST, "/auth/verify", {"email": email, "challenges": Array(challenges), "code": code})


func logout(everywhere := false) -> Dictionary:
	return await call_api(HTTPClient.METHOD_POST, "/auth/logout", {"everywhere": everywhere}, true)


func me() -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/me", null, true)


func get_profile() -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/v1/games/%s/profile" % game, null, true)


func put_profile(profile: Dictionary, version: int) -> Dictionary:
	return await call_api(HTTPClient.METHOD_PUT, "/v1/games/%s/profile" % game, {"profile": profile, "version": version}, true)


## Remote settings (public, no sign-in): {version, values}
func get_settings() -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/v1/games/%s/settings" % game)


# --- feedback ---

## A player report. Signed in when a token exists (so the player can see it later), anonymous otherwise.
func submit_feedback(category: String, text: String, build: String, device: String, attachments: Array) -> Dictionary:
	var body := {"game": game, "category": category, "text": text, "build": build, "device": device, "attachments": attachments}
	return await call_api(HTTPClient.METHOD_POST, "/v1/feedback", body, token != "", "feedback")


func upload_attachment(report_id: String, kind: String, upload_token: String, bytes: PackedByteArray, content_type: String) -> Dictionary:
	return await call_raw(HTTPClient.METHOD_PUT, "/v1/feedback/%s/attachments/%s" % [report_id, kind], bytes, content_type, "feedback",
		PackedStringArray(["X-Upload-Token: " + upload_token]))


func my_feedback() -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/v1/feedback/mine", null, true, "feedback")


# --- leaderboards ---

## Today's challenge (public): {game, day, seed, endsAt}. The same seed for everyone until midnight UTC.
func get_daily() -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/v1/games/%s/daily" % game, null, false, "leaderboards")


## Start a run on a board ("day" or "week"), signed in: {token, board, seed, expiresAt}. The token goes back with
## the score, so the server knows it handed out this seed to this player.
func start_run(board: String) -> Dictionary:
	return await call_api(HTTPClient.METHOD_POST, "/v1/games/%s/runs" % game, {"board": board}, true, "leaderboards")


## Send a score for a run (signed in): {id, board, score, status: "pending"}. The server computes the score from the
## result with the game's rules and lists it as pending until the replay check has played the match again.
func submit_score(run_token: String, result: Dictionary, animal: String, bots: String, replay: Dictionary) -> Dictionary:
	var body := {"token": run_token, "result": result, "animal": animal, "bots": bots, "replay": replay}
	return await call_api(HTTPClient.METHOD_POST, "/v1/games/%s/scores" % game, body, true, "leaderboards")


## A board ("day", "week", "day:<date>", "week:<iso week>"): {board, players, entries: [{rank, player, score,
## pending}], me}. Signed in, "me" holds the player's own place even outside the top 50.
## friends_only (signed in): just the player and the players they added.
func get_board(board: String, friends_only := false) -> Dictionary:
	var q := "?filter=friends" if friends_only else ""
	return await call_api(HTTPClient.METHOD_GET, "/v1/games/%s/boards/%s%s" % [game, board, q], null, token != "" or friends_only, "leaderboards")


## Publish the player's public profile (signed in): {name: {a, n, num}, animal, badges: ["crab:2"], collection}.
## Names are indices into the game's word lists, never free text. Returns {ok, player} (the public id).
func put_public_profile(profile: Dictionary) -> Dictionary:
	return await call_api(HTTPClient.METHOD_PUT, "/v1/games/%s/me" % game, profile, true, "leaderboards")


## Someone's public profile by their public id (from a board row): {player, name, animal, badges, collection}.
func get_player(player_id: String) -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/v1/games/%s/players/%s" % [game, player_id], null, false, "leaderboards")


## The player's friend code and friends (signed in): {code, friends: [{player, name}], max}.
func get_friends() -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/v1/games/%s/friends" % game, null, true, "leaderboards")


## Add a friend by code (case, spaces and dashes don't matter): {player, name}. One way, like following.
func add_friend(code: String) -> Dictionary:
	return await call_api(HTTPClient.METHOD_POST, "/v1/games/%s/friends" % game, {"code": code}, true, "leaderboards")


func remove_friend(player_id: String) -> Dictionary:
	return await call_api(HTTPClient.METHOD_DELETE, "/v1/games/%s/friends/%s" % [game, player_id], null, true, "leaderboards")


# --- privacy: export and delete (each service answers for its own data) ---

## The public privacy statement (accounts serves it), in the given language ("nl" / "en").
func privacy_url(lang := "en") -> String:
	return "%s/privacy?lang=%s" % [base_for("accounts"), lang]


func export_account() -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/v1/me/export", null, true)


func delete_account() -> Dictionary:
	return await call_api(HTTPClient.METHOD_DELETE, "/v1/me", {"confirm": "delete"}, true)


func export_leaderboards() -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/v1/games/%s/mine" % game, null, true, "leaderboards")


func delete_leaderboards() -> Dictionary:
	return await call_api(HTTPClient.METHOD_DELETE, "/v1/games/%s/mine" % game, null, true, "leaderboards")


func export_feedback() -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/v1/feedback/mine/export", null, true, "feedback")


func delete_feedback() -> Dictionary:
	return await call_api(HTTPClient.METHOD_DELETE, "/v1/feedback/mine", null, true, "feedback")


# --- online matches (pvp relay) ---

## WebSocket address of the online lobby for this game (the relay groups players, then sends a room).
func pvp_lobby_url(animal: String, mode := "") -> String:
	var url := "%s/v1/games/%s/pvp?animal=%s" % [_ws(base_for("pvp")), game, animal.uri_encode()]
	return url + ("&mode=" + mode.uri_encode() if mode != "" else "")


## WebSocket address of a match room (seat and key come from the lobby's "match" message).
func pvp_room_url(room: String, slot: int, key: String) -> String:
	return "%s/v1/games/%s/pvp/room/%s?slot=%d&key=%s" % [_ws(base_for("pvp")), game, room, slot, key]


static func _ws(http_base: String) -> String:
	return http_base.replace("https://", "wss://").replace("http://", "ws://")
