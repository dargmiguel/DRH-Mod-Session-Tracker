package mods.session_tracker;

/**
 * One dungeon run: what the run added, kept for the "last run" block of the panel.
 */
class RunRecord {
	public var gold:Int = 0;
	public var xp:Int = 0;
	public var orbs:Int = 0;
	public var chests:Int = 0;
	public var floors:Int = 0;
	public var ms:Int = 0;
	public var items:Array<ItemEntry> = [];

	public function new() {}
}
