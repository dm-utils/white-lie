class_name Controls
extends RefCounted
## Which controls a player gets: the debug argument wins, then the player's choice in the settings, then the device.


static func choose(profile: Dictionary, args: Dictionary, touchscreen: bool) -> String:
	if ["keys", "mouse", "touch"].has(str(args.get("controls", ""))):
		return str(args.controls)
	var chosen := str(profile.get("settings", {}).get("controls", ""))
	if ["keys", "mouse", "touch"].has(chosen):
		return chosen
	return "touch" if touchscreen else "keys"
