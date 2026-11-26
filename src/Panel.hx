package mods.session_tracker;

import mods.api.Context;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;

/**
 * The overlay panel: the day's totals, the run in progress or the last one, and the last run's new items.
 *
 * Drag it by its header. Its default corner is the bottom left, where the Dungeon Minimap's panel (top right by
 * default) does not reach.
 */
class Panel extends Sprite {
	static inline final WIDTH = 246.;
	static inline final PAD = 10.;
	static inline final LINE = 15.;
	static inline final HEADER = 22.;
	static inline final ITEM_LINES = 3;

	static inline final COL_TEXT = 0xF2EEE4;
	static inline final COL_MUTED = 0x9C978C;
	static inline final COL_TITLE = 0xF6DFAE;
	static inline final COL_GOLD = 0xFFD45E;
	static inline final COL_XP = 0x58C9FF;
	static inline final COL_CHEST = 0xCBA8FF;
	static inline final COL_LEGENDARY = 0xFFB43C;
	static inline final COL_ITEM = 0xD9D4C8;
	static inline final COL_BORDER = 0x6E6045;
	static inline final COL_FILL = 0x141A20;

	static final MONTHS:Array<String> = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
	static final LABELS:Array<String> = ["Gold", "XP", "Chests", "Runs", "Floors", "Time", "Per run"];

	var ctx:Context;
	var background:Shape = new Shape();
	var title:TextField;
	var day:TextField;
	var labelFields:Array<TextField> = [];
	var valueFields:Array<TextField> = [];
	var sectionTitle:TextField;
	var sectionValue:TextField;
	var itemFields:Array<TextField> = [];

	var panelHeight:Float = 0.;
	var drawnHeight:Float = -1.;
	var signature:String = "";
	var dragged:Bool = false;
	var dragging:Bool = false;
	var grabX:Float = 0.;
	var grabY:Float = 0.;

	public function new(ctx:Context) {
		super();
		this.ctx = ctx;
		title = makeField(12, COL_TITLE, true, TextFormatAlign.LEFT);
		title.text = "SESSION TRACKER";
		addChild(title);
		day = makeField(11, COL_MUTED, false, TextFormatAlign.RIGHT);
		addChild(day);
		var colors:Array<Int> = [COL_GOLD, COL_XP, COL_CHEST, COL_TEXT, COL_TEXT, COL_TEXT, COL_MUTED];
		for (i in 0...LABELS.length) {
			var label = makeField(12, COL_MUTED, false, TextFormatAlign.LEFT);
			label.text = LABELS[i];
			labelFields.push(label);
			addChild(label);
			var value = makeField(12, colors[i], true, TextFormatAlign.RIGHT);
			valueFields.push(value);
			addChild(value);
		}
		sectionTitle = makeField(10, COL_MUTED, true, TextFormatAlign.LEFT);
		addChild(sectionTitle);
		sectionValue = makeField(11, COL_TEXT, false, TextFormatAlign.LEFT);
		addChild(sectionValue);
		for (index in 0...ITEM_LINES) {
			var field = makeField(11, COL_ITEM, false, TextFormatAlign.LEFT);
			itemFields.push(field);
			addChild(field);
		}
		addChildAt(background, 0);
		addEventListener(MouseEvent.MOUSE_DOWN, press);
		layout();
	}

	/** Pulls what it shows from the day's data and the live run. */
	public function refresh(data:SessionData, tracker:Tracker):Void {
		var next = buildSignature(data, tracker);
		if (next == signature && drawnHeight >= 0)
			return;
		signature = next;
		var values:Array<String> = [
			formatInt(data.gold),
			formatInt(data.xp),
			formatInt(data.chests),
			formatInt(data.runs),
			formatInt(data.floors),
			formatClock(data.ms),
			averages(data)
		];
		for (i in 0...valueFields.length)
			setText(valueFields[i], values[i]);
		setText(day, dayLabel(data));
		var items = showItems(data, tracker);
		if (tracker.active()) {
			setText(sectionTitle, "THIS RUN");
			setText(sectionValue, formatInt(tracker.liveGold()) + " gold  " + formatInt(tracker.liveXp()) + " xp  "
				+ formatInt(tracker.liveChests()) + " chests  " + formatClock(tracker.liveMs()));
		} else if (data.last != null) {
			var last = data.last;
			setText(sectionTitle, "LAST RUN");
			setText(sectionValue, formatInt(last.gold) + " gold  " + formatInt(last.xp) + " xp  " + formatInt(last.chests)
				+ " chests  " + formatClock(last.ms));
		} else {
			setText(sectionTitle, "LAST RUN");
			setText(sectionValue, "none yet");
		}
		for (i in 0...itemFields.length) {
			if (i < items.length) {
				var item = items[i];
				var text = item.name;
				if (item.rarity != "" && item.rarity != "COMMON")
					text += "  " + item.rarity.toLowerCase();
				if (item.count > 1)
					text += "  x" + item.count;
				setItemText(itemFields[i], text, item.legendary ? COL_LEGENDARY : COL_ITEM);
				itemFields[i].visible = true;
			} else {
				setText(itemFields[i], "");
				itemFields[i].visible = false;
			}
		}
		layout();
	}

