# Run Work Under the HIPPO Guard

Run every local compute-bearing command under HIPPO admission, never bypassed:

```sh
./hippo run --class <ephemeral|transactional|service> --resource-tier <light|standard|heavy> --disk-path . -- <cmd>
```

Pick the class and tier for what the work is: `ephemeral` for repeatable checks, `transactional` for indivisible
mutations, `service` for long-running development servers.

Exit `124` means a limit stopped the work: `storage-blocked` means free disk first, since waiting frees none;
`capacity-deferred` means retry when the host is quieter. Exit `125` means HIPPO itself refused; only `never-started`
receipts apply, so replan instead of retrying.

Since v0.13.0, a machine file may also carry opt-in proportional thresholds (`coordination.memoryPolicy`, schema 3
only) and an opt-in per-machine swap gate (`coordination.swapUsedMaxMultiple`); an omitted key keeps the legacy
behavior. The swap gate waives byte-based swap warnings while swap in use stays within the declared multiple of
physical RAM; PSI and pressure signals still apply. No production percents, floors, or multiples are set anywhere yet.
