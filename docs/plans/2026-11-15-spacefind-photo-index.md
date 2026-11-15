# SpaceFind Photo Index Implementation Plan

**Goal:** Let a crew member recognize an item and read its last recorded location directly from Inventory, including when the phone is offline.

**Architecture:** Restyle the existing SwiftUI workflow. Share adaptive colors and the existing thumbnail renderer. Keep the existing navigation, search, photo pipeline, and synchronization model as the sources of behavior.

**Tech Stack:** SwiftUI, UIKit adaptive colors, XCTest/XCUITest, iOS 16 and later.

**Spec:** [Approved Photo index brief](../specs/2026-11-15-spacefind-photo-index-design.md)

## Global constraints

- Start with the selected 100 × 72 pt thumbnail, 8 pt corners, 12 pt text gap, 16 pt side margins, and a minimum 44 pt Add item hit area.
- Use the iPhone appearance setting, native text styles, native controls and system transitions. Preserve VoiceOver reading order, action labels, and existing test identifiers.
- Show photos and locations from the same report. Preserve local data, offline access, pending edits, conflict resolution, and camera/library behavior.

## Review focus

1. Two items share a name. Each row opens its own photo and location (task 1).
2. Both crew members report different moves. No candidate appears confirmed in the list, and both are distinguishable on detail (tasks 1–2).
3. A long location at accessibility text sizes remains fully readable, including in dark appearance (tasks 1–2).
4. A cached item is pending while the laptop is unreachable. The item status, connection action, Add item, and final row remain reachable (task 3).
5. A crew photo is very wide, tall, or unavailable. The row keeps its alignment and detail shows the whole available image (task 2).

## Files and verification setup

| Path | Responsibility |
| --- | --- |
| `ios/SpaceFind/CrewTheme.swift` (new) | Adaptive colors shared by the app's views. Xcode already synchronizes the source folder. |
| `ios/SpaceFind/InventoryView.swift` | Inventory header, native search, row hierarchy, status, counts, and empty states. |
| `ios/SpaceFind/ItemEditor.swift` | Shared thumbnail presentation, item detail, conflict choices, and create/move forms. |
| `ios/SpaceFind/SpaceFindApp.swift` | Root tint, crew invite, startup/retry, and connection notice. |
| `ios/SpaceFindUITests/CrewWalkthrough.swift` | Extend the existing seeded walkthrough where it can distinguish a regression. |

Run from the repository root. Use `xcrun simctl list devices available` to choose two fresh disposable iPhones and set `PHOTO_SIM_A` and `PHOTO_SIM_B` to their UDIDs. The rehearsal command below supplies the pairing and fixture IDs to XCTest, seeds a conflict, confirms it on the first phone, and checks the result on the second. For a repeat run, use fresh disposable simulator state. The simulator's seeded photos are color swatches. Use actual sample tool photos for the visual scan and crop checks.

```sh
python3 scripts/test_demo.py "$PHOTO_SIM_A" "$PHOTO_SIM_B"
```

Expected result is exit 0 with both UI walkthroughs executed on each phone. Treat a skipped seeded test as unverified.

### Task 1 — Deliver the Photo index screen

**Interfaces.** Consume `Inventory.search(_:)`, `Inventory.isPending(_:)`, and `Item.reports`. Introduce `CrewTheme.surface`, `.ink`, `.accent`, and `.divider` as static SwiftUI colors. Extend the existing `PhotoThumbnail` in ItemEditor.swift with a defaulted `cornerRadius: CGFloat = 12` so the list can request 8. Make these edits sequentially with task 2.

- [x] Extend `testJoinSearchAndInspectWrench` immediately before the existing row tap. On the first simulator pin the conflicted row's combined accessibility label. On the second require the confirmed location. Run the rehearsal and observe the current row disclosing the first candidate.

  ```swift
  if environment["SPACEFIND_TEST_SECOND_PHONE"] == "1" {
      XCTAssertTrue(row.label.localizedCaseInsensitiveContains("locker 2"))
  } else {
      XCTAssertTrue(row.label.contains("Needs confirmation"))
      for candidate in ["locker 2", "tool bag"] {
          XCTAssertFalse(row.label.localizedCaseInsensitiveContains(candidate))
      }
  }
  ```

- [x] Add the four colors using light values #F9FBF9, #1B2928, #205E50 and #DCE3DD respectively. Resolve to system background, label, a lighter green, and separator in dark appearance. Use these in Inventory and apply the shared action tint at the root.
- [x] Replace the inset groups with a plain divided list. Compose the small diagonal mark and SpaceFind wordmark above a single leading Inventory title. Keep the native searchable navigation stack and a green circular Add item button. Show “All items” or “Results” using the trimmed query and actual result count, including zero. Preserve both empty messages.
- [x] In `InventoryRow`, display a report only when exactly one exists. Use its photo and full location. For multiple reports show a neutral placeholder and “Needs confirmation”. For zero reports use the existing missing-location copy. Append “Waiting to sync” independently. Use the spec's geometry, semibold name and high-contrast location. Allow wrapping and stack the text under the photo at accessibility sizes.
- [x] Run the rehearsal. Then create two items with the same label and different photos/locations. Search, open each by its own row, and confirm identity. At default and accessibility sizes in light and dark, read “Blue pouch beside the workbench” in the list and try a longer location. Verify zero matches, clearing search, the count, and the Add item hit area.
- [x] Commit the passing inventory, theme, thumbnail-radius, root-tint, and test changes as one reviewable change.

