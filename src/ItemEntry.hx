package mods.session_tracker;

/**
 * One item found since the dungeon started: what the panel shows for a run.
 */
class ItemEntry {
	public var kind:String;
	public var name:String;
	public var rarity:String;
	public var legendary:Bool;
	public var color:Int;
	public var count:Int;

	public function new(kind:String, name:String, rarity:String, legendary:Bool, color:Int, count:Int) {
		this.kind = kind;
		this.name = name;
		this.rarity = rarity;
		this.legendary = legendary;
		this.color = color;
		this.count = count;
	}
}
