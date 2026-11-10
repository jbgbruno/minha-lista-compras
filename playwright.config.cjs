const { defineConfig } = require("@playwright/test");

module.exports = defineConfig({
    testDir: "./tests/e2e",
    fullyParallel: false,
    workers: 1,
    timeout: 90000,
    expect: { timeout: 15000 },
    reporter: "list",
    outputDir: "./test-results",
    use: {
        baseURL: "http://127.0.0.1:4173",
        browserName: "chromium",
        launchOptions: { slowMo: process.argv.includes("--headed") ? 400 : 0 },
        trace: "retain-on-failure",
        screenshot: "only-on-failure",
    },
    webServer: {
        command: "node tests/serve.cjs",
        url: "http://127.0.0.1:4173",
        reuseExistingServer: !process.env.CI,
        timeout: 15000,
    },
});
