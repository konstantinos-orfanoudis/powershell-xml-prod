# SSCP Mastery Coach Companion

This companion extension is the browser side of the two-phase tutor build.

## What it does

- Opens the local tutor web app at `/sscp`
- Captures the current page into the tutor
- Captures selected text into the tutor
- Uses browser text-to-speech for quick read-aloud of the current page or selection

## Load it locally

Quick Windows setup from the project root:

```powershell
.\Open-SSCP-Extension-Setup.ps1
```

That opens the tutor, opens the Edge extensions page, and opens this extension folder in Explorer.

1. Open `chrome://extensions` or `edge://extensions`
2. Enable **Developer mode**
3. Click **Load unpacked**
4. Choose this folder: `browser-extension/sscp-companion`

## Default tutor URL

The popup defaults to `http://localhost:3000`.

If your app is running somewhere else, update the URL in the popup and click **Save URL**.

## Expected app endpoints

The extension posts captures to:

- `POST /api/sscp/extension/capture`
- `GET /api/sscp/extension/captures`

Those endpoints are implemented in the main Next.js app.
