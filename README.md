# Lie Detector (Garmin Connect IQ)

A for-fun HRV stress-spike detector for Garmin watches. **Not a real polygraph.**

1. Waits for the first valid beat-to-beat (RR) intervals.
2. Calibrates for ~60 s (RMSSD over the last 12 valid RR, sampled once per second) to build a personal baseline.
3. Draws a live z-score graph (last 60 points) with a center line and +/-2.5 reference lines.
4. When |z| > 2.5 it shows "Lie hypothesis!" for ~5 s and marks the spike with a magenta dot.
5. To restart calibration (hand the watch to someone else), exit the app and open it again. Buttons do nothing inside the app, so pressing one for the backlight is safe.

Only live data from the moment the app opens is used. Nothing is stored or persisted.

## API notes (checked against Connect IQ SDK 9.3.0 docs)

- `Toybox.Sensor.registerSensorDataListener` - since API 2.3.0
- `Sensor.SensorData.heartRateData` / `Sensor.HeartRateData.heartBeatIntervals` - since API 3.0.0
- Therefore `minApiLevel="3.0.0"`. Permission: `Sensor`.
- The listener is unregistered in `onHide`.

`manifest.xml` lists every round-screen watch-app device in the installed SDK with API level 3.0 or higher.

## Build and run

Requirements: Connect IQ SDK + the "Monkey C" VS Code extension, and a developer key
(VS Code: `Monkey C: Generate a Developer Key`).

**VS Code:** open the folder, press **F5**, pick a device, and the simulator starts.
In the simulator use `Simulation > FIT Data > Simulate Data` or a HR sensor simulation to feed heart-beat intervals.

**Command line:**

```
monkeyc -d fenix7 -f monkey.jungle -o bin/LieDetector.prg -y developer_key.der
monkeydo bin/LieDetector.prg fenix7
```

## Sideload to the watch

1. Build for your device (above, or `Monkey C: Build for Device` in VS Code).
2. Connect the watch by USB.
3. Copy `bin/LieDetector.prg` to `GARMIN/Apps/` on the watch.
4. Disconnect; find "Lie Detector" in the apps list.

Optical wrist HR does not report RR intervals on every device or firmware. If the app stays on
"Waiting for HRV data", try a chest strap or check the device's support.

## License

MIT, see [LICENSE](LICENSE).
