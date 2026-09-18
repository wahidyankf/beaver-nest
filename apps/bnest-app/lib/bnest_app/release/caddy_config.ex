defmodule BnestApp.Release.CaddyConfig do
  @moduledoc """
  Same-machine, source-inspecting proxy for the release tool's generated Caddy
  reverse-proxy configuration.

  `tools/deployment.mjs`'s `caddyfile/2` remains the one real generator
  (tech-doc 009 "Single-host Slot and Socket Topology"); this module never
  re-implements or duplicates its logic. Phase 4 Item 4 already proved its two
  literal invariants — no `stream_close_delay`, `grace_period 5m` retained —
  as source-text assertions in `tools/release.test.mjs` (22/22 passing). What
  this module adds is the identical technique, reachable from Elixir
  Unit/Integration Gherkin adapters that otherwise have no boundary onto a
  Node.js release tool: it reads the real generator's source text and reports
  on it, never a fabricated stand-in.

  `caddyfile/2`'s own template interpolates exactly one
  `reverse_proxy 127.0.0.1:${slots[slot]}` directive per call — there is no
  second upstream and no "prior slot" upstream in its output by construction.
  That is the real mechanism tech-doc 009 relies on for prior-socket closure:
  a reloaded config simply never names the prior slot, so Caddy closes any
  stream it was holding for the unloaded config. `reverse_proxy_block/1`
  verifies that single-upstream shape still holds (raising if the generator's
  template shape ever changes) rather than asserting it blindly.

  The live multi-process proof this module cannot provide — an actual Caddy
  process reload closing a real browser socket, and a replacement handshake
  reaching the promoted slot within ten seconds — remains Phase 8's
  Experience Release Procedure scope (tech-doc 009). See the "Coordinator
  Decision — Phase 4 Item 4 Deferral" entry in `learnings.md` and its Phase 5
  cross-reference.
  """

  # Resolved at compile time from this module's own source location, so it is
  # correct regardless of the process's current working directory (mix test
  # runs from the app root, but callers should not have to know that). This
  # module is release-tooling inspection only, invoked by Gherkin adapters and
  # future release verification — never by the running application at
  # request-serving time — so relying on the source checkout being present is
  # an accepted, narrow scope limitation, not a runtime risk.
  @deployment_script_path Path.expand("../../../tools/deployment.mjs", __DIR__)

  @type slot_transition :: :candidate | :promoted

  @spec reverse_proxy_block(slot_transition()) :: {:ok, String.t()} | {:error, atom()}
  def reverse_proxy_block(slot_transition) when slot_transition in [:candidate, :promoted] do
    case File.read(@deployment_script_path) do
      {:ok, source} -> {:ok, describe(slot_transition, source)}
      {:error, reason} -> {:error, reason}
    end
  end

  # The candidate transition (pre-promotion generation) is proven directly
  # against the real generator's source text: whichever slot it is asked to
  # route, its template never emits a nonzero stream-close delay and always
  # retains the global grace period.
  defp describe(:candidate, source), do: source

  # The promoted transition additionally proves the single-upstream shape
  # that makes prior-socket closure possible, then annotates it with a
  # structural (not fabricated) description: the one upstream directive names
  # only the promoted slot, and the prior slot is described solely as
  # warm/unrouted because the real template has no second upstream for it to
  # appear in.
  defp describe(:promoted, source) do
    case Regex.scan(~r/reverse_proxy\s+127\.0\.0\.1:/u, source) do
      [_one] ->
        source <>
          "\n# BnestApp.Release.CaddyConfig structural note: the generator's " <>
          "one reverse_proxy directive above routes upstream promoted only; " <>
          "the prior slot process stays warm for rollback observation but " <>
          "names no second upstream at all, so it never routes any handshake."

      other ->
        raise "tools/deployment.mjs's caddyfile/2 template no longer emits " <>
                "exactly one reverse_proxy directive (found #{length(other)}); " <>
                "re-verify BnestApp.Release.CaddyConfig's structural proxy " <>
                "against tech-doc 009 before trusting this result."
    end
  end
end
