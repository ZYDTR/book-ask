#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
python3 -m unittest discover -s tests -p 'test_*.py'
mkdir -p build
xcrun swiftc src/ReadingContext.swift tests/context.swift -o build/context-tests
build/context-tests
xcrun swiftc src/SelectionTrigger.swift tests/selection_trigger.swift -o build/selection-trigger-tests
build/selection-trigger-tests
if build/selection-trigger-tests --old-release-cache; then
  print -u2 'FAIL: regression did not detect the stale mouse-release cache'
  exit 1
fi
if build/selection-trigger-tests --old-foreground-gate; then
  print -u2 'FAIL: regression did not detect the old foreground gate'
  exit 1
fi
xcrun swiftc -framework AppKit src/ReadingTextArea.swift tests/text_layout.swift -o build/text-layout-tests
build/text-layout-tests

xcrun swiftc src/WordbookStore.swift tests/wordbook.swift -o build/wordbook-tests
build/wordbook-tests
xcrun swiftc -framework AppKit src/ReadingPreferences.swift src/PaperTheme.swift src/ReadingTextArea.swift src/WordbookStore.swift src/WordbookWindow.swift tests/wordbook_layout.swift -o build/wordbook-layout-tests
build/wordbook-layout-tests
xcrun swiftc src/DiagnosticLog.swift tests/diagnostic_log.swift -o build/diagnostic-tests
build/diagnostic-tests
xcrun swiftc -framework AppKit -framework ApplicationServices src/ClipboardCapture.swift src/BooksCopy.swift tests/clipboard_capture.swift -o build/clipboard-capture-tests
build/clipboard-capture-tests

# Compile the actual BookAsk definition without starting its application loop.
sed '/^let application = NSApplication.shared/,$d' src/main.swift > build/BookAskForTests.swift
panel_sources=(src/*.swift)
panel_sources=(${panel_sources:#src/main.swift})
xcrun swiftc -swift-version 5 -framework AppKit -framework ApplicationServices \
  "${panel_sources[@]}" build/BookAskForTests.swift tests/reading_panel.swift -o build/reading-panel-tests
build/reading-panel-tests
if build/reading-panel-tests --old-no-outside-dismiss; then
  print -u2 'FAIL: regression did not detect the previous Books click behavior'
  exit 1
fi

xcrun swiftc -swift-version 5 -framework AppKit -framework ApplicationServices \
  "${panel_sources[@]}" build/BookAskForTests.swift tests/reading_visual_layout.swift -o build/reading-visual-tests
build/reading-visual-tests


xcrun swiftc -swift-version 5 -framework AppKit -framework ApplicationServices \
  "${panel_sources[@]}" build/BookAskForTests.swift tests/wordbook_cache.swift -o build/wordbook-cache-tests
build/wordbook-cache-tests
if build/wordbook-cache-tests --old-no-cache; then
  print -u2 'FAIL: regression did not detect repeated model requests for existing terms'
  exit 1
fi
