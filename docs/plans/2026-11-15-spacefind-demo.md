# SpaceFind first demo implementation plan

**Goal:** Let two crew members on iPhones record, find, and move photographed items through one laptop-hosted inventory on Wi-Fi with the internet disconnected.

**Architecture:** A small Python service owns one SQLite database, including the photos. The iPhone app keeps a durable local snapshot and queue of edits. It sends edits in creation order and refreshes the snapshot while the app is open.

**Tech stack:** Python standard library, SQLite, HTTPS, SwiftUI, URLSession, XCTest. Use a native Xcode project with a shared SpaceFind scheme. The two phones were reported to run iOS 27.0.1 and 26.6.2. The app targets iOS 16 and later.

**Spec:** [Approved SpaceFind design](../specs/2026-11-15-spacefind-design.md)

## Global constraints

- One laptop, one inventory, two iPhones, one private crew invite. Joining and sharing must work without internet.
- Each item has a stable ID independent of its label. Require a photo, label, and location. The description is optional.
- Pending changes and photos survive app relaunch. Show **Waiting to sync** until the laptop durably accepts the change.
- In a conflict, show both location/photo pairs. Either crew member can confirm one.

## Review focus

| Case | Expected outcome | Checked in |
| --- | --- | --- |
| Laptop commits a move but the acknowledgment is lost | Retrying creates one report | Task 1 |
| One phone makes two moves offline | Its later move succeeds its earlier one without a false conflict | Tasks 1 and 2 |
| A third report arrives while a crew member is confirming a location | A stale confirmation cannot discard the new report | Task 1 |
| Phone relaunches before a replacement photo uploads | Pending photo and location stay paired | Task 2 |
| Two items share a label, or the user cancels a move | Only an explicitly saved edit to the selected ID changes anything | Task 3 |

## Files and interfaces

- `server/spacefind.py` — laptop service, invite verification, SQLite transactions and command-line startup. `server/test_spacefind.py` — service tests using a temporary database.
- `ios/SpaceFind.xcodeproj` — app and test targets. Under `ios/SpaceFind/`, `Inventory.swift` owns local records and pending writes, `CrewService.swift` handles pairing and sync, `SpaceFindApp.swift` starts the app, and `InventoryView.swift` and `ItemEditor.swift` implement the crew workflows. Put persistence and sync tests in `ios/SpaceFindTests/InventoryTests.swift` and `SyncTests.swift`.
- `README.md` — laptop startup, phone setup, and physical rehearsal. Keep generated databases, invites, signing credentials, photos, and TLS keys out of Git.

### Task 1 — Persist and share an inventory on the laptop

- [x] Write `server/test_spacefind.py` first. Verify a wrong invite cannot join and an unauthenticated client cannot read or write. Create a wrench, reopen the database, and assert that the photo bytes and location match. Replay its mutation ID and assert there is still one item.
- [x] Add a two-client test. Moves with the same parent report produce two candidates in either arrival order. A move based on a client's own preceding report replaces that candidate only. Confirming with the current candidate IDs leaves the chosen report. After another move arrives, confirming with stale IDs returns HTTP 409 and preserves all current candidates.
- [x] Run `python3 -m unittest discover -s server -v` before implementation to see the missing service failure.
- [x] Implement `POST /join` (invite → device token), authenticated `GET /inventory` (items and current candidate reports), and authenticated `POST /changes` (one create, move, or confirmation). Use UUIDs for items and changes. A move's change ID is also its report ID. A move names its parent report. A confirmation names the observed candidate IDs and the chosen report. Each new report carries its location and JPEG bytes together. For this small inventory, encode photo bytes as base64 in JSON and store them as blobs in SQLite.
- [x] In one transaction validate the operation, check for an already accepted change ID, apply it once, and record its receipt. Keep only the report data required for active candidates and retry handling. Validate nonblank required fields, a 2 MiB decoded JPEG limit and a 3 MiB request limit, and references to the correct item. Return success after commit. Add a startup command that opens the same database after restart, serves HTTPS on the LAN, and provides the crew lead with pairing information. Pin the laptop certificate on the phones using a fingerprint delivered with the private invite. Keep secrets out of request logs.
- [x] Rerun the server suite. Commit and push the working laptop service when the persistence, access, retry, and conflict cases pass.

