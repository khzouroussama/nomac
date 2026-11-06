#!/usr/bin/env python3
"""A scripted iPhone with no iPhone: usbmuxd's and lockdownd's protocols over one TCP port or Unix socket.

Written from libimobiledevice's and pymobiledevice3's sources (docs/formats/lockdown.md) for the
first-run experiments (device_experiments.py `first-run`). libimobiledevice's own tools and nomac
talk to it alike (USBMUXD_SOCKET_ADDRESS), so what each sends can be compared and the pair record one
writes can be read by the other. It proves nothing about what a real iPhone accepts.

--pair is what `Pair` answers, in order, the last repeating: ok, pending, locked, denied. Pair checks
the signatures of the host's and device's certificates against the root's key. The session's TLS
trusts exactly the certificate the client presents, whose key the client proves: libimobiledevice
presents the root and pymobiledevice3 and nomac the host's, and OpenSSL's verifier refuses a
certificate with an empty name as "self-signed" unless it alone is trusted. Every request is
appended to --log as a JSON line.
"""
import argparse
import base64
import json
import os
import plistlib
import socket
import socketserver
import ssl
import struct
import subprocess
import tempfile
import threading

LOCKDOWN_PORT = 62078
SERVICES = {
    "com.apple.amfi.lockdown": 49160,
    "com.apple.mobile.mobile_image_mounter": 49161,
}


def der_elements(data):
    """(start, header length, total length) of the DER elements in `data`."""
    elements = []
    index = 0
    while index < len(data):
        length = data[index + 1]
        header = 2
        if length & 0x80:
            header += length & 0x7f
            length = int.from_bytes(data[index + 2:index + header], "big")
        elements.append((index, header, header + length))
        index += header + length
    return elements


def der_of(pem):
    return base64.b64decode("".join(line for line in pem.decode().splitlines() if not line.startswith("-----")))


def signed_by(certificate_pem, issuer_pem, folder):
    """Whether the issuer's key made the certificate's signature, over the certificate's own TBS bytes."""
    data = der_of(certificate_pem)
    start, header, total = der_elements(data)[0]
    body = data[start + header:start + total]
    parts = der_elements(body)
    tbs = body[parts[0][0]:parts[0][0] + parts[0][2]]
    algorithm = body[parts[1][0]:parts[1][0] + parts[1][2]]
    signature = body[parts[2][0] + parts[2][1] + 1:parts[2][0] + parts[2][2]]
    digest = "-sha256" if b"\x2a\x86\x48\x86\xf7\x0d\x01\x01\x0b" in algorithm else "-sha1"
    paths = {name: os.path.join(folder, name) for name in ["tbs.bin", "signature.bin", "issuer.pem", "issuer.pub"]}
    for name, content in [("tbs.bin", tbs), ("signature.bin", signature), ("issuer.pem", issuer_pem)]:
        with open(paths[name], "wb") as file:
            file.write(content)
    subprocess.run(["openssl", "x509", "-in", paths["issuer.pem"], "-noout", "-pubkey", "-out", paths["issuer.pub"]], check=True, capture_output=True)
    return subprocess.run(["openssl", "dgst", digest, "-verify", paths["issuer.pub"], "-signature", paths["signature.bin"], paths["tbs.bin"]], capture_output=True).returncode == 0


def read_exactly(connection, count):
    data = b""
    while len(data) < count:
        chunk = connection.recv(count - len(data))
        if not chunk:
            return None
        data += chunk
    return data


