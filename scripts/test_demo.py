"""Run the laptop + iOS walkthrough on two fresh iPhone simulators."""
import argparse
import base64
import json
import os
from pathlib import Path
import ssl
import subprocess
import sys
import tempfile
import threading
import urllib.request
from uuid import uuid4

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "server"))
from spacefind import create_server


def seed_walkthrough(pairing, folder):
    crew = json.loads(pairing)
    context = ssl.create_default_context(cafile=str(folder / "server-cert.pem"))
    headers = {"Content-Type": "application/json"}

    def post(path, body):
        request = urllib.request.Request(crew["url"] + path, headers=headers,
                                         data=json.dumps(body).encode())
        with urllib.request.urlopen(request, context=context, timeout=10) as reply:
            return json.load(reply)

    token = post("/join", {"invite": crew["invite"]})["token"]
    headers["Authorization"] = "Bearer " + token
    item, initial, chosen = (str(uuid4()) for _ in range(3))
    for index, (report, location, color) in enumerate([
        (initial, "blue pouch", "0 0 255"), (chosen, "locker 2", "255 0 0"),
        (str(uuid4()), "tool bag", "0 255 0")
    ]):
        source, jpeg = folder / "swatch.ppm", folder / "swatch.jpg"
        source.write_text("P3 1 1 255 " + color + "\n")
        subprocess.run(["sips", "-s", "format", "jpeg", source, "--out", jpeg],
                       check=True, stdout=subprocess.DEVNULL)
        change = ({"kind": "move", "parentID": initial} if index else
                  {"kind": "create", "label": "Walkthrough wrench", "description": "12 mm"})
        post("/changes", dict(change, itemID=item, id=report, location=location,
                              photo=base64.b64encode(jpeg.read_bytes()).decode()))
    lost_id = str(uuid4())
    post("/changes", dict(id=str(uuid4()), itemID=lost_id, kind="reportMissing",
                          label="Walkthrough flashlight", location="tool drawer",
                          photo=base64.b64encode(jpeg.read_bytes()).decode()))
    radar_id = str(uuid4())
    post("/changes", dict(id=str(uuid4()), itemID=radar_id, kind="create",
                          label="Radar walk fixture", description="Radar trial target",
                          location="spacefind-radar-v1 1.5 -2.0",
                          photo=base64.b64encode((folder / "swatch.jpg").read_bytes()).decode()))
    unpositioned_id = str(uuid4())
    post("/changes", dict(id=str(uuid4()), itemID=unpositioned_id, kind="create",
                          label="Radar ordinary fixture", description="Unpositioned inventory item",
                          location="tool cabinet",
                          photo=base64.b64encode((folder / "swatch.jpg").read_bytes()).decode()))
    return item, chosen, lost_id, radar_id, unpositioned_id


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("simulators", nargs=2, metavar="UDID")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="spacefind-test-") as temporary:
        folder = Path(temporary) / "crew"
        server = create_server(folder, host="127.0.0.1", port=0, host_name="localhost")
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            item, chosen, lost_id, radar_item, unpositioned_item = seed_walkthrough(server.pairing, folder)
            offline_test = "SpaceFindUITests/CrewWalkthrough/testReadSharedPhotoWithLaptopOffline"
            for index, device in enumerate(args.simulators):
                subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], check=True)
                appearance = "dark" if index else "light"
                subprocess.run(["xcrun", "simctl", "ui", device, "appearance", appearance], check=True)
                subprocess.run(["xcrun", "simctl", "addmedia", device, folder / "swatch.jpg"], check=True)
                env = dict(os.environ, TEST_RUNNER_SPACEFIND_TEST_PAIRING=server.pairing,
                           TEST_RUNNER_SPACEFIND_TEST_ITEM=item,
                           TEST_RUNNER_SPACEFIND_TEST_CHOSEN=chosen,
                           TEST_RUNNER_SPACEFIND_TEST_RADAR_ITEM=radar_item,
                           TEST_RUNNER_SPACEFIND_TEST_UNPOSITIONED_ITEM=unpositioned_item,
                           TEST_RUNNER_SPACEFIND_TEST_APPEARANCE=appearance,
                           TEST_RUNNER_SPACEFIND_TEST_SECOND_PHONE=str(index))
                command = ["xcodebuild", "test", "-project", "ios/SpaceFind.xcodeproj",
                           "-scheme", "SpaceFind", "-parallel-testing-enabled", "NO",
                           "-destination", "platform=iOS Simulator,id=" + device]
                selection = ["-only-testing:SpaceFindUITests"] if index else []
                subprocess.run(command + selection + ["-skip-testing:" + offline_test],
                               cwd=ROOT, env=env, check=True)

        finally:
            server.shutdown()
            thread.join()
            server.server_close()
        command[1] = "test-without-building"
        env["TEST_RUNNER_SPACEFIND_OFFLINE_REPORT_ID"] = lost_id
        subprocess.run(command + ["-only-testing:" + offline_test], cwd=ROOT, env=env, check=True)


if __name__ == "__main__":
    run()
