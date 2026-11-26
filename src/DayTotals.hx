package mods.session_tracker;

/**
 * Totals of a past day or session, kept in the same file so the current one is not the only record.
 *
 * `day` is the day it began; `session` says it was a manual session rather than a calendar day.
 */
class DayTotals {
	public var day:String = "";
	public var session:Bool = false;
	public var gold:Int = 0;
	public var xp:Int = 0;
	public var chests:Int = 0;
	public var runs:Int = 0;
	public var floors:Int = 0;
	public var ms:Int = 0;

	public function new() {}
}
