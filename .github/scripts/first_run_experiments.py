#!/usr/bin/env python3
"""A Linux machine's first install on an iPhone, as far as it goes with no iPhone (B-407).

Runs in a throwaway container with libimobiledevice's usbmuxd and tools, and fake_device.py in place
of an iPhone; nomac runs on the host and reaches both through loopback-only published ports.
Everything is self-generated; no account, no device, nothing from the owner.

- csr: `nomac signing request`'s request against `openssl req -new` of the same key, on the host's
  OpenSSL and the container's.
- usbmuxd-records: what the real usbmuxd answers to ReadBUID, SavePairRecord, ReadPairRecord and
  DeletePairRecord, and `nomac device list` through a forward of its socket.
- usbmuxd-states: the socket with no daemon, with a stopped daemon, and without write permission.
- pair-reference: libimobiledevice's `idevicepair pair` against the fake: the requests and the record.
- pair-*: `nomac device pair` against the fake: the same requests, each answer of the Trust dialog,
  and a record libimobiledevice's tools can use, and the reverse.
- developer-mode-*, session-*: nomac's messages for Developer Mode off and a lost pairing.
- --distributions: for each Linux distribution's image, the package, where it puts usbmuxd, how its
  service starts it, and what SavePairRecord answers.

Each case prints PASS or FAIL with what was seen; the facts go to --output as JSON.
"""
import argparse
import json
import os
import plistlib
import subprocess
import tempfile
import time

CONTAINER = "nomac-first-run"
UDID = "00008140-00FACE00FACE001E"
FAKE_PORT = 27115
MUX_PORT = 27116
FAILED = []
FACTS = {}


def docker(*arguments, check=True, detach=False):
    command = ["docker", "exec"] + (["-d"] if detach else []) + [CONTAINER] + list(arguments)
    return subprocess.run(command, capture_output=True, text=True, check=check)


def shell(script, check=False):
    return docker("sh", "-c", script, check=check)


def expect(case, condition, seen=""):
    print(f"{'PASS' if condition else 'FAIL'} {case}" + (f": {seen}" if seen else ""))
    if not condition:
        FAILED.append(case)


class Tools:
    def __init__(self, nomac):
        self.nomac = nomac

    def run(self, *arguments, address=f"127.0.0.1:{FAKE_PORT}"):
        environment = {**os.environ, "USBMUXD_SOCKET_ADDRESS": address}
        return subprocess.run([self.nomac, *arguments], capture_output=True, text=True, env=environment)


def fake(*options):
    shell("kill $(cat /tmp/fake.pid) 2>/dev/null; rm -f /tmp/fake.log; true")
    docker("sh", "-c", "echo $$ > /tmp/fake.pid; exec python3 -I /scripts/fake_device.py --listen 0.0.0.0:%d --udid %s --log /tmp/fake.log %s" % (FAKE_PORT, UDID, " ".join(options)), detach=True)
    for _ in range(100):
        if docker("python3", "-c", f"import socket;socket.create_connection(('127.0.0.1',{FAKE_PORT}),1)", check=False).returncode == 0:
            return
        time.sleep(0.2)
    raise SystemExit("the fake device did not start")


def log():
    text = shell("cat /tmp/fake.log").stdout
    return [json.loads(line) for line in text.splitlines()]


def libimobiledevice(script):
    return shell(f"USBMUXD_SOCKET_ADDRESS=127.0.0.1:{FAKE_PORT}; export USBMUXD_SOCKET_ADDRESS; {script}")


def ask_usbmuxd(message):
    script = """
import plistlib, socket, struct, sys
message = plistlib.loads(sys.stdin.buffer.read())
connection = socket.socket(socket.AF_UNIX)
connection.connect("/var/run/usbmuxd")
body = plistlib.dumps({"ClientVersionString": "x", "ProgName": "x", "kLibUSBMuxVersion": 3, **message})
connection.sendall(struct.pack("<IIII", 16 + len(body), 1, 8, 1) + body)
length = struct.unpack("<IIII", connection.recv(16))[0]
data = b""
while len(data) < length - 16:
    data += connection.recv(length - 16 - len(data))
sys.stdout.buffer.write(data)
"""
    result = subprocess.run(["docker", "exec", "-i", CONTAINER, "python3", "-I", "-c", script], input=plistlib.dumps(message), capture_output=True, check=True)
    return plistlib.loads(result.stdout)


