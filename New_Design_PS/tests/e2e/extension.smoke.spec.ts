import path from "node:path";
import os from "node:os";

import { chromium, expect, test } from "@playwright/test";

test("extension companion loads and its popup renders", async () => {
  const extensionPath = path.join(process.cwd(), "browser-extension", "sscp-companion");
  const userDataDir = path.join(os.tmpdir(), `playwright-extension-profile-${Date.now()}`);

  const context = await chromium.launchPersistentContext(userDataDir, {
    channel: "chromium",
    headless: true,
    args: [
      `--disable-extensions-except=${extensionPath}`,
      `--load-extension=${extensionPath}`,
    ],
  });

  try {
    const page = await context.newPage();
    await page.goto("http://127.0.0.1:3100/sscp", {
      waitUntil: "domcontentloaded",
      timeout: 120000,
    });

    await expect
      .poll(async () =>
        page.evaluate(() => document.documentElement.dataset.sscpCompanionReady),
        { timeout: 15000 },
      )
      .toBe("true");

    const runtimeId = await page.evaluate(
      () => document.documentElement.dataset.sscpCompanionRuntimeId,
    );

    expect(runtimeId).toBeTruthy();

    const popup = await context.newPage();
    await popup.goto(`chrome-extension://${runtimeId}/popup.html`);
    await expect(popup.getByText(/Browser Companion/i)).toBeVisible();
    await expect(popup.getByRole("button", { name: /Quiz This Page/i })).toBeVisible();
  } finally {
    await context.close();
  }
});
