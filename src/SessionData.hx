package mods.session_tracker;

/**
 * The totals of one session, plus the ones before it.
 *
 * `session.json` holds this object flat: `period` says whether the totals end with the calendar day or with the
 * next manual reset, `day` is the day they are for, and a daily file from another day is archived into `history`
 * and reset when it is loaded. Nothing here throws on a malformed file: every field falls back to its default.
 */
class SessionData {
	public static inline final FILE_VERSION = 2;
	public static inline final HISTORY_LIMIT = 60;
	public static inline final ITEM_LIMIT = 60;
	/** The totals are of one local calendar day: a new day archives them and starts empty. */
	public static inline final DAILY = "daily";
	/** The totals run from one reset to the next, across days. */
	public static inline final SESSION = "session";

	public var day:String = "";
	/** `DAILY` or `SESSION`: what ends the totals. */
	public var period:String = DAILY;
	/** In a session, the day it began; empty in daily mode. */
	public var since:String = "";
	public var gold:Int = 0;
	public var xp:Int = 0;
	public var chests:Int = 0;
	public var runs:Int = 0;
	public var floors:Int = 0;
	public var ms:Int = 0;
	public var items:Array<ItemEntry> = [];
	public var last:Null<RunRecord> = null;
	public var history:Array<DayTotals> = [];

	public function new() {}

	/** Clears the day's counters, keeping the day and the history. */
	public function resetToday():Void {
		gold = 0;
		xp = 0;
		chests = 0;
		runs = 0;
		floors = 0;
		ms = 0;
		items = [];
		last = null;
	}

	/** Archives a day that ended and starts `day` empty; a day with nothing in it is not archived. */
	public function startDay(day:String):Void {
		archiveCurrent();
		resetToday();
		this.day = day;
		since = "";
		period = DAILY;
	}

	/** Pushes the totals so far to the history, unless there is nothing in them. */
	public function archiveCurrent():Void {
		if (day == "" || !touched())
			return;
		var totals = new DayTotals();
		totals.day = day;
		totals.session = isSession();
		totals.gold = gold;
		totals.xp = xp;
		totals.chests = chests;
		totals.runs = runs;
		totals.floors = floors;
		totals.ms = ms;
		history.push(totals);
		if (history.length > HISTORY_LIMIT)
			history.splice(0, history.length - HISTORY_LIMIT);
	}

	/** Switches to a session where it is: the totals so far are its first part, and midnight no longer ends it. */
	public function beginSession(day:String):Void {
		if (isSession())
			return;
		period = SESSION;
		since = day == "" ? (this.day == "" ? localDay() : this.day) : day;
	}

	/** Back to daily: a session that outlived its first day is archived, and today starts empty. */
	public function endSession(today:String):Void {
		if (!isSession())
			return;
		if (day != today) {
			// Archived while it is still a session, so the history marks it as one.
			archiveCurrent();
			resetToday();
			day = today;
		}
		period = DAILY;
		since = "";
	}

	/** The reset key in a session: this one goes to the history and a new one starts today. */
	public function restartSession(today:String):Void {
		archiveCurrent();
		resetToday();
		day = today;
		since = today;
	}

	public function isSession():Bool {
		return period == SESSION;
	}

	function touched():Bool {
		return runs > 0 || gold > 0 || xp > 0 || chests > 0 || ms > 0;
	}

	public function addItem(entry:ItemEntry):Void {
		for (existing in items) {
			if (existing.kind == entry.kind && existing.name == entry.name && existing.rarity == entry.rarity) {
				existing.count += entry.count;
				return;
			}
		}
		items.push(entry);
		if (items.length > ITEM_LIMIT)
			items.splice(0, items.length - ITEM_LIMIT);
	}

	public static function localDay():String {
		var now = Date.now();
		return now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-" + pad(now.getDate());
	}

	static function pad(n:Int):String {
		return n < 10 ? "0" + n : "" + n;
	}

	public function encode():Dynamic {
		return {
			version: FILE_VERSION,
			day: day,
			period: period,
			since: since,
			gold: gold,
			xp: xp,
			chests: chests,
			runs: runs,
			floors: floors,
			ms: ms,
			items: encodeItems(items),
			last: encodeRun(last),
			history: encodeHistory(history)
		};
	}

