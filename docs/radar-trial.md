# SpaceFind Radar Trial

The finder tries to stop within **2.0 metres of where the photographer stood** using only the two dots. Run this on one level, using two iPhones and a stationary MacBook. Bring a tape measure and tape for marking positions. The estimated distance on the phone is not a physical measurement.

## Before the first walk

1. Install the trial build from this branch on both phones. In Xcode select the SpaceFind scheme and your development team, then run on each phone. Its separate bundle identifier is `org.spacefind.radartrial`.
2. Keep both phones and the MacBook on the same local network. Both demo phones are already paired. If the MacBook service needs restarting, run the following from the trial worktree, using its Wi-Fi address on the demo network. Keep the same data directory to reuse its credentials and photos.

   ```sh
   python3 server/spacefind.py --host-name "$(ipconfig getifaddr en0)" --data-dir .spacefind/radar-trial --port 8444
   ```

3. Paste the trial server's private pairing string into the trial app on each phone and join. Allow local network access and Motion & Fitness on both. Only the photographer needs camera permission.
4. Place a plain strip of tape at the shared starting spot in front of the stationary MacBook. On the **Radar** tab, tap **Start radar at MacBook** from that exact spot. Hold the phone flat, screen up, with its top edge pointing toward the centre of the MacBook screen. Wait for **Ready — waiting for first steps** before leaving. The two starts may happen at different times. Keep the app in the foreground throughout each walk. If tracking is interrupted or the crew dot stays frozen while walking, log the interruption and return to the origin to restart.

## Run one walk

1. Start the photographer at the origin. Follow the marked route while holding the phone consistently with its top edge toward the direction of travel. At the destination, stop; wait for the estimate to settle. Mark the photographer's standing spot discreetly. In **Capture a target**, watch the current estimate settle, tap **Take target photo**, then **Take photo** and **Save target**. When the app shows **Synced**, give the finder the target label.
2. Start the finder at the same origin. Walk a different approach with at least one turn. Tap **Find a target** during the walk and select the shared target. The filled blue dot marks the finder and the orange ring marks the photo spot. For a blind run, the finder stays on the **Radar** tab until both standing spots have been marked. Trial captures are omitted from **Inventory**. Keep the destination mark and the photographer's route out of the finder's sight.
3. Let the finder choose where to stop using only the radar. Tap **Stop tracking here** and mark the stopping spot before tapping **Reveal photo**. Note the displayed separation, then use the tape to measure the straight-line floor distance between the two standing marks. A second person can do the marking if an otherwise visible mark would reveal the answer.
4. Reset at the origin for the next run and take a fresh photo. Swap phone roles for at least one run. Log interruptions separately and repeat those walks. Keep every completed walk, including misses.

## Measurements

| Walk | Photographer / finder | Route lengths and turns (both paths) | Radar estimate at stop | Tape measurement | Within 2.0 m? |
| --- | --- | --- | --- | --- | --- |
| 1 | iPhone 16 / iPhone 14 Plus (assigned) | | | | Pending |
| 2 | | | | | Pending |
| 3 | | | | | Pending |

Record interrupted attempts and the reason here. A successful three-walk demonstration requires all three completed tape measurements to be at most 2.0 m. The test applies only to the routes, hand positions and phones used.

## Bench check, November 15, 2026

The physical iPhone 16 uploaded a fixture JPEG with coordinates `(-2.125, 4.0)` to a disposable MacBook server. The physical iPhone 14 Plus fetched the same JPEG bytes and coordinates. Both phones reported device-motion and pedometer-distance support and successfully fetched from the walking trial server using their own saved credentials. The fixture was kept out of the inventory used for the three walks.
