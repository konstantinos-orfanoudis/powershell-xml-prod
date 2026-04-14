import { expect, test } from "@playwright/test";

test("main tutor workflows render and respond", async ({ page }) => {
  await page.goto("/sscp", { waitUntil: "domcontentloaded", timeout: 120000 });

  await expect(page.getByRole("heading", { name: /SSCP \/ CISSP \/ CTO Question Tutor/i })).toBeVisible();
  await expect(page.getByRole("button", { name: /Generate questions/i })).toBeVisible();
  await expect
    .poll(async () => page.locator("main").getAttribute("data-coach-ready"), { timeout: 120000 })
    .toBe("true");

  await page.getByRole("button", { name: /Single domain/i }).click();
  await page.getByRole("button", { name: /^CTO$/i }).click();
  await page.getByRole("button", { name: /Generate questions/i }).click();

  await expect(page.getByText(/Question set with answers ready\./i)).toBeVisible({ timeout: 120000 });
  await expect(page.getByText(/Answers and explanations are displayed below/i).first()).toBeVisible({ timeout: 60000 });
  await expect(page.getByText(/An SSCP may answer like this/i).first()).toBeVisible({ timeout: 60000 });
  await expect(page.getByText(/A CISSP may answer like this/i).first()).toBeVisible({ timeout: 60000 });
  await expect(page.getByText(/A CTO may answer like this/i).first()).toBeVisible({ timeout: 60000 });
});
