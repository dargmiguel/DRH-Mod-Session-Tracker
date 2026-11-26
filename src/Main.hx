package mods.session_tracker;

import mods.api.Context;
import mods.api.Mod;

class Main extends Mod {
	override public function init(context:Context):Void {
		context.log("loaded");
	}
}
