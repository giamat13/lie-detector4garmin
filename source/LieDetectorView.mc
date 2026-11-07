import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class LieDetectorView extends WatchUi.View {

    // Tunables
    private const RR_MIN_MS = 300;
    private const RR_MAX_MS = 2000;
    private const WINDOW = 12;          // RR intervals per RMSSD window
    private const MIN_RR_FOR_RMSSD = 6; // need at least this many to compute
    private const CALIB_SECONDS = 60;
    private const MIN_BASELINE_SAMPLES = 5;
    private const GRAPH_POINTS = 60;
    private const THRESHOLD = 2.5;
    private const Z_RANGE = 4.0;        // graph shows -Z_RANGE..+Z_RANGE
    private const BANNER_MS = 5000;

    private const ST_WAITING = 0;
    private const ST_CALIBRATING = 1;
    private const ST_RUNNING = 2;

    private var _state as Number = 0;
    private var _timer as Timer.Timer?;
    private var _listening as Boolean = false;

    private var _rr as Array<Number> = [] as Array<Number>;

    // Baseline (Welford running mean / variance of RMSSD)
    private var _calibElapsed as Number = 0;
    private var _n as Number = 0;
    private var _mean as Float = 0.0;
    private var _m2 as Float = 0.0;
    private var _std as Float = 1.0;

    // Graph data
    private var _zs as Array<Float> = [] as Array<Float>;
    private var _spikes as Array<Boolean> = [] as Array<Boolean>;
    private var _lastSpikeMs as Number = -1;
    private var _blink as Boolean = false;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        try {
            Sensor.registerSensorDataListener(method(:onSensorData), {
                :period => 1,
                :heartBeatIntervals => { :enabled => true }
            });
            _listening = true;
        } catch (e) {
            _listening = false;
        }
        var t = new Timer.Timer();
        t.start(method(:onTick), 1000, true);
        _timer = t;
    }

    function onHide() as Void {
        if (_listening) {
            Sensor.unregisterSensorDataListener();
            _listening = false;
        }
        var t = _timer;
        if (t != null) {
            t.stop();
            _timer = null;
        }
    }

    // Sensor callback: collect valid beat-to-beat intervals.
    function onSensorData(sd as Sensor.SensorData) as Void {
        var hr = sd.heartRateData;
        if (hr == null) {
            return;
        }
        var list = hr.heartBeatIntervals;
        for (var i = 0; i < list.size(); i++) {
            var v = list[i];
            if (v >= RR_MIN_MS && v <= RR_MAX_MS) {
                _rr.add(v);
                if (_rr.size() > WINDOW) {
                    _rr = _rr.slice(1, null);
                }
                if (_state == ST_WAITING) {
                    _state = ST_CALIBRATING;
                    _calibElapsed = 0;
                }
            }
        }
    }

    // Once per second.
    function onTick() as Void {
        _blink = !_blink;

        if (_state == ST_CALIBRATING) {
            _calibElapsed++;
            var r = rmssd();
            if (r != null && _rr.size() >= WINDOW) {
                // Welford update
                _n++;
                var d = r - _mean;
                _mean += d / _n;
                _m2 += d * (r - _mean);
            }
            if (_calibElapsed >= CALIB_SECONDS && _n >= MIN_BASELINE_SAMPLES) {
                var sd = Math.sqrt(_m2 / (_n - 1)).toFloat();
                // Floor avoids absurd z-scores from a very steady baseline.
                var floorStd = _mean * 0.1;
                if (floorStd < 1.0) {
                    floorStd = 1.0;
                }
                _std = (sd > floorStd) ? sd : floorStd;
                _state = ST_RUNNING;
            }
        } else if (_state == ST_RUNNING) {
            var r = rmssd();
            if (r != null) {
                var z = (r - _mean) / _std;
                var spike = (z > THRESHOLD || z < -THRESHOLD);
                _zs.add(z);
                _spikes.add(spike);
                if (_zs.size() > GRAPH_POINTS) {
                    _zs = _zs.slice(1, null);
                    _spikes = _spikes.slice(1, null);
                }
                if (spike) {
                    _lastSpikeMs = System.getTimer();
                }
            }
        }
        WatchUi.requestUpdate();
    }

    private function rmssd() as Float? {
        var n = _rr.size();
        if (n < MIN_RR_FOR_RMSSD) {
            return null;
        }
        var sum = 0.0;
        for (var i = 1; i < n; i++) {
            var d = (_rr[i] - _rr[i - 1]).toFloat();
            sum += d * d;
        }
        return Math.sqrt(sum / (n - 1)).toFloat();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.11, Graphics.FONT_SMALL,
            WatchUi.loadResource(Rez.Strings.Title) as String, c);

        if (_state == ST_WAITING) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.5, Graphics.FONT_SMALL,
                WatchUi.loadResource(Rez.Strings.Waiting) as String, c);
        } else if (_state == ST_CALIBRATING) {
            var pct = _calibElapsed * 100 / CALIB_SECONDS;
            if (pct > 100) {
                pct = 100;
            }
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.30, Graphics.FONT_SMALL,
                WatchUi.loadResource(Rez.Strings.Calibrating) as String, c);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.50, Graphics.FONT_NUMBER_HOT,
                pct.format("%d") + "%", c);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.72, Graphics.FONT_SMALL,
                WatchUi.loadResource(Rez.Strings.TakeSeat) as String, c);
        } else {
            drawGraph(dc, w, h);
            drawBanner(dc, w, h, c);
        }
    }

    private function drawGraph(dc as Dc, w as Number, h as Number) as Void {
        var left = w * 0.14;
        var right = w * 0.86;
        var top = h * 0.25;
        var bottom = h * 0.72;
        var midY = (top + bottom) / 2.0;
        var halfH = (bottom - top) / 2.0;

        // Center baseline and +/- threshold lines
        dc.setPenWidth(1);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(left, midY, right, midY);
        var thY = halfH * THRESHOLD / Z_RANGE;
        dc.setColor(Graphics.COLOR_DK_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(left, midY - thY, right, midY - thY);
        dc.drawLine(left, midY + thY, right, midY + thY);

        var n = _zs.size();
        if (n == 0) {
            return;
        }
        var stepX = (right - left) / (GRAPH_POINTS - 1);
        var x0 = right - (n - 1) * stepX; // newest point at the right edge
        var px = 0.0;
        var py = 0.0;

        dc.setPenWidth(2);
        for (var i = 0; i < n; i++) {
            var z = _zs[i];
            if (z > Z_RANGE) { z = Z_RANGE; }
            if (z < -Z_RANGE) { z = -Z_RANGE; }
            var x = x0 + i * stepX;
            var y = midY - (z / Z_RANGE) * halfH;
            if (i > 0) {
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(px, py, x, y);
            }
            px = x;
            py = y;
        }
        // Spike markers on top of the line
        dc.setColor(Graphics.COLOR_PINK, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < n; i++) {
            if (_spikes[i]) {
                var z = _zs[i];
                if (z > Z_RANGE) { z = Z_RANGE; }
                if (z < -Z_RANGE) { z = -Z_RANGE; }
                dc.fillCircle(x0 + i * stepX, midY - (z / Z_RANGE) * halfH,
                    (w * 0.015).toNumber() + 1);
            }
        }
        dc.setPenWidth(1);
    }

    private function drawBanner(dc as Dc, w as Number, h as Number, c as Number) as Void {
        if (_lastSpikeMs < 0 || System.getTimer() - _lastSpikeMs > BANNER_MS) {
            return;
        }
        dc.setColor(_blink ? Graphics.COLOR_BLUE : Graphics.COLOR_PINK,
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.84, Graphics.FONT_SMALL,
            WatchUi.loadResource(Rez.Strings.Alert) as String, c);
    }
}
