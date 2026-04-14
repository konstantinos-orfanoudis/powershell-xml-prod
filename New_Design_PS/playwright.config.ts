import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/e2e",
  timeout: 180_000,
  workers: 1,
  use: {
    baseURL: "http://127.0.0.1:3100",
    headless: true,
    navigationTimeout: 120_000,
  },
  webServer: {
    command: "npx next dev -H 127.0.0.1 -p 3100",
    url: "http://127.0.0.1:3100",
    reuseExistingServer: false,
    timeout: 240_000,
  },
});
