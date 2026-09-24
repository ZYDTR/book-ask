#!/bin/zsh
# Local DMG creation. --preview never contacts Apple or consumes credentials.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:-}"
if [[ "$mode" != '--preview' && "$mode" != '--release' ]]; then
  print -u2 'Usage: zsh scripts/package.sh --preview | --release'
  exit 2
fi
if [[ "$mode" == '--release' ]]; then
  if [[ -z "${BOOK_ASK_SIGN_IDENTITY:-}" || "$BOOK_ASK_SIGN_IDENTITY" == '-' || -z "${BOOK_ASK_NOTARY_PROFILE:-}" ]]; then
    print -u2 'Release requires BOOK_ASK_SIGN_IDENTITY (Developer ID Application) and BOOK_ASK_NOTARY_PROFILE. No package was published.'
    exit 1
  fi
  if [[ "$BOOK_ASK_SIGN_IDENTITY" != 'Developer ID Application:'* ]]; then
    print -u2 'Use a Developer ID Application identity for distribution.'
    exit 1
  fi
fi
mkdir -p "$project_dir/build" "$project_dir/dist"
stage="$(mktemp -d "$project_dir/build/package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
export BOOK_ASK_BUILD_DIR="$stage/compiled"
export BOOK_ASK_ARCHS='arm64 x86_64'
if [[ "$mode" == '--preview' ]]; then
  export BOOK_ASK_SIGN_IDENTITY='-'
  export BOOK_ASK_BUNDLE_ID='com.zydtr.book-ask.preview'
else
  export BOOK_ASK_BUNDLE_ID='com.zydtr.book-ask'
fi
zsh "$project_dir/scripts/build.sh"
mkdir -p "$stage/image"
ditto "$BOOK_ASK_BUILD_DIR/读书提问.app" "$stage/image/读书提问.app"
ln -s /Applications "$stage/image/Applications"
python3 "$project_dir/scripts/package_notes.py" "$stage/image/开始使用.txt" "$mode" "$stage/image/读书提问.app/Contents/Resources/TrialConfiguration.json"
suffix=''
[[ "$mode" == '--preview' ]] && suffix='-preview'
dmg="$project_dir/dist/BookAsk-0.2.6${suffix}-universal.dmg"
hdiutil create -volname "读书提问 0.2.6${suffix}" -srcfolder "$stage/image" -ov -format UDZO "$dmg"
if [[ "$mode" == '--release' ]]; then
  codesign --sign "$BOOK_ASK_SIGN_IDENTITY" --timestamp "$dmg"
  xcrun notarytool submit "$dmg" --keychain-profile "$BOOK_ASK_NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
  spctl --assess --type open --context context:primary-signature "$dmg"
fi
shasum -a 256 "$dmg" > "$dmg.sha256"
print -r -- "$dmg"
