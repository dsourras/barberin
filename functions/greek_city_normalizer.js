const catalog = require("./greek_city_catalog.json");

function normalizeCityKey(value) {
  return String(value || "")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLocaleLowerCase("el-GR")
      .replace(/ς/g, "σ")
      .replace(/[’'`]/g, "")
      .replace(/[^a-z0-9\u0370-\u03ff\u1f00-\u1fff]+/giu, " ")
      .replace(/\s+/g, " ")
      .trim();
}

function buildCanonicalShopIdentity({shopName, address, city} = {}) {
  const location = normalizeShopAddress({address, city});
  const normalizedName = normalizeCityKey(shopName);
  const normalizedStreet = normalizeCityKey(location.streetAddress);
  const normalizedCity = normalizeCityKey(location.cityKey || location.city);
  if (!normalizedName || !normalizedStreet) {
    return "";
  }
  return [normalizedName, normalizedCity, normalizedStreet].join("|");
}

const cityByKey = new Map();
for (const entry of catalog.cities || []) {
  const canonical = String(entry?.canonical || "").trim();
  if (!canonical) continue;
  for (const alias of [canonical, ...(entry.aliases || [])]) {
    const key = normalizeCityKey(alias);
    if (key) cityByKey.set(key, canonical);
  }
}

// Common historical and everyday spellings not consistently present in source datasets.
const additionalAliases = {
  "αθηναι": "Αθήνα",
  "athina": "Αθήνα",
  "athens": "Αθήνα",
  "θεσσαλονικαι": "Θεσσαλονίκη",
  "saloniki": "Θεσσαλονίκη",
  "thessaloniki": "Θεσσαλονίκη",
  "πατραι": "Πάτρα",
  "patras": "Πάτρα",
  "πειραιευς": "Πειραιάς",
  "πειραιας": "Πειραιάς",
  "larissa": "Λάρισα",
  "ηρακλειον": "Ηράκλειο",
  "καλαμαι": "Καλαμάτα",
  "nea moudania": "Νέα Μουδανιά",
  "nea kallikrateia": "Νέα Καλλικράτεια",
  "keratsini": "Κερατσίνι",
  "αγιοσ γεωργιοσ κερατσινιου": "Κερατσίνι",
  "agios georgios keratsiniou": "Κερατσίνι",
  "piraeus": "Πειραιάς",
  "patra": "Πάτρα",
};
for (const [alias, canonical] of Object.entries(additionalAliases)) {
  cityByKey.set(normalizeCityKey(alias), canonical);
}

function canonicalGreekCity(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  return cityByKey.get(normalizeCityKey(raw)) || raw;
}

function splitAddressCity(address) {
  const rawAddress = String(address || "").trim();
  if (!rawAddress) {
    return {streetAddress: "", city: "", cityKey: ""};
  }
  const parts = rawAddress.split(",").map((part) => part.trim());
  for (let index = parts.length - 1; index >= 0; index -= 1) {
    const key = normalizeCityKey(parts[index]);
    if (cityByKey.has(key)) {
      const city = cityByKey.get(key);
      return {
        streetAddress: parts.slice(0, index).join(", ").trim(),
        city,
        cityKey: normalizeCityKey(city),
      };
    }
  }
  return {streetAddress: rawAddress, city: "", cityKey: ""};
}

function normalizeShopAddress({address, city} = {}) {
  const rawAddress = String(address || "").trim();
  const rawCity = String(city || "").trim();
  const location = rawCity ? {
    streetAddress: rawAddress,
    city: canonicalGreekCity(rawCity),
    cityKey: normalizeCityKey(canonicalGreekCity(rawCity)),
  } : splitAddressCity(rawAddress);
  return {
    ...location,
    address: [location.streetAddress, location.city]
        .filter(Boolean)
        .join(", ") || rawAddress,
  };
}

function normalizeShopLocation(shop) {
  const source = shop && typeof shop === "object" ? shop : {};
  return normalizeShopAddress({
    address: String(source.streetAddress || source.address || "").trim(),
    city: String(source.city || "").trim(),
  });
}

module.exports = {
  buildCanonicalShopIdentity,
  canonicalGreekCity,
  normalizeCityKey,
  normalizeShopAddress,
  normalizeShopLocation,
};
