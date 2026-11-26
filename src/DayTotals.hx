package mods.session_tracker;

/**
 * Totals of a past day, kept in the same file so the session is not the only record.
 */
class DayTotals {
	public var day:String = "";
	public var gold:Int = 0;
	public var xp:Int = 0;
	public var chests:Int = 0;
	public var runs:Int = 0;
	public var floors:Int = 0;
	public var ms:Int = 0;

	public function new() {}
}
