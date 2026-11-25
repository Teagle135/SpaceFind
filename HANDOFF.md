# SpaceFind handoff

The default branch contains the shared iPhone inventory demo. A Mac on the same Wi-Fi runs the Python and SQLite service. The iPhone app shows each item’s photo and last recorded location, supports offline edits and conflict resolution, and lets crew members report and close lost items.

## Run the demo

Follow [Start the laptop](README.md#start-the-laptop) and [Install and join](README.md#install-and-join) in the README. Use the existing service data directory when continuing a demo. It contains the SQLite inventory, private invite and TLS identity. Back it up locally before moving a service and keep it out of Git. Share the pairing string privately.

The [two-phone rehearsal](README.md#rehearse-with-a-wrench) covers photos, offline changes, conflicts and restore after restart. The [README verification record](README.md#verification-on-november-15-2026) has the device evidence. The physical walkthrough with Wi-Fi’s internet uplink disconnected remains to be run.

## Verify changes

```sh
python3 -m unittest discover -s server -v
xcrun simctl list devices available
python3 scripts/test_demo.py FIRST_SIMULATOR_UDID SECOND_SIMULATOR_UDID
```

Use two fresh simulator IDs for the automated rehearsal. The script runs a disposable local service and exercises the actual iPhone app. Use the physical walkthrough to check camera permissions, local-network reachability and Wi-Fi behavior.

## Radar experiments

- [`spacefind-radar-trial`](https://github.com/Teagle135/SpaceFind/tree/spacefind-radar-trial) is the shared-origin prototype.
- [`themed-radar`](https://github.com/Teagle135/SpaceFind/tree/themed-radar) carries the themed radar and photo-first inventory work.

A synced item coordinate confirms that the server delivered the recorded location. Measuring the finder’s position requires a physical walk from the shared origin. Record distances and errors before claiming the two-metre target.
