const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const { chromium } = require("@playwright/test");

const workspace = path.resolve(__dirname, "..");
const htmlPath = path.join(workspace, "index.html");

function loadCredentials() {
    const envPath = path.join(workspace, ".env");
    if (!fs.existsSync(envPath)) {
        throw new Error("Arquivo .env não encontrado na raiz do projeto.");
    }

    const values = {};
    const content = fs.readFileSync(envPath, "utf8").replace(/^\uFEFF/, "");
    content.split(/\r?\n/).forEach((line) => {
        const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
        if (!match) return;
        values[match[1]] = match[2].replace(/^(['"])(.*)\1$/, "$2");
    });

    const accounts = [
        { email: values.usuario_1, password: values.senha_1 },
        { email: values.usuario_2, password: values.senha_2 },
    ];
    if (accounts.some((account) => !account.email || !account.password)) {
        throw new Error("O .env precisa definir usuario_1, senha_1, usuario_2 e senha_2.");
    }
    if (accounts[0].email.toLowerCase() === accounts[1].email.toLowerCase()) {
        throw new Error("As duas contas do .env precisam ser diferentes.");
    }
    return accounts;
}

function startServer() {
    const server = http.createServer((request, response) => {
        const pathname = new URL(request.url, "http://localhost").pathname;
        if (pathname !== "/" && pathname !== "/index.html") {
            response.writeHead(404).end("Not found");
            return;
        }
        response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        fs.createReadStream(htmlPath).pipe(response);
    });
    return new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(0, "127.0.0.1", () => resolve(server));
    });
}

async function waitForLoggedIn(page) {
    await page.locator("#form-novo").waitFor({ state: "visible", timeout: 30000 });
    await page.waitForFunction(
        () => document.querySelector("#status-supabase")?.textContent === "Sincronizado",
        null,
        { timeout: 30000 },
    );
}

async function login(page, account) {
    if (await page.locator("#form-novo").isVisible().catch(() => false)) {
        await waitForLoggedIn(page);
        return;
    }
    await page.locator("#auth-email").fill(account.email);
    await page.locator("#auth-senha").fill(account.password);
    await page.locator("#btn-entrar").click();
    await waitForLoggedIn(page);
}

async function removeTestProduct(page, productName, account) {
    if (page.isClosed()) return false;
    let removeButton = page.getByRole("button", {
        name: `Remover ${productName}`,
        exact: true,
    });
    if (!(await removeButton.isVisible().catch(() => false))) {
        await page.reload({ waitUntil: "domcontentloaded" }).catch(() => { });
        await login(page, account).catch(() => { });
        removeButton = page.getByRole("button", {
            name: `Remover ${productName}`,
            exact: true,
        });
    }
    if (!(await removeButton.isVisible().catch(() => false))) return false;

    page.once("dialog", (dialog) => dialog.accept().catch(() => { }));
    await removeButton.click();
    await page.getByText(productName, { exact: true }).waitFor({
        state: "detached",
        timeout: 15000,
    });
    return true;
}

async function main() {
    const accounts = loadCredentials();
    const productName = `PW compartilhado ${crypto.randomBytes(6).toString("hex")}`;
    let server;
    let browser;
    let context;
    let page;
    let insertionConfirmed = false;
    let verified = false;
    let cleanupConfirmed = false;
    let stage = "inicialização";
    let testError;

    try {
        server = await startServer();
        const address = server.address();
        const headed = process.env.PW_HEADED === "1";
        browser = await chromium.launch({
            headless: !headed,
            slowMo: headed ? 500 : 0,
        });
        context = await browser.newContext();
        page = await context.newPage();
        if (headed) {
            console.log(`Janela Playwright aberta em http://127.0.0.1:${address.port}/`);
        }

        stage = "login da conta 1";
        console.log("Etapa 1/5: entrando com usuario_1.");
        await page.goto(`http://127.0.0.1:${address.port}/`, {
            waitUntil: "domcontentloaded",
        });
        await login(page, accounts[0]);

        stage = "inclusão do produto temporário";
        console.log("Etapa 2/5: adicionando um produto temporário em Outros.");
        await page.locator("#novo-nome").fill(productName);
        await page.locator("#novo-categoria").selectOption({ label: "Outros" });
        await page.getByRole("button", { name: "Adicionar", exact: true }).click();
        await page
            .getByText("Produto adicionado. Todos os usuários já podem vê-lo.", {
                exact: true,
            })
            .waitFor({ timeout: 20000 });
        insertionConfirmed = true;

        stage = "logout da conta 1";
        console.log("Etapa 3/5: saindo da conta 1.");
        await page.locator("#btn-sair").click();
        await page.locator("#btn-entrar").waitFor({ state: "visible", timeout: 10000 });

        stage = "login da conta 2";
        console.log("Etapa 4/5: entrando com usuario_2.");
        await login(page, accounts[1]);

        stage = "visibilidade entre usuários";
        console.log("Etapa 5/5: verificando o produto na conta 2.");
        await page.getByText(productName, { exact: true }).waitFor({
            state: "visible",
            timeout: 20000,
        });
        verified = true;
        if (headed) await page.waitForTimeout(2000);
    } catch (error) {
        testError = error;
    } finally {
        if (insertionConfirmed) {
            stage = "limpeza do produto temporário";
            try {
                cleanupConfirmed = await removeTestProduct(page, productName, accounts[1]);
                if (!cleanupConfirmed) {
                    cleanupConfirmed = await removeTestProduct(page, productName, accounts[0]);
                }
            } catch {
                cleanupConfirmed = false;
            }
        }
        await context?.close().catch(() => { });
        await browser?.close().catch(() => { });
        if (server) {
            await new Promise((resolve) => server.close(resolve));
        }
    }

    if (testError) {
        console.error(`FALHOU na etapa: ${stage}. Detalhes omitidos para proteger as credenciais.`);
        process.exitCode = 1;
    } else {
        assert.equal(verified, true, "A segunda conta deve encontrar o produto compartilhado.");
    }
    if (insertionConfirmed && !cleanupConfirmed) {
        console.error(`ATENÇÃO: não consegui confirmar a remoção de "${productName}" do catálogo.`);
        process.exitCode = 1;
    }
    if (process.exitCode) return;

    console.log("PASSOU: a conta 1 adicionou um produto e a conta 2 conseguiu visualizá-lo.");
    console.log("LIMPEZA: o produto temporário foi removido do catálogo compartilhado.");
}

main().catch(() => {
    console.error("FALHOU na inicialização. Verifique a instalação do Playwright e o .env; credenciais não foram exibidas.");
    process.exitCode = 1;
});
