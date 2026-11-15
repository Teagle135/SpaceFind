# Shared Lost-Item Reports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Any joined crew member can report a missing item, share its last-seen location and optional photo, and close the search by recording where it was found.

**Architecture:** Store each search as a distinct lost-item record. Extend the existing authenticated change queue and inventory snapshot to carry lost reports alongside inventory items. The phone shows locally saved work immediately, and the laptop decides competing closures in a single SQLite transaction.

**Tech Stack:** SwiftUI on iOS 16+, Foundation, PhotosUI, XCTest, Python standard library HTTPS service, SQLite.

**Spec:** [Approved shared lost-item reports design](../specs/2026-11-15-shared-lost-item-reports-design.md), commit `d803d94`.

## Global Constraints

- Reporting requires an item name and last-seen location. Closing requires a found location. Reject blank or whitespace-only values. Camera and library photos are optional.
- A lost report has its own ID, even when a second report or an inventory entry has the same name. Keep the original photo and both locations after closure.
- Keep the existing crew pairing, laptop certificate pinning, 2 MiB JPEG limit, 3 MiB request limit, atomic phone saves and **Waiting to sync** indicator.
- Ship the additive laptop update before the phone update. Existing phone caches, pending inventory edits and populated laptop databases must upgrade in place.

## Review Focus

| Condition | Expected result and owning task |
|---|---|
| Accepted closure is retried after another phone attempts closure | Original change ID still succeeds. A distinct losing closure gets the winner’s location (1, 3). |
| Old database or phone cache contains inventory and an unsent move | Inventory, JPEG bytes and pending change IDs survive upgrade (1, 2). |
| An edit arrives while a snapshot is in flight | The arriving snapshot preserves the new pending edit and its local display (3). |
| Storage fails while saving a report, or the crew switches laptops with work pending | Form stays usable after failure. Pending reports stay bound to the original laptop (2, 4). |
| Camera unavailable or library selection cancelled | A text-only report can still be submitted. Inventory keeps its required-photo behavior (4). |

---

## Files and verification setup

| File | Responsibility |
|---|---|
| `server/spacefind.py`, `server/test_spacefind.py` | Extend the existing transaction, validation, snapshot and HTTP tests. |
| `ios/SpaceFind/Inventory.swift`, `ios/SpaceFindTests/InventoryTests.swift` | Add the lost-report model, cache upgrade, offline projection and queue operations. |
| `ios/SpaceFind/CrewService.swift`, `ios/SpaceFindTests/SyncTests.swift`, `ios/SpaceFindTests/CrewIntegrationTests.swift` | Decode snapshots, distinguish an already-closed report from other failures and verify two-client convergence. |
| `ios/SpaceFind/LostItemsView.swift` (new), `ios/SpaceFind/SpaceFindApp.swift`, `ios/SpaceFind/ItemEditor.swift`, `ios/SpaceFindUITests/CrewWalkthrough.swift` | Add navigation and report screens, reuse photo selection and rehearse the crew flow. |

Run commands from the repository root. Use `xcrun simctl list devices available` to choose two fresh iPhone simulators and set shell variables `SIM_A` and `SIM_B` to their UDIDs. For focused tests define:

```sh
ios_test() {
  xcodebuild test -project ios/SpaceFind.xcodeproj -scheme SpaceFind \
    -parallel-testing-enabled NO -destination "platform=iOS Simulator,id=$SIM_A" "$@"
}
```

The Xcode project discovers files under its app and test directories automatically. Each full rehearsal starts a disposable laptop with a new identity. Use fresh simulator state for each rehearsal so a saved pairing from the previous run cannot select the wrong laptop.

### Task 1: Persist and share lost reports on the laptop

**Interfaces.** Extend `POST /changes` with two kinds. For `reportMissing`, send `{id, kind, itemID, label, location, photo?}`. For `markFound`, send `{id, kind, itemID, location}`. Here the existing wire key `itemID` holds the lost report’s UUID. It is independent of inventory. Each operation has a distinct, stable `id`. Extend authenticated `GET /inventory` with `lostReports: [{id, name, lastSeen, photo?, foundAt?}]`. Missing optional fields represent no photo or an open search.

