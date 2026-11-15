# SpaceFind

SpaceFind helps a crew find an item by its photo and last recorded location. Two iPhones share one inventory through a laptop on the same Wi-Fi. The laptop hosts the service locally.

## Start the laptop

On the demo Mac, install Python 3 and make sure `openssl` is on the command path. In the SpaceFind checkout, run:

```sh
python3 server/spacefind.py --host-name "$(scutil --get LocalHostName).local" --data-dir .spacefind --port 8443
```

The first start creates the SQLite database, a private invite, and a TLS certificate and key under `.spacefind/`. Keep this directory to reuse the inventory, credentials, and certificate after a restart. Keep the terminal running and the laptop awake during the demo.

The service prints a pairing string. Share the full string privately with the two crew members, for example via AirDrop. It includes the address, the certificate fingerprint that identifies the laptop, and the invite. Both phones must be on Wi-Fi that allows connections to the laptop. Allow incoming connections if macOS prompts. If the laptop name does not resolve on that network, use the laptop's Wi-Fi IPv4 address as `--host-name` when setting up the demo and share the corresponding pairing string.

## Install and join

1. Open `ios/SpaceFind.xcodeproj` in Xcode. In the SpaceFind app target's **Signing & Capabilities**, select your development team and set a unique bundle identifier if your team requires one.
2. Connect an iPhone, enable Developer Mode if prompted, select it as the run destination, and run the SpaceFind scheme. Repeat for the second iPhone. Use an Xcode version that supports running on each phone. The app's deployment target is iOS 16.
3. Open SpaceFind, paste the laptop's pairing string, and tap **Join inventory**. Allow local network access when prompted. Both phones now use the same database.

## Rehearse with a wrench

1. Keep Wi-Fi running and disconnect its internet uplink. Join both phones. On phone A take or select a wrench photo, add the label “Wrench,” an optional description, and “blue pouch beside the workbench.” Find it on phone B by part of the label or location.
2. Turn off Wi-Fi on A and update the location to “red pouch near the hatch.” Relaunch the app. A shows **Waiting to sync** and B still has the blue pouch. Turn Wi-Fi back on and leave SpaceFind open. Both show the red pouch after sync.
3. Once both phones agree, disconnect both. Move the wrench on A to “locker 2” with a replacement photo. Move it on B to “tool bag” with the original photo. Reconnect one phone at a time. Inspect both reports and confirm one. Both phones should converge on that location and photo.
4. Stop and restart the laptop service with the same command. Once everything has synced, reinstall the app on one demo phone and reconnect to verify that the shared photo and confirmed location are still on the laptop. Removing the app before sync can discard that phone's pending edits.

[Approved design](docs/specs/2026-11-15-spacefind-design.md) · [Implementation plan](docs/plans/2026-11-15-spacefind-demo.md)

## Developer checks

Run `python3 -m unittest discover -s server -v` from the checkout to test the laptop service. For the iPhone and service rehearsal, use two fresh iPhone simulators. List their IDs with `xcrun simctl list devices available`, then run:

```sh
python3 scripts/test_demo.py FIRST_SIMULATOR_UDID SECOND_SIMULATOR_UDID
```

The rehearsal starts a disposable laptop database on loopback, adds a test image to each simulator's library, and exercises the real app and service together. Use the physical walkthrough above to check Wi-Fi reachability, camera capture, and local-network permissions aboard the demo network.

### Verification on November 15, 2026

- Laptop tests cover IPv4 and IPv6 reachability, database restart, replaying a change after a lost acknowledgment, and stale conflict confirmation.
- Xcode 26.0.1, iOS 26.0 simulator runtime: 7 unit and integration tests passed. Both UI tests passed on each of the iPhone 17 Pro and iPhone 17 simulators. They joined the same laptop service, searched the inventory, checked the confirmed location, canceled an edit, and saved a library photo.
- Signed SpaceFind 1.0 ran on an iPhone 16 (iOS 26.6.2, USB development connection) and an iPhone 14 Plus (iOS 27.0.1, wireless development connection). All 7 app tests passed on each phone against the laptop’s local hostname.
- Both phones passed the inventory UI walkthrough. The iPhone 16 confirmed “locker 2” for the test wrench. The iPhone 14 Plus displayed that choice. Both phones’ saved copies matched the laptop’s location and photo bytes, with zero pending edits.
- A crew member captured and saved “Camera check” at “Workbench” on the iPhone 16 and saw it on the iPhone 14 Plus. Both phones stored the same photo bytes and location as the laptop, with zero pending edits.
- A crew member moved “Camera check” to “Red Pouch” offline and reopened SpaceFind on the disconnected iPhone 16. It still showed “Red Pouch” and **Waiting to sync**. After reconnection, both phones and the laptop stored that location and identical photo bytes. Both phone queues were empty.
- After independent offline moves of “Camera check,” the crew saw both locations and selected “Locker 2.” Both iPhones and the laptop held the same replacement photo and confirmed location, with zero pending edits on either phone.
- With the iPhone 16 connected by USB and the Mac and iPhone 14 Plus on an internet-connected hotspot, the 14 Plus received “Locker 3.” Its saved location and photo matched the laptop, and its edit queue was empty. The physical test of sharing over Wi-Fi with the internet uplink disconnected is deferred.
- Fresh-install recovery passed on the iPhone 14 Plus. Before uninstalling, both inventory entries matched the laptop and the phone had zero pending edits. The laptop service was restarted, SpaceFind was reinstalled, and the new app container had no inventory cache before launch. Both entries were recovered with identical IDs, labels, descriptions, locations, and photo bytes. The on-device UI check opened “Camera check” and verified “Locker 3.”
