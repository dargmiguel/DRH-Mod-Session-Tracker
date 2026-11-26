package mods.session_tracker;

/**
 * Reads and writes `session.json` in the mod's own data folder.
 *
 * A missing, empty or malformed file is not an error: the session starts fresh and the next save replaces it.
 */
class SessionStore {
	public static inline final FILE = "session.json";

	var path:String;
	var log:String->Void;

	public function new(dataDir:String, log:String->Void) {
		this.path = dataDir + "/" + FILE;
		this.log = log;
	}

	/**
	 * The stored totals, reconciled with the chosen period: a daily file from another day rolls to today, a
	 * session file keeps counting across days, and a file whose mode the player changed while the game was
	 * closed is moved to the chosen one.
	 */
	public function load(preferred:String):SessionData {
		var loaded:Null<SessionData> = null;
		try {
			if (sys.FileSystem.exists(path)) {
				var text = sys.io.File.getContent(path);
				if (text != null && StringTools.trim(text).length > 0)
					loaded = SessionData.decode(haxe.Json.parse(text));
			}
		} catch (error:Dynamic) {
			log("session file could not be read, starting a new session: " + Std.string(error));
			loaded = null;
		}
		var data = loaded == null ? new SessionData() : loaded;
		var today = SessionData.localDay();
		var changed = false;
		if (data.day == "") {
			data.day = today;
			changed = true;
		}
		if (data.isSession()) {
			if (preferred != SessionData.SESSION) {
				data.endSession(today);
				changed = true;
			}
		} else {
			if (data.day != today) {
				data.startDay(today);
				changed = true;
			}
			if (preferred == SessionData.SESSION) {
				data.beginSession(data.day);
				changed = true;
			}
		}
		if (changed)
			save(data);
		return data;
	}

	public function save(data:SessionData):Bool {
		try {
			sys.io.File.saveContent(path, haxe.Json.stringify(data.encode()));
			return true;
		} catch (error:Dynamic) {
			log("session file could not be written: " + Std.string(error));
			return false;
		}
	}
}
