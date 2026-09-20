#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
target="$HOME/Applications/读书提问.app"
mkdir -p "$HOME/Applications"
ditto "$project_dir/build/读书提问.app" "$target"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target"
/System/Library/CoreServices/pbs -update
print -r -- "Installed $target"
