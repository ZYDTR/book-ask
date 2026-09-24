#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${BOOK_ASK_BUILD_DIR:-$project_dir/build}"
app_dir="$build_dir/读书提问.app"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/book-ask-build.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
mkdir -p "$app_dir/Contents/MacOS"
architectures=(${=BOOK_ASK_ARCHS:-$(uname -m)})
binaries=()
for architecture in "${architectures[@]}"; do
  case "$architecture" in arm64|x86_64) ;; *) print -u2 'Only arm64 and x86_64 are supported'; exit 1 ;; esac
  xcrun swiftc -swift-version 5 -O -target "$architecture-apple-macosx12.0" \
    -framework AppKit -framework Foundation -framework ApplicationServices \
    "$project_dir"/src/*.swift -o "$scratch_dir/BookAsk-$architecture"
  binaries+=("$scratch_dir/BookAsk-$architecture")
done
xcrun lipo -create "${binaries[@]}" -output "$app_dir/Contents/MacOS/BookAsk"
python3 "$project_dir/scripts/write_plist.py" "$app_dir/Contents/Info.plist"
python3 "$project_dir/scripts/stage_trial_config.py" \
  "${BOOK_ASK_TRIAL_CONFIG:-$project_dir/resources/TrialConfiguration.example.json}" \
  "$app_dir/Contents/Resources/TrialConfiguration.json"
identity="${BOOK_ASK_SIGN_IDENTITY:--}"
if [[ "$identity" == '-' ]]; then
  codesign --force --sign - "$app_dir" >/dev/null
else
  codesign --force --sign "$identity" --options runtime --timestamp "$app_dir" >/dev/null
fi
codesign --verify --deep --strict "$app_dir"
print -r -- "$app_dir"
