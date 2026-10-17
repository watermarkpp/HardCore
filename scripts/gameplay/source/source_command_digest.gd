extends RefCounted
## Both ends hash the same original Variant bytes, without text conversion.
static func sha256(value: Variant) -> String:
	return bytes_sha256(var_to_bytes(value))
static func bytes_sha256(value: PackedByteArray) -> String:
	var context := HashingContext.new()
	var started: int = context.start(HashingContext.HASH_SHA256)
	if started!=OK:
		push_error("Original command SHA256 initialization failed")
		return ""
	var updated: int = context.update(value)
	if updated!=OK:
		push_error("Original command SHA256 byte capture failed")
		return ""
	return context.finish().hex_encode()
