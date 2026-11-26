package mods.session_tracker;

import mods.api.Context;

/**
 * What the account owned at one moment, reduced to comparable keys.
 *
 * The `api` has no per-item id for weapons (its `uid` arrived with api 1.6), so a weapon is compared by its kind,
 * power, required level and rarity: an identical second copy still shows as a count of two. Pets have a `uid`, and
 * consumables are compared by the stack's count.
 */
class InventoryDiff {
	var counts:Map<String, Int> = new Map();
	var entries:Map<String, ItemEntry> = new Map();

	public function new() {}

	/** The account's inventory now; an account that is not loaded yet gives an empty snapshot. */
	public static function take(ctx:Context, log:String->Void):InventoryDiff {
		var snapshot = new InventoryDiff();
		try {
			var account = ctx.state.account;
			var inventory = account == null ? null : account.inventory;
			if (inventory == null)
				return snapshot;
			for (weapon in inventory.weapons) {
				var key = "weapon:" + weapon.id + ":" + weapon.power + ":" + weapon.requiredLevel + ":" + weapon.rarity;
				snapshot.add(key, new ItemEntry("weapon", weapon.name, weapon.rarity, weapon.legendary, weapon.rarityColor, 1));
			}
			for (pet in inventory.pets) {
				var key = "pet:" + pet.uid;
				snapshot.add(key, new ItemEntry("pet", pet.name, "", false, 0, 1));
			}
			for (stack in inventory.consumables) {
				var key = "consumable:" + stack.id;
				snapshot.add(key, new ItemEntry("consumable", stack.name, "", false, 0, stack.count));
			}
		} catch (error:Dynamic) {
			log("inventory snapshot: " + Std.string(error));
		}
		return snapshot;
	}

	/** Items that this snapshot has and `before` did not, as one entry per kind. */
	public function newSince(before:InventoryDiff):Array<ItemEntry> {
		var out:Array<ItemEntry> = [];
		for (key in counts.keys()) {
			var now = counts.get(key);
			if (now == null)
				continue;
			var delta = now - before.countOf(key);
			if (delta <= 0)
				continue;
			var template = entries.get(key);
			if (template == null)
				continue;
			out.push(new ItemEntry(template.kind, template.name, template.rarity, template.legendary, template.color, delta));
		}
		return out;
	}

	function countOf(key:String):Int {
		var value = counts.get(key);
		return value == null ? 0 : value;
	}

	function add(key:String, entry:ItemEntry):Void {
		counts.set(key, countOf(key) + entry.count);
		if (!entries.exists(key))
			entries.set(key, entry);
	}
}
