const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");
const { test, expect } = require("@playwright/test");
const { loadAccounts, login, removeProductIfPresent } = require("./helpers.cjs");

const CABECALHO = "categoria;nome;quantidade;unidade;preco_aproximado;observacao";

async function escolherArquivoCsv(page, arquivo) {
    const [fileChooser] = await Promise.all([
        page.waitForEvent("filechooser"),
        page.getByRole("button", { name: "Importar CSV" }).click(),
    ]);
    await fileChooser.setFiles(arquivo);
}

test("importa novos produtos, conta duplicatas e mostra o resultado", async ({ page }, testInfo) => {
    const [account] = loadAccounts();
    const productName = `PW E2E import ${crypto.randomBytes(6).toString("hex")}`;
    let importAttempted = false;
    await page.goto("/");
    await login(page, account);

    try {
        const csvPath = testInfo.outputPath("importacao-valida.csv");
        await fs.mkdir(path.dirname(csvPath), { recursive: true });
        const row = `Outros;${productName};2;Un;1,5;"criado pelo teste E2E"`;
        await fs.writeFile(csvPath, `\uFEFF${CABECALHO}\r\n${row}\r\n${row}\r\n`, "utf8");

        page.once("dialog", (dialog) => dialog.accept().catch(() => { }));
        importAttempted = true;
        await escolherArquivoCsv(page, csvPath);

        const result = page.locator("#resultado-csv");
        await expect(result).toContainText("Importados: 1 | Já existentes: 1 | Erros: 0");
        await expect(page.locator("#app .nome").getByText(productName, { exact: true })).toBeVisible();
        await expect(page.locator("#status-supabase")).toHaveText("Importação concluída.");
    } finally {
        if (importAttempted) {
            await removeProductIfPresent(page, productName, account).catch(() => false);
        }
    }
});

test("CSV com linha inválida informa o erro sem gravar produto", async ({ page }, testInfo) => {
    const [account] = loadAccounts();
    const productName = `PW E2E invalido ${crypto.randomBytes(6).toString("hex")}`;
    await page.goto("/");
    await login(page, account);

    const csvPath = testInfo.outputPath("importacao-invalida.csv");
    await fs.mkdir(path.dirname(csvPath), { recursive: true });
    await fs.writeFile(
        csvPath,
        `\uFEFF${CABECALHO}\r\nOutros;${productName};-3;Un;;\r\n`,
        "utf8",
    );
    await escolherArquivoCsv(page, csvPath);

    const result = page.locator("#resultado-csv");
    await expect(result).toContainText("Importados: 0 | Já existentes: 0 | Erros: 1");
    await expect(result).toContainText("Linha 2:");
    await expect(page.locator("#app .nome").getByText(productName, { exact: true })).toHaveCount(0);
    await expect(page.locator("#status-supabase")).toHaveText("Sincronizado");
    assert.equal(await page.locator("#form-novo").isVisible(), true);
});