	public function setShown(value:Bool):Void {
		visible = value;
		mouseEnabled = value;
		mouseChildren = value;
		if (value)
			place();
	}

	/** Keeps the panel inside the view; a panel the player dragged stays where it was put. */
	public function place():Void {
		if (ctx.viewHeight <= 0)
			return;
		if (!dragged) {
			x = 10;
			y = Math.max(8, ctx.viewHeight - panelHeight - 12);
		} else {
			x = Math.max(0, Math.min(Math.max(0, ctx.viewWidth - WIDTH), x));
			y = Math.max(0, Math.min(Math.max(0, ctx.viewHeight - panelHeight), y));
		}
	}

	public function destroy():Void {
		release(null);
		removeEventListener(MouseEvent.MOUSE_DOWN, press);
		if (parent != null)
			parent.removeChild(this);
	}

	function showItems(data:SessionData, tracker:Tracker):Array<ItemEntry> {
		var out:Array<ItemEntry> = [];
		if (tracker.active() || data.last == null)
			return out;
		var items = data.last.items;
		if (items == null)
			return out;
		for (item in items) {
			if (out.length == ITEM_LINES)
				break;
			out.push(item);
		}
		return out;
	}

	function layout():Void {
		var y = HEADER;
		title.x = PAD;
		title.y = 5;
		title.width = WIDTH - PAD * 2 - 78;
		day.x = WIDTH - PAD - 78;
		day.y = 6;
		day.width = 78;
		for (i in 0...labelFields.length) {
			labelFields[i].x = PAD;
			labelFields[i].y = y;
			valueFields[i].x = PAD;
			valueFields[i].y = y;
			valueFields[i].width = WIDTH - PAD * 2;
			y += LINE;
		}
		y += 5;
		sectionTitle.x = PAD;
		sectionTitle.y = y;
		y += 12;
		sectionValue.x = PAD;
		sectionValue.y = y;
		sectionValue.width = WIDTH - PAD * 2;
		y += LINE;
		for (i in 0...itemFields.length) {
			itemFields[i].x = PAD;
			itemFields[i].y = y;
			itemFields[i].width = WIDTH - PAD * 2;
			y += LINE;
		}
		panelHeight = y + 6;
		if (panelHeight != drawnHeight) {
			drawnHeight = panelHeight;
			draw();
		}
		place();
	}

	function draw():Void {
		background.graphics.clear();
		background.graphics.lineStyle(1, COL_BORDER, 0.9);
		background.graphics.beginFill(COL_FILL, 0.92);
		background.graphics.drawRoundRect(0, 0, WIDTH, panelHeight, 8, 8);
		background.graphics.endFill();
		background.graphics.lineStyle(1, COL_BORDER, 0.35);
		var lineY = HEADER + LINE * labelFields.length + 3;
		background.graphics.moveTo(PAD, lineY);
		background.graphics.lineTo(WIDTH - PAD, lineY);
	}

	function press(event:MouseEvent):Void {
		if (event == null || stage == null || event.localY > HEADER)
			return;
		dragging = true;
		grabX = event.stageX - x;
		grabY = event.stageY - y;
		stage.addEventListener(MouseEvent.MOUSE_MOVE, move);
		stage.addEventListener(MouseEvent.MOUSE_UP, release);
		stage.addEventListener(Event.DEACTIVATE, release);
		event.stopPropagation();
	}

