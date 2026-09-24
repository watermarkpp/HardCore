extends Node

const OverlayScript := preload("res://scripts/ui_layout_calibration_overlay.gd")


func _ready() -> void:
	var target := Control.new()
	target.name = "ForgePanel"
	target.size = Vector2(800, 600)
	add_child(target)
	var artwork_panel := Control.new()
	artwork_panel.name = "ForgeArtworkPanel"
	artwork_panel.size = Vector2(400, 300)
	target.add_child(artwork_panel)
	var artworks: Array[TextureRect] = []
	for index in 3:
		var artwork := TextureRect.new()
		artwork.name = ["ForgeImageInitial", "ForgeImageSuccess", "ForgeImageFailure"][index]
		artwork.position = Vector2(20 + index * 7, 15 + index * 3)
		artwork.size = Vector2(200 + index * 4, 180 + index * 5)
		artwork_panel.add_child(artwork)
		artwork.visible = index == 0
		artworks.append(artwork)
	var overlay := OverlayScript.new()
	add_child(overlay)
	overlay.target = target
	var nodes := {"ForgeArtworkPanel/ForgeImageInitial": {"deleted": false}}
	assert(overlay._add_forge_artwork_entries(nodes))
	_assert_artwork_entries(nodes, artworks)
	artworks[0].hide()
	artworks[1].show()
	# Saving after a different preview must retain all three layers and the
	# independently calibrated geometry of the two inactive images.
	assert(overlay._add_forge_artwork_entries(nodes))
	_assert_artwork_entries(nodes, artworks)
	print("FORGE_CALIBRATOR_SAVE_PASS")
	get_tree().quit(0)


func _assert_artwork_entries(nodes: Dictionary, artworks: Array[TextureRect]) -> void:
	assert(nodes.size() == 3, "forge save omitted an inactive result image")
	for artwork: TextureRect in artworks:
		var path := "ForgeArtworkPanel/%s" % artwork.name
		var entry: Dictionary = nodes[path]
		assert(not bool(entry.deleted), "%s was mistaken for a deleted layer" % artwork.name)
		assert(bool(entry.visible) == artwork.visible)
		assert((entry.logicalRect as Array) == [artwork.position.x, artwork.position.y, artwork.size.x, artwork.size.y])
