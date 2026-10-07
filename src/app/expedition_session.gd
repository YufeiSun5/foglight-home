extends RefCounted
## Sole writer of the optional, disposable encounter state. Never receives a save port.
## Story/wardrobe persistence remains owned by StateStore; this object cannot commit it.
const RunRules=preload("res://src/domain/tower_run_rules.gd")
const CombatRules=preload("res://src/domain/combat_rules.gd")
signal changed
signal effects(events:Array)
signal ended(reason:String)
var _run:Dictionary={}
var _combat:Dictionary={}
var _cards:Dictionary={}
var _stats:Dictionary={}
var _revision=0
var _generation=0
var _counter=0
var _busy=false
var _paused=false
var _ledger:Dictionary={}
var _ready=false

func start(catalog:Dictionary,run_id:String,epoch:int,seed_value:int,stages:int=3)->Dictionary:
	if _ready:return {"ok":false,"error":"already_started"}
	# Expose only modes backed by the current simulator; chain remains filtered
	# until real multi-target movement is present, never a silent melee fallback.
	var full=RunRules.validate_catalog(catalog)
	if not full.get("ok",false):return full
	var supported=catalog.duplicate(true)
	if supported.get("cards") is Array:
		supported.cards=supported.cards.filter(func(card):return not card.get("modifiers",{}).has("chain_charge"))
	var checked:Dictionary=RunRules.validate_catalog(supported)
	if not checked.get("ok",false):return checked
	_cards=checked.cards
	var fresh:Dictionary=RunRules.fresh(run_id,epoch,seed_value,_cards,stages)
	if not fresh.get("ok",false):return fresh
	_run=fresh.state
	var boot=_new_encounter()
	if not boot.get("ok",false):_run={};return boot
	_ready=true;changed.emit()
	return {"ok":true}

func view()->Dictionary:
	return {"ready":_ready,"run":_run.duplicate(true),"combat":_combat.duplicate(true),"stats":_stats.duplicate(true),"paused":_paused,"revision":_revision,"generation":_generation}

func projectile_sweeps()->Array:
	return CombatRules.projectile_sweeps(_combat) if _ready else []

func intent(action:String,payload:Dictionary={})->Dictionary:
	_counter+=1
	return {"id":str(_counter),"run_id":_run.get("run_id",""),"generation":_generation,"revision":_revision,"action":action,"payload":payload.duplicate(true)}

func submit(command:Dictionary)->Dictionary:
	if _busy:return {"ok":false,"error":"reentrant"}
	if not _ready or command.get("run_id")!=_run.get("run_id"):return {"ok":false,"error":"stale_run"}
	if not command.get("payload") is Dictionary or not command.get("id") is String:return {"ok":false,"error":"invalid_intent"}
	var fingerprint=JSON.stringify(command,"",true).sha256_text()
	if _ledger.has(command.id):
		return _ledger[command.id].result.duplicate(true) if _ledger[command.id].fingerprint==fingerprint else {"ok":false,"error":"id_conflict"}
	if command.get("generation")!=_generation:return {"ok":false,"error":"stale_generation"}
	if command.get("revision")!=_revision:return {"ok":false,"error":"stale_revision"}
	if _run.phase=="ended":return {"ok":false,"error":"run_ended"}
	_busy=true
	var result:Dictionary
	match command.get("action",""):
		"frame":result=_frame(command.payload)
		"choose":result=_choose(command.payload)
		"pause":
			_paused=true;result=_cancel_combat_inputs()
		"cancel_input":result=_cancel_combat_inputs()
		"resume":
			_paused=false;result={"ok":true}
		"exit":result=_cancel_combat_inputs(true)
		_:result={"ok":false,"error":"unknown_intent"}
	if result.get("ok",false):
		_revision+=1
		# Continuous frame intents are protected by revision/tick instead of a growing ledger.
		if command.action!="frame":
			_ledger[command.id]={"fingerprint":fingerprint,"result":result.duplicate(true)}
			while _ledger.size()>64:_ledger.erase(_ledger.keys()[0])
		changed.emit()
		if _run.phase=="ended":ended.emit(_run.end_reason)
	_busy=false
	return result.duplicate(true)

func card_previews()->Array:
	var previews:Array=[]
	if _run.get("phase")!="awaiting_choice":return previews
	for id in _run.offer:
		var preview:Dictionary=RunRules.preview(_run,id,_cards)
		if preview.get("ok",false):previews.append(preview)
	return previews

func _new_encounter()->Dictionary:
	var derived:Dictionary=RunRules.stats(_run,_cards)
	if not derived.get("ok",false):return derived
	var next:Dictionary=CombatRules.fresh(str(_run.run_id)+"@"+str(_run.stage),derived.stats)
	if not next.get("ok",false):return next
	_stats=derived.stats;_combat=next.state;_generation+=1;_paused=false
	return {"ok":true}

func _frame(payload:Dictionary)->Dictionary:
	if _run.phase!="stage_active":return {"ok":true}
	var frame=payload.duplicate(true)
	frame.run_id=_combat.run_id;frame.tick=int(_combat.tick)+1
	frame.paused=_paused or bool(frame.get("paused",false))
	var next:Dictionary=CombatRules.step(_combat,frame)
	if not next.get("ok",false):return next
	return _accept_combat_step(next)

func _accept_combat_step(next:Dictionary)->Dictionary:
	# Every step, including immediate input cancellation, settles terminal combat.
	_combat=next.state
	if not next.events.is_empty():effects.emit(next.events.duplicate(true))
	if _combat.player.hp<=0:return _run_command("fail",{},"application")
	if _combat.enemy.hp<=0:
		var cleared=_run_command("clear_stage",{"stage":_run.stage},"application")
		if cleared.get("ok",false):
			_generation+=1
			# Exhausted card pools may proceed directly without a choice screen.
			if _run.phase=="stage_active":return _new_encounter()
		return cleared
	if _combat.status=="ended":
		return _run_command("exit",{},"player") if _combat.end_reason=="exited" else _run_command("fail",{},"application")
	return {"ok":true}

func _choose(payload:Dictionary)->Dictionary:
	var result=_run_command("choose",{"stage":_run.stage,"card_id":payload.get("card_id","")},"player")
	if not result.get("ok",false):return result
	return _new_encounter()

func _run_command(action:String,payload:Dictionary,source:String)->Dictionary:
	_counter+=1
	var c=RunRules.make_command(_run,"run:"+str(_counter),action,payload,source)
	var reduced:Dictionary=RunRules.reduce(_run,c,_cards)
	if not reduced.get("ok",false):return reduced
	_run=reduced.state
	if not reduced.events.is_empty():effects.emit(reduced.events.duplicate(true))
	return {"ok":true}

func _cancel_combat_inputs(exiting:bool=false)->Dictionary:
	if _combat.is_empty() or _combat.status=="ended":return _run_command("exit",{},"player") if exiting else {"ok":true}
	var frame={"run_id":_combat.run_id,"tick":int(_combat.tick)+1,
		"player_position":_combat.player.position.duplicate(),"player_facing":_combat.player.facing.duplicate(),"enemy_position":_combat.enemy.position.duplicate(),
		"line_of_sight":false,"attack_pressed":false,"attack_released":false,"defend_pressed":false,"defend_released":false,"dodge_pressed":false,"focused":true,"paused":not exiting,"exit":exiting}
	var result=CombatRules.step(_combat,frame)
	if not result.get("ok",false):return result
	return _accept_combat_step(result)
