# Markdown Links

Every repository-authored Markdown file must keep its internal links valid. Resolve a relative link from the file that contains it; its target must remain inside the repository and exist as a file or directory.

Fragments and query strings do not alter the target-file check. External and protocol links are outside this local validation. Markdown files below `plans/done/` are historical archives and are excluded as link-validation sources; current documents may still link to them.

Badakmini enforces the rule across repository-owned Markdown through:

```sh
npm exec -- nx run -p badakmini-cli -t test:repo
```

Update affected links in the same change as a move, rename, or deletion.
