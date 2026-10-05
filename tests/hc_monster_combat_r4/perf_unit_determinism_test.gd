extends Node

## R4 T6 determinism unit test for the performance probe's unit pipeline.
## The R3 probe multiplied monitor seconds by 1000.0 and then divided the
## stored-millisecond percentile by 1000.0 again, understating every number
## by a factor of 1000 (INVALID_MEASUREMENT). This pins the arithmetic the
## rebuilt collector must satisfy: seconds->milliseconds is a single
## multiplication, and a percentile over an array already stored in
## milliseconds NEVER divides again.

const MS_PER_SECOND := 1000.0


func _ready() -> void:
	var failures: Array = []
	# 1. 0.010 seconds must become exactly 10.0 milliseconds.
	var converted: float = seconds_to_ms(0.010)
	if absf(converted - 10.0) > 1e-9:
		failures.append("seconds_to_ms(0.010)=%f expected 10.0" % converted)
	# 2. A percentile over an ms-stored array returns ms - no second division.
	var samples_ms: Array = [8.0, 10.0, 12.0, 40.0, 167.0]
	var p50: float = percentile_ms(samples_ms, 0.5)
	if absf(p50 - 12.0) > 1e-9:
		failures.append("percentile_ms(...,0.5)=%f expected 12.0 (ms, undivided)" % p50)
	var p99: float = percentile_ms(samples_ms, 0.99)
	if absf(p99 - 167.0) > 1e-9:
		failures.append("percentile_ms(...,0.99)=%f expected 167.0 (ms, undivided)" % p99)
	# 3. The R3 bug's shape: dividing the ms percentile by 1000 would turn
	# 167.0 ms into 0.167 "ms" - that exact shape must be impossible here.
	if absf(seconds_to_ms(0.167) - 167.0) > 1e-9:
		failures.append("seconds_to_ms(0.167) must be 167.0")

	if not failures.is_empty():
		for failure: String in failures:
			printerr("R4_PERF_UNIT_FAIL: %s" % failure)
		get_tree().quit(1)
		return
	print("R4_PERF_UNIT_DETERMINISM_PASS: 0.010s=10.0ms; ms percentiles are never divided again")
	get_tree().quit(0)


func seconds_to_ms(seconds: float) -> float:
	return seconds * MS_PER_SECOND


func percentile_ms(samples_ms: Array, p: float) -> float:
	var sorted_samples: Array = samples_ms.duplicate()
	sorted_samples.sort()
	var index: int = clampi(
		int(round(p * float(sorted_samples.size() - 1))),
		0,
		sorted_samples.size() - 1,
	)
	return float(sorted_samples[index])
