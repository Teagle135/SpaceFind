# SpaceFind for iPhone

Design proposed for approval on November 15, 2026.

## Purpose

A crew member who needs a tool can look it up on their iPhone, recognize it by its photo, and see the last place someone recorded for it. For example, searching for “wrench” might show a photo of the wrench and the location “blue pouch beside the workbench.” The location comes from the person who put the tool away and can go stale if someone moves it.

## Approaches

The user chose a native iPhone app. It can use the camera and photo library and store the inventory on the device for offline use. Building it requires a Mac with Xcode.

A Home Screen web app would be easier to distribute as a demo link. Its local inventory would depend on browser-managed storage, and clearing website data could erase it.

## Recording an item

The user takes a photo or selects an existing one, gives the item a label, enters its last recorded location in their own words, and can add a description. A successful save adds the item to the inventory. Proposed defaults are one photo per item, a required label and location, and an optional description. Two physical items with the same label can have separate entries.

## Finding and moving an item

Opening SpaceFind shows the saved inventory. Each result shows the label, photo, and last recorded location together. Opening the item also reveals the description. The proposed search matches part of the label, description, or location, ignoring capitalization. An empty search shows all items. If a search has no matches, the user can clear or change it.

When the item moves, the user opens its entry and chooses **Update location**. They enter the new location and can keep or replace the photo. Saving updates that one entry. Canceling leaves the previously saved location and photo intact. The first version keeps only the latest location and skips automatic photo matching. Creating an extra entry on every move could send someone to an outdated location.

## Local storage and failure handling

The inventory belongs to one installation on one iPhone. Store an app-owned copy of each selected photo and its associated data locally so the item still works offline, after relaunch, and if the original library photo is removed. Give each item a stable identity independent of its label. Save the location and any replacement photo together. If saving fails, preserve the previous entry, keep the user's edits available for retry, and explain the failure. If camera access is denied, the user can still choose a library photo.

## Scope and builder decisions

The initial version covers capture, local storage, browse, search, and location updates. Accounts, cross-device sync, location history, and live tracking are outside this version. The builder may choose the local database, image sizing, and screen layout. The deployment target must support the user's iPhone. The exact iOS version can be confirmed before selecting version-dependent APIs.

## Acceptance check

1. With the phone offline, create a wrench using a photo, a label, a description, and the location “blue pouch beside the workbench.” Relaunch and confirm the entry is present.
2. Find it by part of its label, description, and location. Confirm the result includes its photo and the blue-pouch location.
3. Move it to “red pouch near the hatch” while keeping the original photo. Confirm the same entry now shows the new location and the old location no longer matches.
4. Start another move with a replacement photo and cancel. Confirm the saved entry is intact. Repeat and save, then relaunch and confirm the new photo and location persisted together.
5. Add a second wrench with the same label. Update one and confirm the other keeps its own location and photo.
