# Shared lost-item reports

SpaceFind for iPhone · November 15, 2026 · Design for review

A crew member who loses a torque wrench can tell the whole crew where to start looking. Whoever finds it can close the search and tell everyone where it turned up. The report can describe any item, including one that has never been in inventory.

## Approaches

The crew chose **shared lost-item reports**. Each report describes one search and has its own identity. Opening or closing a report makes no change to inventory, even when its name matches a catalogued item. The tradeoff is that someone looking up a wrench in inventory goes to Lost items to check for an open search.

The alternative was to track **Missing** and **Found** on inventory entries. A catalogued tool would have one place for both kinds of information, but reporting an uncatalogued item would create a permanent inventory entry. The crew wants to report a missing personal item without cataloguing it.

## Reporting and finding an item

The approved mockups show two crew members’ views of the same report. On a phone, each member uses the same two actions.

1. **Report a missing item.** Enter **Item name** and **Where was it last seen?**. Optionally take a photo or choose one from the library. **Report missing item** saves the report as **Missing**. A name and location are sufficient. Treat whitespace-only text as empty. If saving fails, keep the form and its contents available for retry.
2. **Mark as found.** Any joined member can open a missing report, see the name, **Last seen** location and optional photo, enter **Where did you find it?**, and tap **Mark as found**. Require a nonblank location. Dismissing the form before saving leaves the search open.
3. **Read the outcome.** Once shared, the report shows **Found** to every joined member. Keep the original **Last seen** and the new **Found at** location together with the original photo, if supplied. For the wrench, that might read “Last seen — beside the workbench” and “Found at — locker 2.” A found report is closed. If the same item goes missing again, start a new report.

## Proposed navigation and sync behavior

These details extend the two approved forms and are proposed for review.

- Give joined members a **Lost items** destination alongside **Inventory**. Offer **Report a missing item** even when the list is empty. Group reports under **Missing** and **Found**, with open searches first. Each row shows the item name and the relevant location labelled **Last seen** or **Found at**. Use text for status so it is readable with VoiceOver and independent of color.
- Use the existing crew pairing, laptop service, photo handling and foreground sync. A phone can open or close a report offline, including a report it just created. Save the change and any photo locally before dismissing the form. Show **Waiting to sync** until the laptop acknowledges it. Connected phones see the update on their next sync.
- Give each report a stable ID so two searches for “Torque wrench” can be closed independently. The laptop stores creation and closure durably. Retrying either operation after a lost acknowledgment must have the same effect as sending it once.
- If two phones close the same report offline, keep the first closure the laptop accepts. The other phone shows the accepted **Found at** location and tells its crew member the report was already closed. Clear that superseded change and continue syncing other work. This rule gives the crew one outcome without asking them to reconcile two closed searches.
- Apply the existing crew access and photo size limits to reports. Preserve existing inventory, photos and queued edits when opening old phone caches or upgrading the laptop database. Pending reports have the same protection against switching to a different laptop as pending inventory edits.

The builder can choose the API shape, database layout and Swift types. The scope is filing, sharing, reading and closing a search. Reopening, report editing, notifications and inventory linking are outside this design.

## Acceptance checks

1. From an empty Lost items list, phone A reports “Torque wrench”, last seen “beside the workbench”, without a photo. Phone B sees one **Missing** report after sync. The inventory on both phones has the same entries as before. Repeat with a photo and verify B can view it.
2. On B, a blank found location cannot close the report. Enter “locker 2” and mark it found. Both phones show **Found**, the original last-seen location and the found location. A second open report with the same name stays missing.
3. Create and close a report on A while offline. Relaunch before reconnecting. The report and pending state survive. After reconnection, both phones show one closed report with both locations. Restart the laptop and verify the report is still available.
4. Close a shared report independently on two offline phones using different locations. Reconnect one at a time. Both phones show the first accepted location, the second crew member sees the explanation, and later queued changes sync. A replay of the accepted closure succeeds without a conflict.
