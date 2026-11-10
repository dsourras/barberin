function hasRequiredSelfServeShopFields({ownerName, ownerEmail, shopName, address}) {
  return [ownerName, ownerEmail, shopName, address]
      .every((value) => String(value || "").trim().length > 0);
}

function isValidShopContactPhone(value) {
  const phone = String(value || "").trim();
  const digits = phone.replace(/\D/g, "");
  return /^\+?[0-9\s().-]+$/.test(phone) &&
    digits.length >= 7 && digits.length <= 15;
}

module.exports = {hasRequiredSelfServeShopFields, isValidShopContactPhone};
