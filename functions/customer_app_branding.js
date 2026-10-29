const COLOR_KEYS = [
  "canvas", "paper", "ink", "primary", "primaryDark", "soft", "accent",
];

function normalizeCustomerAppPalette(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("customer-app-palette-required");
  }
  const palette = {};
  for (const key of COLOR_KEYS) {
    const color = String(value[key] || "").trim().toUpperCase();
    if (!/^#[0-9A-F]{6}$/.test(color)) {
      throw new Error(`invalid-customer-app-color-${key}`);
    }
    palette[key] = color;
  }
  return palette;
}

module.exports = {COLOR_KEYS, normalizeCustomerAppPalette};