### Task 2 — Carry the photo treatment through detail, confirmation, and editing

**Interfaces.** In ItemEditor.swift add `contentMode: ContentMode = .fill` to `PhotoThumbnail`. The Inventory caller from task 1 retains fill and 8 pt corners. The detail, conflict, and editor callers can now request fit. Keep the existing data, accessibility label, and maximum pixel size parameters.

- [x] Before changing the renderer, open a portrait photo and a wide photo with identifiable features near the edges. Observe the existing fixed-height detail crop. In the first-phone branch of the seeded walkthrough, before tapping the chosen candidate, assert both candidate buttons are available:

  ```swift
  XCTAssertEqual(app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "confirm-")
  ).count, 2)
  ```

- [x] Make the full photo visible on detail and in the editor preview using aspect fit within the available width. Keep thumbnail decoding, placeholder size, clipping, and cancellation behavior. Keep the location directly beneath the detail photo, followed by pending status and description.
- [x] Use equally sized photo-and-location options for conflicts, each with its own “Keep this location” action and existing identifier. Apply the theme, preserve multiline locations and switch to a stacked arrangement when accessibility text needs the width.
- [x] Give editable fields persistent visible labels and preserve existing accessibility names. Keep the current required-photo guidance, preparing state, inline read-only item label on moves, Save eligibility, Cancel, camera permission recovery, library fallback, and failure feedback. Apply the shared colors to these form surfaces.
- [x] Run the rehearsal and repeat the edge-of-frame check. Verify photo placeholders preserve geometry when data is unavailable. Check conflicting report pairs with visibly different photos, then confirm one and verify its location and photo together. At large text sizes inspect a long candidate location. Exercise Add, an unchanged-photo move, replacement-photo move, and Cancel. Verify Save is disabled until the required inputs are ready.
- [x] Commit the detail, editor, thumbnail-mode, and test changes together.

### Task 3 — Finish crew connection screens and verify the workflow

**Interfaces.** Use the colors from task 1 in `CrewRoot` and its existing `pairingForm`. Retain the existing state, sync loop, retry callbacks, and bottom safe-area inset.

- [ ] In the existing `openInventory(_:)` UI-test helper, inside the branch where the secure field is on screen, type the pairing value, then assert `XCTAssertTrue(app.staticTexts["Pairing string"].exists)` before tapping Join. Run the rehearsal with fresh simulators. The placeholder alone should fail the visible-label check after typing.
- [x] Add the persistent pairing label, keep the field secure, and give Join inventory the prominent action style. Keep joining progress, Wi-Fi instructions, errors, startup progress and Try again next to the relevant control. Carry the same styling into Update connection. Allow the bottom notice to wrap above the safe area without obscuring the last row.
- [x] Run the two-phone rehearsal for the complete branch. Run the offline walkthrough from the [demo instructions](../../README.md) with disposable records. Disconnect a joined phone, search, save a move, relaunch, and confirm the last row, Add item, “Waiting to sync”, and Update connection are reachable. Reconnect and verify convergence. Inspect an invalid invite and retry. Check VoiceOver announces name, location or conflict, and pending status in that order, with each action reachable.
- [x] Check both appearances at default and accessibility text sizes on supported iPhone sizes. Record which simulator and physical-device checks actually ran, including camera capture and permission fallback when hardware is available. Commit the connection and test changes. Review the final changes against the brief.

## Verification record — November 15, 2026

| Check | Observed result |
| --- | --- |
| Laptop service | All 13 Python tests passed. |
| Two-phone rehearsal | `scripts/test_demo.py` exited successfully on disposable iPhone 16e and iPhone 17 simulators running iOS 26. All 12 app tests and all three UI walkthroughs passed, with the UI walkthroughs running on each phone. The original list failed the new conflicting-location assertion before the change. |
| Photos and forms | On an iPhone 17 Pro simulator, tested duplicate labels, long locations, an unavailable photo, competing reports, portrait and landscape detail photos, canceling a move, keeping a photo, selecting a replacement, and saving a library photo. Invalid invite and retry passed with the pairing label visible after typing. |
| Offline and reconnection | Stopped the disposable service, recorded a move, relaunched the app and found the cached item by searching. Its accessibility label announced the name, new location, and pending status in that order. Add item, the last row, and Update connection were reachable. Restarting the service cleared pending status and delivered the exact location to the server. A separate move stored the selected replacement photo and its exact location together. |
| Appearance | Inspected native screenshots of Inventory in light and dark appearance at the default and largest accessibility text sizes. At accessibility sizes, the photo sits above the wrapping name and location. At the largest setting in dark appearance, both long conflicting locations were readable through their accessible labels and both confirmation buttons were reachable. |
| Search and Add item | A focused UI check verified the 44 pt minimum hit area, the result count at zero, the no-match message, and the restored all-items count after clearing search. A new form showed the required-photo guidance and disabled Save. |
| Camera | The iPhone 16 saved a real camera photo. The disposable server received a 655,178-byte JPEG paired with the expected location. The test cache was cleared and the normal signed themed build was installed in place. The simulator also exercised camera denial and the library fallback action. |

The preliminary pairing-label test raced app startup before entering a value. Its hierarchy showed only a placeholder; the corrected test waited for app readiness and passed after typing.

The iPhone 14 Plus reached its free provisioning limit during the separate test-app install. Physical camera verification used the iPhone 16. Accessibility order was verified through the iOS accessibility tree. Live VoiceOver audio remains unchecked.
