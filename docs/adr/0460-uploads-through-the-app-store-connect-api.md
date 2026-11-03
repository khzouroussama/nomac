# ADR 0460: Uploading builds through the App Store Connect API

- Status: proposed (no upload has run; the first one waits on the owner's API key and go-ahead)
- Date: 2026-11-03

## Context

After `nomac export` writes an app-store-connect IPA, the build has to reach App Store Connect
for TestFlight and review. On a Mac that is Xcode's Organizer, `xcodebuild -exportArchive` with
`destination` `upload`, `altool --upload-package` or Transporter. None of them runs on Linux
except Transporter's own Linux build, a closed-source Java application from Apple (the
`iTMSTransporter` row of docs/ARCHITECTURE.md, planned as a subprocess until now).

Since version 4.0 the public App Store Connect API has build uploads (`buildUploads`,
`buildUploadFiles`; Apple's OpenAPI specification 4.5.1, docs/formats/app-store-connect-upload.md):
create a build upload for an app's version, build number and platform, reserve each file, send
it in the parts the reservation lists to the URLs it gives, commit it with its checksum, and read
the build upload's state while App Store Connect processes it. Requests are authorized with a
JSON Web Token signed with an App Store Connect API key (ES256), which is how CI services upload
without an Apple ID. Apple documents it: "You can also use Xcode or Transporter to upload app
binaries."

How altool or Xcode use the service is not observable without sending a build: altool fetches
its configuration from Apple even for `--help` (offline it stops: "The file “Defaults.properties”
couldn’t be opened"), and Xcode's App Store information step (`generateAppStoreInformation`) runs
in an XPC helper that does not start under the experiments' offline sandbox
(`distribution_experiments.py` `app-store-information`). Their traffic is not to be read by
decompiling them (CLAUDE.md, legal line).

## Decision

1. **`nomac upload` speaks the public App Store Connect API itself** (`NomacDistribution`):
   the app found by its bundle ID (`GET /v1/apps`) unless `--apple-id` names it, one build upload,
   the IPA reserved as its `ASSET` (`com.apple.ipa`), its parts sent as listed (three attempts
   each), the file committed with its MD5, and with `--wait` the build upload read every 30
   seconds until `COMPLETE` or `FAILED`. No Apple tool runs, on any platform.
2. **Only API keys authenticate.** The key is found as altool finds it (`--api-key`,
   `--api-issuer`, `--p8-file-path`, or `AuthKey_<key ID>.p8` in altool's folders), a team key
   with its issuer, an individual key without. nomac never asks for an Apple ID or password and
   keeps no credential: each request gets a token valid for 10 minutes.
3. **Everything up to the network is tested without it**: the token (verified with the key's
   public key), the IPA's values, every request body, part slicing, retries, the commit's
   checksum, the polling and Apple's error documents, against a scripted transport whose answers
   follow the OpenAPI schemas (`NomacDistributionTests`); `nomac upload --dry-run` prints the
   requests, and `.github/scripts/upload_spec_check.py` checks them against Apple's current
   specification.
4. **The first real upload is the owner's**: with their key, their app record and their
   go-ahead, a self-written app's app-store-connect IPA (ADR 0101's plan, "Proving acceptance
   early", step 2). What it shows is written down in docs/formats/app-store-connect-upload.md
   and B-463.

Rejected: running Apple's Transporter for Linux as a subprocess. It would make nomac depend on
an Apple binary the user downloads separately and on Java, for a service the public API offers;
it stays a fallback if the API refuses something only Transporter sends (B-462).

## Consequences

- `nomac upload` works the same on Linux and macOS and needs only the IPA and an API key.
- What App Store Connect requires beyond the IPA is unknown until the first upload: whether it
  wants the `ASSET_DESCRIPTION` file (an App Store information property list, which Xcode writes
  with `generateAppStoreInformation`) or the `ASSET_SPI` one, and whether the commit's MD5 file
  checksum is the expected kind. Apple's validation errors come back in the build upload's state
  and are printed (B-462, B-463).
- Validation without uploading (`altool --validate-app`) has no public API equivalent (B-464).