- [ ] In `server/test_spacefind.py`, add `test_lost_report_lifecycle_and_replay`. Join two clients and open two reports named “Torque wrench”, one with a JPEG. Close only the first. Check `self.assertEqual((first["lastSeen"], first["foundAt"]), ("beside the workbench", "locker 2"))`, the original JPEG, the still-open sibling and the unchanged inventory. Replay the accepted create and close with identical IDs and bodies and expect `(200, {})`.
- [ ] Add `test_first_closure_wins` using competing closure IDs and locations. Assert exactly one success, the other receives **409** with `{"code":"alreadyFound","foundAt":<winner>}`, and the snapshot agrees. Replaying the winning ID succeeds. Reusing an accepted ID with altered content yields an ordinary conflict, never `alreadyFound`. Cover unauthorized requests, unknown report IDs, blank fields and malformed or oversized supplied photos using the existing request helpers.
- [ ] Add an upgrade/restart case with a populated pre-feature database (existing inventory schema and rows, no lost-report table). Run `python3 -m unittest discover -s server -v`. The new tests must fail for the unsupported operations or missing snapshot field.
- [ ] In `server/spacefind.py`, add `lost_reports(id, name, last_seen, photo, found_at)` in `_initialize_db`. Extend `_normalize_change(body)` with per-kind field whitelists and the existing UUID, text and JPEG checks. In `_change(db_path, body)`, use the existing payload hash and replay check **before** testing whether the report is closed. Under the same `BEGIN IMMEDIATE`, insert a missing report or set only `found_at` on the open row. Reject ID collisions consistently across report, inventory and change IDs. Return the typed conflict only for a different closure of an existing closed report.
- [ ] Read both collections under the existing snapshot transaction. Run the server suite again. Expect all tests to pass, including restart with the saved token, original inventory photo and recovered lost report.
- [ ] Commit the server and server tests as `feat: share lost-item reports through the crew service`.

### Task 2: Save and reopen reports offline on iPhone

**Interfaces.** In `Inventory.swift`, add `LostItemReport: Codable, Equatable, Identifiable` with `id: UUID`, `name: String`, `lastSeen: String`, `photo: Data?` and `foundAt: String?`. Add `Inventory.lostReports: [LostItemReport]`, `reportMissing(name:lastSeen:photo:) throws -> UUID` taking `String, String, Data?`, and `markFound(reportID:foundAt:) throws` taking `UUID, String`. Use existing `isPending(_:)`, `pendingChanges` and the same FIFO for both record types.

- [ ] In `InventoryTests.swift`, add `testOfflineLostReportSurvivesRelaunch`. Create with a photo, close offline, reopen the file and assert `XCTAssertEqual(reopened.pendingChanges.map(\.kind), [.reportMissing, .markFound])`. Assert stable report and operation IDs, both locations, photo bytes, empty inventory and pending status. Repeat creation without a photo. Validate blank text, bad supplied photo and oversized encoded body leave the queue unchanged.
- [ ] Add `testLegacyCachePreservesPendingMove` using the old JSON shape containing `items` and `pending`. Assert `XCTAssertEqual(reopened.pendingChanges.first?.id, originalMoveID)`, the previously saved photo and displayed move, and an empty lost-report list. Force an atomic write failure in a temporary directory and verify no record or change is published.
- [ ] Run `ios_test -only-testing:SpaceFindTests/InventoryTests`. Expect the new model or methods to be missing on the first run.
- [ ] Add the two `ChangeKind` cases and validate at enqueue. Use the two wire shapes in Task 1, trimming text and validating an attached JPEG and encoded size before saving. Reject local closure of a missing ID or an already-found report. Add lost reports to the persisted store, defaulting an **absent** collection to empty on decode. Preserve errors for corrupt data. Apply changes to the appropriate collection when rendering the saved snapshot plus pending edits and when acknowledging a change. Publish only after the atomic save succeeds.
- [ ] Rerun the focused tests and expect all to pass. Verify the existing laptop-switch guard reads the same combined `pendingChanges`. Commit as `feat: persist missing and found reports offline`.

### Task 3: Reconcile the shared outcome and keep syncing

**Interfaces.** Introduce `CrewSnapshot: Decodable, Equatable` containing `items: [Item]` and `lostReports: [LostItemReport]`. Change `CrewAPI.fetch() async throws -> CrewSnapshot` in both the real service and test doubles. Keep `send(_ change: Change) async throws`. Add `CrewError.alreadyFound(foundAt: String)`. Expose `Inventory.closureNotices: [UUID: String]`, mapping report ID to accepted location, and `dismissClosureNotice(reportID: UUID)` for Task 4.

