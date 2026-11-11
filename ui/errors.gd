class_name UiErrors
extends RefCounted
## Turns the platform's stable error codes into player-facing text (via tr()).


static func text(err: Variant) -> String:
	if err == null:
		return TranslationServer.translate("ERROR_GENERIC")
	var e: St33fError = err
	match e.code:
		"invalid_email":
			return TranslationServer.translate("ERROR_INVALID_EMAIL")
		"invalid_code":
			return TranslationServer.translate("ERROR_INVALID_CODE")
		"rate_limited":
			return TranslationServer.translate("ERROR_RATE_LIMITED").format({"seconds": maxi(1, e.retry_after())})
		"mail_unavailable":
			return TranslationServer.translate("ERROR_MAIL_UNAVAILABLE")
		"network":
			return TranslationServer.translate("ERROR_NETWORK")
	return TranslationServer.translate("ERROR_GENERIC")