### Task 2 — Keep each phone usable offline

- [x] Create the Xcode project and test targets. Use a temporary directory and a fake service in tests. In `InventoryTests.swift`, save an offline create followed by two moves. Reopen the store and assert the same item ID, newest local location and photo, and ordered pending changes. In `SyncTests.swift`, drop the first acknowledgment, retry, and assert that the same change ID is sent. Receiving a snapshot must preserve later pending work.
- [x] Implement the shared wire types from Task 1. Use one atomically replaced Codable file in Application Support for the demo snapshot, normalized photo bytes, and pending changes. Stage each update before replacing persisted and visible state. A local write failure leaves existing data intact and the user's form available for retry.
- [x] Implement one serialized sync operation. Upload the pending queue in order, retire only acknowledged changes, fetch the snapshot, and display it with any remaining local edits applied. If a confirmation is stale, fetch the current candidates and ask for a fresh selection. Retry on foreground entry and a short foreground timer. Keep pending edits across network failures.
- [x] Let the lead share one pairing string containing the laptop address, certificate fingerprint, and invite so each crew member can paste it once. Verify the pinned server before sending credentials and keep the device token in Keychain. Add tests that a different certificate or rejected invite cannot establish a session.
- [x] Choose an installed simulator from `xcrun simctl list devices available`. Run `xcodebuild test -project ios/SpaceFind.xcodeproj -scheme SpaceFind -destination "platform=iOS Simulator,id=$SIMULATOR_UDID"` with that simulator's UDID before and after implementing the store and sync. Commit and push when the tests pass.

### Task 3 — Record, search, move, and confirm from the phone

- [x] Cover partial case-insensitive searches across label, description, and location, empty search, and two items with the same label. Assert that saving a move changes only the selected ID and canceling a draft preserves the previous photo and location.
- [x] Build the join screen, searchable inventory, and item detail. Results show the photo, label and location together. Show both candidate locations and photos on a conflicted item and allow either crew member to select one. Label every pending edit **Waiting to sync**.
- [x] In the editor, support a new camera photo or library selection. Keep the library option available after camera permission denial. Normalize and size photos to fit the service limit. Preserve the current photo on a move unless the user replaces it. Add local-network and camera usage descriptions, and surface save or pairing failures where the user can retry.
- [x] Run the Task 2 test command and exercise join, search, cancel and conflict selection in the simulator. Reserve the camera capture check for a physical iPhone. Commit and push the working app.

### Task 4 — Verify the two-iPhone demo

- [x] Document the exact laptop start command, generation and reuse of its local TLS identity, how to find the laptop's address, where the lead sees pairing information, and how to sign and install on each demo phone.
- [x] Install, launch, and join the shared laptop inventory on both physical iPhones.
- [x] Capture a photo on the iPhone 16 and verify the same photo and location on the laptop and iPhone 14 Plus.
- [ ] **Deferred by request.** Repeat the physical walkthrough with the Wi-Fi network’s internet uplink disconnected.
- [x] On the disconnected iPhone 16, reopen SpaceFind and confirm “Red Pouch” and **Waiting to sync**. After reconnecting, verify that both phones and the laptop agree.
- [x] Make conflicting offline moves on the two physical phones, replacing the photo on one. Reconnect, confirm one report, and verify the chosen photo and location on both phones.
- [ ] Verify recovery from the laptop after a fresh install on one previously synced phone. Use the [design acceptance checks](../specs/2026-11-15-spacefind-design.md#demo-acceptance-checks) for the walkthrough.
- [x] Run the Python and Xcode suites, review the final diff against the design, and push the verified milestone to GitHub.
