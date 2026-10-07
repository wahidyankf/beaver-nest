# Maintenance Workflows

Upkeep and delivery: what keeps the repository clean and lean, and the service reachable.

## Directory Map

- [Dev artifact clean-up](dev-artifact-clean-up.md) removes the worktree, both copies of the branch, and the build output this work produced, and nothing else, then brings the primary checkout level with `origin/main`.
- [Dev artifact clean-up modules](dev-artifact-clean-up/README.md) hold other actors' artifacts and bare clones, in reading order.
- [Development Caddy deployment](development-caddy-deployment.md) promotes verified blue/green Phoenix releases behind the stable local Caddy proxy.
- [Development server restart](development-server-restart.md) restarts an existing local server through its original tmux pane and Nx target.
- [Development tailnet proxy](development-tailnet-proxy.md) manages a persistent private HTTPS proxy independently from app-server restarts.
- [Rules grooming](rules-grooming.md) sweeps the rule corpus for volume carrying no obligation and hands every approved reduction to propagation.
