#!/bin/sh
set -eu

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
repo_root=$(CDPATH= cd -- "$tool_dir/../.." && pwd)
local_config=tools/resource-guard/resource-guard.local.json
example_config=tools/resource-guard/resource-guard.local.json.example

cd "$repo_root"
git check-ignore --quiet "$local_config"
if git ls-files --error-unmatch "$local_config" >/dev/null 2>&1; then
  echo "$local_config must not be tracked" >&2
  exit 1
fi
[ -f "$example_config" ]
if git check-ignore --quiet "$example_config"; then
  echo "$example_config must remain committable" >&2
  exit 1
fi

tracked_artifacts=$(git ls-files 'tools/resource-guard/.cache/**' 'tools/resource-guard/dist/**' 'tools/resource-guard/coverage/**' 'tools/resource-guard/resource-guard.exe')
if [ -n "$tracked_artifacts" ]; then
  echo "compiled resource-guard artifacts are tracked:" >&2
  echo "$tracked_artifacts" >&2
  exit 1
fi

first_line=$(sed -n '1p' tools/resource-guard/resource-guard)
if [ "$first_line" != '#!/bin/sh' ]; then
  echo "tracked resource-guard entrypoint must remain the POSIX bootstrap" >&2
  exit 1
fi
