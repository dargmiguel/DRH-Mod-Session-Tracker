package mods.session_tracker;

import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;

/**
 * The calendar chart under the panel: one line of gold, XP or chests over the last week, the last month or
 * everything the file keeps.
 *
 * Its caption is its control: the metric's name cycles through the three, and each range picks its span. A day the
 * file has no entry for leaves a gap in the line instead of a drop to zero, and the highest day of the range
 * reaches the top of the plot.
 */
class Chart extends Sprite {
	public static inline final HEIGHT = 62.;
	public static inline final PLOT = 38.;
	public static inline final METRIC_GOLD = 0;
	public static inline final METRIC_XP = 1;
	public static inline final METRIC_CHESTS = 2;
	/** The caption's controls, for the panel's coordinate hit test. */
	public static inline final ZONE_METRIC = 0;
	public static inline final ZONE_NONE = -1;

	static final METRIC_NAMES:Array<String> = ["GOLD", "XP", "CHESTS"];
	static final SPANS:Array<Int> = [7, 30, 60];
	static final RANGE_NAMES:Array<String> = ["7D", "30D", "ALL"];
	static inline final CAPTION = 14.;
	static inline final METRIC_W = 52.;
	static inline final RANGE_X0 = 56.;
	static inline final RANGE_W = 32.;
	static inline final RANGE_STEP = 36.;
	static inline final DOT = 1.8;

	static inline final COL_LINE = 0xFFD45E;
	static inline final COL_GRID = 0x3E444D;
	static inline final COL_ACTIVE = 0xF6DFAE;
	static inline final COL_MUTED = 0x9C978C;

	var plotWidth:Float;
	var metric:Int = METRIC_GOLD;
	var range:Int = 0;
	var grid:Shape = new Shape();
	var line:Shape = new Shape();
	var metricField:TextField;
	var rangeFields:Array<TextField> = [];
	var empty:TextField;
	var history:Array<DayTotals> = [];
	var today:Null<SessionData>;

	public function new(plotWidth:Float) {
		super();
		this.plotWidth = plotWidth;
		metricField = field(METRIC_NAMES[metric], TextFormatAlign.LEFT);
		addChild(metricField);
		for (index in 0...RANGE_NAMES.length) {
			var pick = field(RANGE_NAMES[index], TextFormatAlign.LEFT);
			rangeFields.push(pick);
			addChild(pick);
		}
		empty = field("no days yet", TextFormatAlign.LEFT);
		empty.y = CAPTION + 10;
		empty.visible = false;
		addChild(empty);
		addChild(grid);
		addChild(line);
		layout();
	}

	/** The days and the day in progress to draw; called on every refresh, and kept for the next click. */
	public function setData(history:Array<DayTotals>, today:SessionData):Void {
		this.history = history == null ? [] : history;
		this.today = today;
		redraw();
	}

	/**
	 * One point per day of the range, oldest to newest, `null` for a day the file has no entry for; the values are
	 * scaled so the highest reaches just under the top of the plot.
	 */
	public static function points(history:Array<DayTotals>, today:SessionData, metric:Int, span:Int, width:Float,
			plot:Float):Array<Null<{x:Float, y:Float}>> {
		var out:Array<Null<{x:Float, y:Float}>> = [];
		var values:Map<String, Float> = new Map();
		if (history != null)
			for (totals in history) {
				if (totals == null || totals.day == "")
					continue;
				values.set(totals.day, metricValue(totals.gold, totals.xp, totals.chests, metric));
			}
		if (today != null && today.day != "")
			values.set(today.day, metricValue(today.gold, today.xp, today.chests, metric));
		var days = lastDays(span < 1 ? 1 : span);
		var max = 0.;
		for (day in days) {
			var value = values.get(day);
			if (value != null && value > max)
				max = value;
		}
		for (index in 0...days.length) {
			var value = values.get(days[index]);
			if (value == null || max <= 0) {
				out.push(null);
				continue;
			}
			var x = days.length > 1 ? index * width / (days.length - 1) : width / 2;
			out.push({x: x, y: plot - (value / max) * (plot - 2)});
		}
		return out;
	}

