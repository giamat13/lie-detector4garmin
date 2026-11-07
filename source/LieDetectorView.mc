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
    private const RR_JUMP = 0.25;       // reject RR >25% away from the window mean (artifact/ectopic)
    private const WINDOW = 12;          // RR intervals per RMSSD window
    private const MIN_RR_FOR_RMSSD = 6; // need at least this many to compute
    private const CALIB_SECONDS = 60;
    private const GUIDE_SECONDS = 30;   // paced-breathing phase (not used for the baseline)
    private const BREATH_CYCLE_MS = 10000; // 6 breaths/min: 5 s in, 5 s out
    private const MIN_BASELINE_SAMPLES = 5;
    private const MIN_STD = 0.1;        // floor for std of ln(RMSSD) (about 10%)
    private const GRAPH_POINTS = 60;
    private const THRESHOLD = 2.5;
    private const CONFIRM_SAMPLES = 2;  // consecutive samples beyond threshold needed
    private const Z_RANGE = 4.0;        // graph shows -Z_RANGE..+Z_RANGE
    private const BANNER_MS = 5000;

    private const ST_WAITING = 0;
    private const ST_CALIBRATING = 1;
    private const ST_RUNNING = 2;

    private var _state as Number = 0;
    private var _timer as Timer.Timer?;
    private var _animTimer as Timer.Timer?;
    private var _listening as Boolean = false;
    private var _calibStartMs as Number = 0;

    private var _rr as Array<Number> = [] as Array<Number>;

    // Baseline (Welford running mean / variance of ln(RMSSD))
    private var _calibElapsed as Number = 0;
    private var _n as Number = 0;
    private var _mean as Float = 0.0;
    private var _m2 as Float = 0.0;
    private var _std as Float = 1.0;

    // Graph data
    private var _zs as Array<Float> = [] as Array<Float>;
    private var _spikes as Array<Boolean> = [] as Array<Boolean>;
    private var _streak as Number = 0;
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
        var a = new Timer.Timer();
        a.start(method(:onAnim), 100, true);
        _animTimer = a;
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
        var a = _animTimer;
        if (a != null) {
            a.stop();
            _animTimer = null;
        }
    }

    // Smooth breathing-circle animation, only while calibrating.
    function onAnim() as Void {
        if (_state == ST_CALIBRATING) {
            WatchUi.requestUpdate();
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
            if (v < RR_MIN_MS || v > RR_MAX_MS) {
                continue;
            }
            if (_rr.size() >= 3) {
                var m = windowMean();
                if ((v - m).abs() > RR_JUMP * m) {
                    continue; // artifact / ectopic beat
                }
            }
            _rr.add(v);
            if (_rr.size() > WINDOW) {
                _rr = _rr.slice(1, null);
            }
            if (_state == ST_WAITING) {
                _state = ST_CALIBRATING;
                _calibElapsed = 0;
                _calibStartMs = System.getTimer();
            }
        }
    }

    // Once per second.
    function onTick() as Void {
        _blink = !_blink;

        if (_state == ST_CALIBRATING) {
            _calibElapsed++;
            // The baseline is taken only after the paced-breathing phase, while
            // breathing normally (paced breathing inflates RMSSD).
            if (_calibElapsed > GUIDE_SECONDS && _rr.size() >= WINDOW) {
                var r = rmssd();
                if (r != null && r > 0) {
                    var x = Math.ln(r).toFloat();
                    _n++;
                    var d = x - _mean;
                    _mean += d / _n;
                    _m2 += d * (x - _mean);
                }
            }
            if (_calibElapsed >= CALIB_SECONDS && _n >= MIN_BASELINE_SAMPLES) {
                var sd = Math.sqrt(_m2 / (_n - 1)).toFloat();
                _std = (sd > MIN_STD) ? sd : MIN_STD;
                _state = ST_RUNNING;
            }
        } else if (_state == ST_RUNNING) {
            var r = rmssd();
            if (r != null && r > 0) {
                var z = (Math.ln(r).toFloat() - _mean) / _std;
                var beyond = (z > THRESHOLD || z < -THRESHOLD);
                _streak = beyond ? _streak + 1 : 0;
                var spike = (_streak >= CONFIRM_SAMPLES);
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

    private function windowMean() as Float {
        var s = 0.0;
        for (var i = 0; i < _rr.size(); i++) {
            s += _rr[i];
        }
        return s / _rr.size();
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
            drawCalibration(dc, w, h, c);
        } else {
            drawGraph(dc, w, h);
            drawBanner(dc, w, h, c);
        }
    }

    private function drawCalibration(dc as Dc, w as Number, h as Number, c as Number) as Void {
        var pct = _calibElapsed * 100 / CALIB_SECONDS;
        if (pct > 100) {
            pct = 100;
        }
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.23, Graphics.FONT_SMALL,
            WatchUi.loadResource(Rez.Strings.Calibrating) as String, c);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.33, Graphics.FONT_TINY,
            WatchUi.loadResource(Rez.Strings.TakeSeat) as String, c);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.45, Graphics.FONT_MEDIUM, pct.format("%d") + "%", c);

        var cy = h * 0.66;
        var rMax = h * 0.11;
        var rMin = h * 0.04;
        var word;
        if (_calibElapsed < GUIDE_SECONDS) {
            // Paced breathing guide: circle grows on inhale, shrinks on exhale.
            var phase = (System.getTimer() - _calibStartMs) % BREATH_CYCLE_MS;
            var k = (1.0 - Math.cos(2.0 * Math.PI * phase / BREATH_CYCLE_MS)) / 2.0;
            var r = rMin + (rMax - rMin) * k;
            dc.setColor(Graphics.COLOR_DK_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(w / 2, cy, r);
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            dc.drawCircle(w / 2, cy, r);
            dc.setPenWidth(1);
            word = (phase < BREATH_CYCLE_MS / 2)
                ? Rez.Strings.BreatheIn : Rez.Strings.BreatheOut;
        } else {
            word = Rez.Strings.BreatheNormal;
        }
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.88, Graphics.FONT_TINY,
            WatchUi.loadResource(word) as String, c);
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