def csr(tools):
    with tempfile.TemporaryDirectory(prefix="nomac-csr-") as folder:
        made = subprocess.run([tools.nomac, "signing", "request", "--output-directory", folder], capture_output=True, text=True)
        expect("csr: nomac signing request", made.returncode == 0, made.stderr.strip()[:200])
        key = os.path.join(folder, "development.key")
        expect("csr: the key is readable only by its owner", oct(os.stat(key).st_mode)[-3:] == "600")
        ours = open(os.path.join(folder, "development.csr"), "rb").read()
        host = subprocess.run(["openssl", "req", "-new", "-key", key, "-subj", "/CN=nomac development/C=US"], capture_output=True, check=True).stdout
        version = subprocess.run(["openssl", "version"], capture_output=True, text=True).stdout.strip()
        expect(f"csr: same bytes as {version}", ours == host)
        subprocess.run(["docker", "cp", key, f"{CONTAINER}:/tmp/csr.key"], check=True, capture_output=True)
        container = docker("openssl", "req", "-new", "-key", "/tmp/csr.key", "-subj", "/CN=nomac development/C=US").stdout.encode()
        version = docker("openssl", "version").stdout.strip()
        shell("rm -f /tmp/csr.key")
        expect(f"csr: same bytes as {version}", ours == container)
        again = subprocess.run([tools.nomac, "signing", "request", "--output-directory", folder], capture_output=True, text=True)
        expect("csr: a second request refuses to replace the first", again.returncode != 0 and "already exists" in again.stderr, again.stderr.strip()[:120])


def usbmuxd_records(tools):
    shell("usbmuxd -U usbmux >/dev/null 2>&1; sleep 1")
    record = plistlib.dumps({"HostID": "H", "SystemBUID": "B", "HostCertificate": b"c", "HostPrivateKey": b"k"})
    facts = {"version": shell("usbmuxd -V").stdout.strip(), "socket mode": shell("stat -c %a /var/run/usbmuxd").stdout.strip()}
    facts["ListDevices"] = ask_usbmuxd({"MessageType": "ListDevices"})
    facts["ReadBUID keys"] = sorted(ask_usbmuxd({"MessageType": "ReadBUID"}))
    facts["ReadPairRecord missing"] = ask_usbmuxd({"MessageType": "ReadPairRecord", "PairRecordID": UDID}).get("Number")
    facts["SavePairRecord"] = ask_usbmuxd({"MessageType": "SavePairRecord", "PairRecordID": UDID, "PairRecordData": record}).get("Number")
    facts["read back the same"] = ask_usbmuxd({"MessageType": "ReadPairRecord", "PairRecordID": UDID}).get("PairRecordData") == record
    facts["SavePairRecord no data"] = ask_usbmuxd({"MessageType": "SavePairRecord", "PairRecordID": UDID}).get("Number")
    facts["Connect unknown device"] = ask_usbmuxd({"MessageType": "Connect", "DeviceID": 9, "PortNumber": 32498}).get("Number")
    facts["DeletePairRecord"] = ask_usbmuxd({"MessageType": "DeletePairRecord", "PairRecordID": UDID}).get("Number")
    facts["DeletePairRecord again"] = ask_usbmuxd({"MessageType": "DeletePairRecord", "PairRecordID": UDID}).get("Number")
    FACTS["usbmuxd-records"] = facts
    print("usbmuxd-records:", facts)
    expect("usbmuxd-records: a saved record reads back whatever the Result says", facts["read back the same"])
    docker("sh", "-c", f"exec socat TCP-LISTEN:{MUX_PORT},fork,reuseaddr UNIX-CONNECT:/var/run/usbmuxd", detach=True)
    time.sleep(1)
    listed = tools.run("device", "list", address=f"127.0.0.1:{MUX_PORT}")
    expect("usbmuxd-records: nomac device list with no device", listed.returncode == 0 and listed.stdout == "" and "no device at all" in listed.stderr, listed.stderr.strip())
    status = tools.run("device", "status", "--device", UDID, address=f"127.0.0.1:{MUX_PORT}")
    expect("usbmuxd-records: nomac device status with no device", status.returncode != 0 and "usbmuxd sees no device" in status.stderr, status.stderr.strip().replace("\n", " | "))
    shell("pkill socat; true")


