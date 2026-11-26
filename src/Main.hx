package mods.session_tracker;

import mods.api.Context;
import mods.api.Mod;
import mods.api.Subscription;
import mods.api.dungeon.Floor;
import modding.ModSubscription;
import openfl.Lib;
import openfl.events.Event;
import openfl.ui.Keyboard;

import distributedObjects.DistributedDungionArea;
import distributedObjects.DistributedDungeonSummary;
import distributedObjects.PlayerGameObjectOwner;

/**
 * Session Tracker: the day's totals and this launch's, in one panel with two tabs.
 *
 * The day tab is kept in `context.data`, ends at midnight and keeps the earlier days as history; the session tab
 * starts at zero every time the game opens and is never written to the file. Both are fed by the same runs.
 *
 * Gold and XP come from the live game through `context.core`, so the mod is `extends`; the `api` alone has the
 * account's balance but no per-run gain. Every game object read through the core is guarded, so a DRH update that
 * renames one costs the counter, not the game.
 */
class Main extends Mod {
	static inline final TICK_MS = 350;

	var ctx:Context;
	var store:SessionStore;
	var data:SessionData;
	var tracker:Tracker;
	var panel:Panel;
	var snapshot:InventoryDiff;
	var subscriptions:Array<Subscription> = [];
	var coreSubscriptions:Array<ModSubscription> = [];
	var nextTick:Int = 0;
	var shown:Bool = true;
	/** Which tab the panel shows: the day's totals or this launch's. */
	var tab:Int = Panel.TAB_DAY;
	var logged:Map<String, Bool> = new Map();
	var loggingBroken:Bool = false;

	override public function init(context:Context):Void {
		ctx = context;
		store = new SessionStore(context.data, log);
		data = store.load();
		tracker = new Tracker(context, data);
		// Ctrl+Shift+T, as the Dungeon Minimap uses Ctrl+Shift+M. F6, F7 and F9 belong to Weapon Rater and
		// Weapon Lock, and a key binds once, so the reset keeps F3.
		context.keys.action("togglePanel", "Session panel", "Show or hide the session tracker panel.", Keyboard.T, true, true)
			.onPress(togglePanel);
		context.keys.action("resetSession", "Reset session", "Clear the totals of the tab on screen.", Keyboard.F3)
			.onPress(resetSession);
		subscriptions.push(context.onFloorEnter(onFloorEnter));
		subscriptions.push(context.onTownEnter(onTownEnter));
		subscribeCore();
		log("day " + data.day + ": " + data.runs + " runs, " + data.gold + " gold, " + data.xp + " xp");
	}

	override public function ready(context:Context):Void {
		try {
			panel = new Panel(context);
			panel.setOnTabSelected(selectTab);
			ctx.overlay.addChild(panel);
			panel.setShown(shown);
			ctx.overlay.addEventListener(Event.ENTER_FRAME, onFrame);
			refresh();
		} catch (error:Dynamic) {
			panel = null;
			log("panel unavailable, counters keep running: " + Std.string(error));
		}
	}

	override public function dispose():Void {
		try {
			if (tracker != null && tracker.active())
				finishRun(null, null);
			if (store != null && data != null)
				store.save(data);
		} catch (error:Dynamic) {
			log("dispose: " + Std.string(error));
		}
		try {
			ctx.overlay.removeEventListener(Event.ENTER_FRAME, onFrame);
		} catch (error:Dynamic) {
			log("dispose overlay: " + Std.string(error));
		}
		if (panel != null) {
			try {
				panel.destroy();
			} catch (error:Dynamic) {
				log("panel dispose: " + Std.string(error));
			}
			panel = null;
		}
		for (subscription in subscriptions)
			subscription.cancel();
		for (subscription in coreSubscriptions)
			subscription.cancel();
	}

	function onFrame(event:Event):Void {
		try {
			var now = Lib.getTimer();
			if (now < nextTick)
				return;
			nextTick = now + TICK_MS;
			tracker.sample();
			checkDay();
			refresh();
		} catch (error:Dynamic) {
			logOnce("frame: " + Std.string(error));
		}
	}

	/** A session that runs past midnight ends there: the finished day goes to the history. */
	function checkDay():Void {
		var today = SessionData.localDay();
		if (today == data.day)
			return;
		if (tracker.active())
			finishRun(null, null);
		data.startDay(today);
		snapshot = InventoryDiff.take(ctx, logOnce);
		store.save(data);
		log("new session day " + today);
	}

	function onFloorEnter(floor:Floor):Void {
		try {
			if (!tracker.active())
				snapshot = InventoryDiff.take(ctx, logOnce);
			tracker.addFloor();
			refresh();
		} catch (error:Dynamic) {
			log("floor enter: " + Std.string(error));
		}
	}

	function onTownEnter():Void {
		try {
			if (tracker.active())
				finishRun(null, null);
			tracker.syncBalanceFromAccount();
			collectItems();
			store.save(data);
			refresh();
		} catch (error:Dynamic) {
			log("town enter: " + Std.string(error));
		}
	}

