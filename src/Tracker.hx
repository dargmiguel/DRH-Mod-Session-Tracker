package mods.session_tracker;

import mods.api.Context;
import openfl.Lib;

import distributedObjects.Area;
import distributedObjects.DistributedDungeonFloor;

/**
 * The arithmetic of one dungeon run and of the day.
 *
 * Gold is what the account balance gained inside the run: the server sends the balance to the live player object,
 * and the baseline is the balance at the first floor, so what was spent in town before the run is not counted. XP
 * is the end-of-dungeon report's total when the game sent one, and the XP doobers picked up otherwise. Chests are
 * the treasure doobers the party collected, as the dungeon area counts them.
 *
 * Every game object read here comes from beyond the `api`, so the readers are guarded: a DRH update that changes
 * one costs the counter, not the game. A balance of `NO_BALANCE` means "not known yet".
 */
class Tracker {
	static inline final NO_BALANCE = -1;

	var ctx:Context;
	public var data:SessionData;
	public var run:Null<RunRecord> = null;

	var startBalance:Int = NO_BALANCE;
	var liveBalance:Int = NO_BALANCE;
	var endBalance:Int = NO_BALANCE;
	var startedAt:Int = 0;
	var orbsBase:Int = 0;
	var chestsBase:Int = 0;
	var area:Null<Area> = null;

	public function new(ctx:Context, data:SessionData) {
		this.ctx = ctx;
		this.data = data;
	}

	public function active():Bool {
		return run != null;
	}

	/** First floor of a dungeon: the run starts here, with the balance it starts from. */
	public function beginRun():Void {
		if (run != null)
			return;
		run = new RunRecord();
		startedAt = Lib.getTimer();
		startBalance = liveBalance != NO_BALANCE ? liveBalance : accountBalance();
		endBalance = NO_BALANCE;
		var current = liveArea();
		orbsBase = current == null ? 0 : orbs(current);
		chestsBase = current == null ? 0 : chests(current);
	}

	public function addFloor():Void {
		beginRun();
		var record:Null<RunRecord> = run;
		if (record != null)
			record.floors++;
		sample();
	}

	/** Ends the run: `reportXp` and `reportGold` come from the end screen when the game sent them. */
	public function finishRun(reportXp:Null<Int>, reportGold:Null<Int>):Null<RunRecord> {
		var record:Null<RunRecord> = run;
		if (record == null)
			return null;
		sample();
		run = null;
		record.ms = Std.int(Math.max(0, Lib.getTimer() - startedAt));
		record.gold = goldOf(reportGold);
		record.xp = record.orbs;
		if (reportXp != null)
			record.xp = reportXp;
		data.gold += record.gold;
		data.xp += record.xp;
		data.chests += record.chests;
		data.floors += record.floors;
		data.ms += record.ms;
		data.runs += 1;
		data.last = record;
		startBalance = NO_BALANCE;
		endBalance = NO_BALANCE;
		return record;
	}

	/** Counters from zero from this moment on, for the key that clears the session mid-run. */
	public function restartRun():Void {
		var record:Null<RunRecord> = run;
		if (record == null)
			return;
		sample();
		startedAt = Lib.getTimer();
		startBalance = liveBalance != NO_BALANCE ? liveBalance : accountBalance();
		endBalance = NO_BALANCE;
		var current = liveArea();
		orbsBase = current == null ? 0 : orbs(current);
		chestsBase = current == null ? 0 : chests(current);
		record.gold = 0;
		record.xp = 0;
		record.orbs = 0;
		record.chests = 0;
		record.floors = 0;
		record.ms = 0;
		record.items = [];
	}

	/** The balance the server just sent to the live player object. */
	public function observeBalance(value:Null<Int>):Void {
		if (value == null)
			return;
		if (value < 0)
			return;
		liveBalance = value;
		if (run != null)
			endBalance = value;
	}

	public function setArea(object:Dynamic):Void {
		area = cast object;
	}

	public function forgetArea(object:Dynamic):Void {
		if (object == area)
			area = null;
	}

	/** Back in town the account's balance is the fresh one: it already holds the run's gold. */
	public function syncBalanceFromAccount():Void {
		var coins = accountBalance();
		if (coins != NO_BALANCE)
			liveBalance = coins;
	}

	/** Reads the live dungeon counters; cheap enough for a few times a second. */
	public function sample():Void {
		var record:Null<RunRecord> = run;
		if (record == null)
			return;
		var current = liveArea();
		if (current == null)
			return;
		area = current;
		var collected = Std.int(Math.max(0, orbs(current) - orbsBase));
		if (collected > record.orbs)
			record.orbs = collected;
		var opened = Std.int(Math.max(0, chests(current) - chestsBase));
		if (opened > record.chests)
			record.chests = opened;
	}

	public function addItems(items:Array<ItemEntry>):Void {
		if (items == null || items.length == 0)
			return;
		for (item in items) {
			data.addItem(item);
			var record = data.last;
			if (record != null)
				record.items.push(item);
		}
	}

	public function liveGold():Int {
		if (run == null || startBalance == NO_BALANCE)
			return 0;
		var end = endBalance != NO_BALANCE ? endBalance : startBalance;
		return Std.int(Math.max(0, end - startBalance));
	}

	public function liveXp():Int {
		var record:Null<RunRecord> = run;
		return record == null ? 0 : record.orbs;
	}

	public function liveChests():Int {
		var record:Null<RunRecord> = run;
		return record == null ? 0 : record.chests;
	}

	public function liveMs():Int {
		return run == null ? 0 : Std.int(Math.max(0, Lib.getTimer() - startedAt));
	}

	function goldOf(reportGold:Null<Int>):Int {
		var start = startBalance;
		var end = endBalance;
		if (end == NO_BALANCE)
			end = accountBalance();
		if (end == NO_BALANCE)
			end = liveBalance;
		if (start != NO_BALANCE && end != NO_BALANCE)
			return Std.int(Math.max(0, end - start));
		return reportGold == null ? 0 : reportGold;
	}

	/** The account's balance: refreshed by the game on a town reload and by every town transaction. */
	function accountBalance():Int {
		try {
			var account = ctx.state.account;
			if (account == null)
				return NO_BALANCE;
			return account.coins;
		} catch (error:Dynamic) {
			return NO_BALANCE;
		}
	}

	function liveArea():Null<Area> {
		var known = area;
		if (known != null && !isGone(known))
			return known;
		try {
			var apiFloor = ctx.state.floor;
			var facade:Dynamic = ctx.core.facade;
			var objects:Dynamic = facade == null ? null : facade.gameObjectManager;
			if (apiFloor == null || objects == null)
				return null;
			var floor = Std.downcast(objects.getReferenceFromId(apiFloor.id), DistributedDungeonFloor);
			if (floor == null || floor.isDestroyed)
				return null;
			var parent = floor.parentArea;
			return parent == null || parent.isDestroyed ? null : parent;
		} catch (error:Dynamic) {
			return null;
		}
	}

	function isGone(value:Dynamic):Bool {
		try {
			return Reflect.field(value, "isDestroyed") == true;
		} catch (error:Dynamic) {
			return true;
		}
	}

	function orbs(value:Area):Int {
		try {
			return value.expCollected;
		} catch (error:Dynamic) {
			return 0;
		}
	}

	function chests(value:Area):Int {
		try {
			var collected = value.treasureCollected;
			return collected == null ? 0 : collected.length;
		} catch (error:Dynamic) {
			return 0;
		}
	}
}
