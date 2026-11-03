#!/usr/bin/env python3
"""Observe the device protocols nomac speaks, and compare nomac's side of them.

Runs against usbmuxd (docs/formats/usbmux.md): macOS's, or libimobiledevice's on Linux
(--socket, B-407). Read-only: no pairing, no trust, no install. The replies are written to the output folder as the shapes of their values (keys and
types), never the identifiers they hold, and each experiment prints a one-line summary.

- usbmux-list: `ListDevices`, with the header fields of the reply.
- usbmux-unknown: a request with an unknown `MessageType`, for usbmuxd's `Result` number.
- usbmux-buid: `ReadBUID`, the host's system BUID.
- usbmux-pair-record: `ReadPairRecord` for --pair-udid, a record planted in usbmuxd's folder
  (on Linux, /var/lib/lockdown/<UDID>.plist), and for a UDID without one.
- nomac-list: `nomac device list` against the same socket, for the same number of devices.
"""
import argparse
import json
import os
import plistlib
import socket
import struct
import subprocess

SOCKET = "/var/run/usbmuxd"


def ask(message, tag):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.connect(SOCKET)
        body = plistlib.dumps(message)
        connection.sendall(struct.pack("<IIII", 16 + len(body), 1, 8, tag) + body)
        header = read(connection, 16)
        length, version, message_type, reply_tag = struct.unpack("<IIII", header)
        return {"version": version, "type": message_type, "tag": reply_tag}, plistlib.loads(read(connection, length - 16))


def read(connection, count):
    data = b""
    while len(data) < count:
        chunk = connection.recv(count - len(data))
        if not chunk:
            raise SystemExit("usbmuxd closed the connection")
        data += chunk
    return data


def shape(value):
    if isinstance(value, dict):
        return {key: shape(item) for key, item in value.items()}
    if isinstance(value, list):
        return [shape(item) for item in value]
    return type(value).__name__


def client(message_type):
    return {"MessageType": message_type, "ClientVersionString": "nomac", "ProgName": "nomac", "kLibUSBMuxVersion": 3}


def main():
    global SOCKET
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", required=True, help="a folder outside the repository")
    parser.add_argument("--nomac", default=".build/debug/nomac")
    parser.add_argument("--socket", default=SOCKET)
    parser.add_argument("--pair-udid", help="a UDID whose pair record usbmuxd holds")
    arguments = parser.parse_args()
    SOCKET = arguments.socket
    os.makedirs(arguments.output, exist_ok=True)
    results = {}

    header, reply = ask(client("ListDevices"), 1)
    results["usbmux-list"] = {"header": header, "reply": shape(reply)}
    print(f"usbmux-list: header {header}, {len(reply.get('DeviceList', []))} devices")

    header, reply = ask(client("nomac-unknown"), 7)
    results["usbmux-unknown"] = {"header": header, "reply": reply}
    print(f"usbmux-unknown: header {header}, reply {reply}")

    header, reply = ask(client("ReadBUID"), 2)
    results["usbmux-buid"] = {"header": header, "reply": shape(reply)}
    print(f"usbmux-buid: header {header}, reply {shape(reply)}")

    if arguments.pair_udid:
        header, reply = ask({**client("ReadPairRecord"), "PairRecordID": arguments.pair_udid}, 3)
        record = plistlib.loads(reply["PairRecordData"]) if isinstance(reply.get("PairRecordData"), bytes) else None
        data = reply.get("PairRecordData", b"")
        encoding = "binary" if data.startswith(b"bplist00") else "XML" if data.lstrip().startswith(b"<?xml") else "other"
        results["usbmux-pair-record"] = {"header": header, "reply": shape(reply), "record": shape(record), "encoding": encoding}
        print(f"usbmux-pair-record: header {header}, reply {shape(reply)}, {encoding} record with keys {sorted(record or [])}")
        header, reply = ask({**client("ReadPairRecord"), "PairRecordID": "nomac-no-such-device"}, 4)
        results["usbmux-pair-record-missing"] = {"header": header, "reply": reply}
        print(f"usbmux-pair-record-missing: header {header}, reply {reply}")

    environment = {key: value for key, value in os.environ.items() if key != "USBMUXD_SOCKET_ADDRESS"}
    if SOCKET != "/var/run/usbmuxd":
        environment["USBMUXD_SOCKET_ADDRESS"] = "UNIX:" + SOCKET
    listed = subprocess.run([arguments.nomac, "device", "list"], capture_output=True, text=True, check=True,
                            env=environment).stdout.splitlines()
    results["nomac-list"] = {"devices": len(listed), "connection types": sorted(line.split("\t")[1] for line in listed)}
    print(f"nomac-list: {len(listed)} devices")

    with open(os.path.join(arguments.output, "device_experiments.json"), "w") as file:
        json.dump(results, file, indent=2, sort_keys=True)


if __name__ == "__main__":
    main()
