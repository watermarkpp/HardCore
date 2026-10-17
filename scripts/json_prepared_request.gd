extends RefCounted

## Domain-owner handle for a private prepared request. This object is not sent
## to a worker. The shared service owns approvals and the worker owns only JSON.
var _service: RefCounted
var job: RefCounted
var path := ""
var _cancelled := false
var terminal_result := false

func configure(service: RefCounted, request: RefCounted) -> void:
	if service == null or not service.assert_owner():
		return
	_service = service
	job = request
	path = job.path

func result(wait := false) -> Dictionary:
	if _service == null or not _service.assert_owner():
		return {"finished": false, "success": false, "reason": "persistence_owner_mismatch"}
	return _service.finish(job, wait) if _cancelled or terminal_result else _service.finish_preparation(job, wait)

func cancel() -> bool:
	if _service == null or not _service.assert_owner():
		return false
	var accepted: bool = _service.cancel(job)
	_cancelled = accepted
	return accepted
