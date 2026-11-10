function hasRequiredSelfServeShopFields({ownerName, ownerEmail, shopName, address}) {
  return [ownerName, ownerEmail, shopName, address]
      .every((value) => String(value || "").trim().length > 0);
}

module.exports = {hasRequiredSelfServeShopFields};
