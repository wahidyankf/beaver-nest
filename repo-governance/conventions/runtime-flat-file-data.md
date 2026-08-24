# Runtime Flat-File Data

Use local flat files only for small, private runtime data below `data/`. This convention applies to every application, tool, and agent that reads or writes that directory.

## Layout

- `data/general/` contains mutable application-wide data shared by the household. Static content shipped with an application must remain in source control.
- `data/users/<user-id>/` contains preferences and activity progress owned by one identified user. An application must not write here until it has an ownership boundary that prevents records from being mixed between users.
- `data/system/` contains application-owned operational state, such as migration or durable-work state. It must not contain credentials, tokens, or user-authored content.

## File Rules

- Keep all runtime data ignored by Git; only approved directory placeholders may be tracked.
- Keep each activity in its own subdirectory, for example `data/users/<user-id>/sifat-allah/progress.json`.
- Persist UTF-8 JSON with an explicit schema version, validate it when reading, and use atomic replacement when writing.
- Never derive a file path directly from browser or other external input.

Flat files are an interim local-storage mechanism. Revisit this convention when the planned private database volume becomes available.
