# SpaceFind appearance — Photo index

Design for review, November 15, 2026.

## Intent and scope

A crew member should be able to recognize a tool and read its last recorded location in one glance at Inventory. The user chose a professional crew tool with a subtle spacecraft identity. Apply the chosen appearance to the native iPhone app, from joining an inventory through resolving a disputed location. The existing demo design governs search, capture, offline storage, pairing, and synchronization.

## Approaches

- **A · Photo index, selected by the user.** Generous thumbnails form a consistent left column. The item name and location sit together on the right. Taller rows trade some list density for easier recognition, particularly when two tools have the same label.
- **B · Location index.** Compact thumbnails and smaller item labels leave room for a bold location. More entries fit on screen, but a crew member identifying a tool by sight gets a smaller image.

## Inventory

Use the selected light mockup as the reference. A small SpaceFind wordmark and simple diagonal mark sit above the left-aligned Inventory title. Search and Add item stay near the top. Give Add item its green circular treatment and a minimum 44-point hit area. Above the list, show “All items” and the real item count. During a search, label this group “Results” and count the matches. Keep the existing native search behavior.

Use a single list with fine dividers. At default text size start with a 100 × 72 pt photo, an 8 pt corner radius, roughly 12 pt between photo and text, and 16 pt side margins. Align the item name and location to the same left edge. Use a semibold headline for the name and high-contrast, regular body or subheadline text for the location. Give the location enough space to read “Blue pouch beside the workbench” in full. Rows grow for longer text. At accessibility text sizes, let text use the full row width below the photo when needed.

Use the crew’s actual photo. Crop the thumbnail consistently and allow the full photo to be seen on the detail screen. While a thumbnail decodes or if it is unavailable, keep its space and use the existing photo placeholder. A photo and a location presented together must always come from the same report.

## Appearance across the app

The proposed light palette follows A’s near-white surface (#F9FBF9), charcoal text (#1B2928), muted green action tint (#205E50), and fine gray-green dividers (#DCE3DD). Use native system text styles, familiar symbols, and system transitions. Keep motion quiet while the crew scans a list. Follow the iPhone appearance setting. In dark appearance use system dark surfaces and primary text with a lighter green action tint. Keep warning symbols and wording legible in both appearances. The small wordmark and disciplined alignment carry the spacecraft identity.

| Surface | Treatment |
| --- | --- |
| Join and reconnect | Give the crew invite form a visible pairing-string label and one prominent join action. Keep Wi-Fi guidance, progress, retry, and errors close to the relevant action. |
| Item detail | Show the photo first, with the recorded location directly beneath it. Description follows. Keep Update location in its familiar toolbar position. |
| Add item and update location | Use persistent field labels, clear required-photo feedback, and the same photo treatment. Keep the existing camera, library, Save, and Cancel actions and their enabled states. Keep progress and errors readable while editing. |
| Empty inventory and empty search | Retain their distinct messages and next steps. Keep Search and Add item accessible. |
| Offline and pending | Keep the connection message and Update connection action separate from the list rows. Put the sync symbol and “Waiting to sync” below the affected item's location. Leave ordinary rows free of status badges. |
| Conflicting reports | In the list, show the item name, a neutral thumbnail placeholder, and “Needs confirmation” where the location normally appears. This avoids implying the first report is confirmed. On detail, show every candidate as an equally weighted photo-and-location pair with its own Keep this location action. A pending status may coexist with a conflict. |

## Builder decisions and checks

Matching system dark appearance, emphasizing location through contrast, and extending A to the supporting screens are proposed design decisions. The builder can tune exact sizes and adaptive colors for legibility on the supported iPhones. Use the existing SwiftUI views and iOS 16 deployment target. Keep the browser study’s sample equipment, simulated phone frame, status bar and home indicator out of the app layout. Use native controls and preserve VoiceOver labels, reading order, and existing UI-test identifiers.

Review a populated list at default and accessibility text sizes in both appearances. Find the wrench and read its location without opening it. Try two items with the same name, a long location, a pending item, and a conflict. Check that candidate photos stay paired with their locations. Walk through joining, adding a photo, updating a location, and the existing offline and confirmation flows. Verify that Add item and the final list row remain reachable when the connection notice is visible.
