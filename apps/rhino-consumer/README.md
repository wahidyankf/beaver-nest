# RHINO Consumer

This project owns Beaver Nest's repository documentation gate. It has no source. It is a
`project.json` and this README, composing invocations of the pinned
[RHINO](https://github.com/wahidyankf/rhino) executable as Nx targets — the same shape the
Badakmini project used to compose raw `dotnet` commands, and for the same reason: the tool is not
an Nx-plugin language, so its targets are declared rather than inferred.

## What it owns, and what it does not

It owns **which checks run and in what combination**. That is all.

It does not own the executable, its command surface, its exit codes, or its configuration schema —
those live upstream. It does not own the policy either: every value enforced here is declared in
[`repo-config.yml`](../../repo-config.yml) at the repository root. And it does not own the
bootstrap that installs the executable; that is [`./rhino`](../../rhino), specified by
[the RHINO consumer specification](../../specs/tools/rhino-consumer/README.md).

The division matters when a check fails. A finding means this repository disagrees with
`repo-config.yml`. A refusal means the invocation or the configuration was unusable. Neither is a
reason to edit anything in this directory.

## Prerequisites

None beyond a checkout. `./rhino` installs the pinned release into a machine-wide cache on first
use and verifies it on every use; the pin is [`rhino.lock`](../../rhino.lock). The first run on a
cold cache downloads roughly two megabytes and takes about a second; every run after that resolves
from the cache in tens of milliseconds.

## Targets

Run from the repository root:

```console
$ npm exec -- nx run rhino-consumer:test:repo
$ npm exec -- nx run rhino-consumer:test:bootstrap
```

Heavy or repeated local runs go through the [HIPPO guard](../../repo-governance/development/resource-aware-development.md):

```console
$ ./hippo run --class ephemeral --disk-path . -- npm exec -- nx run rhino-consumer:test:repo
```

### `test:repo`

Six validator invocations in parallel, failing the target if any of them fails:

| Invocation                                | What it checks                                            |
| ----------------------------------------- | --------------------------------------------------------- |
| `rhino repo-config validate`              | the declared policy itself is complete and usable         |
| `rhino governance word-budget validate`   | every governed surface is inside its declared word budget |
| `rhino governance directory-map validate` | every mapped tree's READMEs name their siblings           |
| `rhino harness parity validate`           | every declared harness adapter still routes to the canon  |
| `rhino md internal-link validate`         | every relative Markdown link resolves                     |
| `rhino md mermaid validate`               | every diagram stays inside the label and colour rules     |

Badakmini ran eight invocations to cover the same ground. The count fell rather than the coverage:
its four `--directory` calls became one, because the four mapped trees are now declared in
`repo-config.yml` and the call site no longer restates them. `repo-config validate` is the one
addition, and it has no Badakmini counterpart — the policy only became a checkable artifact when it
stopped being compiled into the validator.

The commands are written as `./rhino …`, which resolves only from the repository root. That is
deliberate: the alternative is a target that runs from the wrong directory and reports a clean
result for a tree nobody asked about.

### `test:bootstrap`

Runs [the consumer bootstrap suite](../../.github/scripts/test-rhino-bootstrap.sh) — sixteen
scenarios over cache integrity, install serialization, stale-owner reclamation, and bounded
retention, against a synthetic release, so it touches neither GitHub nor the real cache. The
pre-push hook runs it when a pushed range touches the consumer boundary; this target exists so it
is also runnable on its own.

## Paths

| Path                                      | What it is                         |
| ----------------------------------------- | ---------------------------------- |
| `apps/rhino-consumer/project.json`        | the targets                        |
| `repo-config.yml`                         | the declared policy                |
| `rhino`                                   | the bootstrap                      |
| `rhino.lock`                              | the pinned release and its digests |
| `.github/scripts/test-rhino-bootstrap.sh` | the bootstrap suite                |
| `specs/tools/rhino-consumer/`             | the bootstrap's specification      |

## See also

- [Repository README](../../README.md)
- [Software quality enforcement](../../repo-governance/development/software-quality-enforcement.md)
- [Push hook verification](../../repo-governance/conventions/push-hook-verification.md)
