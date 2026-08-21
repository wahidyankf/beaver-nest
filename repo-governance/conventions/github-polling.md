# GitHub Polling

When monitoring a GitHub operation or waiting for GitHub state to change, issue at most one status request every two minutes. Keep a minimum of 120 seconds between repeated GitHub queries in the same monitoring loop.

This limit applies whether polling uses GitHub CLI, an API, a browser, an integration, or another tool. Do not use watch commands or automatic refresh intervals that query GitHub more frequently. Prefer an event-driven wait when one is available.

A single user-requested lookup is not polling. It becomes polling when another status request is made while waiting for the same operation or state transition. After the first lookup, wait the full interval before querying again, even when completion is expected sooner.

This convention reduces avoidable GitHub API traffic and rate-limit pressure without preventing deliberate one-off repository operations.
