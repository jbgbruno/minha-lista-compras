const crypto = require("node:crypto");
const { test, expect } = require("@playwright/test");
const { loadAccounts, login, logout, removeProductIfPresent } = require("./helpers.cjs");

test("produto adicionado pela conta 1 fica visível para a conta 2", async ({ page }) => {
    const accounts = loadAccounts();
    const productName = `PW E2E compartilhado ${crypto.randomBytes(6).toString("hex")}`;
    let added = false;
    await page.goto("/");

    try {
        await login(page, accounts[0]);
        await page.locator("#novo-nome").fill(productName);
        await page.locator("#novo-categoria").selectOption({ label: "Outros" });
        await page.getByRole("button", { name: "Adicionar", exact: true }).click();
        await expect(page.locator("#status-supabase")).toHaveText(
            "Produto adicionado. Todos os usuários já podem vê-lo.",
        );
        added = true;
        await expect(page.locator("#app .nome").getByText(productName, { exact: true })).toBeVisible();

        await logout(page);
        await login(page, accounts[1]);
        await expect(page.locator("#app .nome").getByText(productName, { exact: true })).toBeVisible();
    } finally {
        if (added) {
            let removed = await removeProductIfPresent(page, productName, accounts[1]).catch(() => false);
            if (!removed) {
                removed = await removeProductIfPresent(page, productName, accounts[0]).catch(() => false);
            }
            expect(removed, "o produto temporário deve ser removido após o teste").toBe(true);
        }
    }
});
