extends SceneTree
const Session=preload("res://src/app/expedition_session.gd")
var checks=0
var failures=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func sample(combat:Dictionary)->Dictionary:
	return {"player_position":combat.player.position.duplicate(),"player_facing":combat.player.facing.duplicate(),"enemy_position":combat.enemy.position.duplicate(),"line_of_sight":false,"attack_pressed":false,"attack_released":false,"defend_pressed":false,"defend_released":false,"dodge_pressed":false,"focused":true,"paused":false,"exit":false}
func _init()->void:
	var cards=JSON.parse_string(FileAccess.get_file_as_string("res://data/tower_cards.json"))
	for mode in ["pause","unfocused","wardrobe"]:
		var app=Session.new();check(app.start(cards,"clock-"+mode,1,7,3).ok,"start "+mode)
		# A valid near-limit fixture makes the former minutes-long native failure
		# reproducible without waiting or changing the production time budget.
		app._combat.tick=35998;app._combat.sim_tick=35998
		var cancellations=[];app.effects.connect(func(events):cancellations.append_array(events))
		check(app.submit(app.intent("pause" if mode=="pause" else "cancel_input")).ok,"cancel current input once "+mode)
		var waiting=app.view().combat;var events_before=cancellations.duplicate(true)
		var f=sample(waiting);f.paused=mode=="wardrobe";f.focused=mode!="unfocused"
		for i in 1000:app.submit(app.intent("frame",f))
		check(app.view().combat==waiting and app.view().run.phase=="stage_active","wall time never consumes paused sequence "+mode)
		check(cancellations==events_before,"idle observations emit no gameplay effects "+mode)
		var stale=app.intent("frame",f)
		check(app.submit(app.intent("resume")).ok,"resume "+mode)
		check(not app.submit(stale).ok,"old paused callback remains stale "+mode)
		check(app.submit(app.intent("frame",sample(waiting))).ok,"fresh active frame accepted "+mode)
		check(app.view().run.phase=="ended" and app.view().combat.end_reason=="time_limit","active simulation keeps finite limit "+mode)
	print("EXPEDITION PAUSE CLOCK: ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
