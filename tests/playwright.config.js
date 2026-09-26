const { defineConfig } = require('@playwright/test');
module.exports = defineConfig({
  testDir: '.',
  testMatch: /.*\.spec\.js/,
  timeout: 30000,
  workers: 4,
  reporter: [['list']],
  use: {
    baseURL: 'http://localhost:4173', locale: 'ar',
    // local runs can point at an already-installed Chromium; CI installs its own
    launchOptions: process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {},
  },
  webServer: { command: 'node serve.js', url: 'http://localhost:4173/manifest.json', reuseExistingServer: true },
});