def usbmuxd_states():
    probe = "import errno,socket\ntry:\n    socket.socket(socket.AF_UNIX).connect('/var/run/usbmuxd')\n    print('connects')\nexcept OSError as error:\n    print(errno.errorcode[error.errno])\n"
    subprocess.run(["docker", "exec", "-i", CONTAINER, "sh", "-c", "cat > /tmp/connect.py"], input=probe, text=True, check=True)
    connect = "python3 -I /tmp/connect.py"
    facts = {"running": shell(connect).stdout.strip()}
    shell("pkill -9 usbmuxd; sleep 0.5")
    facts["killed: socket left"] = shell("test -e /var/run/usbmuxd && echo yes || echo no").stdout.strip()
    facts["killed"] = shell(connect).stdout.strip()
    shell("chmod 600 /var/run/usbmuxd")
    facts["mode 600, another user"] = shell(f"su -s /bin/sh nobody -c '{connect}'").stdout.strip()
    shell("rm -f /var/run/usbmuxd /var/run/usbmuxd.pid")
    facts["no daemon"] = shell(connect).stdout.strip()
    FACTS["usbmuxd-states"] = facts
    print("usbmuxd-states:", facts)
    expect("usbmuxd-states: no daemon is ENOENT, a stopped one ECONNREFUSED, no permission EACCES",
           facts["no daemon"] == "ENOENT" and facts["killed"] == "ECONNREFUSED" and facts["mode 600, another user"] == "EACCES")


def record_keys(entries):
    return [entry["saved_keys"] for entry in entries if "saved_keys" in entry]


def pair_entries(entries):
    return [entry for entry in entries if "pair_answer" in entry]


def lockdown_requests(entries, before="Pair"):
    names = []
    for entry in entries:
        if entry.get("side") == "lockdownd" and entry.get("request"):
            names.append((entry["request"], entry["message"].get("Key")))
            if entry["request"] == before:
                break
    return names


def pair_reference():
    fake("--pair", "pending,locked,ok")
    answers = [libimobiledevice(f"idevicepair -u {UDID} pair 2>&1 | tail -1").stdout.strip() for _ in range(3)]
    entries = log()
    pairs = pair_entries(entries)
    FACTS["pair-reference"] = {"answers": answers, "requests": lockdown_requests(entries), "record": sorted(pairs[-1]["pair_record"]),
                               "others": pairs[-1]["others"], "protocol": pairs[-1]["protocol"], "options": pairs[-1]["options"], "saved": record_keys(entries)[-1]}
    print("pair-reference:", FACTS["pair-reference"])
    expect("pair-reference: idevicepair pairs after the dialog and the lock", "SUCCESS" in answers[-1], answers[-1][:80])


