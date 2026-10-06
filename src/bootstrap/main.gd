extends Node3D
const Harbor = preload("res://src/presentation/harbor.gd")
const View = preload("res://src/presentation/game_view.gd")
const Store = preload("res://src/app/state_store.gd")
const Save = preload("res://src/adapters/file_save.gd")
const Content = preload("res://src/adapters/content_loader.gd")
func _ready() -> void:
	var definitions = Content.load_chapter()
	if definitions.has("error"):
		var error = Label.new(); error.text = definitions.error; add_child(error); return
	var store = Store.new(definitions.nodes, Save.new())
	var harbor = Harbor.new()
	add_child(harbor)
	var view = View.new(); view.configure(store, harbor); add_child(view)
