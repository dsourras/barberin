const assert = require("node:assert/strict");
const test = require("node:test");
const {hasRequiredSelfServeShopFields} =
  require("./shop_registration_validation");

const completeShop = {
  ownerName: "John Apple",
  ownerEmail: "owner@example.com",
  shopName: "Example Barber Shop",
  address: "Main Street 1",
};

test("self-service registration does not require an owner phone", () => {
  assert.equal(hasRequiredSelfServeShopFields(completeShop), true);
  assert.equal(hasRequiredSelfServeShopFields({
    ...completeShop,
    ownerPhone: "",
  }), true);
});

test("shop identity and booking location remain required", () => {
  for (const field of ["ownerName", "ownerEmail", "shopName", "address"]) {
    assert.equal(hasRequiredSelfServeShopFields({
      ...completeShop,
      [field]: " ",
    }), false, field);
  }
});
