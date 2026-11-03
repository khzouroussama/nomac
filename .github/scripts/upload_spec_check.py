#!/usr/bin/env python3
"""Check the App Store Connect requests of `nomac upload` against Apple's OpenAPI specification.

Runs anywhere (no Xcode): `nomac upload <ipa> --dry-run` prints every request it would send,
and each is checked against Apple's public specification of the App Store Connect API
(https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip,
downloaded unless `--spec` names the unzipped `openapi.oas.json`): the path and method exist,
query parameters are the operation's with allowed values, and the JSON body follows the request
schema (required members, no unknown members, types and enumerations). The specification's
version is printed; rerun when Apple publishes a new one.

Usage: upload_spec_check.py <nomac> <ipa> [--spec openapi.oas.json]
"""

import argparse
import json
import re
import subprocess
import sys
import tempfile
import urllib.parse
import zipfile
from pathlib import Path

SPEC_URL = "https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip"
BASE = "https://api.appstoreconnect.apple.com"


def load_spec(path):
    if path:
        return json.loads(Path(path).read_text())
    with tempfile.TemporaryDirectory() as work:
        archive = Path(work) / "spec.zip"
        subprocess.run(["curl", "-sfL", "-o", str(archive), SPEC_URL], check=True)
        with zipfile.ZipFile(archive) as opened:
            name = next(n for n in opened.namelist() if n.endswith(".json") and not n.startswith("__MACOSX"))
            return json.loads(opened.read(name))


def resolve(spec, schema):
    while "$ref" in schema:
        schema = spec["components"]["schemas"][schema["$ref"].split("/")[-1]]
    return schema


def check_value(spec, schema, value, where, problems):
    schema = resolve(spec, schema)
    if "oneOf" in schema or "anyOf" in schema:
        options = schema.get("oneOf") or schema.get("anyOf")
        if not any(not check_value(spec, option, value, where, []) for option in options):
            problems.append(f"{where}: matches none of {len(options)} schemas")
        return problems
    kind = schema.get("type")
    if kind == "object":
        if not isinstance(value, dict):
            return problems + [f"{where}: expected an object"]
        properties = schema.get("properties", {})
        for name in schema.get("required", []):
            if name not in value:
                problems.append(f"{where}: missing required {name}")
        for name, member in value.items():
            if name not in properties:
                problems.append(f"{where}: unknown member {name}")
            else:
                check_value(spec, properties[name], member, f"{where}.{name}", problems)
    elif kind == "array":
        if not isinstance(value, list):
            return problems + [f"{where}: expected an array"]
        for index, item in enumerate(value):
            check_value(spec, schema.get("items", {}), item, f"{where}[{index}]", problems)
    elif kind == "string":
        if not isinstance(value, str):
            problems.append(f"{where}: expected a string")
        elif "enum" in schema and value not in schema["enum"]:
            problems.append(f"{where}: {value!r} not in {schema['enum']}")
    elif kind == "integer":
        if not isinstance(value, int) or isinstance(value, bool):
            problems.append(f"{where}: expected an integer")
        elif not schema.get("minimum", value) <= value <= schema.get("maximum", value):
            problems.append(f"{where}: {value} out of range")
    elif kind == "boolean" and not isinstance(value, bool):
        problems.append(f"{where}: expected a boolean")
    return problems


def operation(spec, method, path):
    for template, item in spec["paths"].items():
        pattern = "^" + re.sub(r"\{[^}]+\}", "[^/]+", template) + "$"
        if re.match(pattern, path) and method.lower() in item:
            return template, item[method.lower()], item.get("parameters", [])
    return None, None, []


def check_request(spec, line):
    method, url, *body = line.split(" ", 2)
    parsed = urllib.parse.urlsplit(url)
    template, entry, shared = operation(spec, method, parsed.path)
    if entry is None:
        return [f"{method} {parsed.path}: no such operation"]
    problems = []
    parameters = {p["name"]: p for p in [resolve(spec, p) if "$ref" in p else p for p in shared + entry.get("parameters", [])]
                  if p.get("in") == "query"}
    for name, value in urllib.parse.parse_qsl(parsed.query):
        if name not in parameters:
            problems.append(f"{method} {template}: unknown query parameter {name}")
            continue
        schema = resolve(spec, parameters[name].get("schema", {}))
        allowed = resolve(spec, schema.get("items", {})).get("enum") if schema.get("type") == "array" else schema.get("enum")
        for part in value.split(","):
            if allowed and part not in allowed:
                problems.append(f"{method} {template}: {name}={part} not in {allowed}")
    content = entry.get("requestBody", {}).get("content", {}).get("application/json")
    if body and content:
        problems += check_value(spec, content["schema"], json.loads(body[0]), f"{method} {template}", [])
    elif body or content:
        problems.append(f"{method} {template}: body {'given' if body else 'missing'}")
    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("nomac")
    parser.add_argument("ipa")
    parser.add_argument("--spec")
    arguments = parser.parse_args()
    spec = load_spec(arguments.spec)
    printed = subprocess.run([arguments.nomac, "upload", arguments.ipa, "--dry-run"], capture_output=True, text=True, check=True).stdout
    requests = [line for line in printed.splitlines() if re.match(rf"^(GET|POST|PATCH|DELETE) {re.escape(BASE)}/", line)]
    problems = [problem for line in requests for problem in check_request(spec, line)]
    print(f"App Store Connect API {spec['info']['version']}: {len(requests)} requests, {len(problems)} problems")
    for problem in problems:
        print(f"  {problem}")
    sys.exit(1 if problems or not requests else 0)


if __name__ == "__main__":
    main()
