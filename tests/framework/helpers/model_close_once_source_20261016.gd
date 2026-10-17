extends "res://tests/framework/helpers/persistent_profile_process_source_20261015.gd"
## A successful business close is final even while the real Main Feature
## finalizer is still outstanding. False retained-owner closes may recur.
var _actual_business_close_completed := false
func close_session() -> bool:
	if _actual_business_close_completed:
		push_error("actual_Source_model_reentered_after_successful_business_close")
		return false
	var completed: bool = super.close_session()
	if completed: _actual_business_close_completed = true
	return completed
