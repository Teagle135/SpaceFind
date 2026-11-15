# Two-iPhone Radar Trial Implementation Plan

**Goal:** Measure whether the finder can stop within 2.0 m of the spot where the other phone took a photo, using only step and turn estimates for tracking.

**Architecture:** Build a throwaway SpaceFind variant on the trial branch. Both phones start at the same marked position and orientation beside a stationary MacBook. The trial shares the shutter position and photo through the existing paired inventory service. The searching phone tracks its own position locally throughout the foreground session.

**Tech Stack:** SwiftUI, Core Motion, UIKit camera capture, XCTest and the existing Python/SQLite service.

**Spec:** The crew's November 15 demo brief in this chat, restated below. Scope is a physical walking experiment in a single-level demo space.

## Global Constraints

- No camera-based tracking, marker scans, floor plans, facing indicator or added positioning hardware. Use the rear camera only to take the item photo.
- The target is the photographer's standing spot at shutter time. Capture it automatically. Start tracking before walking on both phones.
- Display the estimated positions as two dots on fixed axes. The physical pass criterion is a measured endpoint error of at most 2.0 m; the on-screen distance is only an estimate.
- Use a separate trial app identity, a disposable service data directory and the same fixed MacBook origin for the trial. Keep production inventory and credentials separate. No server schema changes.

## Review Focus

- Delayed distance samples around a turn must use heading history for the distance interval.
- Stationary phone rotation must produce zero displacement.
- Removing motion permission or interrupting tracking must make a stale position unavailable.
- Moving during photo review, retaking and cancelling must preserve the correct shutter binding.
- Nearby screen dots can still mean a physical miss. Record independent measurements before revealing the photo.

---

### Task 1: Estimate a walking position from a shared start

**Files:** Create `ios/SpaceFind/RadarTracker.swift` and `ios/SpaceFindTests/RadarTrackerTests.swift`. Add the motion usage description in `ios/AppInfo.plist`.

**Interfaces:** Expose a metre-based Codable `RadarPoint(x:y:)`, and a main-thread observable `RadarTracker` with start, stop, tracking status and an optional estimated position. Keep the pure timestamped sample integration callable from unit tests.

- [ ] Write failing tests for a 3 m forward leg followed by a 4 m right leg (expected x=4, y=3), a delayed distance sample spanning that turn, a stationary quarter turn, a duplicate sample and reset after interrupted tracking.
- [ ] Integrate pedometer distance increments against time-aligned relative headings. Distribute a batched increment over its measured interval using heading history; document its constant-speed approximation. Use a monotonic time base for motion and distance samples. Ignore stale callbacks from a previous start. Treat missing sensors, denied permission and an interrupted session as unavailable. Distinguish waiting for first valid readings from ready.
- [ ] Verify with the RadarTrackerTests class on the iPhone simulator. Commit tracker, permission copy and tests together.

### Task 2: Capture and find one trial target across phones

**Files:** Create `ios/SpaceFind/RadarTrialView.swift`, `ios/SpaceFind/RadarTrialCamera.swift` and `ios/SpaceFindTests/RadarTrialTests.swift`. Adapt `ios/SpaceFind/SpaceFindApp.swift`, `ios/SpaceFind/ItemEditor.swift` (reuse its JPEG normalization), and `ios/SpaceFind.xcodeproj/project.pbxproj` for the trial build. Reuse `Inventory.create(label:description:location:photo:)` and existing pairing and sync.

**Interfaces:** Own one tracker for the joined session, across capture and Find. Use a versioned trial position encoded in the existing report location field alongside the same report's photo. Give each new capture an identifiable trial label; choose a target by item ID. Decode only recognized finite trial coordinates.

- [ ] Write tests for coordinate round-trip with signed fractional metres, malformed and ordinary location text, delayed photo review after a simulated move, retake and cancellation. Reuse the disposable two-client integration harness to verify that the second phone gets the same coordinates and image bytes.
- [ ] Give the prototype its own app identity and visible trial name. After joining, guide each phone to start at the same spot with its top edge pointed along the same reference. Walk holding the phone in a consistent forward orientation. Show tracking readiness and a restart-at-MacBook action when necessary.
- [ ] Freeze the coordinate when the shutter is triggered, pair it with that capture's normalized photo, and save through the existing offline queue. Handle failure/cancel without creating a target. Account for pedometer delivery lag around capture; for this trial have the photographer stop and let the last walking readings settle before taking the shot.
- [ ] Find draws a fixed-axis radar with labelled, distinguishable dots, a common scale on both axes and estimated distance. Show the linked photo on request after the finder stops. Give feedback for missing coordinates, pending sync and invalid tracking. Verify that Find can run with camera access denied on the searching phone.
- [ ] Run tracker and trial tests, the two-client service check, and build for iPhone. Commit the working trial.

### Task 3: Measure physical accuracy

**Files:** Create `docs/radar-trial.md` for the setup, route and results. Use a disposable server directory and port for these runs.

- [ ] Install the trial alongside SpaceFind on both demo phones. Pair both to the trial server. Check actual motion delivery, capture and sync with the phones in hand.
- [ ] Mark the exact shared start, pointing direction and photographer's shutter spot. Walk both phones from the start along different routes including a turn; the finder must not see the target mark, destination photo or photographer's route before stopping. The finder calls a stop when the dots coincide as closely as practical. Mark that position before showing the photo.
- [ ] Measure the straight-line floor distance between the two marks with a tape. Record each run's route length, turns, phone roles, displayed separation, measured separation and any tracking interruptions. Proposed trial size: three runs, swapping phone roles for at least one. Record interrupted runs separately and repeat them; retain misses.
- [ ] Report each measured error against 2.0 m. Call this a successful demonstration only if all three completed routes meet the target. This small trial measures behavior on those routes; it cannot establish a general accuracy guarantee. Physical walking, camera operation and tape readings require a person with the phones; leave results pending until observed. Commit the protocol and any actual results.
