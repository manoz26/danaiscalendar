#!/usr/bin/env bash
# Creates fresh simulators for CI on the runtime that matches the selected Xcode's SDK:
#   - the newest "iPad Pro 13-inch" (fallback: "iPad Air 13-inch")
#   - the newest "iPhone NN Pro"
# Boots only the iPad (one simulator at a time keeps app launches fast; the workflow boots
# the iPhone later with boot-simulator.sh) and prints key=value lines for $GITHUB_OUTPUT.
set -euo pipefail

sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)

# Some Xcode versions also ship device-specific runtimes (e.g. one that only supports a
# single new iPhone), so keep only runtimes that support both a 13" iPad and an iPhone Pro.
runtime_json=$(xcrun simctl list runtimes available --json | jq --arg sdk "$sdk" '
  ($sdk | split(".") | map(tonumber)) as $s
  | [.runtimes[]
     | select(.identifier | test("SimRuntime\\.iOS"))
     | select(.isAvailable)
     | select(((.version | split(".") | map(tonumber))[0:2]) <= $s[0:2])
     | select(any(.supportedDeviceTypes[]?; .name | test("^iPad (Pro|Air) 13-inch")))
     | select(any(.supportedDeviceTypes[]?; .name | test("^iPhone [0-9]+ Pro$")))]
  | sort_by([(.version | split(".") | map(tonumber)), (.supportedDeviceTypes | length)])
  | last')

runtime=$(jq -r '.identifier // empty' <<<"$runtime_json")
if [[ -z "$runtime" ]]; then
  echo "No iOS simulator runtime found for SDK $sdk" >&2
  xcrun simctl list runtimes >&2
  exit 1
fi

pick_type() {
  jq -r --arg pattern "$1" '
    [.supportedDeviceTypes[] | select(.name | test($pattern))]
    | sort_by([(.name | [scan("[0-9]+")] | map(tonumber)), .name])
    | last | .identifier // empty' <<<"$runtime_json"
}

ipad_type=$(pick_type '^iPad Pro 13-inch')
[[ -n "$ipad_type" ]] || ipad_type=$(pick_type '^iPad Air 13-inch')
iphone_type=$(pick_type '^iPhone [0-9]+ Pro$')

if [[ -z "$ipad_type" || -z "$iphone_type" ]]; then
  echo "Could not find iPad 13\" / iPhone Pro device types in $runtime" >&2
  jq -r '.supportedDeviceTypes[].name' <<<"$runtime_json" >&2
  exit 1
fi

type_name() { jq -r --arg id "$1" '.supportedDeviceTypes[] | select(.identifier == $id) | .name' <<<"$runtime_json"; }

ipad=$(xcrun simctl create "CI iPad 13" "$ipad_type" "$runtime")
iphone=$(xcrun simctl create "CI iPhone" "$iphone_type" "$runtime")

bash "$(dirname "$0")/boot-simulator.sh" "$ipad"

{
  echo "Runtime: $runtime (SDK $sdk)"
  echo "iPad: $(type_name "$ipad_type") $ipad"
  echo "iPhone: $(type_name "$iphone_type") $iphone"
} >&2

echo "ipad=$ipad"
echo "iphone=$iphone"
echo "ipad_name=$(type_name "$ipad_type")"
echo "iphone_name=$(type_name "$iphone_type")"
echo "runtime=$runtime"