	/** The end screen: the run's settled numbers, and the chests it reveals. */
	function onSummary(summary:Dynamic):Void {
		if (!tracker.active())
			return;
		var xp:Null<Int> = null;
		var gold:Null<Int> = null;
		try {
			var report = localReport(summary);
			if (report != null) {
				xp = intField(report, "xp_earned") + intField(report, "xp_bonus") + intField(report, "team_xp_bonus");
				gold = intField(report, "gold_earned");
			}
		} catch (error:Dynamic) {
			log("end screen report: " + Std.string(error));
		}
		finishRun(xp, gold);
	}

	function finishRun(xp:Null<Int>, gold:Null<Int>):Void {
		var record = tracker.finishRun(xp, gold);
		collectItems();
		store.save(data);
		refresh();
		if (record != null)
			log("run " + record.gold + " gold, " + record.xp + " xp, " + record.chests + " chests, " + record.floors + " floors");
	}

	/** New inventory compared to the snapshot taken at the first floor, added to the day. */
	function collectItems():Void {
		if (snapshot == null)
			return;
		var current = InventoryDiff.take(ctx, logOnce);
		var found = current.newSince(snapshot);
		snapshot = current;
		if (found.length == 0)
			return;
		tracker.addItems(found);
	}

	function togglePanel():Void {
		shown = !shown;
		if (panel == null)
			return;
		try {
			panel.setShown(shown);
			refresh();
		} catch (error:Dynamic) {
			logOnce("panel toggle: " + Std.string(error));
		}
	}

	/** The reset key clears the tab on screen: the day is saved empty, the session is only cleared. */
	function resetSession():Void {
		try {
			if (tab == Panel.TAB_SESSION)
				tracker.session.resetToday();
			else {
				data.resetToday();
				store.save(data);
			}
			tracker.restartRun();
			snapshot = InventoryDiff.take(ctx, logOnce);
			refresh();
			log(tab == Panel.TAB_SESSION ? "session cleared" : "day cleared for " + data.day);
		} catch (error:Dynamic) {
			log("reset: " + Std.string(error));
		}
	}

	/** The panel reported a tab click: that tab is the one on screen from now on. */
	function selectTab(index:Int):Void {
		tab = index == Panel.TAB_SESSION ? Panel.TAB_SESSION : Panel.TAB_DAY;
		refresh();
	}

	function refresh():Void {
		if (panel == null || !panel.visible)
			return;
		try {
			panel.refresh(data, tracker.session, tracker, tab);
		} catch (error:Dynamic) {
			logOnce("panel refresh: " + Std.string(error));
		}
	}

	function subscribeCore():Void {
		try {
			var core = ctx.core;
			coreSubscriptions.push(core.onFieldReceived(function(object, id, name) {
				try {
					if (name == null || !StringTools.endsWith(name, ".basicCurrency"))
						return;
					if (Std.downcast(object, PlayerGameObjectOwner) == null)
						return;
					tracker.observeBalance(readCurrency(object));
				} catch (error:Dynamic) {
					logOnce("balance field: " + Std.string(error));
				}
			}));
			coreSubscriptions.push(core.onObjectReady(function(object) {
				try {
					if (Std.isOfType(object, DistributedDungionArea))
						tracker.setArea(object);
					else if (Std.isOfType(object, DistributedDungeonSummary))
						onSummary(object);
				} catch (error:Dynamic) {
					logOnce("object ready: " + Std.string(error));
				}
			}));
			coreSubscriptions.push(core.onObjectGone(function(object) {
				try {
					tracker.forgetArea(object);
				} catch (error:Dynamic) {
					logOnce("object gone: " + Std.string(error));
				}
			}));
		} catch (error:Dynamic) {
			log("core events unavailable: " + Std.string(error));
		}
	}

	/** The local player's line of the end screen report, else the first one, as the game's own UI reads it. */
	function localReport(summary:Dynamic):Dynamic {
		var reports:Dynamic = Reflect.getProperty(summary, "report");
		if (!Std.isOfType(reports, Array))
			return null;
		var list:Array<Dynamic> = cast reports;
		if (list.length == 0)
			return null;
		var accountId = 0;
		try {
			var account = ctx.state.account;
			accountId = account == null ? 0 : account.id;
		} catch (error:Dynamic) {
			logOnce("account id: " + Std.string(error));
		}
		if (accountId != 0)
			for (report in list)
				if (report != null && intField(report, "id") == accountId)
					return report;
		return list[0];
	}

	function readCurrency(object:Dynamic):Null<Int> {
		try {
			var value:Dynamic = Reflect.getProperty(object, "basicCurrency");
			return Std.parseInt(Std.string(value));
		} catch (error:Dynamic) {
			return null;
		}
	}

	function intField(source:Dynamic, name:String):Int {
		try {
			var value:Dynamic = Reflect.field(source, name);
			var parsed = Std.parseInt(Std.string(value));
			return parsed == null ? 0 : parsed;
		} catch (error:Dynamic) {
			return 0;
		}
	}

	/** Logs once per distinct prefix: a handler that fails every frame would flood the game's log. */
	function logOnce(message:String):Void {
		var key = message.length > 48 ? message.substr(0, 48) : message;
		if (logged.exists(key))
			return;
		logged.set(key, true);
		log(message);
	}

	function log(message:String):Void {
		if (loggingBroken)
			return;
		try {
			ctx.log(message);
		} catch (error:Dynamic) {
			loggingBroken = true;
		}
	}
}
