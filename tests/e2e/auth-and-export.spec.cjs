const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const { test, expect } = require("@playwright/test");
const { loadAccounts, login } = require("./helpers.cjs");

const CABECALHO = "categoria;nome;quantidade;unidade;preco_aproximado;observacao";

test("ações de dados ficam ocultas sem autenticação", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("#form-auth")).toBeVisible();
    await expect(page.locator("#ferramentas-csv")).toBeHidden();
});

test("usuário autenticado vê exportação, modelo e importação", async ({ page }) => {
    const [account] = loadAccounts();
    await page.goto("/");
    await login(page, account);

    await expect(page.locator("#ferramentas-csv")).toBeVisible();
    await expect(page.getByRole("button", { name: "Exportar CSV" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Baixar modelo" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Importar CSV" })).toBeVisible();
});

test("modelo e exportação baixam CSV com cabeçalhos e produtos", async ({ page }, testInfo) => {
    const [account] = loadAccounts();
    await page.goto("/");
    await login(page, account);

    const [modelo] = await Promise.all([
        page.waitForEvent("download"),
        page.getByRole("button", { name: "Baixar modelo" }).click(),
    ]);
    assert.equal(modelo.suggestedFilename(), "modelo-produtos.csv");
    const modeloPath = testInfo.outputPath("modelo-produtos.csv");
    await modelo.saveAs(modeloPath);
    const textoModelo = (await fs.readFile(modeloPath, "utf8")).replace(/^\uFEFF/, "").trim();
    assert.equal(textoModelo, CABECALHO);

    const [exportacao] = await Promise.all([
        page.waitForEvent("download"),
        page.getByRole("button", { name: "Exportar CSV" }).click(),
    ]);
    assert.equal(exportacao.suggestedFilename(), "produtos-catalogo.csv");
    const exportacaoPath = testInfo.outputPath("produtos-catalogo.csv");
    await exportacao.saveAs(exportacaoPath);
    const textoExportado = (await fs.readFile(exportacaoPath, "utf8")).replace(/^\uFEFF/, "");
    assert.ok(textoExportado.startsWith(`${CABECALHO}\r\n`));
    assert.match(textoExportado, /Mercearia;Arroz(?:;|\r?\n)/);
});
