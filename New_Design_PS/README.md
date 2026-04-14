# SSCP + CISSP Coach Workspace

This workspace contains the full tutor project plus the browser extension companion.

## What is included

- `app/sscp` - the main SSCP study coach UI
- `app/api/sscp` - planning, teaching, drills, reviews, mock exams, notes import, resources, narration, and extension capture routes
- `lib/sscp` - study models, catalog data, notes parsing, and tutor logic
- `browser-extension/sscp-companion` - Chrome/Edge extension for page capture, selection capture, and quick read-aloud

## Source trust policy

The tutor uses three source layers in this order:

1. `official` - canonical ISC2 outline grounding for SSCP and CISSP
2. `trusted_live` - current cybersecurity articles, videos, and examples from trusted sources
3. `user_notes` - imported note material from the local `SSCP.zip` archive as supplemental reinforcement only

If these conflict, the higher-trust source wins.

## Run the tutor on Windows

From the project root:

```powershell
npm install
npm run dev
```

Then open:

`http://localhost:3000/sscp`

If you want a one-command launcher on Windows, run:

```powershell
.\Start-SSCP-CISSP-Coach.ps1
```

That script installs dependencies if needed, launches the dev server, and opens the tutor page.

## Browser extension companion

Extension folder:

`browser-extension/sscp-companion`

Quick Windows setup:

```powershell
.\Open-SSCP-Extension-Setup.ps1
```

That script opens the tutor, opens the Edge extensions page, and opens the unpacked extension folder in Explorer.

To load it into Chrome or Edge:

1. Open `chrome://extensions` or `edge://extensions`
2. Turn on `Developer mode`
3. Click `Load unpacked`
4. Choose `browser-extension/sscp-companion`

The extension expects the tutor app to be running locally and defaults to:

`http://localhost:3000`

## Desktop notes import

The tutor can import and chunk supplemental PDF notes from:

`C:\Users\aiuser\Desktop\SSCP.zip`

Those note chunks are labeled as `User notes reference`, not `official source`.

## Main tutor features

- Adaptive 7-day study planning
- Learn, Drill, Resources, and Library workspaces
- Mixed-format questions
- Side-by-side `SSCP review` and `CISSP review`
- Read-aloud controls
- Mindmaps and diagrams for summaries and memorization
- Curated and live cybersecurity resources
- Browser extension capture flow

## Build check

To verify the workspace compiles:

```powershell
npm run build
```

## Notes

- The app is designed as a local-first workspace.
- The browser extension is a companion, not a replacement for the main tutor UI.
- Current cybersecurity resources should always be treated as time-sensitive and shown with source/date context.