- [ ] In `SyncTests.swift`, adapt both existing fakes to return snapshots. Add `testLosingClosureKeepsWinnerAndDrainsLaterWork`: send a losing close followed by a new missing report. Assert `XCTAssertEqual(store.lostReports.first(where: { $0.id == closedID })?.foundAt, "locker 2")`, a notice for that ID, the later report on the server and an empty queue. Inject an edit during fetch and verify it remains pending. Simulate a dropped successful closure acknowledgment and verify retry reuses its ID and produces no losing-closure notice.
- [ ] Run `ios_test -only-testing:SpaceFindTests/SyncTests`. Expect failure on the new snapshot or reconciliation assertions.
- [ ] Update `CrewService.swift` to decode both collections and map only the Task 1 typed response on a `markFound` request to `alreadyFound`. Preserve ordinary errors and inventory confirmation handling. In `Inventory.performSync`, atomically replace the losing found location with the accepted one and dequeue only that operation. Surface the notice independently of the transient connection banner, then continue draining. A transport or local write failure retains pending work. On ordinary fetch and stale inventory confirmation, apply both snapshot collections against the **current** pending queue after each await.
- [ ] In `CrewIntegrationTests.swift`, add `testTwoCrewMembersCloseLostReportOffline` against two joined clients with distinct local files. Confirm that one client can close the other’s report, that an offline create-then-close survives reinitializing the store and that racing offline closures converge in reconnection order. Assert both locations, JPEG bytes when supplied, cleared queues and unchanged inventory. Use unique report IDs so these tests can share the rehearsal database.
- [ ] Rerun focused sync tests, then run the disposable rehearsal command in Task 4 for real client/service coverage. Require the new integration case to **pass**, since a bare XCTest run skips pairing-dependent tests. Commit as `feat: reconcile found reports across crew phones`.

### Task 4: Connect the approved screens and rehearse the crew flow

**Interfaces.** `LostItemsView(inventory: Inventory)` observes the store from Task 2. Open detail by report UUID. Share the camera and library controls from `ItemEditor.swift` as `ItemPhotoSection(photo:isLoading:required:)` with bindings to `Data?` and `Bool` and a `Bool` for required-photo copy.

- [ ] In `CrewWalkthrough.swift`, add `testSharedLostItemWalkthrough` using the existing pairing and second-phone flag. Phone A files a uniquely identifiable, photo-free report, waits for its pending indicator to clear, then leaves it missing. Phone B opens that same report, cancels a found entry, checks it is still missing, enters “locker 2”, and saves. Assert `XCTAssertFalse(markFound.isEnabled)` for a blank found location and check that the closed detail exposes **Found**, **Last seen**, **Found at** and both values. Use a walkthrough-specific name shared by both phones in the disposable database.
- [ ] Run `python3 scripts/test_demo.py "$SIM_A" "$SIM_B"`. Expect the new walkthrough to fail at the missing Lost items destination.
- [ ] In `SpaceFindApp.swift`, host **Inventory** and **Lost items** as sibling tabs after joining, keeping one foreground sync loop and the existing reconnect guard. In `LostItemsView.swift`, expose **Report a missing item** from both the empty and populated list. Group **Missing** before **Found**. Show the name, labelled relevant location, pending state and status as accessible text. Resolve detail from the live store by ID so another phone closing the report updates an open screen.
- [ ] Implement the two approved forms with the exact labels from the spec. Invoke the store methods on save, preserve input on error, and discard unsaved drafts on cancel. Show the original optional photo and both locations after closure. On the losing phone show which report was already closed and the accepted location. Keep that notice available until acknowledged even if the user is on the other tab.
- [ ] Extract the existing photo selection, JPEG preparation, camera permission handling and loading state into the shared section. Keep inventory photos required, allow omission for a lost report, and prevent save during photo preparation. Verify camera denial or library cancellation still permits submitting text. On a physical iPhone, check camera capture and VoiceOver reading order for status and locations.
- [ ] Run `python3 -m unittest discover -s server -v` and the two-simulator rehearsal again with fresh simulators. Expect the unit, integration and UI cases to pass, including existing inventory photo and conflict walkthroughs. Verify a failed local save keeps the draft and that a different laptop cannot take over with a lost report pending. Record which checks ran on devices.
- [ ] Commit as `feat: add shared lost-item reporting to SpaceFind`.
