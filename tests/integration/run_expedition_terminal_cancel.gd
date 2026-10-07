extends SceneTree
const Session=preload("res://src/app/expedition_session.gd")
var checks=0
var failures=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _init()->void:
	var cards=JSON.parse_string(FileAccess.get_file_as_string("res://data/tower_cards.json"))
	for action in ["cancel_input","pause"]:
		var app=Session.new()
		check(app.start(cards,"limit-"+action,1,0,3).ok,"start "+action)
		app._combat.tick=35999;app._combat.sim_tick=35999
		var seen={"ended":0,"reason":""}
		app.ended.connect(func(reason):seen.ended+=1;seen.reason=reason)
		var intent=app.intent(action);var result=app.submit(intent)
		check(result.ok,"cancel at technical time boundary succeeds")
		check(app.view().combat.status=="ended" and app.view().combat.end_reason=="time_limit","combat reached its time limit")
		check(app.view().run.phase=="ended" and app.view().run.end_reason=="failed","run settles at the same boundary")
		check(seen.ended==1 and seen.reason=="failed","one return-to-story notification")
		var before=app.view()
		check(app.submit(intent)==result and app.view()==before and seen.ended==1,"exact cancel replay cannot return twice")
		check(app.submit(app.intent("frame",{})).get("error")=="run_ended","later frame is rejected as a settled run")
		check(app.view()==before and seen.ended==1,"rejected frame is inert")
	print("EXPEDITION TERMINAL CANCEL: ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
