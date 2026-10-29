const assert = require("node:assert/strict");
const test = require("node:test");
const {normalizeCustomerAppPalette} = require("./customer_app_branding");

const palette = {
  canvas: "#F6F5EF",
  paper: "#FFFDF8",
  ink: "#102B35",
  primary: "#1B5B70",
  primaryDark: "#0F3440",
  soft: "#DCEEF2",
  accent: "#9AC7B7",
};

test("requires an explicit complete seven-color palette", () => {
  assert.deepEqual(normalizeCustomerAppPalette(palette), palette);
  assert.throws(() => normalizeCustomerAppPalette(null),
      /customer-app-palette-required/);
  assert.throws(() => normalizeCustomerAppPalette({...palette, ink: ""}),
      /invalid-customer-app-color-ink/);
  assert.throws(() => normalizeCustomerAppPalette({...palette, accent: "red"}),
      /invalid-customer-app-color-accent/);
});
