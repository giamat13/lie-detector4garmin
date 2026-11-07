# Connect IQ Store – Lie Detector

Upload files: `cover_500x500.png` (Cover Image), `hero_1440x720.png` (Hero Image).

## Title (max 50 characters)

Lie Detector (HRV stress spikes)

## Description (max 4000 characters)

Lie Detector is a for-fun HRV stress-spike detector for your watch. It is NOT a real polygraph and cannot tell whether someone is lying. Use it as a party toy, not for any real decision.

How it works:
- Open the app. It shows "Waiting for HRV data" until your watch sends beat-to-beat intervals.
- Calibration (about 60 seconds): a breathing guide (6 breaths per minute) runs for 30 seconds. Then the app measures your baseline while you breathe normally.
- Live graph: your HRV (RMSSD, shown as a z-score against your own baseline) updates every second. A center line and two reference lines mark the threshold.
- Spike: when the value moves well away from your baseline for two readings in a row, a "Lie hypothesis!" banner appears for about 5 seconds and the spike is marked with a dot on the graph.
- Handing the watch to someone else: exit the app and open it again to start a new calibration.

Privacy: the app reads heart-rate interval data on the watch only. It keeps everything in memory, stores nothing between runs, and sends nothing anywhere.

Requirements: a Garmin watch with Connect IQ API level 3.0 or newer and a heart-rate sensor that reports beat-to-beat intervals. If the app stays on "Waiting for HRV data", your sensor is not sending these intervals.

Source code is open under the MIT license.

## Store form answers

| Field | Answer | Note |
|---|---|---|
| Does your app collect user data? | No | Heart-rate data is read on the watch only and is not stored or sent. If you choose Yes, you must add a privacy policy link. |
| Does your app decode/encode any ANT+ profiles? | No | The watch's own sensor API provides the data. |
| Does your app have regional limits? | No | Confirm before submitting. |
| Monetization | No | Free app, no tips, no payments. |
| Source Code URL | https://github.com/GIAMAT13/lie-detector4garmin | Optional. |

## Still to do by hand

- Screen images (up to 150 KB each): take them from the simulator or the watch. The form requires them.
- Device icons (optional): 128x128, reduced colours. Skipped for now.
