# Free LFG

A sortable, filterable table for the group finder: leader, roles, free slots, one-click whisper from a template, live filters like (heal >= 1 or tank >= 1) and dps <= 1. /flfg

Part of the **Free** addon suite for WoW Forever, by DecardCain.

## Releasing

1. Bump `## Version` in `FreeLFG.toc` and commit.
2. Push a tag with the same version: `git tag v<version> && git push --tags`.
3. GitHub Actions packages the addon with the BigWigs packager and uploads it to CurseForge (secret `CF_API_KEY`) and to the GitHub releases.