	function move(event:MouseEvent):Void {
		if (!dragging)
			return;
		dragged = true;
		x = Math.max(0, Math.min(Math.max(0, ctx.viewWidth - WIDTH), event.stageX - grabX));
		y = Math.max(0, Math.min(Math.max(0, ctx.viewHeight - panelHeight), event.stageY - grabY));
	}

	function release(event:Event):Void {
		dragging = false;
		if (stage == null)
			return;
		stage.removeEventListener(MouseEvent.MOUSE_MOVE, move);
		stage.removeEventListener(MouseEvent.MOUSE_UP, release);
		stage.removeEventListener(Event.DEACTIVATE, release);
	}

	/** The format carries the alignment: `TextField` has no `textAlign` of its own. */
	function makeField(size:Int, color:Int, bold:Bool, align:TextFormatAlign):TextField {
		var format = new TextFormat("Arial", size, color, bold);
		format.align = align;
		var field = new TextField();
		field.autoSize = TextFieldAutoSize.NONE;
		field.selectable = false;
		field.mouseEnabled = false;
		field.multiline = false;
		field.wordWrap = false;
		field.defaultTextFormat = format;
		return field;
	}

	function setText(field:TextField, text:String):Void {
		if (field.text != text)
			field.text = text;
	}

	/** An item line, whose color depends on the rarity of the item it shows. */
	function setItemText(field:TextField, text:String, color:Int):Void {
		if (field.text != text)
			field.text = text;
		field.setTextFormat(new TextFormat("Arial", 11, color, false));
	}

	function buildSignature(data:SessionData, tracker:Tracker):String {
		var last = data.last;
		var items = "";
		if (last != null && last.items != null)
			for (item in last.items)
				items += item.name + item.count + ",";
		return [
			"" + data.day,
			"" + data.period + "/" + data.since,
			"" + data.gold,
			"" + data.xp,
			"" + data.chests,
			"" + data.runs,
			"" + data.floors,
			"" + data.ms,
			tracker.active() ? "run" : "town",
			"" + tracker.liveGold(),
			"" + tracker.liveXp(),
			"" + tracker.liveChests(),
			"" + tracker.liveMs(),
			last == null ? "" : "" + last.gold + "/" + last.xp + "/" + last.chests + "/" + last.ms,
			items
		].join("|");
	}

	/** Average gold and XP of a run of the day. */
	static function averages(data:SessionData):String {
		if (data.runs == 0)
			return "none yet";
		return formatInt(Std.int(data.gold / data.runs)) + " g  " + formatInt(Std.int(data.xp / data.runs)) + " xp";
	}

	/** The day of a daily total, or the day a session began: the two are told apart at a glance. */
	public static function dayLabel(data:SessionData):String {
		if (data.isSession()) {
			var started = monthDay(data.since == "" ? data.day : data.since);
			return started == "" ? "manual" : "since " + started;
		}
		return monthDay(data.day);
	}

	static function monthDay(day:String):String {
		var parts = day.split("-");
		if (parts.length < 3)
			return "";
		var month = Std.parseInt(parts[1]);
		var number = Std.parseInt(parts[2]);
		if (month == null || number == null)
			return "";
		if (month < 1 || month > 12)
			return "";
		return number + " " + MONTHS[month - 1];
	}

	public static function formatInt(value:Int):String {
		var negative = value < 0;
		var digits = Std.string(negative ? -value : value);
		var out = "";
		var group = 0;
		var i = digits.length - 1;
		while (i >= 0) {
			out = digits.charAt(i) + out;
			group++;
			if (group == 3 && i > 0) {
				out = "," + out;
				group = 0;
			}
			i--;
		}
		return (negative ? "-" : "") + out;
	}

	public static function formatClock(ms:Int):String {
		var seconds = Std.int(Math.max(0, ms) / 1000);
		var hours = Std.int(seconds / 3600);
		var minutes = Std.int((seconds % 3600) / 60);
		var rest = seconds % 60;
		return hours > 0 ? hours + ":" + pad2(minutes) + ":" + pad2(rest) : minutes + ":" + pad2(rest);
	}

	static function pad2(value:Int):String {
		return value < 10 ? "0" + value : "" + value;
	}
}
