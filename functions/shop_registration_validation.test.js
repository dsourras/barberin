const assert = require("node:assert/strict");
const test = require("node:test");
const {hasRequiredSelfServeShopFields, isValidShopContactPhone} =
  require("./shop_registration_validation");

const completeShop = {
  ownerName: "John Apple",
  ownerEmail: "owner@example.com",
  shopName: "Example Barber Shop",
  address: "Main Street 1",
};

test("initial registration can collect the shop phone in the next step", () => {
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

test("shop contact phone accepts real national or international numbers", () => {
  assert.equal(isValidShopContactPhone("+30 693 689 7702"), true);
  assert.equal(isValidShopContactPhone("(212) 555-0198"), true);
  assert.equal(isValidShopContactPhone("123"), false);
  assert.equal(isValidShopContactPhone("+30 abc 6936897702"), false);
  assert.equal(isValidShopContactPhone(""), false);
});
