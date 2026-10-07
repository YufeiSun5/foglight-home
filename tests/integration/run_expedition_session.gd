extends SceneTree
const Session=preload("res://src/app/expedition_session.gd")
var checks=0
var failures=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func frame(pressed=false,released=false,combat:Dictionary={})->Dictionary:
	var value= {"player_position":[0.0,0.0],"player_facing":[0.0,-1.0],"enemy_position":[0.0,-1.0],"line_of_sight":true,"attack_pressed":pressed,"attack_released":released,"defend_pressed":false,"defend_released":false,"dodge_pressed":false,"focused":true,"paused":false,"exit":false}
	if combat.has("additional_enemies"):
		value.additional_enemies=[]
		for enemy in combat.additional_enemies:value.additional_enemies.append({"id":enemy.id,"position":enemy.position.duplicate(),"present":enemy.present,"line_of_sight":true})
	return value

func _init()->void:
	var catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/tower_cards.json"))
	var app=Session.new()
	check(app.start(catalog,"session-test",1,123,3).ok,"session starts")
	check(app.view().run.phase=="stage_active","first encounter needs no card")
	var exposed=app.view();exposed.combat.player.hp=0
	check(app.view().combat.player.hp==100,"snapshot cannot mutate session")
	var stale=app.intent("frame",frame())
	check(app.submit(app.intent("frame",frame(false,false,app.view().combat))).ok,"first sampled frame accepted")
	check(not app.submit(stale).ok,"old frame intent rejected")
	for tick in 400:
		if app.view().run.phase!="stage_active":break
		var result=app.submit(app.intent("frame",frame(tick%42==0,tick%42==1,app.view().combat)))
		check(result.ok,"accepted fixed combat step"+str(tick))
	check(app.view().run.phase=="awaiting_choice","victory opens next-stage card choice")
	check(app.view().run.stage==2,"encounter progression is stage-based")
	var previews=app.card_previews()
	check(previews.size()==3,"three effective cards offered")
	for preview in previews:
		check(preview.after.charge.mode in ["melee_charge","ranged_charge","chain_charge"],"offered card has supported derived mode")
		check(not preview.changes.is_empty(),"card shows derived changes")
	var choice=app.intent("choose",{"card_id":previews[0].card.id})
	check(app.submit(choice).ok,"card choice begins next encounter")
	var after=app.view()
	check(app.submit(choice).ok and app.view()==after,"exact repeated card returns receipt without rerunning encounter")
	var old=choice.duplicate(true);old.id="unseen-old-command"
	check(not app.submit(old).ok and app.view()==after,"old generation callback rejected")
	check(app.view().combat.player.hp==100,"prototype safety pause restores health between stages")
	var pause=app.intent("pause")
	check(app.submit(pause).ok,"pause intent accepted")
	check(app.submit(app.intent("frame",frame(true,false,app.view().combat))).ok,"paused frame accepted safely")
	check(app.view().combat.status=="paused" and not app.view().combat.player.attack_held,"pause clears held action")
	check(app.submit(app.intent("resume")).ok,"resume accepted")
	var resumed=frame(false,false,app.view().combat)
	resumed.player_position=app.view().combat.player.position
	resumed.enemy_position=app.view().combat.enemy.position
	check(app.submit(app.intent("frame",resumed)).ok,"resume frame accepted without paused teleport")
	var exit_intent=app.intent("exit")
	check(app.submit(exit_intent).ok,"exit accepted")
	var ended=app.view()
	check(ended.run.phase=="ended" and ended.run.ranks.is_empty(),"exit disposes run upgrades")
	check(app.submit(exit_intent).ok and app.view()==ended,"exit replay has no side effects")
	var timeout_app=Session.new()
	check(timeout_app.start(catalog,"timeout-fixture",2,125,3).ok,"bounded encounter fixture starts")
	# White-box valid near-limit transient fixture; no save/state-store access.
	timeout_app._combat.tick=35999;timeout_app._combat.sim_tick=35999
	timeout_app._combat.enemy.position=[20.0,20.0]
	var last=frame();last.enemy_position=[20.0,20.0];last.line_of_sight=false
	check(timeout_app.submit(timeout_app.intent("frame",last)).ok,"encounter limit returns through application")
	check(timeout_app.view().run.phase=="ended" and timeout_app.view().run.end_reason=="failed","time limit cannot strand run in encounter_ended error")
	print("EXPEDITION SESSION: ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
