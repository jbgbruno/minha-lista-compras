const fs = require("node:fs");
const path = require("node:path");

function loadAccounts() {
    const envPath = path.resolve(__dirname, "..", "..", ".env");
    if (!fs.existsSync(envPath)) {
        throw new Error("Arquivo .env não encontrado na raiz do projeto.");
    }
    const values = {};
    fs.readFileSync(envPath, "utf8")
        .replace(/^\uFEFF/, "")
        .split(/\r?\n/)
        .forEach((line) => {
            const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
            if (match) values[match[1]] = match[2].replace(/^(['"])(.*)\1$/, "$2");
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

async function logout(page) {
    await page.locator("#btn-sair").click();
    await page.locator("#form-auth").waitFor({ state: "visible", timeout: 10000 });
}

async function removeProductIfPresent(page, productName, account) {
    if (page.isClosed()) return false;
    let removeButton = page.getByRole("button", {
        name: `Remover ${productName}`,
        exact: true,
    });
    if (!(await removeButton.isVisible().catch(() => false))) {
        if (!(await page.locator("#form-novo").isVisible().catch(() => false))) {
            await login(page, account);
        } else {
            await waitForLoggedIn(page);
        }
        removeButton = page.getByRole("button", {
            name: `Remover ${productName}`,
            exact: true,
        });
    }
    if (!(await removeButton.isVisible().catch(() => false))) return false;

    page.once("dialog", (dialog) => dialog.accept().catch(() => { }));
    await removeButton.click();
    await page.locator("#app .nome").getByText(productName, { exact: true }).waitFor({
        state: "detached",
        timeout: 15000,
    });
    return true;
}

module.exports = { loadAccounts, login, logout, removeProductIfPresent, waitForLoggedIn };
