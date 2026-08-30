#!/bin/sh
set -eu

app_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
repo_root=$(CDPATH= cd -- "$app_dir/../.." && pwd)
local_config=apps/resource-guard/resource-guard.local.json
example_config=apps/resource-guard/resource-guard.local.json.example
legacy_tree=tools
legacy_specs=specs/""tools
legacy_reference=tools/""resource-guard

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
git ls-files --error-unmatch "$example_config" >/dev/null

if [ -e "$legacy_tree" ] || [ -e "$legacy_specs" ]; then
  echo "legacy resource-guard trees remain" >&2
  exit 1
fi
if git grep --quiet "$legacy_reference"; then
  echo "legacy resource-guard path references remain" >&2
  exit 1
fi

tracked_artifacts=$(git ls-files 'apps/resource-guard/.cache/**' 'apps/resource-guard/dist/**' 'apps/resource-guard/coverage/**' 'apps/resource-guard/resource-guard.exe')
if [ -n "$tracked_artifacts" ]; then
  echo "compiled resource-guard artifacts are tracked:" >&2
  echo "$tracked_artifacts" >&2
  exit 1
fi

first_line=$(sed -n '1p' apps/resource-guard/resource-guard)
if [ "$first_line" != '#!/bin/sh' ]; then
  echo "tracked resource-guard entrypoint must remain the POSIX bootstrap" >&2
  exit 1
fi
