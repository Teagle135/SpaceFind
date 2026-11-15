# SpaceFind for iPhone

First demo design, updated November 15, 2026.

## Purpose and setup

Two crew members share one spacecraft inventory. When one puts away a wrench, the other can search for it and see its photo and last recorded location. The crew supplies the location. If the wrench moves without anyone recording it, its entry can go stale.

For the demo, a laptop stands in for the spacecraft's onboard computer. It hosts the shared database and a service the two native iPhone apps reach over the same Wi-Fi network. The network must allow the phones to reach the laptop. The laptop must be awake and its service running for updates to pass between phones. The entire demo, including joining, works without internet.

## Approaches considered

The chosen native iPhone app supports photo capture, photo-library access, and offline use. A Home Screen web app would be easier to distribute by link, but clearing website data could erase pending offline work.

The laptop holds the authoritative copy of the inventory, including photos. A database confined to one phone would leave the other crew member without the shared record. An internet-hosted database would allow remote access, but phones on a disconnected spacecraft could not exchange updates through it. The laptop-hosted approach lets the crew demonstrate sharing without deploying a cloud service.

## Join, record, and find

The crew lead gives invited members a private code for the spacecraft inventory. Each iPhone joins using the code while connected to the onboard service. The service verifies access before it shares records or accepts changes. Both members can browse, add items, update locations, and resolve conflicting reports.

To record an item, take a photo or choose one from the library, enter a label and location, and optionally add a description. If camera access is denied, the library remains available. Each item has its own identity so two wrenches with the same label can be stored and updated independently. Once synced, the photo and record remain on the laptop even if the original library photo or the phone app is removed.

An empty search shows the inventory. Typing part of a label, description, or location finds matches regardless of capitalization. Each result shows the label, photo, and last recorded location together. Open the item to read its description. To move it, choose **Update location**, enter the new place, and keep or replace its photo. Canceling preserves the existing record.

## Offline use and conflicting moves

Each joined iPhone keeps a local copy of the items and photos it has received. While the laptop is unreachable, the crew can search that copy, add items, and record moves. Saving on the phone preserves pending edits and their photos across relaunch and marks them **Waiting to sync**. A local save failure keeps the form available for retry.

On reconnect, the phone automatically sends its pending changes and fetches shared updates. Other connected phones receive those updates. A retry after an interrupted transfer must neither duplicate an item nor separate its new photo from its location. A pending edit stays on the phone until the service confirms that it has stored the report and its photo.

If two crew members edit the same saved version of an item and independently record different moves, the service preserves both reports regardless of reconnection order. The item is marked as needing confirmation and shows both candidate locations with their associated photos. Either crew member can confirm one report. Both phones then show the confirmed location and photo. Full movement history, live tracking, label editing, and deletion are outside the demo.

The builder may choose the database engine, service interface, and sync mechanism. The iOS deployment target must support both demo phones.

## Demo acceptance checks

1. Disconnect internet access while keeping local Wi-Fi active. Start the laptop service. Join both phones with the crew's private invite code. Verify that an invalid code on an unjoined phone cannot open the inventory.
2. On phone A, add a wrench with a photo, description, and the location “blue pouch beside the workbench.” On phone B, search by part of its label, description, and location. Confirm the photo and the blue-pouch location appear together.
3. Disconnect A from Wi-Fi. Find the wrench offline and move it to “red pouch near the hatch,” keeping the photo. Relaunch A and confirm **Waiting to sync** is still visible. B should still show the blue pouch. Reconnect A. Confirm both phones show the red pouch with the original photo and only one entry for that wrench.
4. Starting with both phones synced, disconnect both. On A, record “locker 2” with a replacement photo. On B, record “tool bag” with the existing photo. Reconnect them one at a time. Confirm both reports are available, select “locker 2,” and verify both phones converge on that location and its replacement photo.
5. Restart the laptop service and rejoin from a fresh app installation on one phone. Verify the shared wrench and its photo can be retrieved from the laptop.
