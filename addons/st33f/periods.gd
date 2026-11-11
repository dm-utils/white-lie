class_name St33fPeriods
extends RefCounted
## Stamps for daily and weekly boards, always in UTC: "2026-11-10" and ISO weeks like "2026-W46".


static func utc_day(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


static func iso_week(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	var weekday: int = d.weekday if d.weekday != 0 else 7 # Monday=1 .. Sunday=7
	# the ISO week belongs to the year of its Thursday
	var thursday := unix - (unix % 86400) + (4 - weekday) * 86400
	var t := Time.get_datetime_dict_from_unix_time(thursday)
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": t.year, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var week := 1 + int((thursday - jan1) / 86400) / 7
	return "%04d-W%02d" % [t.year, week]
