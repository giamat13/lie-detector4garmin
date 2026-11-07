import Toybox.Lang;
import Toybox.WatchUi;

// No custom input: calibration restarts only when the app is closed and reopened.
class LieDetectorDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }
}