class Device:
    def __init__(self, arguments):
        self.udid = arguments.udid
        self.buid = "00000000-0000-4000-8000-000000000000"
        self.pair_script = arguments.pair.split(",")
        self.developer_mode = arguments.developer_mode == "on"
        self.session_error = arguments.session_error
        self.service_tls = arguments.service_tls
        self.log_path = arguments.log
        self.folder = tempfile.mkdtemp(prefix="fake-device-")
        self.key_path = os.path.join(self.folder, "device.key")
        subprocess.run(["openssl", "genrsa", "-out", self.key_path, "2048"], check=True, capture_output=True)
        self.public_key = subprocess.run(["openssl", "rsa", "-in", self.key_path, "-RSAPublicKey_out"], check=True, capture_output=True).stdout
        self.records = {}
        self.hosts = {}
        self.revealed = False
        self.lock = threading.Lock()

    def log(self, **fields):
        if not self.log_path:
            return
        with self.lock, open(self.log_path, "a") as file:
            file.write(json.dumps(fields, sort_keys=True, default=lambda value: value.decode("latin1")) + "\n")

    def next_pair_answer(self):
        with self.lock:
            return self.pair_script.pop(0) if len(self.pair_script) > 1 else self.pair_script[0]

    def write(self, name, data):
        path = os.path.join(self.folder, name)
        with open(path, "wb") as file:
            file.write(data)
        return path

    def check_chain(self, record):
        root = self.write("root.pem", record["RootCertificate"])
        results = {"RootCertificate": signed_by(record["RootCertificate"], record["RootCertificate"], self.folder)}
        for name in ["HostCertificate", "DeviceCertificate"]:
            path = self.write(name + ".pem", record[name])
            results[name] = signed_by(record[name], record["RootCertificate"], self.folder)
            results[name + " text"] = subprocess.run(["openssl", "x509", "-in", path, "-noout", "-text", "-certopt", "no_pubkey,no_sigdump"],
                                                     capture_output=True, text=True).stdout
        results["RootCertificate text"] = subprocess.run(["openssl", "x509", "-in", root, "-noout", "-text", "-certopt", "no_pubkey,no_sigdump"],
                                                         capture_output=True, text=True).stdout
        device_public = subprocess.run(["openssl", "x509", "-in", self.write("d.pem", record["DeviceCertificate"]), "-noout", "-pubkey"], capture_output=True).stdout
        mine = subprocess.run(["openssl", "rsa", "-in", self.key_path, "-pubout"], capture_output=True).stdout
        results["DeviceCertificate holds the device's key"] = device_public == mine
        return results


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        device = self.server.device
        connection = self.request
        while True:
            header = read_exactly(connection, 16)
            if not header:
                return
            length, version, message_type, tag = struct.unpack("<IIII", header)
            body = read_exactly(connection, length - 16)
            message = plistlib.loads(body)
            kind = message.get("MessageType")
            device.log(side="usbmuxd", request=kind, header=[version, message_type], fields=sorted(message), progname=message.get("ProgName"))

            def reply(fields):
                data = plistlib.dumps(fields)
                connection.sendall(struct.pack("<IIII", 16 + len(data), 1, 8, tag) + data)

            def result(number):
                reply({"MessageType": "Result", "Number": number})

            attached = {"DeviceID": 1, "MessageType": "Attached",
                        "Properties": {"ConnectionType": "USB", "DeviceID": 1, "SerialNumber": device.udid}}
            if kind == "ListDevices":
                reply({"DeviceList": [attached]})
            elif kind == "Listen":
                result(0)
                reply(attached)
                read_exactly(connection, 1)
                return
            elif kind == "ReadBUID":
                reply({"BUID": device.buid})
            elif kind == "ReadPairRecord":
                record = device.records.get(message.get("PairRecordID"))
                reply({"PairRecordData": record}) if record else result(2)
            elif kind == "SavePairRecord":
                data = message.get("PairRecordData")
                device.log(side="usbmuxd", saved_keys=sorted(plistlib.loads(data)), device_id=message.get("DeviceID"), encoding="XML" if data.lstrip().startswith(b"<?xml") else "binary")
                device.records[message["PairRecordID"]] = data
                result(0)
            elif kind == "DeletePairRecord":
                device.records.pop(message.get("PairRecordID"), None)
                result(0)
            elif kind == "FakeForgetHosts":
                device.hosts.clear()
                result(0)
            elif kind == "Connect":
                port = socket.ntohs(message["PortNumber"])
                if port == LOCKDOWN_PORT:
                    result(0)
                    return Lockdown(device, connection).serve()
                if port in SERVICES.values():
                    result(0)
                    return Service(device, connection, port).serve()
                return result(3)
            else:
                result(1)


class Framed:
    def __init__(self, device, connection):
        self.device = device
        self.connection = connection

    def receive(self):
        header = read_exactly(self.connection, 4)
        if not header:
            return None
        return plistlib.loads(read_exactly(self.connection, struct.unpack(">I", header)[0]))

    def send(self, fields):
        data = plistlib.dumps(fields)
        self.connection.sendall(struct.pack(">I", len(data)) + data)


class Service(Framed):
    def __init__(self, device, connection, port):
        super().__init__(device, connection)
        self.port = port

    def serve(self):
        if self.device.service_tls:
            self.connection = self.device.session_context.wrap_socket(self.connection, server_side=True)
        while True:
            message = self.receive()
            if message is None:
                return
            self.device.log(side="service", port=self.port, message=message)
            if self.port == SERVICES["com.apple.amfi.lockdown"]:
                self.device.revealed = message.get("action") == 0
                self.send({"success": True})
            elif message.get("Command") == "CopyDevices":
                self.send({"EntryList": [], "Status": "Complete"})
            else:
                self.send({"Error": "UnknownCommand"})


