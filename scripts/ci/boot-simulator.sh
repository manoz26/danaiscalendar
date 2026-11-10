#!/usr/bin/env bash
# Boots a simulator, waits until it is ready and sets a clean status bar.
# Usage: boot-simulator.sh <udid>
set -euo pipefail

udid="$1"
xcrun simctl boot "$udid" 2>/dev/null || true   # already booted is fine
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl status_bar "$udid" override \
  --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