def pair_with_nomac(tools):
    reference = FACTS["pair-reference"]
    fake("--pair", "pending,locked,ok")
    paired = tools.run("device", "pair", "--device", UDID)
    expect("pair: nomac device pair", paired.returncode == 0 and paired.stdout.strip().endswith(f"paired with {UDID}"), paired.stdout.strip().replace("\n", " | ") + paired.stderr.strip()[:300])
    expect("pair: says to tap Trust, then to unlock", "tap Trust" in paired.stdout and "unlock" in paired.stdout)
    entries = log()
    pairs = pair_entries(entries)
    last = pairs[-1]
    expect("pair: asks what idevicepair asks, in order", [name for name in lockdown_requests(entries)][:3] == [name for name in reference["requests"] if name != ("QueryType", None)][:3],
           str(lockdown_requests(entries)))
    expect("pair: the same PairRecord fields", sorted(last["pair_record"]) == reference["record"], str(sorted(last["pair_record"])))
    expect("pair: the same request fields and options", last["others"] == reference["others"] and last["protocol"] == reference["protocol"] and last["options"] == reference["options"])
    expect("pair: the same fields kept in the record", record_keys(entries)[-1] == reference["saved"], str(record_keys(entries)[-1]))
    chain = last["chain"]
    expect("pair: the root's key signed the root's, the host's and the device's certificates", chain["RootCertificate"] and chain["HostCertificate"] and chain["DeviceCertificate"])
    expect("pair: the device's certificate holds the device's key", chain["DeviceCertificate holds the device's key"])
    FACTS["pair-certificates"] = {name: chain[name] for name in ["RootCertificate text", "HostCertificate text", "DeviceCertificate text"]}
    sessions = [entry for entry in entries if "tls" in entry]
    expect("pair: the session's TLS presents a certificate of the pair and proves its key", any(entry["client_certificate"] for entry in sessions), str(sessions[-1:]))
    again = tools.run("device", "pair", "--device", UDID)
    expect("pair: a second run finds the pairing", again.stdout.strip() == f"already paired with {UDID}", again.stdout.strip())
    used = libimobiledevice(f"ideviceinfo -u {UDID} -k ProductVersion; idevicepair -u {UDID} validate")
    expect("pair: libimobiledevice's tools use nomac's record", "27.0.1" in used.stdout and "SUCCESS" in used.stdout, used.stdout.strip().replace("\n", " | ")[:120])


def libimobiledevice_record(tools):
    fake("--pair", "ok")
    libimobiledevice(f"idevicepair -u {UDID} pair")
    status = tools.run("device", "status", "--device", UDID)
    expect("pair-reverse: nomac reads libimobiledevice's binary record and starts a session", "lockdown: paired, session started" in status.stdout, status.stdout.strip().replace("\n", " | ")[:200])


def pair_answers(tools):
    fake("--pair", "denied")
    denied = tools.run("device", "pair", "--device", UDID)
    expect("pair-denied: says what to do", denied.returncode != 0 and "UserDeniedPairing" in denied.stderr and "Reset Location & Privacy" in denied.stderr, denied.stderr.strip().replace("\n", " | ")[:260])
    fake("--pair", "pending")
    waited = tools.run("device", "pair", "--device", UDID, "--timeout", "2")
    expect("pair-timeout: stops with the next step", waited.returncode != 0 and "did not answer the pairing in 2 seconds" in waited.stderr, waited.stderr.strip().replace("\n", " | ")[:240])
    fake("--pair", "ok")
    unpaired = tools.run("device", "status", "--device", UDID)
    expect("session-unpaired: nomac device status names nomac device pair", unpaired.returncode != 0 and "nomac device pair" in unpaired.stderr, unpaired.stderr.strip().replace("\n", " | ")[:240])
    libimobiledevice(f"idevicepair -u {UDID} pair")
    forget(UDID)
    lost = tools.run("device", "status", "--device", UDID)
    expect("session-lost: a device that forgot this host names nomac device pair", lost.returncode != 0 and "InvalidHostID" in lost.stderr and "nomac device pair" in lost.stderr, lost.stderr.strip().replace("\n", " | ")[:240])
    repaired = tools.run("device", "pair", "--device", UDID)
    expect("session-lost: nomac device pair pairs again", repaired.stdout.strip() == f"paired with {UDID}", repaired.stdout.strip()[:120])
    fake("--pair", "ok", "--session-error", "PasswordProtected")
    libimobiledevice(f"idevicepair -u {UDID} pair")
    locked = tools.run("device", "status", "--device", UDID)
    expect("session-locked: says to unlock", locked.returncode != 0 and "the device is locked" in locked.stderr, locked.stderr.strip().replace("\n", " | ")[:200])


def forget(udid):
    subprocess.run(["docker", "exec", "-i", CONTAINER, "python3", "-I", "-c",
                    f"import plistlib,socket,struct;b=plistlib.dumps({{'MessageType':'FakeForgetHosts'}});c=socket.create_connection(('127.0.0.1',{FAKE_PORT}));c.sendall(struct.pack('<IIII',16+len(b),1,8,1)+b);c.recv(4096)"], check=True)


