#!/bin/zsh
# Records the demo video: a simulator of its own with a tidy status bar, the
# DemoTour UI test driving the app at a watchable pace, then
# Scripts/finish-demo.sh framing the result.
#
#   Scripts/record-demo.sh [output-dir]    (default: ~/Desktop/City Tourist demo)
#
# Needs Xcode and ffmpeg (brew install ffmpeg). The demo trip is built around
# the time you record, so recording between about noon and 8pm gives the
# fullest Today screen.
set -euo pipefail
cd "$(dirname "$0")/.."
out=${1:-"$HOME/Desktop/City Tourist demo"}
work=$(mktemp -d)
name="City Tourist Demo"

udid=$(xcrun simctl list devices | grep "$name (" | grep -oE '[0-9A-F-]{36}' | head -1 || true)
[[ -n $udid ]] || udid=$(xcrun simctl create "$name" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro)
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl ui "$udid" appearance light
xcrun simctl status_bar "$udid" override --time "$(date +%-I:%M)" --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

destination="platform=iOS Simulator,id=$udid"
echo "Building…"
xcodebuild build-for-testing -project CityTourist.xcodeproj -scheme DemoTour \
  -destination "$destination" -derivedDataPath "$work/build" -quiet

echo "Recording the tour (about 90 seconds)…"
xcrun simctl io "$udid" recordVideo --codec=h264 --force "$work/raw.mov" > /dev/null 2>&1 &
recorder=$!
sleep 2
xcodebuild test-without-building -project CityTourist.xcodeproj -scheme DemoTour \
  -destination "$destination" -derivedDataPath "$work/build" \
  -only-testing:CityTouristUITests/DemoTour/testTour -quiet
sleep 1
kill -INT $recorder
wait $recorder || true

Scripts/finish-demo.sh "$work/raw.mov" "$out"
