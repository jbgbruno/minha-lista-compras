.PHONY: install test-compartilhamento test-compartilhamento-visual test-e2e test-e2e-visual

install:
	npm install
	npx playwright install chromium

test-compartilhamento: install
	npm run test:sharing

test-compartilhamento-visual: install
	node -e "process.env.PW_HEADED='1'; require('./tests/compartilhamento.playwright.cjs')"

test-e2e: install
	npm run test:e2e

test-e2e-visual: install
	npm run test:e2e:headed
