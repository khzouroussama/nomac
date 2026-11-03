# Examples

## Retro Rampage, an open-source game, to an IPA

Tested on a fresh Ubuntu 24.04 with no network after the clone (2026-11-03).

```sh
# Retro Rampage, an open-source game.
git clone https://github.com/nicklockwood/RetroRampage && cd RetroRampage
nomac check Source/Rampage.xcodeproj
nomac build -project Source/Rampage.xcodeproj -scheme Rampage -configuration Release \
    -destination generic/platform=iOS IPHONEOS_DEPLOYMENT_TARGET=15.0 CODE_SIGNING_ALLOWED=NO
nomac archive -project Source/Rampage.xcodeproj -scheme Rampage -configuration Release \
    -destination generic/platform=iOS -archivePath Rampage.xcarchive IPHONEOS_DEPLOYMENT_TARGET=15.0 \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual AD_HOC_CODE_SIGNING_ALLOWED=YES \
    PROVISIONING_PROFILE_REQUIRED=NO DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
cat > ExportOptions.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>debugging</string>
	<key>signingCertificate</key>
	<string>-</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>teamID</key>
	<string>NOMAC00000</string>
</dict>
</plist>
PLIST
nomac export -archivePath Rampage.xcarchive -exportPath out -exportOptionsPlist ExportOptions.plist
```

Retro Rampage sets iOS 11.0, below Xcode 27's minimum, so the commands raise it.
`nomac check` exits with status 1 here: the project uses 5 features nomac has not verified (that
deployment target and signing settings). The IPA is signed ad hoc, so no iPhone installs it.

## Signing for an iPhone, installing and launching

See [INSTALL-ON-IPHONE.md](INSTALL-ON-IPHONE.md).