class Lockdown(Framed):
    VALUES = {
        "ProductVersion": "27.0.1", "BuildVersion": "27A000", "DeviceClass": "iPhone", "ProductType": "iPhone17,2",
        "WiFiAddress": "00:00:00:00:00:01", "DeviceName": "scripted iPhone", "ActivationState": "Activated",
    }

    def serve(self):
        device = self.device
        while True:
            message = self.receive()
            if message is None:
                return
            request = message.get("Request")
            logged = {key: value for key, value in message.items() if key != "PairRecord"}
            device.log(side="lockdownd", request=request, message=logged)
            if request == "QueryType":
                self.send({"Request": request, "Type": "com.apple.mobile.lockdown"})
            elif request == "GetValue":
                self.get_value(message)
            elif request == "SetValue":
                self.send({"Request": request})
            elif request == "Pair":
                self.pair(message)
            elif request == "StartSession":
                if not self.start_session(message):
                    return
            elif request == "StopSession":
                self.send({"Request": request})
            elif request == "StartService":
                self.start_service(message)
            else:
                self.send({"Request": request, "Error": "UnknownRequest"})

    def get_value(self, message):
        key = message.get("Key")
        domain = message.get("Domain")
        if domain == "com.apple.security.mac.amfi" and key == "DeveloperModeStatus":
            self.send({"Request": "GetValue", "Domain": domain, "Key": key, "Value": self.device.developer_mode})
        elif key == "DevicePublicKey":
            self.send({"Request": "GetValue", "Key": key, "Value": self.device.public_key})
        elif key is None:
            self.send({"Request": "GetValue", "Value": {**self.VALUES, "UniqueDeviceID": self.device.udid, "DevicePublicKey": self.device.public_key}})
        elif key in self.VALUES:
            self.send({"Request": "GetValue", "Key": key, "Value": self.VALUES[key]})
        else:
            self.send({"Request": "GetValue", "Key": key, "Error": "MissingValue"})

    def pair(self, message):
        device = self.device
        record = message.get("PairRecord", {})
        answer = device.next_pair_answer()
        fields = {key: ("data" if isinstance(value, bytes) else value) for key, value in record.items()}
        chain = device.check_chain(record) if "RootCertificate" in record else {}
        device.log(side="lockdownd", pair_answer=answer, pair_record=fields, others=sorted(set(message) - {"PairRecord"}),
                   protocol=message.get("ProtocolVersion"), options=message.get("PairingOptions"), chain=chain)
        errors = {"pending": "PairingDialogResponsePending", "locked": "PasswordProtected", "denied": "UserDeniedPairing"}
        if answer in errors:
            return self.send({"Request": "Pair", "Error": errors[answer]})
        device.hosts[record["HostID"]] = record
        self.send({"Request": "Pair", "EscrowBag": b"scripted escrow bag"})

    def start_session(self, message):
        device = self.device
        if device.session_error:
            self.send({"Request": "StartSession", "Error": device.session_error})
            return True
        record = device.hosts.get(message.get("HostID"))
        if not record:
            self.send({"Request": "StartSession", "Error": "InvalidHostID"})
            return True
        self.send({"Request": "StartSession", "SessionID": "SCRIPTED", "EnableSessionSSL": True})
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.set_ciphers("ALL:@SECLEVEL=0")
        context.load_cert_chain(device.write("session-device.pem", record["DeviceCertificate"]), device.key_path)
        context.verify_mode = ssl.CERT_REQUIRED
        presented = record["HostCertificate"] if message.get("Label") == "nomac" else record["RootCertificate"]
        context.load_verify_locations(cadata=presented.decode())
        device.session_context = context
        try:
            self.connection = context.wrap_socket(self.connection, server_side=True)
        except ssl.SSLError as error:
            device.log(side="lockdownd", tls_failed=str(error))
            return False
        device.log(side="lockdownd", tls=self.connection.version(), client_certificate=bool(self.connection.getpeercert(binary_form=True)))
        return True

    def start_service(self, message):
        port = SERVICES.get(message.get("Service"))
        if port is None:
            return self.send({"Request": "StartService", "Service": message.get("Service"), "Error": "InvalidService"})
        self.send({"Request": "StartService", "Service": message["Service"], "Port": port, "EnableServiceSSL": self.device.service_tls})


class TCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class UnixServer(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--listen", required=True, help="<host>:<port> or UNIX:<path>")
    parser.add_argument("--udid", default="00008140-00FACE00FACE001E")
    parser.add_argument("--pair", default="ok", help="what Pair answers, in order: ok, pending, locked, denied")
    parser.add_argument("--developer-mode", choices=["on", "off"], default="on")
    parser.add_argument("--session-error", help="an error StartSession always answers")
    parser.add_argument("--service-tls", action="store_true", help="services start with a TLS handshake")
    parser.add_argument("--log")
    arguments = parser.parse_args()
    device = Device(arguments)
    if arguments.listen.startswith("UNIX:"):
        path = arguments.listen[5:]
        if os.path.exists(path):
            os.unlink(path)
        server = UnixServer(path, Handler)
        os.chmod(path, 0o666)
    else:
        host, port = arguments.listen.rsplit(":", 1)
        server = TCPServer((host, int(port)), Handler)
    server.device = device
    server.serve_forever()


if __name__ == "__main__":
    main()
