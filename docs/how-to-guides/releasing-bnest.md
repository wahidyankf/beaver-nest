# Releasing Bnest

This guide runs a no-downtime Bnest release on a provisioned host. The [Caddy deployment workflow](../../repo-governance/workflows/development-caddy-deployment.md) is the authoritative rule; this page is the procedure that satisfies it.

The managed `release:run` target is transactional. A single invocation runs the release gates, builds an immutable artifact from a temporary worktree, proves the migration set, prepares the inactive slot, promotes it, proves the routed revision and a connected LiveView, then drains and retires the previous slot. Do not decompose it into `release:build`, `deploy:prepare`, and `deploy:promote` for a routine release.

## 1. Confirm the source is releasable

`release:run` re-asserts that the working tree is clean and that `HEAD` equals `origin/main` before and after **every** gate, and again at build. Any edit during the run aborts it.

Land documentation, rule, and code changes first, then release the resulting revision:

```sh
git fetch origin main
git rev-parse HEAD origin/main   # must match
git status --porcelain           # must be empty
./hippo status                   # must report state=normal
```

A release also needs the inactive slot free. Production uses `4000` and `4001`; Caddy routes on `4100`:

```sh
lsof -nP -iTCP:4000 -iTCP:4001 -iTCP:4100 -sTCP:LISTEN
```

## 2. Derive the machine-local configuration

`BNEST_DEPLOY_ROOT`, `BNEST_RUNTIME_ROOT`, `BNEST_DEPLOY_COOKIE_FILE`, `BNEST_DEPLOY_SECRET_KEY_BASE_FILE`, `BNEST_PRODUCTION_ORIGIN`, and `HIPPO_BIN` are machine-local. An unset shell does not mean they are unavailable: a provisioned host keeps them outside the repository between sessions, and the running blue or green launchd unit already names every one of them.

Derive them rather than recalling them. The unit's `EnvironmentVariables` supply the runtime root and the served host; its `ProgramArguments` release path supplies the deploy root:

```sh
plist="$HOME/Library/LaunchAgents/com.bnest.app.blue.plist"
/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:BNEST_RUNTIME_ROOT" "$plist"
/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:PHX_HOST" "$plist"
/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist"
```

Write the exports to a file outside the repository, mode `600`, and source it. Export a secret's **path**, never its contents, and never echo one. Sourcing a file also keeps the values out of shell history and process listings, which a long inline assignment does not.

```sh
# <machine-local>/deploy-env.sh — mode 600, outside every checkout.
bnest_load_deploy_env() {
  plist="$HOME/Library/LaunchAgents/com.bnest.app.blue.plist"
  pb() { /usr/libexec/PlistBuddy -c "Print $1" "$plist"; }

  BNEST_RUNTIME_ROOT=$(pb ":EnvironmentVariables:BNEST_RUNTIME_ROOT") || return 78
  host=$(pb ":EnvironmentVariables:PHX_HOST") || return 78
  binary=$(pb ":ProgramArguments:0") || return 78
  # <deploy-root>/releases/<sha>/bin/bnest_app -> <deploy-root>
  BNEST_DEPLOY_ROOT=$(dirname "$(dirname "$(dirname "$(dirname "$binary")")")")

  BNEST_DEPLOY_COOKIE_FILE="$BNEST_DEPLOY_ROOT/release.cookie"
  BNEST_DEPLOY_SECRET_KEY_BASE_FILE="$BNEST_DEPLOY_ROOT/secret_key_base"
  BNEST_PRODUCTION_ORIGIN="https://$host"
  HIPPO_BIN="<repository-root>/hippo"

  for required in "$BNEST_DEPLOY_COOKIE_FILE" "$BNEST_DEPLOY_SECRET_KEY_BASE_FILE" "$HIPPO_BIN"; do
    [ -f "$required" ] || { echo "missing file: $required" >&2; return 78; }
  done

  export BNEST_DEPLOY_ROOT BNEST_RUNTIME_ROOT BNEST_DEPLOY_COOKIE_FILE
  export BNEST_DEPLOY_SECRET_KEY_BASE_FILE BNEST_PRODUCTION_ORIGIN HIPPO_BIN
  unset plist host binary required
}
bnest_load_deploy_env
```

Two traps are worth naming. `HIPPO_BIN` is required by the release host and is easy to miss because no other target needs it. And under zsh, `path` is tied to `PATH`, so a scratch variable of that name silently destroys the search path of the shell that sources the file; the loop above uses `required` instead.

`BNEST_DEPLOY_WORKTREE` needs no value. `release:run` creates and removes its own temporary worktree.

## 3. Record the pre-release baseline

Capture the routed slot and revision so the cutover can be shown to have changed them:

```sh
. <machine-local>/deploy-env.sh
npm exec -- nx run -p bnest-app -t proxy:status
curl -fsS http://127.0.0.1:4100/health/ready
curl -fsS "$BNEST_PRODUCTION_ORIGIN/health/ready"
```

## 4. Run the release

```sh
. <machine-local>/deploy-env.sh
npm exec -- nx run -p bnest-app -t release:run -- --revision <sha>
```

The run takes tens of minutes because it executes the full gate manifest before building. Expect it to be long-running rather than hung. It prints one JSON result. `outcome` is `passed` on success; `queued` means another release owns the host lock and `deferred` means HIPPO withheld capacity — neither is a failure, and neither leaves a partial cutover. Any other outcome sets a non-zero exit status.

## 5. Verify the routed cutover

The routed backend, not only the candidate, must serve the intended revision:

```sh
npm exec -- nx run -p bnest-app -t proxy:status
curl -fsS http://127.0.0.1:4100/health/ready
curl -fsS "$BNEST_PRODUCTION_ORIGIN/health/ready"
lsof -nP -iTCP:4000 -iTCP:4001 -sTCP:LISTEN   # exactly one slot listens
git worktree list                              # no release worktree remains
```

Both readiness probes must report the released revision. Sample the exact origin repeatedly against the [continuity budget](../../repo-governance/development/live-service-continuity.md), and confirm a connected LiveView at the exact served origin for a UI or LiveView change.

## Recovery

Never stop Caddy to change its configuration. If candidate health, routing, or LiveView verification fails, leave the previous backend running and use `deploy:rollback` before diagnosis. Do not retry a failed candidate until its health failure is understood.
