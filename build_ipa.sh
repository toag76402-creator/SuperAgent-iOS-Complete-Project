#!/bin/bash
set -e
xcodegen generate
xcodebuild clean build \
  -project SuperAgent.xcodeproj \
  -scheme SuperAgent \
  -sdk iphoneos \
  -configuration Release \
  -arch arm64 \
  -derivedDataPath ./build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

test -d ./build/Build/Products/Release-iphoneos/SuperAgent.app/PlugIns/SuperAgentBroadcast.appex
rm -rf Payload SuperAgent.ipa
mkdir -p Payload
cp -r ./build/Build/Products/Release-iphoneos/SuperAgent.app Payload/
zip -r9 SuperAgent.ipa Payload
echo "✅ SuperAgent.ipa is ready!"