	/** The local days of a range, oldest first, in the form `SessionData.localDay` writes. */
	public static function lastDays(count:Int):Array<String> {
		var out:Array<String> = [];
		var now = Date.now();
		for (index in 0...count) {
			var day = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (count - 1 - index), 12, 0, 0);
			out.push(formatDay(day));
		}
		return out;
	}

	static function formatDay(day:Date):String {
		var month = day.getMonth() + 1;
		var number = day.getDate();
		return day.getFullYear() + "-" + (month < 10 ? "0" + month : "" + month) + "-"
			+ (number < 10 ? "0" + number : "" + number);
	}

	static function metricValue(gold:Int, xp:Int, chests:Int, metric:Int):Float {
		return metric == METRIC_XP ? xp : (metric == METRIC_CHESTS ? chests : gold);
	}

	/** The caption control at a point of the chart: `ZONE_METRIC`, a range index plus one, or `ZONE_NONE`. */
	public static function zoneAt(x:Float, y:Float):Int {
		if (y < 0 || y > CAPTION)
			return ZONE_NONE;
		if (x >= 0 && x <= METRIC_W)
			return ZONE_METRIC;
		for (index in 0...RANGE_NAMES.length) {
			var left = RANGE_X0 + RANGE_STEP * index;
			if (x >= left && x <= left + RANGE_W)
				return index + 1;
		}
		return ZONE_NONE;
	}

	/** A click of the panel, in the chart's own coordinates. */
	public function clickAt(x:Float, y:Float):Void {
		var zone = zoneAt(x, y);
		if (zone == ZONE_METRIC)
			nextMetric();
		else if (zone > 0)
			selectRange(zone - 1);
	}

	function nextMetric():Void {
		metric = (metric + 1) % METRIC_NAMES.length;
		var text = METRIC_NAMES[metric];
		if (metricField.text != text)
			metricField.text = text;
		applyFormats();
		redraw();
	}

	function selectRange(index:Int):Void {
		if (index < 0 || index >= SPANS.length)
			return;
		range = index;
		applyFormats();
		redraw();
	}

	function redraw():Void {
		var spans = points(history, today, metric, SPANS[range], plotWidth, PLOT);
		grid.graphics.clear();
		line.graphics.clear();
		var base = CAPTION + PLOT;
		grid.graphics.lineStyle(1, COL_GRID, 0.6);
		grid.graphics.moveTo(0, base);
		grid.graphics.lineTo(plotWidth, base);
		var plotted = false;
		for (point in spans)
			if (point != null)
				plotted = true;
		empty.visible = !plotted;
		if (!plotted)
			return;
		line.graphics.lineStyle(1.5, COL_LINE, 1);
		var started = false;
		for (point in spans) {
			if (point == null) {
				started = false;
				continue;
			}
			var y = CAPTION + point.y;
			if (started)
				line.graphics.lineTo(point.x, y);
			else
				line.graphics.moveTo(point.x, y);
			started = true;
		}
		// A dot per day: a single day is a dot, not an empty plot.
		line.graphics.beginFill(COL_LINE, 1);
		for (point in spans)
			if (point != null)
				line.graphics.drawCircle(point.x, CAPTION + point.y, DOT);
		line.graphics.endFill();
	}

	function layout():Void {
		metricField.x = 0;
		metricField.y = 0;
		metricField.width = METRIC_W;
		for (index in 0...rangeFields.length) {
			rangeFields[index].x = RANGE_X0 + RANGE_STEP * index;
			rangeFields[index].y = 0;
			rangeFields[index].width = RANGE_W;
		}
		applyFormats();
	}

	function applyFormats():Void {
		metricField.setTextFormat(new TextFormat("Arial", 10, COL_ACTIVE, true));
		for (index in 0...rangeFields.length)
			rangeFields[index].setTextFormat(new TextFormat("Arial", 10, index == range ? COL_ACTIVE : COL_MUTED, true));
	}

	function field(text:String, align:TextFormatAlign):TextField {
		var format = new TextFormat("Arial", 10, COL_MUTED, true);
		format.align = align;
		var field = new TextField();
		field.autoSize = TextFieldAutoSize.NONE;
		field.selectable = false;
		field.mouseEnabled = false;
		field.multiline = false;
		field.wordWrap = false;
		field.defaultTextFormat = format;
		field.text = text;
		return field;
	}
}
