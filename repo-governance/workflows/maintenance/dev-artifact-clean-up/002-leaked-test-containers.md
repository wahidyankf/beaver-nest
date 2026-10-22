# Leaked Test Containers

What [dev artifact clean-up](../dev-artifact-clean-up.md) does about containers, volumes, and networks that a task's test or dev run left behind. It never touches the running service's containers or runtime data.

A **leaked test container** is a container, volume, or network that a task's test or dev run created and that outlives
the run. A run killed before its own teardown, such as one HIPPO shed, leaks one. Leaked containers
hold memory in the container VM, and HIPPO then defers unrelated work with memory warnings.

Detect them read-only. `$ROOT` is the task's checkout or worktree; a repository may also declare a name prefix:

```bash
for n in $(docker ps -a --format '{{.Names}}'); do
  w=$(docker inspect "$n" --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}')
  case "$w" in "$ROOT"|"$ROOT"/*) echo "$n";; esac
done
```

Remove only those names, then re-run the listing and expect zero. `<project>` is the container's
`com.docker.compose.project` label:

```bash
docker rm -f -v <name>
docker volume rm $(docker volume ls -q --filter label=com.docker.compose.project=<project>)
docker network rm $(docker network ls -q --filter label=com.docker.compose.project=<project>)
```

Never use `docker system prune`, `docker volume prune`, or an alias that removes every container for this: each removes
what the task did not create. Never remove a container another actor is running. When no container is left running and
the engine runs in a desktop VM, stop its app (`docker desktop stop`); the VM keeps its memory until it stops.