def developer_mode(tools):
    for options, name in [([], "plain"), (["--service-tls"], "tls")]:
        fake("--pair", "ok", "--developer-mode", "off", *options)
        tools.run("device", "pair", "--device", UDID)
        status = tools.run("device", "status", "--device", UDID)
        expect(f"developer-mode-off-{name}: nomac device status stops with the way on", status.returncode != 0 and "Developer Mode is off" in status.stderr and "developer-mode --device" in status.stderr,
               status.stderr.strip().replace("\n", " | ")[:260])
        reveal = tools.run("device", "developer-mode", "--device", UDID)
        actions = [entry["message"] for entry in log() if entry.get("side") == "service"]
        expect(f"developer-mode-off-{name}: nomac device developer-mode shows the row", reveal.returncode == 0 and actions == [{"action": 0}], reveal.stdout.strip().replace("\n", " | ")[:200] + reveal.stderr.strip()[:200])
    fake("--pair", "ok", "--developer-mode", "on")
    tools.run("device", "pair", "--device", UDID)
    on = tools.run("device", "developer-mode", "--device", UDID)
    expect("developer-mode-on: says it is on and sends nothing", on.stdout.strip() == "Developer Mode is on" and not [entry for entry in log() if entry.get("side") == "service"], on.stdout.strip())
    status = tools.run("device", "status", "--device", UDID)
    expect("developer-mode-on: nomac device status goes on to the image", "Developer Mode: enabled" in status.stdout and "Developer Disk Image: not mounted" in status.stdout, status.stdout.strip().replace("\n", " | ")[:300])


def nothing_answers(tools):
    closed = tools.run("device", "list", address="127.0.0.1:9")
    expect("no-usbmuxd: a forward not running says so", closed.returncode != 0 and "USBMUXD_SOCKET_ADDRESS" in closed.stderr, closed.stderr.strip().replace("\n", " | ")[:200])
    missing = tools.run("device", "list", address="UNIX:/tmp/nomac-no-such-socket")
    expect("no-usbmuxd: a missing socket says so", missing.returncode != 0, missing.stderr.strip().replace("\n", " | ")[:200])


DISTRIBUTION_PROBE = """
import os, plistlib, re, socket, subprocess, time
SOCKET = "/var/run/usbmuxd"
def ask(message):
    connection = socket.socket(socket.AF_UNIX)
    connection.connect(SOCKET)
    body = plistlib.dumps({"ClientVersionString": "x", "ProgName": "x", "kLibUSBMuxVersion": 3, **message})
    connection.sendall(__import__("struct").pack("<IIII", 16 + len(body), 1, 8, 1) + body)
    length = __import__("struct").unpack("<IIII", connection.recv(16))[0]
    data = b""
    while len(data) < length - 16:
        data += connection.recv(length - 16 - len(data))
    return plistlib.loads(data)
def run(command):
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    return (result.stdout + result.stderr).strip()
unit = run("cat /usr/lib/systemd/system/usbmuxd.service /lib/systemd/system/usbmuxd.service 2>/dev/null | grep -m1 ExecStart")
user = re.search(r"--user (\\S+)", unit)
facts = {"binaries": [path for path in ["/usr/sbin/usbmuxd", "/usr/bin/usbmuxd", "/sbin/usbmuxd"] if os.path.isfile(path)], "version": run("usbmuxd -V"), "unit": unit,
         "udev rule": run("ls /usr/lib/udev/rules.d /lib/udev/rules.d 2>/dev/null | grep -m1 usbmuxd")}
daemon = subprocess.Popen("usbmuxd --user %s --systemd" % (user.group(1) if user else "usbmux"), shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(2)
facts["service mode stays up with no device"] = daemon.poll() is None
if os.path.exists(SOCKET):
    udid = "00008140-00FACE00FACE001E"
    record = plistlib.dumps({"HostID": "H", "SystemBUID": "B", "HostCertificate": b"c", "HostPrivateKey": b"k"})
    facts["ReadPairRecord missing"] = ask({"MessageType": "ReadPairRecord", "PairRecordID": udid}).get("Number")
    facts["SavePairRecord"] = ask({"MessageType": "SavePairRecord", "PairRecordID": udid, "PairRecordData": record}).get("Number")
    facts["read back the same"] = ask({"MessageType": "ReadPairRecord", "PairRecordID": udid}).get("PairRecordData") == record
    facts["socket mode"] = oct(os.stat(SOCKET).st_mode)[-3:]
import json
print(json.dumps(facts))
"""