	public static function decode(raw:Dynamic):SessionData {
		var data = new SessionData();
		if (raw == null)
			return data;
		data.day = str(raw, "day");
		data.period = str(raw, "period") == SESSION ? SESSION : DAILY;
		data.since = str(raw, "since");
		data.gold = count(raw, "gold");
		data.xp = count(raw, "xp");
		data.chests = count(raw, "chests");
		data.runs = count(raw, "runs");
		data.floors = count(raw, "floors");
		data.ms = count(raw, "ms");
		data.items = decodeItems(Reflect.field(raw, "items"));
		data.last = decodeRun(Reflect.field(raw, "last"));
		data.history = decodeHistory(Reflect.field(raw, "history"));
		return data;
	}

	public static function encodeItems(items:Array<ItemEntry>):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		if (items == null)
			return out;
		for (item in items) {
			out.push({
				kind: item.kind,
				name: item.name,
				rarity: item.rarity,
				legendary: item.legendary,
				color: item.color,
				count: item.count
			});
		}
		return out;
	}

	public static function decodeItems(raw:Dynamic):Array<ItemEntry> {
		var out:Array<ItemEntry> = [];
		if (!Std.isOfType(raw, Array))
			return out;
		var list:Array<Dynamic> = cast raw;
		for (entry in list) {
			if (entry == null)
				continue;
			var color = number(entry, "color");
			var amount = count(entry, "count");
			out.push(new ItemEntry(str(entry, "kind"), str(entry, "name"), str(entry, "rarity"), flag(entry, "legendary"),
				color <= 0 ? 0xE8E4DA : color, amount < 1 ? 1 : amount));
		}
		return out;
	}

	static function encodeRun(run:Null<RunRecord>):Dynamic {
		if (run == null)
			return null;
		return {
			gold: run.gold,
			xp: run.xp,
			orbs: run.orbs,
			chests: run.chests,
			floors: run.floors,
			ms: run.ms,
			items: encodeItems(run.items)
		};
	}

	static function decodeRun(raw:Dynamic):Null<RunRecord> {
		if (raw == null || Std.isOfType(raw, String))
			return null;
		var run = new RunRecord();
		run.gold = count(raw, "gold");
		run.xp = count(raw, "xp");
		run.orbs = count(raw, "orbs");
		run.chests = count(raw, "chests");
		run.floors = count(raw, "floors");
		run.ms = count(raw, "ms");
		run.items = decodeItems(Reflect.field(raw, "items"));
		return run;
	}

	static function encodeHistory(history:Array<DayTotals>):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		if (history == null)
			return out;
		for (totals in history) {
			out.push({
				day: totals.day,
				session: totals.session,
				gold: totals.gold,
				xp: totals.xp,
				chests: totals.chests,
				runs: totals.runs,
				floors: totals.floors,
				ms: totals.ms
			});
		}
		return out;
	}

	static function decodeHistory(raw:Dynamic):Array<DayTotals> {
		var out:Array<DayTotals> = [];
		if (!Std.isOfType(raw, Array))
			return out;
		var list:Array<Dynamic> = cast raw;
		for (entry in list) {
			if (entry == null)
				continue;
			var totals = new DayTotals();
			totals.day = str(entry, "day");
			totals.session = flag(entry, "session");
			totals.gold = count(entry, "gold");
			totals.xp = count(entry, "xp");
			totals.chests = count(entry, "chests");
			totals.runs = count(entry, "runs");
			totals.floors = count(entry, "floors");
			totals.ms = count(entry, "ms");
			out.push(totals);
		}
		return out;
	}

	static function str(source:Dynamic, name:String):String {
		var value:Dynamic = Reflect.field(source, name);
		return Std.isOfType(value, String) ? (value : String) : "";
	}

	static function flag(source:Dynamic, name:String):Bool {
		return Reflect.field(source, name) == true;
	}

	/** A non-negative whole number; `String` is read too, so a hand-edited file is not a parse error. */
	static function count(source:Dynamic, name:String):Int {
		return Std.int(Math.max(0, number(source, name)));
	}

	static function number(source:Dynamic, name:String):Int {
		var value:Dynamic = Reflect.field(source, name);
		if (value == null)
			return 0;
		var parsed = Std.parseInt(Std.string(value));
		return parsed == null ? 0 : parsed;
	}
}
