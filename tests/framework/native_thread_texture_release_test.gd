extends Node

## Engine-only diagnostic: a worker allocates a texture, then the main thread
## retires its last owner with or without first executing queued initialization.
## RenderingServer.force_sync is used only by this diagnostic, never gameplay.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
@export var synchronize_before_release := false
var proof := Proof.new()
var failures: Array[String] = []
var worker: Thread

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _make_texture() -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)

func _run() -> void:
	check(DisplayServer.get_name() == "headless", "diagnostic explicitly uses the native headless renderer")
	for index in 8:
		worker = Thread.new()
		check(worker.start(_make_texture) == OK, "worker %d starts" % index)
		var texture: Texture2D = worker.wait_to_finish()
		worker = null
		check(texture != null and texture.get_size() == Vector2(8, 8), "worker %d returns a real usable texture" % index)
		var observer: WeakRef = weakref(texture)
		if synchronize_before_release:
			RenderingServer.force_sync()
		texture = null
		check(observer.get_ref() == null, "worker %d texture has no remaining application owner" % index)
		RenderingServer.force_sync()
	await get_tree().process_frame
	var scene_id := "native_thread_texture_release_sync_test" if synchronize_before_release else "native_thread_texture_release_test"
	var written := proof.write_receipt(scene_id, proof.records.size(), failures.size())
	print("NATIVE_THREAD_TEXTURE_RELEASE_", "PASS" if written and failures.is_empty() else "FAIL", " synchronized=", synchronize_before_release, " checks=", proof.records.size())
	get_tree().quit(0 if written and failures.is_empty() else 1)