def distributions(chosen, output):
    apt = "apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends usbmuxd python3"
    dnf = "dnf install -y -q usbmuxd python3"
    images = [("ubuntu:22.04", apt), ("ubuntu:24.04", apt), ("ubuntu:25.10", apt), ("debian:12", apt), ("debian:13", apt), ("fedora:42", dnf), ("fedora:43", dnf),
              ("archlinux:latest", "pacman -Sy --noconfirm --disable-sandbox usbmuxd python"), ("opensuse/tumbleweed:latest", "zypper -n install -y usbmuxd python3")]
    results = {}
    for image, install in images:
        if chosen and image not in chosen:
            continue
        name = CONTAINER + "-distribution"
        subprocess.run(["docker", "rm", "-f", name], capture_output=True)
        subprocess.run(["docker", "run", "-d", "--name", name, "--label", "nomac-agent=first-run", image, "sleep", "infinity"], capture_output=True, check=True)
        installed = subprocess.run(["docker", "exec", name, "sh", "-c", install], capture_output=True, text=True)
        probe = subprocess.run(["docker", "exec", name, "python3", "-I", "-c", DISTRIBUTION_PROBE], capture_output=True, text=True)
        subprocess.run(["docker", "rm", "-f", name], capture_output=True)
        results[image] = json.loads(probe.stdout) if probe.returncode == 0 else {"install status": installed.returncode, "failure": (installed.stderr + probe.stderr)[-300:]}
        print(image, results[image], flush=True)
        with open(output, "w") as file:
            json.dump(results, file, indent=2, sort_keys=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", required=True, help="a folder outside the repository")
    parser.add_argument("--nomac", default=".build/debug/nomac")
    parser.add_argument("--image", default="ubuntu:24.04")
    parser.add_argument("--distributions", nargs="*", help="only the distributions' packages: these images, or with none every image")
    arguments = parser.parse_args()
    os.makedirs(arguments.output, exist_ok=True)
    if arguments.distributions is not None:
        distributions(arguments.distributions, os.path.join(arguments.output, "first_run_distributions.json"))
        return
    scripts = os.path.dirname(os.path.abspath(__file__))
    subprocess.run(["docker", "rm", "-f", CONTAINER], capture_output=True)
    subprocess.run(["docker", "run", "-d", "--name", CONTAINER, "--label", "nomac-agent=first-run", "-p", f"127.0.0.1:{FAKE_PORT}:{FAKE_PORT}", "-p", f"127.0.0.1:{MUX_PORT}:{MUX_PORT}",
                    "-v", f"{scripts}:/scripts:ro", arguments.image, "sleep", "infinity"], capture_output=True, check=True)
    try:
        shell("apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends usbmuxd libimobiledevice-utils socat openssl python3 procps", check=True)
        tools = Tools(os.path.abspath(arguments.nomac))
        FACTS["versions"] = shell("dpkg-query -W usbmuxd libimobiledevice-utils libusbmuxd6 libplist-2.0-4 libplist3 2>/dev/null").stdout.split("\n")
        csr(tools)
        usbmuxd_records(tools)
        usbmuxd_states()
        pair_reference()
        pair_with_nomac(tools)
        libimobiledevice_record(tools)
        pair_answers(tools)
        developer_mode(tools)
        nothing_answers(tools)
    finally:
        subprocess.run(["docker", "rm", "-f", CONTAINER], capture_output=True)
    with open(os.path.join(arguments.output, "first_run_experiments.json"), "w") as file:
        json.dump(FACTS, file, indent=2, sort_keys=True, default=lambda value: value.decode("latin1"))
    print(f"{len(FAILED)} failed" + (f": {FAILED}" if FAILED else ""))
    raise SystemExit(1 if FAILED else 0)


if __name__ == "__main__":
    main()
