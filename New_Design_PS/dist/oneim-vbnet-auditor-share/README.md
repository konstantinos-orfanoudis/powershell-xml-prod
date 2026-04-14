# OneIM VB.NET Auditor Share Package

This zip-ready folder contains a sanitized handoff copy of `oneim-vbnet-auditor` for peer review.

Start here:

- package guide: `oneim-vbnet-auditor/docs/COLLEAGUE-HANDOFF.md`
- skill manifest: `oneim-vbnet-auditor/SKILL.md`
- Codex interface metadata: `oneim-vbnet-auditor/agents/openai.yaml`

Important notes:

- the original `output/` folder was excluded to avoid sharing machine-specific artifacts and sensitive connection details
- the packaged copy was adjusted so live-session defaults can be supplied through `ONEIM_TESTASSIST_ROOT` and `ONEIM_PROJECT_CONFIG_PATH`
- if the reviewer only needs to inspect the logic, they can read the package without installing anything

If the reviewer wants to install it as a Codex skill, copy the `oneim-vbnet-auditor` folder into `%USERPROFILE%\.codex\skills\`.
