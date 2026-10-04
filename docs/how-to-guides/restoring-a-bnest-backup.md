# Restoring a Bnest Backup

This guide proves that one nightly Bnest backup can be restored. The restore drill restores the artifact you choose into a fresh isolated root that the task creates and removes, prints redacted evidence of what it could read, and leaves the backup and the running database untouched. It is the proof that a backup is usable, not only that it exists.

The drill never restores over the live database and never writes to the backup folder. It reads the destination exactly as the nightly backup configuration names it, so run it on the host that holds the backups, with the deployment environment that [Releasing Bnest](releasing-bnest.md) derives.

## 1. Choose an artifact

List the backup folder and pick one nightly artifact by its file name. The retained backups are the seven latest WIB dates, one artifact for each, each beside a receipt file. Choose the newest one you want to trust, or an older one to prove that history restores.

If you are unsure which dates should be there, run the reconcile check first:

```sh
cd apps/bnest-app
mix bnest.backup.reconcile
```

It reports each retained date whose artifact is missing or changed. Pick an artifact from a date it does not list. Exit status `0` means every retained backup is present.

## 2. Run the drill

Pass the bare file name of the artifact. A path, a `..` segment, a directory and a symbolic link are all refused:

```sh
cd apps/bnest-app
mix bnest.backup.restore_drill --artifact <artifact-file-name>
```

The task restores through `Backup.restore/1` into a temporary root it creates, reads the restored database, then removes the root.

## 3. Read the evidence

A successful drill exits `0` and prints these lines, with counts from your artifact:

```text
Restore drill: restored the artifact into a fresh isolated root
Rooms readable: 1
Messages readable: 120, in ascending order
Push subscriptions: 2
Delivery states: delivered, pending
Restore root: removed
```

Two readings are valid but worth a look: `Messages readable: 0` (the artifact holds no messages) and `Delivery states: none` (no push delivery was recorded). Both exit `0`.

"Readable" means the restored database opened, its active room was found, its messages were read back in ascending order and its push subscription structure was present. The counts are the evidence: the room count is normally `1`, the message count should be close to what the household expects for that date, and `Restore root: removed` confirms that nothing was left behind. The output never contains a path, a message body or a push credential, so it is safe to paste into a report.

## 4. What a failure means

Every failure exits `1` and prints one fixed line. None names a path.

| Line                                                                                                    | Meaning                                                                                                     | What to do                                                                                        |
| ------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `Restore drill: refused. The artifact must be a regular file inside the configured backup destination.` | The name is not a regular file directly inside the backup folder (missing, a directory, a link, or a path). | Check the file name against the folder listing and retry with the bare name.                      |
| `Restore drill: the backup destination could not be read.`                                              | The configured backup folder is missing, unmarked or unreadable.                                            | Check the backup configuration and the folder, then run `mix bnest.backup.reconcile`.             |
| `Restore drill: the artifact could not be restored.`                                                    | The file exists but does not restore: it is damaged, truncated or not a Bnest database.                     | Treat this backup as unusable. Run the drill on the next older artifact and record both outcomes. |
| `Rooms readable: 0`, or `Messages readable: N, not in ascending order`                                  | The restored database opened but the room is missing or its messages are out of order.                      | Treat this backup as unusable and restore the next older artifact.                                |
| `Restore root: not removed`                                                                             | The task could not confirm that its temporary root was removed.                                             | Look for a leftover `bnest-restore-` directory in the temporary directory, remove it, and rerun.  |

A restore that fails on a backup that the nightly run reported as verified means every backup since is suspect. Do not delete anything. Record the date and the outcome, restore an older artifact to find the last good one, and raise it with the repository owner before the next nightly run prunes the older copies.

## 5. Afterwards

Nothing needs cleaning: the task removed its root. Record the date, the artifact's date and the printed counts, never the artifact's path or any message content.
