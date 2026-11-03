# Uploading a build to App Store Connect

How `nomac upload` (module `NomacDistribution`, ADR 0460) sends an IPA to App Store Connect,
from Apple's public documentation: the App Store Connect API reference ("Build Uploads",
"Generating Tokens for API Requests", "Uploading Assets to App Store Connect") and its OpenAPI
specification 4.5.1 (`app-store-connect-openapi-specification.zip`), and from `altool --help` of
Xcode 27.0 (altool 27.0.5) for where keys are found. No upload has run yet: what is marked
*unverified* waits on the first one (B-463). `.github/scripts/upload_spec_check.py` checks
nomac's requests against the specification.

## Authentication

Every API request carries `Authorization: Bearer <token>`, a JSON Web Token signed with ES256
by the API key's private key (`AuthKey_<key ID>.p8`, PKCS #8 PEM of a P-256 key):

- header `{"alg":"ES256","kid":"<key ID>","typ":"JWT"}`;
- claims `aud` `appstoreconnect-v1`, `iat` (now, Unix seconds) and `exp` (App Store Connect
  refuses more than 20 minutes after `iat`; nomac gives 10), and `iss` the issuer ID for a team
  key, or `sub` `user` and no `iss` for an individual key;
- the signature is base64url (no padding) of the 64 bytes `r` and `s`.

nomac signs a token per request. The upload URLs of a reservation are pre-authorized: parts are
sent without a token. Given only `--api-key`, the key file is looked for, as altool does, in
`./private_keys`, `~/private_keys`, `~/.private_keys`, `~/.appstoreconnect/private_keys` and
`$API_PRIVATE_KEYS_DIR`, in that order; `--p8-file-path` names it instead.

## The upload

From the IPA nomac reads the app's `Payload/<name>.app/Info.plist` (zip central directory, the
entry stored or deflated; Zip64 is refused, B-306): `CFBundleIdentifier`,
`CFBundleShortVersionString`, `CFBundleVersion`, and the API's `Platform` from the first
`CFBundleSupportedPlatforms` (`iPhoneOS` `IOS`, `AppleTVOS` `TV_OS`, `XROS` `VISION_OS`; macOS
builds are packages, not IPAs). Then, JSON:API documents with `Content-Type: application/json`:

1. `GET /v1/apps?filter[bundleId]=<bundle ID>&fields[apps]=bundleId` (brackets
   percent-encoded): the app whose `bundleId` is exactly the IPA's; `--apple-id` skips this.
2. `POST /v1/buildUploads`: `type` `buildUploads`, attributes `cfBundleShortVersionString`,
   `cfBundleVersion`, `platform`, relationship `app`. 201 with the build upload (`state`
   `AWAITING_UPLOAD`).
3. `POST /v1/buildUploadFiles`: `type` `buildUploadFiles`, attributes `assetType` `ASSET`,
   `fileName` (the IPA's), `fileSize`, `uti` `com.apple.ipa`, relationship `buildUpload`. 201
   with `uploadOperations`: for each part `method`, `url`, `offset`, `length`, `partNumber`,
   `requestHeaders` (`name`, `value`) and `expiration`.
4. Each operation: its method to its URL, its headers, the file's bytes from `offset`, `length`
   of them. Parts may go in any order and may be sent again until the commit; nomac sends them
   in order and tries each three times. An operation outside the file stops the upload.
5. `PATCH /v1/buildUploadFiles/<id>`: `uploaded` true and `sourceFileChecksums`
   `{"file": {"algorithm": "MD5", "hash": <hex MD5 of the whole IPA>}}`. The assets guide
   commits with the file's MD5; the specification also allows `SHA_256` and a `composite` MD5
   (*unverified* which App Store Connect checks for builds). The answer's `assetDeliveryState`
   is `AWAITING_UPLOAD`, `UPLOAD_COMPLETE`, `COMPLETE` or `FAILED`.
6. `GET /v1/buildUploads/<id>?fields[buildUploads]=state`: `state.state` is `AWAITING_UPLOAD`,
   `PROCESSING`, `FAILED` or `COMPLETE`, with `errors`, `warnings` and `infos`
   (`code`, `description`). With `--wait`, every 30 seconds until `COMPLETE` (the build then
   appears under `builds`) or `FAILED` (its errors printed, status 1).

A refused request's `ErrorResponse` (`errors`: `status`, `code`, `title`, `detail`) is printed
as notes of the error. `--dry-run` prints each request (method, URL, body; a part's size; the
token's header and claims, never the token) and answers with placeholder IDs and one part for
the whole file, with a throwaway key when no `--api-key` is given.

## The other files of a build upload

A build upload has three file roles: `assetFile` (`ASSET`), `assetDescriptionFile`
(`ASSET_DESCRIPTION`) and `assetSpiFile` (`ASSET_SPI`), with the UTIs `com.apple.ipa`,
`com.apple.pkg`, `com.apple.binary-property-list`, `com.apple.xml-property-list` and
`com.pkware.zip-archive`. nomac sends the IPA only. Xcode's app-store-connect export can write
an App Store information file (`generateAppStoreInformation`, false by default); whether that is
the description file is not known, because its step runs in Xcode's `com.apple.dt.Xcode.ITunesSoftwareService` XPC helper,
which does not start under the offline sandbox ("Couldn’t communicate with a helper
application", `distribution_experiments.py` `app-store-information`); B-462.
