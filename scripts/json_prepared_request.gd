extends RefCounted

## Main-thread handle for a private prepared request. This object is not sent
## to a worker. The shared service owns approvals and the worker owns only JSON.
var _service: RefCounted
var job: RefCounted
var path := ""
var _cancelled := false

func configure(service: RefCounted, request: RefCounted) -> void:
	_service = service
	job = request
	path = job.path

func result(wait := false) -> Dictionary:
	return _service.finish(job, wait) if _cancelled else _service.finish_preparation(job, wait)

func cancel() -> bool:
	var accepted: bool = _service.cancel(job)
	_cancelled = accepted
	return accepted
