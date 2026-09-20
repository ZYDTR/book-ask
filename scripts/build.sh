#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/build/读书提问.app"
mkdir -p "$app_dir/Contents/MacOS"
xcrun swiftc -swift-version 5 -O -framework AppKit -framework Foundation -framework ApplicationServices \
  "$project_dir/src/DiagnosticLog.swift" "$project_dir/src/ReadingContext.swift" "$project_dir/src/BooksSelection.swift" "$project_dir/src/SelectionTrigger.swift" "$project_dir/src/ReadingTextArea.swift" "$project_dir/src/ReadingPreferences.swift" "$project_dir/src/PaperTheme.swift" "$project_dir/src/ReadingWindow.swift" "$project_dir/src/ReadingPanelController.swift" "$project_dir/src/ReadingPanelPlacement.swift" "$project_dir/src/WordbookStore.swift" "$project_dir/src/WordbookWindow.swift" "$project_dir/src/ClipboardCapture.swift" "$project_dir/src/BooksCopy.swift" "$project_dir/src/main.swift" \
  -o "$app_dir/Contents/MacOS/BookAsk"
python3 "$project_dir/scripts/write_plist.py" "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir" >/dev/null
print -r -- "$app_dir"
