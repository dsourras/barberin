const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onValueWritten} = require("firebase-functions/v2/database");
const {setGlobalOptions} = require("firebase-functions/v2");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getDatabase} = require("firebase-admin/database");
const {getMessaging} = require("firebase-admin/messaging");
const {getStorage} = require("firebase-admin/storage");
const {defineSecret} = require("firebase-functions/params");
const {createHash, randomUUID} = require("node:crypto");
const nodemailer = require("nodemailer");
const {buildCanonicalShopIdentity, normalizeShopAddress, normalizeShopLocation} =
  require("./greek_city_normalizer");

initializeApp();

setGlobalOptions({
  region: "europe-west1",
  maxInstances: 10,
});

const DEFAULT_CUSTOMER_APP_NAME = "Customer Booking App";
const CUSTOMER_NOTIFICATION_CHANNEL_ID = "barbero_customer_updates";
const AVAILABILITY_STEP_MINUTES = 5;
const BILLING_TRIAL_DAYS = 30;
const BILLING_MONTHLY_PRICE_EUR = 29.99;
const BILLING_YEARLY_PRICE_EUR = 299.99;
const BILLING_YEARLY_SAVINGS_EUR = 59.89;
const BILLING_MONTHLY_PRODUCT_ID = "barbero_monthly";
const BILLING_YEARLY_PRODUCT_ID = "barbero_yearly";
const BILLING_ANDROID_PACKAGE_NAME = "com.barberin.app";
const BILLING_IOS_BUNDLE_ID = "com.barberin.app";
const BILLING_MACOS_BUNDLE_ID = "com.barberin.app.macos";
const ANDROID_PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher";
const APPLE_VERIFY_RECEIPT_PRODUCTION_URL = "https://buy.itunes.apple.com/verifyReceipt";
const APPLE_VERIFY_RECEIPT_SANDBOX_URL = "https://sandbox.itunes.apple.com/verifyReceipt";
const BILLING_CREDENTIALS_BUCKET = "barbero-88d00.firebasestorage.app";
const BILLING_CREDENTIALS_PREFIX = "internal/billing-credentials";
const BILLING_CLAIMS_PREFIX = "internal/billing-claims";
const BILLING_SYNC_INDEX_PATH = "billingSyncIndex";
const BILLING_SYNC_INDEX_META_PATH = "billingSyncIndexMeta";
const BILLING_SYNC_INTERVAL_MS = 6 * 60 * 60 * 1000;
const BILLING_SYNC_ERROR_RETRY_MS = 60 * 60 * 1000;
const BILLING_SYNC_EXPIRY_BUFFER_MS = 60 * 60 * 1000;
const BILLING_SYNC_EXPIRED_RETRY_MS = 24 * 60 * 60 * 1000;
const APPOINTMENT_CUTOFF_OPTIONS_MINUTES = [
  0,
  30,
  60,
  120,
  180,
  360,
  720,
  1440,
];
const NOTIFICATION_OUTBOX_PATH = "notificationOutbox";
const NOTIFICATION_INBOX_PATH = "notificationInbox";
const NOTIFICATION_CLEANUP_INDEX_PATH = "notificationCleanupIndex";
const SHOP_DIRECTORY_PATH = "shopDirectory";
const APPOINTMENT_REMINDER_INDEX_PATH = "appointmentReminderIndex";
const APPOINTMENT_REMINDER_INDEX_META_PATH = "appointmentReminderIndexMeta";
const NOTIFICATION_OUTBOX_MAX_ATTEMPTS = 5;
const NOTIFICATION_OUTBOX_LOCK_MS = 10 * 60 * 1000;
const NOTIFICATION_OUTBOX_IDLE_TIMESTAMP = Number.MAX_SAFE_INTEGER;
const NOTIFICATION_CLEANUP_INDEX_META_PATH = "notificationCleanupIndexMeta";
const NOTIFICATION_OUTBOX_RETRY_DELAYS_MS = [
  60 * 1000,
  5 * 60 * 1000,
  15 * 60 * 1000,
  60 * 60 * 1000,
];
const NOTIFICATION_OUTBOX_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
const DELETION_AUDIT_PATH = "deleted/audit";
const DELETION_AUDIT_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
const STORAGE_ACCESS_CLAIM = "barberinShopAccess";
const STORAGE_MEMBERSHIP_INDEX_PATH = "storageMembershipIndex";
const STORAGE_MEMBERSHIP_INDEX_META_PATH = "storageMembershipIndexMeta";
const BARBERIN_EMAIL_SENDER = "dsourras@gmail.com";
const BARBERIN_SUPPORT_EMAIL = "oryn.barberin@gmail.com";
const crewInvitationSmtpPassword = defineSecret("CONTACT_SMTP_PASSWORD_DSOURRAS");
const LEGACY_DELETION_ARCHIVE_PATHS = [
  "deleted/shops",
  "deleted/barberoAccounts",
  "deleted/customerAccounts",
];

function canonicalShopIdentityForRecord(shop) {
  const derived = buildCanonicalShopIdentity({
    shopName: shop?.shopName,
    address: shop?.streetAddress || shop?.address,
    city: shop?.city,
  });
  return derived || String(shop?.canonicalIdentity || "").trim();
}

function findActiveShopByCanonicalIdentity(shops, canonicalIdentity) {
  const normalizedIdentity = String(canonicalIdentity || "").trim();
  if (!normalizedIdentity) {
    return null;
  }
  for (const [shopId, shop] of Object.entries(shops || {})) {
    if (shop?.archivedForTesting === true) {
      continue;
    }
    if (canonicalShopIdentityForRecord(shop) === normalizedIdentity) {
      return {shopId, shop};
    }
  }
  return null;
}

function json(response, status, body) {
  const authFailure = [
    "missing-auth-token",
    "invalid-auth-token",
    "expired-auth-token",
  ].includes(String(body?.details || "").trim());
  const subscriptionFailure = String(body?.details || "").trim() ===
    "subscription-required" || String(body?.message || "").trim() ===
    "subscription-required";
  const effectiveStatus = authFailure && (status === 400 || status === 500) ?
    401 :
    subscriptionFailure && (status === 400 || status === 500) ?
      402 :
      status;
  response.status(effectiveStatus).json(body);
}

function deletionAuditExpiresAt(createdAt = Date.now()) {
  const createdAtMs = typeof createdAt === "number" ?
    createdAt : Date.parse(String(createdAt || ""));
  const safeCreatedAt = Number.isFinite(createdAtMs) ? createdAtMs : Date.now();
  return new Date(safeCreatedAt + DELETION_AUDIT_RETENTION_MS).toISOString();
}

async function syncStorageMembershipClaims(decoded, shops) {
  const uid = String(decoded?.uid || "").trim();
  if (!uid) {
    return;
  }

  const accessByShop = {};
  for (const [shopId, shop] of Object.entries(shops || {})) {
    if (shop?.archivedForTesting === true) {
      continue;
    }
    const billingSnapshot = buildBillingSnapshot(shop?.billing);
    const hasActiveBillingAccess = billingSnapshot.allowsAccess &&
      billingSnapshot.accessUntilMillis > Date.now();
    const ownerMatches = String(shop?.ownerUserUid || "").trim() === uid;
    const crewMatches = buildShopBarbers(shop).some((barber) =>
      String(barber?.authUid || "").trim() === uid &&
      String(barber?.status || "active").trim().toLowerCase() === "active",
    );
    const customers = shop?.customers && typeof shop.customers === "object" ?
      shop.customers :
      {};
    const customerMatches = Object.entries(customers).some(([customerId, customer]) =>
      String(customerId || "").trim() === uid ||
      String(customer?.uid || "").trim() === uid,
    );

    if (customerMatches && hasActiveBillingAccess) {
      accessByShop[String(shopId)] = "customer";
    }
    if (crewMatches && hasActiveBillingAccess) {
      accessByShop[String(shopId)] = "staff";
    }
    if (ownerMatches && hasActiveBillingAccess) {
      accessByShop[String(shopId)] = "owner";
    }
  }

  const userRecord = await getAuth().getUser(uid);
  const currentClaims = userRecord.customClaims &&
    typeof userRecord.customClaims === "object" ?
    userRecord.customClaims :
    {};
  const currentAccess = currentClaims[STORAGE_ACCESS_CLAIM] &&
    typeof currentClaims[STORAGE_ACCESS_CLAIM] === "object" ?
    currentClaims[STORAGE_ACCESS_CLAIM] :
    {};
  if (JSON.stringify(currentAccess) === JSON.stringify(accessByShop)) {
    return;
  }

  await getAuth().setCustomUserClaims(uid, {
    ...currentClaims,
    [STORAGE_ACCESS_CLAIM]: accessByShop,
  });
}

function storageAccessRoleForShop(uid, shop) {
  const normalizedUid = String(uid || "").trim();
  if (!normalizedUid || !shop || typeof shop !== "object" ||
      shop.archivedForTesting === true) {
    return "";
  }

  const billingSnapshot = buildBillingSnapshot(shop.billing);
  if (!billingSnapshot.allowsAccess ||
      billingSnapshot.accessUntilMillis <= Date.now()) {
    return "";
  }

  if (String(shop.ownerUserUid || "").trim() === normalizedUid) {
    return "owner";
  }

  const crewMatches = buildShopBarbers(shop).some((barber) =>
    String(barber?.authUid || "").trim() === normalizedUid &&
    String(barber?.status || "active").trim().toLowerCase() === "active",
  );
  if (crewMatches) {
    return "staff";
  }

  const customers = shop.customers && typeof shop.customers === "object" ?
    shop.customers :
    {};
  const customerMatches = Object.entries(customers).some(([customerId, customer]) =>
    String(customerId || "").trim() === normalizedUid ||
    String(customer?.uid || "").trim() === normalizedUid,
  );
  return customerMatches ? "customer" : "";
}

function storageMembershipUserIds(shop) {
  const userIds = new Set();
  if (shop?.archivedForTesting === true) {
    return userIds;
  }
  const ownerUserUid = String(shop?.ownerUserUid || "").trim();
  if (ownerUserUid) {
    userIds.add(ownerUserUid);
  }

  for (const barber of buildShopBarbers(shop)) {
    const authUid = String(barber?.authUid || "").trim();
    if (authUid) {
      userIds.add(authUid);
    }
  }

  const customers = shop?.customers && typeof shop.customers === "object" ?
    shop.customers :
    {};
  for (const [customerId, customer] of Object.entries(customers)) {
    const customerUid = String(customer?.uid || customerId || "").trim();
    if (customerUid) {
      userIds.add(customerUid);
    }
  }
  return userIds;
}

async function syncStorageMembershipClaimForShop(uid, shopId, shop) {
  const normalizedUid = String(uid || "").trim();
  const normalizedShopId = String(shopId || "").trim();
  if (!normalizedUid || !normalizedShopId) {
    return;
  }

  const userRecord = await getAuth().getUser(normalizedUid);
  const currentClaims = userRecord.customClaims &&
    typeof userRecord.customClaims === "object" ?
    userRecord.customClaims :
    {};
  const currentAccess = currentClaims[STORAGE_ACCESS_CLAIM] &&
    typeof currentClaims[STORAGE_ACCESS_CLAIM] === "object" ?
    {...currentClaims[STORAGE_ACCESS_CLAIM]} :
    {};
  const role = storageAccessRoleForShop(normalizedUid, shop);
  if (role) {
    currentAccess[normalizedShopId] = role;
  } else {
    delete currentAccess[normalizedShopId];
  }

  const previousAccess = userRecord.customClaims?.[STORAGE_ACCESS_CLAIM] || {};
  if (JSON.stringify(previousAccess) === JSON.stringify(currentAccess)) {
    return;
  }

  await getAuth().setCustomUserClaims(normalizedUid, {
    ...currentClaims,
    [STORAGE_ACCESS_CLAIM]: currentAccess,
  });
}

async function refreshStorageMembershipClaimsForShop(shopId) {
  const normalizedShopId = String(shopId || "").trim();
  if (!normalizedShopId) {
    return;
  }

  const snapshot = await getDatabase().ref(`shops/${normalizedShopId}`).get();
  if (!snapshot.exists()) {
    return;
  }
  await refreshStorageMembershipClaimsForShopData(
      normalizedShopId,
      snapshot.val() || {},
  );
}

async function refreshStorageMembershipClaimsForShopData(
    shopId,
    shop,
    candidateUserIds,
) {
  const normalizedShopId = String(shopId || "").trim();
  if (!normalizedShopId) {
    return;
  }

  const userIds = candidateUserIds || storageMembershipUserIds(shop);
  for (const uid of userIds) {
    try {
      await syncStorageMembershipClaimForShop(uid, normalizedShopId, shop || {});
    } catch (error) {
      if (String(error?.code || "").trim() !== "auth/user-not-found") {
        throw error;
      }
    }
  }
}

async function refreshStorageMembershipClaimsForShops(shops) {
  const accessByUser = new Map();
  const now = Date.now();

  for (const [shopId, shop] of Object.entries(shops || {})) {
    const normalizedShopId = String(shopId || "").trim();
    if (!normalizedShopId || !shop || typeof shop !== "object" ||
        shop.archivedForTesting === true) {
      continue;
    }

    const billingSnapshot = buildBillingSnapshot(shop.billing);
    if (!billingSnapshot.allowsAccess ||
        billingSnapshot.accessUntilMillis <= now) {
      continue;
    }

    const grant = (uid, role) => {
      const normalizedUid = String(uid || "").trim();
      if (!normalizedUid) {
        return;
      }
      if (!accessByUser.has(normalizedUid)) {
        accessByUser.set(normalizedUid, {});
      }
      const accessByShop = accessByUser.get(normalizedUid);
      const priority = {customer: 1, staff: 2, owner: 3};
      const currentRole = accessByShop[normalizedShopId];
      if ((priority[role] || 0) >= (priority[currentRole] || 0)) {
        accessByShop[normalizedShopId] = role;
      }
    };

    grant(shop.ownerUserUid, "owner");
    for (const barber of buildShopBarbers(shop)) {
      if (String(barber?.status || "active").trim().toLowerCase() !== "active") {
        continue;
      }
      grant(barber?.authUid, "staff");
    }

    const customers = shop.customers && typeof shop.customers === "object" ?
      shop.customers :
      {};
    for (const [customerId, customer] of Object.entries(customers)) {
      grant(customer?.uid || customerId, "customer");
    }
  }

  for (const [uid, accessByShop] of accessByUser.entries()) {
    try {
      const userRecord = await getAuth().getUser(uid);
      const currentClaims = userRecord.customClaims &&
        typeof userRecord.customClaims === "object" ?
        userRecord.customClaims :
        {};
      const currentAccess = currentClaims[STORAGE_ACCESS_CLAIM] &&
        typeof currentClaims[STORAGE_ACCESS_CLAIM] === "object" ?
        currentClaims[STORAGE_ACCESS_CLAIM] :
        {};
      if (JSON.stringify(currentAccess) === JSON.stringify(accessByShop)) {
        continue;
      }

      await getAuth().setCustomUserClaims(uid, {
        ...currentClaims,
        [STORAGE_ACCESS_CLAIM]: accessByShop,
      });
    } catch (error) {
      if (String(error?.code || "").trim() !== "auth/user-not-found") {
        throw error;
      }
    }
  }
}

function storageMembershipIndexEntryPath(uid, shopId) {
  return `${STORAGE_MEMBERSHIP_INDEX_PATH}/${String(uid || "").trim()}/${String(shopId || "").trim()}`;
}

function buildStorageMembershipIndexRecord(uid, shopId, role, shop, now = Date.now()) {
  const billing = buildBillingSnapshot(shop?.billing);
  return {
    uid: String(uid || "").trim(),
    shopId: String(shopId || "").trim(),
    role: String(role || "").trim(),
    accessUntilMillis: billing.accessUntilMillis,
    updatedAt: new Date(now).toISOString(),
  };
}

async function ensureStorageMembershipIndex(db, now = Date.now()) {
  const markerRef = db.ref(STORAGE_MEMBERSHIP_INDEX_META_PATH);
  const markerSnapshot = await markerRef.get();
  if (Number(markerSnapshot.val()?.version || 0) >= 1) {
    return;
  }

  // This is a one-time migration. Daily repair runs only against the compact
  // UID/shop index below and never needs to download the full shops tree.
  const shopsSnapshot = await db.ref("shops").get();
  const updates = {
    [STORAGE_MEMBERSHIP_INDEX_META_PATH]: {
      version: 1,
      bootstrappedAt: new Date(now).toISOString(),
    },
  };
  for (const [shopId, shop] of Object.entries(shopsSnapshot.val() || {})) {
    if (!shop || typeof shop !== "object") {
      continue;
    }
    for (const uid of storageMembershipUserIds(shop)) {
      const role = storageAccessRoleForShop(uid, shop);
      if (!role) {
        continue;
      }
      updates[storageMembershipIndexEntryPath(uid, shopId)] =
        buildStorageMembershipIndexRecord(uid, shopId, role, shop, now);
    }
  }
  await db.ref().update(updates);
}

async function syncStorageMembershipIndexForShopData(
    db,
    shopId,
    shop,
    candidateUserIds,
) {
  const normalizedShopId = String(shopId || "").trim();
  if (!normalizedShopId) {
    return;
  }

  const userIds = candidateUserIds || storageMembershipUserIds(shop);
  const updates = {};
  for (const uid of userIds) {
    const normalizedUid = String(uid || "").trim();
    if (!normalizedUid) {
      continue;
    }
    const role = storageAccessRoleForShop(normalizedUid, shop || {});
    updates[storageMembershipIndexEntryPath(normalizedUid, normalizedShopId)] =
      role ? buildStorageMembershipIndexRecord(
          normalizedUid,
          normalizedShopId,
          role,
          shop || {},
      ) : null;
  }
  if (Object.keys(updates).length > 0) {
    await db.ref().update(updates);
  }
}

function storageAccessByUserFromIndex(rawIndex, now = Date.now()) {
  const accessByUser = new Map();
  for (const [uid, shopEntries] of Object.entries(rawIndex || {})) {
    if (!shopEntries || typeof shopEntries !== "object") {
      continue;
    }
    const accessByShop = {};
    const priority = {customer: 1, staff: 2, owner: 3};
    for (const [shopId, entry] of Object.entries(shopEntries)) {
      const role = String(entry?.role || "").trim();
      const accessUntilMillis = Number(entry?.accessUntilMillis || 0);
      if (!role || accessUntilMillis <= now) {
        continue;
      }
      const currentRole = accessByShop[shopId];
      if ((priority[role] || 0) >= (priority[currentRole] || 0)) {
        accessByShop[shopId] = role;
      }
    }
    if (Object.keys(accessByShop).length > 0) {
      accessByUser.set(uid, accessByShop);
    }
  }
  return accessByUser;
}

async function syncStorageMembershipClaimsFromIndex(uid, accessByShop) {
  const normalizedUid = String(uid || "").trim();
  if (!normalizedUid) {
    return;
  }
  try {
    const userRecord = await getAuth().getUser(normalizedUid);
    const currentClaims = userRecord.customClaims &&
      typeof userRecord.customClaims === "object" ?
      userRecord.customClaims :
      {};
    const currentAccess = currentClaims[STORAGE_ACCESS_CLAIM] &&
      typeof currentClaims[STORAGE_ACCESS_CLAIM] === "object" ?
      currentClaims[STORAGE_ACCESS_CLAIM] :
      {};
    if (JSON.stringify(currentAccess) === JSON.stringify(accessByShop || {})) {
      return;
    }
    await getAuth().setCustomUserClaims(normalizedUid, {
      ...currentClaims,
      [STORAGE_ACCESS_CLAIM]: accessByShop || {},
    });
  } catch (error) {
    if (String(error?.code || "").trim() !== "auth/user-not-found") {
      throw error;
    }
  }
}

async function refreshStorageMembershipClaimsFromIndex(db, now = Date.now()) {
  await ensureStorageMembershipIndex(db, now);
  const snapshot = await db.ref(STORAGE_MEMBERSHIP_INDEX_PATH).get();
  const rawIndex = snapshot.val() || {};
  const accessByUser = storageAccessByUserFromIndex(rawIndex, now);
  const allUserIds = new Set(Object.keys(rawIndex));
  const expiredEntries = {};
  for (const [uid, shopEntries] of Object.entries(rawIndex)) {
    for (const [shopId, entry] of Object.entries(shopEntries || {})) {
      if (Number(entry?.accessUntilMillis || 0) <= now) {
        expiredEntries[storageMembershipIndexEntryPath(uid, shopId)] = null;
      }
    }
  }
  if (Object.keys(expiredEntries).length > 0) {
    await db.ref().update(expiredEntries);
  }
  for (const uid of allUserIds) {
    await syncStorageMembershipClaimsFromIndex(
        uid,
        accessByUser.get(uid) || {},
    );
  }
}

function storageMembershipChanged(beforeShop, afterShop) {
  return storageMembershipChangedUserIds(beforeShop, afterShop).size > 0;
}

function storageMembershipChangedUserIds(beforeShop, afterShop) {
  const before = beforeShop || {};
  const after = afterShop || {};
  const beforeBilling = buildBillingSnapshot(before.billing);
  const afterBilling = buildBillingSnapshot(after.billing);
  const billingChanged =
    beforeBilling.allowsAccess !== afterBilling.allowsAccess ||
    beforeBilling.accessUntilMillis !== afterBilling.accessUntilMillis;
  const beforeUserIds = storageMembershipUserIds(before);
  const afterUserIds = storageMembershipUserIds(after);
  const allUserIds = new Set([...beforeUserIds, ...afterUserIds]);

  if (billingChanged) {
    return allUserIds;
  }

  return new Set(
      [...allUserIds].filter((uid) =>
        storageAccessRoleForShop(uid, before) !==
        storageAccessRoleForShop(uid, after),
      ),
  );
}

async function refreshStorageMembershipClaimsForUid(uid) {
  const normalizedUid = String(uid || "").trim();
  if (!normalizedUid) {
    return;
  }
  try {
    const db = getDatabase();
    await ensureStorageMembershipIndex(db);
    const snapshot = await db.ref(
        `${STORAGE_MEMBERSHIP_INDEX_PATH}/${normalizedUid}`,
    ).get();
    const accessByUser = storageAccessByUserFromIndex({
      [normalizedUid]: snapshot.val() || {},
    });
    await syncStorageMembershipClaimsFromIndex(
        normalizedUid,
        accessByUser.get(normalizedUid) || {},
    );
  } catch (error) {
    if (String(error?.code || "").trim() === "auth/user-not-found") {
      return;
    }
    throw error;
  }
}

function billingCredentialObjectName(shopId) {
  return `${BILLING_CREDENTIALS_PREFIX}/${encodeURIComponent(String(shopId || "").trim())}.json`;
}

function billingClaimObjectName(purchaseToken) {
  const digest = buildVerificationDigest(purchaseToken);
  return `${BILLING_CLAIMS_PREFIX}/${digest}.json`;
}

async function removeRawBillingVerificationResults(db, shopId) {
  const purchasesRef = db.ref(`shops/${shopId}/billingPurchases`);
  const snapshot = await purchasesRef.get();
  if (!snapshot.exists()) {
    return 0;
  }

  const updates = {};
  for (const [purchaseKey, purchase] of Object.entries(snapshot.val() || {})) {
    if (purchase && typeof purchase === "object" &&
      Object.prototype.hasOwnProperty.call(purchase, "verificationResult")) {
      updates[`${purchaseKey}/verificationResult`] = null;
    }
  }
  if (Object.keys(updates).length === 0) {
    return 0;
  }
  await purchasesRef.update(updates);
  return Object.keys(updates).length;
}

async function saveBillingCredential(shopId, credential) {
  const file = getStorage()
      .bucket(BILLING_CREDENTIALS_BUCKET)
      .file(billingCredentialObjectName(shopId));
  await file.save(JSON.stringify(credential), {
    contentType: "application/json",
    resumable: false,
    metadata: {
      cacheControl: "no-store",
    },
  });
}

async function loadBillingCredential(shopId) {
  const file = getStorage()
      .bucket(BILLING_CREDENTIALS_BUCKET)
      .file(billingCredentialObjectName(shopId));
  try {
    const [contents] = await file.download();
    const parsed = JSON.parse(contents.toString("utf8"));
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch (error) {
    if (Number(error?.code) === 404) {
      return null;
    }
    throw error;
  }
}

async function deleteBillingCredential(shopId) {
  const file = getStorage()
      .bucket(BILLING_CREDENTIALS_BUCKET)
      .file(billingCredentialObjectName(shopId));
  try {
    await file.delete();
  } catch (error) {
    if (Number(error?.code) !== 404) {
      throw error;
    }
  }
}

async function claimBillingToken({shopId, platform, productId, purchaseToken}) {
  const digest = buildVerificationDigest(purchaseToken);
  if (!digest) {
    throw new Error("missing-purchase-token-digest");
  }

  const file = getStorage()
      .bucket(BILLING_CREDENTIALS_BUCKET)
      .file(billingClaimObjectName(purchaseToken));
  const claim = {
    tokenDigest: digest,
    shopId: String(shopId || "").trim(),
    platform: normalizeBillingPlatform(platform),
    productId: String(productId || "").trim(),
    claimedAt: new Date().toISOString(),
  };

  try {
    await file.save(JSON.stringify(claim), {
      contentType: "application/json",
      resumable: false,
      metadata: {
        cacheControl: "no-store",
      },
      preconditionOpts: {
        ifGenerationMatch: 0,
      },
    });
    return;
  } catch (error) {
    if (Number(error?.code) !== 412) {
      throw error;
    }
  }

  const [contents] = await file.download();
  let existingClaim;
  try {
    existingClaim = JSON.parse(contents.toString("utf8"));
  } catch (error) {
    throw new Error("invalid-purchase-token-claim");
  }

  if (
    String(existingClaim?.shopId || "").trim() !== claim.shopId ||
    normalizeBillingPlatform(existingClaim?.platform) !== claim.platform
  ) {
    throw new Error("subscription-token-already-bound");
  }

  // Apple receipts can stay stable across a valid monthly/yearly crossgrade.
  // Keep the global binding on shop and platform, not on the product id.
}

function resolveShopDisplayName(shop) {
  const shopName = String(shop?.shopName || "").trim();
  if (shopName) {
    return shopName;
  }
  const ownerName = String(shop?.ownerName || "").trim();
  if (ownerName) {
    return ownerName;
  }
  return DEFAULT_CUSTOMER_APP_NAME;
}

function normalizeBillingPlan(value) {
  return String(value || "").trim().toLowerCase() === "yearly" ?
    "yearly" :
    "monthly";
}

function normalizeCustomerAppSlug(value) {
  const source = String(value || "")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase();
  const slug = source.replace(/[^a-z0-9]+/g, "");
  return slug.slice(0, 24) || "shop";
}

function buildCustomerAppConfiguration({shopId, shopName, existing}) {
  const current = existing && typeof existing === "object" ? existing : {};
  const normalizedShopId = String(shopId || "").trim();
  const normalizedShopName = String(shopName || "").trim() || "Barber Shop";
  const accessToken = String(current.accessToken || "").trim() ||
    createCustomerAppAccessToken();
  const digest = createHash("sha256")
      .update(normalizedShopId)
      .digest("hex")
      .slice(0, 8);
  const slug = normalizeCustomerAppSlug(normalizedShopId);
  const generatedIdentifier = `com.barberin.customer.app${slug}${digest}`;
  const now = new Date().toISOString();

  const configuration = {
    status: String(current.status || "provisioning_required").trim(),
    shopId: normalizedShopId,
    displayName: String(current.displayName || normalizedShopName).trim(),
    legalDisplayName: String(
        current.legalDisplayName || normalizedShopName,
    ).trim(),
    packageName: String(current.packageName || generatedIdentifier).trim(),
    bundleId: String(current.bundleId || generatedIdentifier).trim(),
    firebaseAndroidAppId: String(current.firebaseAndroidAppId || "").trim(),
    firebaseIosAppId: String(current.firebaseIosAppId || "").trim(),
    mode: "separate",
    accessToken,
    workspaceName: String(
        current.workspaceName || `${normalizedShopName} Customer App`,
    ).trim(),
    template: "barberin_customer_app",
    templateVersion: String(current.templateVersion || "1").trim(),
    provisionedAt: String(current.provisionedAt || "").trim(),
    lastBuildAt: String(current.lastBuildAt || "").trim(),
    lastReleaseAt: String(current.lastReleaseAt || "").trim(),
    provisioningPhase: String(current.provisioningPhase || "idle").trim(),
    provisioningProgressPercent: Number.isFinite(
        Number(current.provisioningProgressPercent),
    ) ? Number(current.provisioningProgressPercent) : 0,
    provisioningErrorReason: String(
        current.provisioningErrorReason || "",
    ).trim(),
    workspacePath: String(current.workspacePath || "").trim(),
    aabPath: String(current.aabPath || "").trim(),
    buildVersion: String(current.buildVersion || "").trim(),
    provisioningAttempt: Number.parseInt(
        current.provisioningAttempt,
        10,
    ) || 0,
    retryCount: Number.parseInt(current.retryCount, 10) || 0,
    createdAt: String(current.createdAt || now).trim(),
    updatedAt: now,
  };
  return configuration;
}

function billingProductIdForPlan(plan) {
  return normalizeBillingPlan(plan) === "yearly" ?
    BILLING_YEARLY_PRODUCT_ID :
    BILLING_MONTHLY_PRODUCT_ID;
}

function billingPlanFromProductId(productId) {
  const normalizedProductId = String(productId || "").trim();
  if (normalizedProductId === BILLING_MONTHLY_PRODUCT_ID) {
    return "monthly";
  }
  if (normalizedProductId === BILLING_YEARLY_PRODUCT_ID) {
    return "yearly";
  }
  return "";
}

function normalizeBillingPlatform(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (normalized === "android") {
    return "android";
  }
  if (["ios", "iphone", "ipad"].includes(normalized)) {
    return "ios";
  }
  if (["macos", "mac", "osx"].includes(normalized)) {
    return "macos";
  }
  return "";
}

function isAppleBillingPlatform(platform) {
  return ["ios", "macos"].includes(normalizeBillingPlatform(platform));
}

function addDaysToIso(dateValue, daysToAdd) {
  const baseDate = dateValue instanceof Date ? dateValue : new Date(dateValue);
  if (Number.isNaN(baseDate.getTime())) {
    return "";
  }
  const nextDate = new Date(baseDate.getTime() + (daysToAdd * 86400000));
  return nextDate.toISOString();
}

function addMonthsToIso(dateValue, monthsToAdd) {
  const baseDate = dateValue instanceof Date ? dateValue : new Date(dateValue);
  if (Number.isNaN(baseDate.getTime())) {
    return "";
  }
  const nextDate = new Date(baseDate);
  nextDate.setMonth(nextDate.getMonth() + monthsToAdd);
  return nextDate.toISOString();
}

function addYearsToIso(dateValue, yearsToAdd) {
  const baseDate = dateValue instanceof Date ? dateValue : new Date(dateValue);
  if (Number.isNaN(baseDate.getTime())) {
    return "";
  }
  const nextDate = new Date(baseDate);
  nextDate.setFullYear(nextDate.getFullYear() + yearsToAdd);
  return nextDate.toISOString();
}

function dateKeyFromDateValue(dateValue) {
  const date = dateValue instanceof Date ? dateValue : new Date(dateValue);
  if (Number.isNaN(date.getTime())) {
    return "";
  }
  const year = String(date.getFullYear()).padStart(4, "0");
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function orthodoxEasterSunday(year) {
  const a = year % 4;
  const b = year % 7;
  const c = year % 19;
  const d = (19 * c + 15) % 30;
  const e = (2 * a + 4 * b - d + 34) % 7;
  const month = Math.floor((d + e + 114) / 31);
  const day = ((d + e + 114) % 31) + 1;
  const julianDate = new Date(Date.UTC(year, month - 1, day));
  julianDate.setUTCDate(julianDate.getUTCDate() + 13);
  return new Date(
      julianDate.getUTCFullYear(),
      julianDate.getUTCMonth(),
      julianDate.getUTCDate(),
  );
}

function buildGreekHolidayMap(year) {
  const easter = orthodoxEasterSunday(year);
  const cleanMonday = new Date(easter);
  cleanMonday.setDate(cleanMonday.getDate() - 48);
  const goodFriday = new Date(easter);
  goodFriday.setDate(goodFriday.getDate() - 2);
  const easterMonday = new Date(easter);
  easterMonday.setDate(easterMonday.getDate() + 1);
  const holySpiritMonday = new Date(easter);
  holySpiritMonday.setDate(holySpiritMonday.getDate() + 50);
  const entries = [
    [new Date(year, 0, 1), "New Year's Day"],
    [new Date(year, 0, 6), "Epiphany"],
    [cleanMonday, "Clean Monday"],
    [new Date(year, 2, 25), "Independence Day"],
    [goodFriday, "Good Friday"],
    [easter, "Orthodox Easter"],
    [easterMonday, "Easter Monday"],
    [new Date(year, 4, 1), "Labour Day"],
    [holySpiritMonday, "Holy Spirit Monday"],
    [new Date(year, 7, 15), "Assumption Day"],
    [new Date(year, 9, 28), "Ohi Day"],
    [new Date(year, 11, 25), "Christmas Day"],
    [new Date(year, 11, 26), "Synaxis of the Mother of God"],
  ];
  return Object.fromEntries(
      entries.map(([date, label]) => [dateKeyFromDateValue(date), label]),
  );
}

function buildDefaultBillingRecord() {
  return {
    status: "setup_required",
    selectedPlan: "monthly",
    pendingPlan: "",
    planConfirmed: false,
    trialEligible: true,
    trialStartedAt: "",
    trialEndsAt: "",
    currentPeriodEnd: "",
    graceUntil: "",
    accessUntilMillis: 0,
    autoRenewEnabled: null,
    cancellationAt: "",
    cancellationReason: "",
    storeStatus: "",
    storeEnvironment: "",
    revokedAt: "",
    refundedAt: "",
    lastStoreSyncAt: "",
    lastStoreSyncStatus: "",
    platform: "",
    storeProductId: "",
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    catalog: {
      monthlyPriceEur: BILLING_MONTHLY_PRICE_EUR,
      yearlyPriceEur: BILLING_YEARLY_PRICE_EUR,
      yearlySavingsEur: BILLING_YEARLY_SAVINGS_EUR,
      monthlyProductId: BILLING_MONTHLY_PRODUCT_ID,
      yearlyProductId: BILLING_YEARLY_PRODUCT_ID,
      trialDays: BILLING_TRIAL_DAYS,
    },
  };
}

function parseBillingTimeMillis(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value > 0 ? value : 0;
  }
  const normalized = String(value || "").trim();
  if (!normalized) {
    return 0;
  }
  const numeric = Number(normalized);
  if (Number.isFinite(numeric) && numeric > 0) {
    return numeric;
  }
  // Firebase/PowerShell can persist ISO timestamps with more than the
  // three fractional-second digits supported by JavaScript Date.parse.
  // Keep millisecond precision while accepting those valid timestamps.
  const parseableDate = normalized.replace(
      /(\.\d{3})\d+(?=Z|[+-]\d{2}:?\d{2}$)/,
      "$1",
  );
  const parsed = Date.parse(parseableDate);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

function billingAccessUntilMillis(rawBilling, status) {
  const normalizedStatus = String(
      status || rawBilling?.status || "",
  ).trim().toLowerCase();
  if (normalizedStatus === "active") {
    return parseBillingTimeMillis(rawBilling?.currentPeriodEnd);
  }
  if (normalizedStatus === "grace_period") {
    return parseBillingTimeMillis(
        rawBilling?.graceUntil || rawBilling?.currentPeriodEnd,
    );
  }
  if (normalizedStatus === "trialing") {
    return parseBillingTimeMillis(rawBilling?.trialEndsAt);
  }
  return 0;
}

function buildDefaultSustainabilityProfile() {
  return {
    monthlyRevenue: 0,
    otherRevenue: 0,
    fixedCosts: 0,
    rentCost: 0,
    payrollCost: 0,
    utilitiesCost: 0,
    suppliesCost: 0,
    taxesCost: 0,
    marketingCost: 0,
    equipmentCost: 0,
    cashReserve: 0,
    workingHoursMonth: 160,
    updatedAt: "",
  };
}

function normalizeSustainabilityProfile(rawProfile) {
  const source = rawProfile && typeof rawProfile === "object" ? rawProfile : {};
  const fallback = buildDefaultSustainabilityProfile();
  const numberValue = (value, fallbackValue = 0) => {
    const parsed = Number.parseFloat(value);
    if (!Number.isFinite(parsed)) {
      return fallbackValue;
    }
    return Math.max(0, parsed);
  };
  const workingHoursMonth = numberValue(
      source.workingHoursMonth,
      fallback.workingHoursMonth,
  );
  return {
    monthlyRevenue: numberValue(source.monthlyRevenue),
    otherRevenue: numberValue(source.otherRevenue),
    fixedCosts: numberValue(source.fixedCosts),
    rentCost: numberValue(source.rentCost),
    payrollCost: numberValue(source.payrollCost),
    utilitiesCost: numberValue(source.utilitiesCost),
    suppliesCost: numberValue(source.suppliesCost),
    taxesCost: numberValue(source.taxesCost),
    marketingCost: numberValue(source.marketingCost),
    equipmentCost: numberValue(source.equipmentCost),
    cashReserve: numberValue(source.cashReserve),
    workingHoursMonth: workingHoursMonth > 0 ? workingHoursMonth : 160,
    updatedAt: new Date().toISOString(),
  };
}

function buildBillingSnapshot(rawBilling) {
  const fallback = buildDefaultBillingRecord();
  const billing = rawBilling && typeof rawBilling === "object" ?
    rawBilling :
    fallback;
  const confirmedPlan = normalizeBillingPlan(
      billing.selectedPlan || fallback.selectedPlan,
  );
  const pendingPlan = normalizeBillingPlan(
      billing.pendingPlan || confirmedPlan,
  );
  const selectedPlan = billing.planConfirmed === true ?
    confirmedPlan :
    pendingPlan;
  const now = new Date();
  const trialEndsAt = String(billing.trialEndsAt || "").trim();
  const currentPeriodEnd = String(billing.currentPeriodEnd || "").trim();
  const trialEndsMillis = parseBillingTimeMillis(trialEndsAt);
  const currentPeriodEndMillis = parseBillingTimeMillis(currentPeriodEnd);
  let status = String(billing.status || "setup_required").trim().toLowerCase();
  // Some older records were written without graceUntil. Keep grace access
  // alive until the verified store expiry rather than expiring immediately.
  const graceUntil = String(billing.graceUntil || "").trim() ||
    (status === "grace_period" ? currentPeriodEnd : "");
  const graceUntilMillis = parseBillingTimeMillis(graceUntil);

  if (status === "trialing") {
    // Preserve access for legacy trials until their recorded end date. This
    // does not convert the trial into a paid subscription; the owner must
    // complete a store purchase once the trial expires.
    if (trialEndsMillis <= 0) {
      status = "setup_required";
    } else if (trialEndsMillis < now.getTime()) {
      status = "expired";
    }
  } else if (status === "active") {
    if (currentPeriodEndMillis <= 0 ||
      currentPeriodEndMillis < now.getTime()
    ) {
      status = "expired";
    }
  } else if (status === "grace_period") {
    if (graceUntilMillis <= 0 ||
      graceUntilMillis < now.getTime()
    ) {
      status = "expired";
    }
  }

  const allowsAccess = ["active", "grace_period", "trialing"].includes(status);
  const requiresOwnerAction = !allowsAccess;
  const accessUntilMillis = allowsAccess ?
    billingAccessUntilMillis(billing, status) :
    0;
  const catalog =
    billing.catalog && typeof billing.catalog === "object" ?
      billing.catalog :
      {};

  return {
    status,
    selectedPlan,
    pendingPlan,
    planConfirmed: billing.planConfirmed === true,
    allowsAccess,
    requiresOwnerAction,
    accessUntilMillis,
    trialStartedAt: String(billing.trialStartedAt || "").trim(),
    trialEndsAt,
    currentPeriodEnd,
    graceUntil,
    autoRenewEnabled:
      typeof billing.autoRenewEnabled === "boolean" ?
        billing.autoRenewEnabled :
        null,
    cancellationAt: String(billing.cancellationAt || "").trim(),
    cancellationReason: String(billing.cancellationReason || "").trim(),
    storeStatus: String(billing.storeStatus || "").trim(),
    storeEnvironment: String(billing.storeEnvironment || "").trim(),
    revokedAt: String(billing.revokedAt || "").trim(),
    refundedAt: String(billing.refundedAt || "").trim(),
    lastStoreSyncAt: String(billing.lastStoreSyncAt || "").trim(),
    lastStoreSyncStatus: String(billing.lastStoreSyncStatus || "").trim(),
    platform: String(billing.platform || "").trim(),
    storeProductId: String(
        billing.storeProductId ||
        (selectedPlan === "yearly" ?
          BILLING_YEARLY_PRODUCT_ID :
          BILLING_MONTHLY_PRODUCT_ID),
    ).trim(),
    // Keep the fallback catalog aligned with the prices configured for the
    // store products. ProductDetails remains the source of truth when online.
    monthlyPriceEur: BILLING_MONTHLY_PRICE_EUR,
    yearlyPriceEur: BILLING_YEARLY_PRICE_EUR,
    yearlySavingsEur: BILLING_YEARLY_SAVINGS_EUR,
    monthlyProductId: String(catalog.monthlyProductId || BILLING_MONTHLY_PRODUCT_ID),
    yearlyProductId: String(catalog.yearlyProductId || BILLING_YEARLY_PRODUCT_ID),
    trialDays:
      Number.parseInt(catalog.trialDays, 10) || BILLING_TRIAL_DAYS,
  };
}

function billingSyncIndexFingerprint(rawBilling) {
  const billing = rawBilling && typeof rawBilling === "object" ?
    rawBilling :
    {};
  return JSON.stringify({
    status: String(billing.status || "").trim().toLowerCase(),
    planConfirmed: billing.planConfirmed === true,
    platform: String(billing.platform || "").trim().toLowerCase(),
    storeProductId: String(billing.storeProductId || "").trim(),
    trialEndsAt: String(billing.trialEndsAt || "").trim(),
    currentPeriodEnd: String(billing.currentPeriodEnd || "").trim(),
    graceUntil: String(billing.graceUntil || "").trim(),
    accessUntilMillis: Number(billing.accessUntilMillis || 0),
    autoRenewEnabled: typeof billing.autoRenewEnabled === "boolean" ?
      billing.autoRenewEnabled :
      null,
    cancellationAt: String(billing.cancellationAt || "").trim(),
    cancellationReason: String(billing.cancellationReason || "").trim(),
    storeStatus: String(billing.storeStatus || "").trim(),
    storeEnvironment: String(billing.storeEnvironment || "").trim(),
    revokedAt: String(billing.revokedAt || "").trim(),
    refundedAt: String(billing.refundedAt || "").trim(),
  });
}

function billingSyncIndexStateChanged(beforeShop, afterShop) {
  return billingSyncIndexFingerprint(beforeShop?.billing) !==
    billingSyncIndexFingerprint(afterShop?.billing);
}

function billingVerificationTarget(rawBilling) {
  const billing = rawBilling && typeof rawBilling === "object" ?
    rawBilling :
    {};
  const platform = String(billing.platform || "").trim().toLowerCase();
  const productId = String(billing.storeProductId || "").trim();
  return billing.planConfirmed === true &&
    ["android", "ios", "macos"].includes(normalizeBillingPlatform(platform)) &&
    billingPlanFromProductId(productId) ?
    {platform: normalizeBillingPlatform(platform), productId} :
    null;
}

function billingSyncNextCheckAt(rawBilling, now = Date.now()) {
  const billing = rawBilling && typeof rawBilling === "object" ?
    rawBilling :
    {};
  const snapshot = buildBillingSnapshot(billing);
  const target = billingVerificationTarget(billing);
  const rawStatus = String(billing.status || "").trim().toLowerCase();
  const trialEndsMillis = parseBillingTimeMillis(snapshot.trialEndsAt);
  const currentPeriodEndMillis = parseBillingTimeMillis(snapshot.currentPeriodEnd);
  const graceUntilMillis = parseBillingTimeMillis(snapshot.graceUntil);
  const expiryMillis = snapshot.status === "trialing" ?
    trialEndsMillis :
    snapshot.status === "grace_period" ?
      graceUntilMillis :
      currentPeriodEndMillis;

  if (snapshot.status === "setup_required") {
    return 0;
  }

  if (snapshot.status === "trialing" && expiryMillis > now) {
    return expiryMillis;
  }

  if (snapshot.status === "pending_verification") {
    return now + BILLING_SYNC_ERROR_RETRY_MS;
  }

  if (expiryMillis > 0 && expiryMillis <= now) {
    const needsFirstExpiryVerification = target &&
      ["active", "grace_period", "pending_verification"].includes(rawStatus);
    return needsFirstExpiryVerification ?
      now :
      now + BILLING_SYNC_EXPIRED_RETRY_MS;
  }

  if (!target) {
    return expiryMillis > now ? expiryMillis : 0;
  }

  if (snapshot.status === "active" || snapshot.status === "grace_period" ||
      rawStatus === "active" || rawStatus === "grace_period") {
    const expiryCheckAt = expiryMillis > 0 ?
      Math.max(now, expiryMillis - BILLING_SYNC_EXPIRY_BUFFER_MS) :
      now + BILLING_SYNC_INTERVAL_MS;
    return Math.min(now + BILLING_SYNC_INTERVAL_MS, expiryCheckAt);
  }

  return now + BILLING_SYNC_EXPIRED_RETRY_MS;
}

function buildBillingSyncIndexRecord(shopId, rawBilling, now = Date.now()) {
  const billing = rawBilling && typeof rawBilling === "object" ?
    rawBilling :
    {};
  const snapshot = buildBillingSnapshot(billing);
  const target = billingVerificationTarget(billing);
  return {
    shopId: String(shopId || "").trim(),
    status: snapshot.status,
    platform: target?.platform || String(billing.platform || "").trim(),
    storeProductId: target?.productId || String(billing.storeProductId || "").trim(),
    planConfirmed: billing.planConfirmed === true,
    accessUntilMillis: snapshot.accessUntilMillis,
    currentPeriodEnd: snapshot.currentPeriodEnd,
    graceUntil: snapshot.graceUntil,
    nextCheckAt: billingSyncNextCheckAt(billing, now),
    updatedAt: new Date(now).toISOString(),
  };
}

function resolveBillingStatusFromGooglePlayState(subscriptionState) {
  switch (String(subscriptionState || "").trim()) {
    case "SUBSCRIPTION_STATE_ACTIVE":
    case "SUBSCRIPTION_STATE_CANCELED":
      return "active";
    case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD":
      return "grace_period";
    case "SUBSCRIPTION_STATE_PENDING":
      return "pending_verification";
    default:
      return "expired";
  }
}

async function postJsonOrThrow(url, payload) {
  let response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(payload),
    });
  } catch (error) {
    throw new Error("store-verification-network-failed");
  }
  if (!response.ok) {
    throw new Error("store-verification-http-failed");
  }
  try {
    return await response.json();
  } catch (error) {
    throw new Error("store-verification-invalid-json");
  }
}

function parseMillis(value) {
  const parsed = Number.parseInt(String(value || "").trim(), 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

function buildVerificationDigest(value) {
  const normalized = String(value || "").trim();
  if (!normalized) {
    return "";
  }
  return createHash("sha256").update(normalized).digest("hex");
}

function resolveBillingStatusFromAppleReceipt({
  expiryTimeMs,
  gracePeriodExpiresMs,
  cancellationTimeMs,
}) {
  const now = Date.now();
  if (cancellationTimeMs > 0) {
    return "expired";
  }
  if (gracePeriodExpiresMs > now) {
    return "grace_period";
  }
  if (expiryTimeMs > now) {
    return "active";
  }
  return "expired";
}

async function verifyIosSubscriptionPurchase({
  platform = "ios",
  receiptData,
  expectedProductId,
}) {
  const sharedSecret = String(
      process.env.APPLE_SHARED_SECRET ||
      process.env.APP_STORE_SHARED_SECRET ||
      process.env.APPLE_APP_SHARED_SECRET ||
      "",
  ).trim();
  const requestPayload = {
    "receipt-data": receiptData,
    "exclude-old-transactions": true,
  };
  if (!sharedSecret) {
    throw new Error("apple-shared-secret-not-configured");
  }
  requestPayload.password = sharedSecret;

  let receipt = await postJsonOrThrow(
      APPLE_VERIFY_RECEIPT_PRODUCTION_URL,
      requestPayload,
  );
  if (Number(receipt?.status) === 21007) {
    receipt = await postJsonOrThrow(
        APPLE_VERIFY_RECEIPT_SANDBOX_URL,
        requestPayload,
    );
  }
  if (Number(receipt?.status) === 21004) {
    throw new Error("ios-shared-secret-invalid");
  }
  if (Number(receipt?.status || 0) !== 0) {
    throw new Error(`ios-receipt-verification-failed-${receipt?.status || "unknown"}`);
  }

  const bundleId = String(receipt?.receipt?.bundle_id || "").trim();
  const expectedBundleId = normalizeBillingPlatform(platform) === "macos" ?
    BILLING_MACOS_BUNDLE_ID :
    BILLING_IOS_BUNDLE_ID;
  if (!bundleId || bundleId !== expectedBundleId) {
    throw new Error("ios-bundle-id-mismatch");
  }

  const latestReceiptInfo = Array.isArray(receipt?.latest_receipt_info) ?
    receipt.latest_receipt_info :
    [];
  const inAppEntries = Array.isArray(receipt?.receipt?.in_app) ?
    receipt.receipt.in_app :
    [];
  const receiptEntries = [...latestReceiptInfo, ...inAppEntries]
      .filter((item) => billingPlanFromProductId(item?.product_id));
  if (!receiptEntries.length) {
    throw new Error("ios-subscription-product-mismatch");
  }

  const now = Date.now();
  const activeEntries = receiptEntries
      .filter((item) => parseMillis(item?.expires_date_ms) > now &&
        !parseMillis(item?.cancellation_date_ms))
      .sort(
          (left, right) =>
            parseMillis(right?.expires_date_ms) - parseMillis(left?.expires_date_ms),
      );
  const expectedEntries = receiptEntries
      .filter((item) => String(item?.product_id || "").trim() === expectedProductId)
      .sort(
          (left, right) =>
            parseMillis(right?.expires_date_ms) - parseMillis(left?.expires_date_ms),
      );
  const latestEntry = activeEntries[0] || expectedEntries[0];
  if (!latestEntry) {
    throw new Error("ios-subscription-product-mismatch");
  }
  const verifiedProductId = String(latestEntry?.product_id || "").trim();
  const expiryTimeMs = parseMillis(latestEntry?.expires_date_ms);
  if (!expiryTimeMs) {
    throw new Error("missing-subscription-expiry");
  }

  const pendingRenewalInfo = Array.isArray(receipt?.pending_renewal_info) ?
    receipt.pending_renewal_info :
    [];
  const matchingRenewal = pendingRenewalInfo.find((item) =>
    String(item?.product_id || "").trim() === verifiedProductId &&
    (!latestEntry?.original_transaction_id ||
      String(item?.original_transaction_id || "").trim() ===
        String(latestEntry.original_transaction_id).trim()),
  ) || pendingRenewalInfo.find((item) =>
    String(item?.product_id || "").trim() === verifiedProductId,
  );
  const gracePeriodExpiresMs = parseMillis(
      matchingRenewal?.grace_period_expires_date_ms,
  );
  const cancellationTimeMs = parseMillis(latestEntry?.cancellation_date_ms);
  const status = resolveBillingStatusFromAppleReceipt({
    expiryTimeMs,
    gracePeriodExpiresMs,
    cancellationTimeMs,
  });
  const isBillingRetry = String(
      matchingRenewal?.is_in_billing_retry_period || "",
  ).trim() === "1";
  const expirationIntent = String(
      matchingRenewal?.expiration_intent || "",
  ).trim();

  return {
    status,
    currentPeriodEnd: new Date(expiryTimeMs).toISOString(),
    graceUntil: gracePeriodExpiresMs > Date.now() ?
      new Date(gracePeriodExpiresMs).toISOString() :
      "",
    autoRenewEnabled: matchingRenewal ?
      String(matchingRenewal.auto_renew_status || "") === "1" :
      null,
    cancellationAt: cancellationTimeMs > 0 ?
      new Date(cancellationTimeMs).toISOString() :
      "",
    cancellationReason: expirationIntent,
    storeStatus: cancellationTimeMs > 0 ?
      "REVOKED" :
      status === "grace_period" ?
        "GRACE_PERIOD" :
        isBillingRetry ?
          "BILLING_RETRY" :
          status === "active" ? "ACTIVE" : "EXPIRED",
    storeEnvironment: String(receipt?.environment || "").trim().toLowerCase(),
    revokedAt: cancellationTimeMs > 0 ?
      new Date(cancellationTimeMs).toISOString() :
      "",
    refundedAt: cancellationTimeMs > 0 ?
      new Date(cancellationTimeMs).toISOString() :
      "",
    latestPurchaseAt: String(
        latestEntry?.purchase_date_ms ?
          new Date(parseMillis(latestEntry.purchase_date_ms)).toISOString() :
        "",
    ).trim(),
    platform: normalizeBillingPlatform(platform) || "ios",
    storeProductId: verifiedProductId,
  };
}

async function verifyAndroidSubscriptionPurchase({
  packageName,
  purchaseToken,
  expectedProductId,
}) {
  // Load the publisher client only for Android purchase verification so the
  // Functions module can initialize quickly during deploy and cold starts.
  const {google} = require("googleapis");
  const auth = new google.auth.GoogleAuth({
    scopes: [ANDROID_PUBLISHER_SCOPE],
  });
  const authClient = await auth.getClient();
  const publisher = google.androidpublisher({
    version: "v3",
    auth: authClient,
  });
  let response;
  try {
    response = await publisher.purchases.subscriptionsv2.get({
      packageName,
      token: purchaseToken,
    });
  } catch (error) {
    throw new Error("android-publisher-verification-failed");
  }
  const purchase = response.data || {};
  const lineItems = Array.isArray(purchase.lineItems) ? purchase.lineItems : [];
  const matchingLineItem = lineItems.find((item) =>
    String(item?.productId || "").trim() === expectedProductId,
  );
  if (!matchingLineItem) {
    throw new Error("subscription-product-mismatch");
  }
  const currentPeriodEnd = String(matchingLineItem.expiryTime || "").trim();
  if (!currentPeriodEnd) {
    throw new Error("missing-subscription-expiry");
  }
  const cancellationContext = purchase?.canceledStateContext || {};
  const cancellationReason = Object.keys(cancellationContext).find((key) =>
    key.endsWith("Cancellation"),
  ) || "";
  const cancellationAt = String(
      cancellationContext?.[cancellationReason]?.cancelTime || "",
  ).trim();
  const expiryTimeMs = parseBillingTimeMillis(currentPeriodEnd);
  const subscriptionState = String(purchase.subscriptionState || "").trim();
  const cancellationHasEndedAccess = cancellationAt && expiryTimeMs > 0 &&
    expiryTimeMs <= Date.now();
  return {
    status: resolveBillingStatusFromGooglePlayState(subscriptionState),
    currentPeriodEnd,
    graceUntil: subscriptionState ===
      "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" ? currentPeriodEnd : "",
    autoRenewEnabled:
      typeof matchingLineItem?.autoRenewingPlan?.autoRenewEnabled === "boolean" ?
        matchingLineItem.autoRenewingPlan.autoRenewEnabled :
        null,
    cancellationAt,
    cancellationReason,
    storeStatus: subscriptionState,
    storeEnvironment: "production",
    revokedAt: cancellationHasEndedAccess ? cancellationAt : "",
    refundedAt: cancellationHasEndedAccess ? cancellationAt : "",
    latestPurchaseAt: String(purchase.startTime || "").trim(),
    platform: "android",
    storeProductId: String(matchingLineItem.productId || "").trim(),
  };
}

async function verifyStorePurchaseOrThrow({
  platform,
  productId,
  purchaseToken,
}) {
  if (platform === "android") {
    return verifyAndroidSubscriptionPurchase({
      packageName: BILLING_ANDROID_PACKAGE_NAME,
      purchaseToken,
      expectedProductId: productId,
    });
  }
  if (isAppleBillingPlatform(platform)) {
    return verifyIosSubscriptionPurchase({
      platform,
      receiptData: purchaseToken,
      expectedProductId: productId,
    });
  }
  throw new Error("unsupported-store-platform");
}

function buildVerifiedBillingRecord({
  currentBilling,
  selectedPlan,
  verifiedPurchase,
  verificationSource,
  purchaseId,
  transactionDate,
}) {
  const now = new Date().toISOString();
  const currentPeriodEnd = String(verifiedPurchase.currentPeriodEnd || "").trim();
  const status = String(verifiedPurchase.status || "expired").trim();
  const latestPurchaseAt = String(verifiedPurchase.latestPurchaseAt || "").trim();
  const graceUntil = String(verifiedPurchase.graceUntil || "").trim() ||
    (status === "grace_period" ? currentPeriodEnd : "");

  const nextBilling = {
    ...currentBilling,
    status,
    selectedPlan: normalizeBillingPlan(
        selectedPlan || currentBilling.selectedPlan,
    ),
    pendingPlan: "",
    planConfirmed: true,
    platform: String(
        verifiedPurchase.platform || currentBilling.platform || "",
    ).trim(),
    trialEligible: false,
    currentPeriodEnd,
    graceUntil,
    autoRenewEnabled:
      typeof verifiedPurchase.autoRenewEnabled === "boolean" ?
        verifiedPurchase.autoRenewEnabled :
        currentBilling.autoRenewEnabled ?? null,
    cancellationAt: String(verifiedPurchase.cancellationAt || "").trim(),
    cancellationReason: String(
        verifiedPurchase.cancellationReason ||
        currentBilling.cancellationReason ||
        "",
    ).trim(),
    storeStatus: String(
        verifiedPurchase.storeStatus || currentBilling.storeStatus || "",
    ).trim(),
    storeEnvironment: String(
        verifiedPurchase.storeEnvironment ||
        currentBilling.storeEnvironment ||
        "",
    ).trim(),
    revokedAt: String(verifiedPurchase.revokedAt || "").trim(),
    refundedAt: String(verifiedPurchase.refundedAt || "").trim(),
    storeProductId: String(
        verifiedPurchase.storeProductId || currentBilling.storeProductId || "",
    ).trim(),
    latestPurchaseId: String(
        purchaseId || currentBilling.latestPurchaseId || "",
    ).trim(),
    latestPurchaseAt: latestPurchaseAt ||
      String(currentBilling.latestPurchaseAt || transactionDate || "").trim(),
    latestVerificationSource: String(
        verificationSource || currentBilling.latestVerificationSource || "",
    ).trim(),
    lastStoreSyncAt: now,
    lastStoreSyncStatus: "ok",
    updatedAt: now,
  };
  nextBilling.accessUntilMillis = billingAccessUntilMillis(
      nextBilling,
      nextBilling.status,
  );
  return nextBilling;
}

function timeToMinutes(value) {
  if (typeof value !== "string" || !value.includes(":")) return -1;
  const [hourText, minuteText] = value.split(":");
  const hour = Number.parseInt(hourText, 10);
  const minute = Number.parseInt(minuteText, 10);
  if (Number.isNaN(hour) || Number.isNaN(minute)) return -1;
  return hour * 60 + minute;
}

function minutesToTime(totalMinutes) {
  const hour = String(Math.floor(totalMinutes / 60)).padStart(2, "0");
  const minute = String(totalMinutes % 60).padStart(2, "0");
  return `${hour}:${minute}`;
}

function sameDate(left, right) {
  return (
    left.getFullYear() === right.getFullYear() &&
    left.getMonth() === right.getMonth() &&
    left.getDate() === right.getDate()
  );
}

function rangesOverlap(startA, endA, startB, endB) {
  return startA < endB && endA > startB;
}

function roundUpToFive(totalMinutes) {
  return Math.ceil(totalMinutes / 5) * 5;
}

function roundUpToStep(totalMinutes, stepMinutes) {
  const step = Math.max(1, Number(stepMinutes) || 1);
  return Math.ceil(totalMinutes / step) * step;
}

function getAthensNowInfo() {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Athens",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
  const parts = Object.fromEntries(
      formatter.formatToParts(new Date())
          .filter((part) => part.type !== "literal")
          .map((part) => [part.type, part.value]),
  );
  const dateKey = `${parts.year}-${parts.month}-${parts.day}`;
  return {
    dateKey,
    totalMinutes: (Number.parseInt(parts.hour, 10) * 60) +
      Number.parseInt(parts.minute, 10),
    daySerial: dateKeyToDaySerial(dateKey),
  };
}

function dateKeyToDaySerial(dateKey) {
  const [yearText, monthText, dayText] = String(dateKey || "").split("-");
  const year = Number.parseInt(yearText, 10);
  const month = Number.parseInt(monthText, 10);
  const day = Number.parseInt(dayText, 10);
  if (!year || !month || !day) return Number.NaN;
  return Math.floor(Date.UTC(year, month - 1, day) / 86400000);
}

function buildOccupiedSlotsFallback(startTime, totalMinutes, slotMinutes) {
  const start = timeToMinutes(startTime);
  if (start < 0) return [startTime];
  const slotsNeeded = Math.max(
      1,
      Math.ceil((totalMinutes > 0 ? totalMinutes : slotMinutes) / slotMinutes),
  );
  return Array.from(
      {length: slotsNeeded},
      (_, index) => minutesToTime(start + index * slotMinutes),
  );
}

function normalizeAppointmentRecord(id, value, slotMinutes) {
  const appointment = value && typeof value === "object" ? value : {};
  return {
    id,
    customerUid: appointment.customerUid || "",
    customerName: appointment.customerName || "",
    customerPhone: appointment.customerPhone || "",
    customerEmail: appointment.customerEmail || "",
    barberId: appointment.barberId || "",
    barberName: appointment.barberName || "",
    date: appointment.date || "",
    time: appointment.time || "",
    services: Array.isArray(appointment.services) ? appointment.services : [],
    serviceKeys: Array.isArray(appointment.serviceKeys) ?
      appointment.serviceKeys :
      [],
    addOnKeys: Array.isArray(appointment.addOnKeys) ?
      appointment.addOnKeys :
      [],
    totalPrice: Number.parseInt(appointment.totalPrice, 10) || 0,
    totalMinutes: Number.parseInt(appointment.totalMinutes, 10) || 0,
    status: normalizeAppointmentStatus(appointment.status),
    blocked: appointment.blocked === true,
    blockReason: String(appointment.blockReason || "").trim(),
    remindersSent:
      appointment.remindersSent &&
      typeof appointment.remindersSent === "object" ?
        appointment.remindersSent :
        {},
    occupiedSlots: Array.isArray(appointment.occupiedSlots) &&
        appointment.occupiedSlots.length > 0 ?
      appointment.occupiedSlots :
      buildOccupiedSlotsFallback(
          appointment.time || "",
          Number.parseInt(appointment.totalMinutes, 10) || 0,
          slotMinutes,
      ),
  };
}

function normalizeAppointmentMap(rawAppointments, slotMinutes) {
  if (!rawAppointments || typeof rawAppointments !== "object") {
    return [];
  }
  return Object.entries(rawAppointments).map(([id, value]) =>
    normalizeAppointmentRecord(id, value, slotMinutes),
  );
}

function serviceLabelForKey(key) {
  switch (key) {
    case "classic_haircut":
      return "Classic Haircut";
    case "skin_fade":
      return "Skin Fade";
    case "beard_trim":
      return "Beard Trim";
    case "haircut_and_beard":
      return "Haircut & Beard";
    case "fade_and_beard":
      return "Fade & Beard";
    case "kids_haircut":
      return "Kids Haircut";
    case "buzz_cut":
      return "Buzz Cut";
    case "scissor_cut":
      return "Scissor Cut";
    case "head_shave":
      return "Head Shave";
    case "hot_towel_shave":
      return "Hot Towel Shave";
    case "beard_shape":
      return "Beard Shape";
    case "hair_styling":
      return "Hair Styling";
    case "eyebrow_trim":
      return "Eyebrow Trim";
    default:
      return String(key || "").replaceAll("_", " ");
  }
}

function defaultServiceDurations() {
  return [
    {key: "classic_haircut", label: "Classic Haircut", minutes: 30, enabled: true, barberIds: []},
    {key: "skin_fade", label: "Skin Fade", minutes: 35, enabled: true, barberIds: []},
    {key: "beard_trim", label: "Beard Trim", minutes: 20, enabled: true, barberIds: []},
    {key: "haircut_and_beard", label: "Haircut & Beard", minutes: 45, enabled: true, barberIds: []},
    {key: "fade_and_beard", label: "Fade & Beard", minutes: 50, enabled: true, barberIds: []},
    {key: "kids_haircut", label: "Kids Haircut", minutes: 25, enabled: true, barberIds: []},
    {key: "buzz_cut", label: "Buzz Cut", minutes: 20, enabled: true, barberIds: []},
    {key: "scissor_cut", label: "Scissor Cut", minutes: 40, enabled: true, barberIds: []},
    {key: "head_shave", label: "Head Shave", minutes: 25, enabled: true, barberIds: []},
    {key: "hot_towel_shave", label: "Hot Towel Shave", minutes: 30, enabled: true, barberIds: []},
    {key: "beard_shape", label: "Beard Shape", minutes: 25, enabled: true, barberIds: []},
    {key: "hair_styling", label: "Hair Styling", minutes: 15, enabled: true, barberIds: []},
    {key: "eyebrow_trim", label: "Eyebrow Trim", minutes: 10, enabled: true, barberIds: []},
  ];
}

function defaultServicePrices() {
  return [
    {key: "classic_haircut", label: "Classic Haircut", price: 15},
    {key: "skin_fade", label: "Skin Fade", price: 18},
    {key: "beard_trim", label: "Beard Trim", price: 10},
    {key: "haircut_and_beard", label: "Haircut & Beard", price: 22},
    {key: "fade_and_beard", label: "Fade & Beard", price: 25},
    {key: "kids_haircut", label: "Kids Haircut", price: 12},
    {key: "buzz_cut", label: "Buzz Cut", price: 10},
    {key: "scissor_cut", label: "Scissor Cut", price: 18},
    {key: "head_shave", label: "Head Shave", price: 12},
    {key: "hot_towel_shave", label: "Hot Towel Shave", price: 15},
    {key: "beard_shape", label: "Beard Shape", price: 12},
    {key: "hair_styling", label: "Hair Styling", price: 8},
    {key: "eyebrow_trim", label: "Eyebrow Trim", price: 5},
  ];
}

function defaultServiceAddOns() {
  return [{
    key: "hair_wash",
    label: "Λούσιμο",
    price: 0,
    minutes: 5,
    enabled: false,
    compatibleServiceKeys: [
      "classic_haircut",
      "skin_fade",
      "haircut_and_beard",
      "fade_and_beard",
      "kids_haircut",
      "buzz_cut",
      "scissor_cut",
    ],
  }];
}

function notificationServiceLabels(shop, appointment) {
  const storedServices = Array.isArray(appointment?.services) ?
    appointment.services
        .map((item) => normalizePossiblyCorruptedText(item))
        .filter(Boolean) :
    [];
  const serviceKeys = Array.isArray(appointment?.serviceKeys) ?
    appointment.serviceKeys
        .map((item) => String(item || "").trim())
        .filter(Boolean) :
    [];
  const addOnKeys = Array.isArray(appointment?.addOnKeys) ?
    appointment.addOnKeys
        .map((item) => String(item || "").trim())
        .filter(Boolean) :
    [];
  if (serviceKeys.length === 0) {
    return storedServices;
  }

  const configuredLabels = Object.fromEntries(
      (Array.isArray(shop?.weekly_schedule?.serviceDurations) ?
        shop.weekly_schedule.serviceDurations : [])
          .map((item) => [
            String(item?.key || "").trim(),
            normalizePossiblyCorruptedText(item?.label),
          ])
          .filter(([key, label]) => key && label),
  );
  const isGenericCustomLabel = (label, key) => {
    const normalizedLabel = String(label || "")
        .trim()
        .toLowerCase()
        .replaceAll("_", " ");
    const normalizedKey = String(key || "").trim().toLowerCase();
    return normalizedLabel === "custom service" ||
      normalizedLabel.startsWith("custom service ") ||
      normalizedKey === "custom_service" ||
      normalizedKey.startsWith("custom_service_");
  };

  const labels = serviceKeys.map((key, index) => {
    const storedLabel = storedServices[index] || "";
    const configuredLabel = configuredLabels[key] || "";
    if (configuredLabel &&
        (isGenericCustomLabel(storedLabel, key) || !storedLabel)) {
      return configuredLabel;
    }
    return storedLabel || configuredLabel || serviceLabelForKey(key);
  }).filter(Boolean);
  if (addOnKeys.length > 0) {
    const configuredAddOnLabels = Object.fromEntries(
        (Array.isArray(shop?.weekly_schedule?.serviceAddOns) ?
          shop.weekly_schedule.serviceAddOns : [])
            .map((item) => [
              String(item?.key || "").trim(),
              normalizePossiblyCorruptedText(item?.label),
            ])
            .filter(([key, label]) => key && label),
    );
    labels.push(...addOnKeys.map((key) =>
      configuredAddOnLabels[key] || (key === "hair_wash" ? "Λούσιμο" : key),
    ));
  }
  return labels;
}

function normalizeAppointmentStatus(value) {
  const normalized = String(value || "").trim().toLowerCase();
  switch (normalized) {
    case "pending":
    case "confirmed":
    case "completed":
    case "cancelled":
    case "no_show":
      return normalized;
    default:
      return "confirmed";
  }
}

function isKnownAppointmentStatus(value) {
  return ["pending", "confirmed", "completed", "cancelled", "no_show"].includes(
      String(value || "").trim().toLowerCase(),
  );
}

function isAllowedAppointmentStatusTransition(currentStatus, nextStatus) {
  const current = normalizeAppointmentStatus(currentStatus);
  const next = normalizeAppointmentStatus(nextStatus);
  if (current === next) {
    return true;
  }
  switch (current) {
    case "pending":
      return next === "confirmed" || next === "completed" ||
        next === "no_show" || next === "cancelled";
    case "confirmed":
      return next === "completed" || next === "no_show" || next === "cancelled";
    case "completed":
    case "cancelled":
    case "no_show":
      return false;
    default:
      return false;
  }
}

function looksCorruptedText(value) {
  const text = String(value || "");
  if (!text) {
    return false;
  }
  if (text.includes("Ξ") || text.includes("�")) {
    return true;
  }
  for (const char of text) {
    const code = char.codePointAt(0);
    if (
      (code >= 0x4E00 && code <= 0x9FFF) ||
      (code >= 0x3400 && code <= 0x4DBF)
    ) {
      return true;
    }
  }
  return false;
}

function decodeLikelyMojibake(value) {
  const source = String(value || "");
  if (!looksCorruptedText(source)) {
    return source;
  }
  try {
    return Buffer.from(source, "latin1").toString("utf8");
  } catch (error) {
    return source;
  }
}

function normalizePossiblyCorruptedText(value) {
  const source = String(value || "").trim();
  if (!source) {
    return source;
  }
  if (!looksCorruptedText(source)) {
    return source;
  }
  const decoded = decodeLikelyMojibake(source).trim();
  if (decoded && !looksCorruptedText(decoded)) {
    return decoded;
  }
  return source;
}

function normalizeCustomerPreferencesRaw(raw) {
  if (Array.isArray(raw)) {
    return raw.map((item) => String(item || "").trim()).filter(Boolean);
  }
  const singleValue = String(raw || "").trim();
  if (!singleValue) {
    return [];
  }
  return [singleValue];
}

function mergeUniqueStrings(left, right) {
  return Array.from(
      new Set(
          []
              .concat(Array.isArray(left) ? left : [left])
              .concat(Array.isArray(right) ? right : [right])
              .map((item) => String(item || "").trim())
              .filter(Boolean),
      ),
  );
}

function buildNormalizedAppointmentServices(appointment) {
  const serviceKeys = Array.isArray(appointment?.serviceKeys) ?
    appointment.serviceKeys.map((item) => String(item || "").trim()).filter(Boolean) :
    [];
  if (serviceKeys.length > 0) {
    return serviceKeys.map(serviceLabelForKey);
  }
  const services = Array.isArray(appointment?.services) ?
    appointment.services.map((item) => normalizePossiblyCorruptedText(item)).filter(Boolean) :
    [];
  if (services.length > 0) {
    return services;
  }
  const singleService = normalizePossiblyCorruptedText(appointment?.service);
  return singleService ? [singleService] : [];
}

function getShopNotificationTokens(shop) {
  const rawTokens =
    shop?.notificationTokens && typeof shop.notificationTokens === "object" ?
      shop.notificationTokens :
      {};
  return Object.values(rawTokens)
      .map((value) => String(value?.token || "").trim())
      .filter(Boolean);
}

function getCustomerNotificationTokens(customer) {
  const rawTokens =
    customer?.notificationTokens &&
    typeof customer.notificationTokens === "object" ?
      customer.notificationTokens :
      {};
  return Object.values(rawTokens)
      .map((value) => String(value?.token || "").trim())
      .filter(Boolean);
}

function normalizeNotificationData(data) {
  return Object.fromEntries(
      Object.entries(data || {}).map(([key, value]) => [
        String(key),
        String(value ?? ""),
      ]),
  );
}

function isPermanentFcmFailure(error) {
  const code = String(error?.code || "").trim().toLowerCase();
  return code === "messaging/invalid-registration-token" ||
    code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-argument";
}

function notificationRetryDelayMs(attempts) {
  const index = Math.min(
      Math.max(Number(attempts || 1) - 1, 0),
      NOTIFICATION_OUTBOX_RETRY_DELAYS_MS.length - 1,
  );
  return NOTIFICATION_OUTBOX_RETRY_DELAYS_MS[index];
}

function notificationCleanupIndexKey(scope, targetPath) {
  return createHash("sha256")
      .update(`${String(scope || "").trim()}|${String(targetPath || "").trim()}`)
      .digest("hex");
}

async function indexNotificationCleanup({scope, targetPath, cleanupAt}) {
  const normalizedScope = String(scope || "").trim();
  const normalizedPath = String(targetPath || "").trim();
  const timestamp = Number(cleanupAt || 0);
  if (!normalizedScope || !normalizedPath || !Number.isFinite(timestamp)) {
    return;
  }
  await getDatabase().ref(
      `${NOTIFICATION_CLEANUP_INDEX_PATH}/${notificationCleanupIndexKey(
          normalizedScope,
          normalizedPath,
      )}`,
  ).set({
    scope: normalizedScope,
    targetPath: normalizedPath,
    cleanupAt: timestamp,
  });
}

async function ensureNotificationCleanupIndex(db, now = Date.now()) {
  const markerRef = db.ref(NOTIFICATION_CLEANUP_INDEX_META_PATH);
  const markerSnapshot = await markerRef.get();
  if (Number(markerSnapshot.val()?.version || 0) >= 1) {
    return;
  }

  // One-time migration for records created before cleanupAt was introduced.
  // Subsequent purges query only the compact cleanup index.
  const updates = {
    [NOTIFICATION_CLEANUP_INDEX_META_PATH]: {
      version: 1,
      bootstrappedAt: new Date(now).toISOString(),
    },
  };
  const outboxSnapshot = await db.ref(NOTIFICATION_OUTBOX_PATH).get();
  for (const [notificationId, item] of Object.entries(outboxSnapshot.val() || {})) {
    const status = String(item?.status || "").trim().toLowerCase();
    if (!['sent', 'failed'].includes(status)) {
      continue;
    }
    const timestamp = Date.parse(String(item?.updatedAt || item?.createdAt || ""));
    if (!Number.isFinite(timestamp)) {
      continue;
    }
    const targetPath = `${NOTIFICATION_OUTBOX_PATH}/${notificationId}`;
    updates[
        `${NOTIFICATION_CLEANUP_INDEX_PATH}/${notificationCleanupIndexKey(
            "outbox",
            targetPath,
        )}`
    ] = {
      scope: "outbox",
      targetPath,
      cleanupAt: timestamp + NOTIFICATION_OUTBOX_RETENTION_MS,
    };
  }

  const inboxSnapshot = await db.ref(NOTIFICATION_INBOX_PATH).get();
  for (const [shopId, items] of Object.entries(inboxSnapshot.val() || {})) {
    for (const [notificationId, item] of Object.entries(items || {})) {
      const timestamp = Date.parse(String(item?.updatedAt || item?.createdAt || ""));
      if (!Number.isFinite(timestamp)) {
        continue;
      }
      const targetPath = `${NOTIFICATION_INBOX_PATH}/${shopId}/${notificationId}`;
      updates[
          `${NOTIFICATION_CLEANUP_INDEX_PATH}/${notificationCleanupIndexKey(
              "inbox",
              targetPath,
          )}`
      ] = {
        scope: "inbox",
        targetPath,
        cleanupAt: timestamp + NOTIFICATION_OUTBOX_RETENTION_MS,
      };
    }
  }
  await db.ref().update(updates);
}

async function claimNotificationOutboxItem(ref) {
  const now = Date.now();
  const lockId = randomUUID();
  const transaction = await ref.transaction((current) => {
    if (!current || typeof current !== "object") {
      return current;
    }
    const status = String(current.status || "").trim().toLowerCase();
    const nextAttemptAt = Number(current.nextAttemptAt || 0);
    const lockExpiresAt = Number(current.lockExpiresAt || 0);
    const isPending = status === "pending" && nextAttemptAt <= now;
    const isStaleProcessing = status === "processing" && lockExpiresAt <= now;
    if (!isPending && !isStaleProcessing) {
      return current;
    }
    return {
      ...current,
      status: "processing",
      lockId,
      lockExpiresAt: now + NOTIFICATION_OUTBOX_LOCK_MS,
      updatedAt: new Date(now).toISOString(),
    };
  });
  const claimed = transaction.snapshot.val();
  if (!transaction.committed || claimed?.lockId !== lockId) {
    return null;
  }
  return claimed;
}

async function updateNotificationOutboxAfterFailure({
  ref,
  item,
  attempts,
  tokens,
  error,
}) {
  const now = Date.now();
  const lastError = String(error?.message || error || "notification-send-failed")
      .slice(0, 500);
  if (attempts >= NOTIFICATION_OUTBOX_MAX_ATTEMPTS) {
    const updatedAt = new Date(now).toISOString();
    await ref.update({
      status: "failed",
      attempts,
      tokens,
      lastError,
      failedAt: updatedAt,
      updatedAt,
      lockId: null,
      lockExpiresAt: NOTIFICATION_OUTBOX_IDLE_TIMESTAMP,
      nextAttemptAt: NOTIFICATION_OUTBOX_IDLE_TIMESTAMP,
    });
    await indexNotificationCleanup({
      scope: "outbox",
      targetPath: `${NOTIFICATION_OUTBOX_PATH}/${ref.key}`,
      cleanupAt: now + NOTIFICATION_OUTBOX_RETENTION_MS,
    });
    return;
  }
  await ref.update({
    status: "pending",
    attempts,
    tokens,
    lastError,
    nextAttemptAt: now + notificationRetryDelayMs(attempts),
    updatedAt: new Date(now).toISOString(),
    lockId: null,
    lockExpiresAt: NOTIFICATION_OUTBOX_IDLE_TIMESTAMP,
  });
}

async function processNotificationOutboxItem(ref) {
  const item = await claimNotificationOutboxItem(ref);
  if (!item) {
    return false;
  }

  const tokens = Array.from(
      new Set(
          (Array.isArray(item.tokens) ? item.tokens : [])
              .map((token) => String(token || "").trim())
              .filter(Boolean),
      ),
  );
  if (tokens.length === 0) {
    const updatedAt = new Date().toISOString();
    await ref.update({
      status: "sent",
      sentAt: updatedAt,
      updatedAt,
      cleanupAt: Date.now() + NOTIFICATION_OUTBOX_RETENTION_MS,
      lockId: null,
      lockExpiresAt: NOTIFICATION_OUTBOX_IDLE_TIMESTAMP,
      nextAttemptAt: NOTIFICATION_OUTBOX_IDLE_TIMESTAMP,
    });
    await indexNotificationCleanup({
      scope: "outbox",
      targetPath: `${NOTIFICATION_OUTBOX_PATH}/${ref.key}`,
      cleanupAt: Date.now() + NOTIFICATION_OUTBOX_RETENTION_MS,
    });
    return true;
  }

  const attempts = Number(item.attempts || 0) + 1;
  const message = {
    tokens,
    notification: item.notification || {},
    data: normalizeNotificationData(item.data),
  };
  const channelId = String(item.androidChannelId || "").trim();
  if (channelId) {
    message.android = {
      priority: "high",
      notification: {channelId},
    };
  }

  try {
    const result = await getMessaging().sendEachForMulticast(message);
    const retryTokens = [];
    let permanentFailureCount = 0;
    (result.responses || []).forEach((response, index) => {
      if (response.success) {
        return;
      }
      if (isPermanentFcmFailure(response.error)) {
        permanentFailureCount += 1;
        return;
      }
      retryTokens.push(tokens[index]);
    });

    if (retryTokens.length === 0) {
      const updatedAt = new Date().toISOString();
      const cleanupAt = Date.now() + NOTIFICATION_OUTBOX_RETENTION_MS;
      await ref.update({
        status: "sent",
        attempts,
        successCount: Number(result.successCount || 0),
        permanentFailureCount,
        sentAt: updatedAt,
        updatedAt,
        cleanupAt,
        lockId: null,
        lockExpiresAt: NOTIFICATION_OUTBOX_IDLE_TIMESTAMP,
        nextAttemptAt: NOTIFICATION_OUTBOX_IDLE_TIMESTAMP,
      });
      await indexNotificationCleanup({
        scope: "outbox",
        targetPath: `${NOTIFICATION_OUTBOX_PATH}/${ref.key}`,
        cleanupAt,
      });
      return true;
    }

    await updateNotificationOutboxAfterFailure({
      ref,
      item,
      attempts,
      tokens: retryTokens,
      error: "transient-fcm-failure",
    });
    return false;
  } catch (error) {
    await updateNotificationOutboxAfterFailure({
      ref,
      item,
      attempts,
      tokens,
      error,
    });
    console.error("notification-outbox-send-failed", error);
    return false;
  }
}

async function enqueueNotificationOutbox({
  shopId,
  eventType,
  tokens,
  notification,
  data,
  androidChannelId,
}) {
  const normalizedTokens = Array.from(
      new Set(
          (Array.isArray(tokens) ? tokens : [])
              .map((token) => String(token || "").trim())
              .filter(Boolean),
      ),
  );
  if (normalizedTokens.length === 0) {
    return false;
  }

  const now = Date.now();
  const ref = getDatabase().ref(NOTIFICATION_OUTBOX_PATH).push();
  await ref.set({
    shopId: String(shopId || "").trim(),
    eventType: String(eventType || "general").trim(),
    tokens: normalizedTokens,
    notification: notification || {},
    data: normalizeNotificationData(data),
    androidChannelId: String(androidChannelId || "").trim(),
    status: "pending",
    attempts: 0,
    lockExpiresAt: NOTIFICATION_OUTBOX_IDLE_TIMESTAMP,
    nextAttemptAt: now,
    createdAt: new Date(now).toISOString(),
    updatedAt: new Date(now).toISOString(),
  });

  // The durable write above is the delivery guarantee. A best-effort immediate
  // attempt keeps notifications fast while the scheduled worker handles retry.
  try {
    await processNotificationOutboxItem(ref);
  } catch (error) {
    console.error("notification-outbox-processing-failed", error);
  }
  return true;
}

function notificationInboxId(eventType, data) {
  const identity = [
    String(eventType || "general").trim(),
    String(data?.appointmentId || "").trim(),
    String(data?.reminderKey || "").trim(),
    String(data?.date || "").trim(),
    String(data?.time || "").trim(),
    String(data?.status || "").trim(),
  ].join("|");
  return createHash("sha256").update(identity).digest("hex").slice(0, 40);
}

async function enqueueOwnerNotificationInbox({
  shopId = "",
  eventType = "general",
  notification = {},
  data = {},
}) {
  try {
    const normalizedShopId = String(shopId || "").trim();
    if (!normalizedShopId) {
      return false;
    }
    const normalizedEventType = String(eventType || "general").trim();
    const normalizedData = normalizeNotificationData(data);
    const notificationId = notificationInboxId(
        normalizedEventType,
        normalizedData,
    );
    const ref = getDatabase().ref(
        `${NOTIFICATION_INBOX_PATH}/${normalizedShopId}/${notificationId}`,
    );
    const existingSnapshot = await ref.get();
    const existing = existingSnapshot.exists() ?
      existingSnapshot.val() || {} :
      {};
    const now = Date.now();
    const updatedAt = new Date(now).toISOString();
    const cleanupAt = now + NOTIFICATION_OUTBOX_RETENTION_MS;
    await ref.set({
      id: notificationId,
      recipient: "owner",
      eventType: normalizedEventType,
      notification: {
        title: String(notification?.title || "").trim(),
        body: String(notification?.body || "").trim(),
      },
      data: normalizedData,
      createdAt: String(existing.createdAt || new Date(now).toISOString()),
      updatedAt,
      cleanupAt,
    });
    await indexNotificationCleanup({
      scope: "inbox",
      targetPath: `${NOTIFICATION_INBOX_PATH}/${normalizedShopId}/${notificationId}`,
      cleanupAt,
    });
    return true;
  } catch (error) {
    console.error("owner-notification-inbox-write-failed", error);
    return false;
  }
}

function findCustomerRecordForAppointment(shop, appointment) {
  const rawCustomers = shop?.customers && typeof shop.customers === "object" ?
    shop.customers :
    {};
  const customerUid = String(appointment?.customerUid || "").trim();
  if (customerUid && rawCustomers[customerUid]) {
    return rawCustomers[customerUid];
  }

  const customerEmail = String(appointment?.customerEmail || "")
      .trim()
      .toLowerCase();
  if (customerEmail) {
    const byEmail = Object.values(rawCustomers).find((customer) =>
      String(customer?.email || "").trim().toLowerCase() === customerEmail,
    );
    if (byEmail) {
      return byEmail;
    }
  }

  const customerName = String(appointment?.customerName || "")
      .trim()
      .toLowerCase();
  if (customerName) {
    const byName = Object.values(rawCustomers).find((customer) =>
      String(customer?.fullName || "").trim().toLowerCase() === customerName,
    );
    if (byName) {
      return byName;
    }
  }

  return null;
}

async function sendCustomerLifecycleNotification({
  shopId = "",
  shop,
  appointment,
  eventType,
}) {
  const customer = findCustomerRecordForAppointment(shop, appointment);
  const tokens = getCustomerNotificationTokens(customer);
  if (tokens.length === 0) {
    return;
  }

  let title = "Ενημέρωση ραντεβού";
  switch (eventType) {
    case "confirmed":
      title = "Το ραντεβού επιβεβαιώθηκε";
      break;
    case "cancelled":
      title = "Το ραντεβού ακυρώθηκε";
      break;
    case "rescheduled":
      title = "Το ραντεβού μεταφέρθηκε";
      break;
    case "completed":
      title = "Το ραντεβού ολοκληρώθηκε";
      break;
    case "no_show":
      title = "Το ραντεβού σημειώθηκε ως no-show";
      break;
  }

  const serviceText = notificationServiceLabels(shop, appointment).join(" • ");
  const bodyParts = [
    String(appointment.barberName || "").trim(),
    String(appointment.date || "").trim(),
    String(appointment.time || "").trim(),
  ].filter(Boolean);
  if (serviceText) {
    bodyParts.push(serviceText);
  }

  try {
    await enqueueNotificationOutbox({
      shopId,
      eventType: `appointment_${eventType}`,
      tokens,
      notification: {
        title,
        body: bodyParts.join(" • "),
      },
      data: {
        type: `appointment_${eventType}`,
        appointmentId: String(appointment.id || ""),
        barberId: String(appointment.barberId || ""),
        barberName: String(appointment.barberName || ""),
        date: String(appointment.date || ""),
        time: String(appointment.time || ""),
        status: String(appointment.status || ""),
      },
      androidChannelId: CUSTOMER_NOTIFICATION_CHANNEL_ID,
    });
  } catch (error) {
    console.error("send-customer-lifecycle-notification-failed", error);
  }
}

function getAppointmentReminderTargets() {
  return [
    {key: "reminder24h", leadMinutes: 24 * 60, label: "Αύριο"},
    {key: "reminder1h", leadMinutes: 60, label: "Σε 1 ώρα"},
  ];
}

function getAppointmentReminderDue(appointment, nowInfo) {
  const appointmentDaySerial = dateKeyToDaySerial(appointment?.date);
  const appointmentMinutes = timeToMinutes(String(appointment?.time || ""));
  if (Number.isNaN(appointmentDaySerial) || appointmentMinutes < 0) {
    return null;
  }

  const remainingMinutes =
    ((appointmentDaySerial - nowInfo.daySerial) * 1440) +
    (appointmentMinutes - nowInfo.totalMinutes);
  if (remainingMinutes < 0) {
    return null;
  }

  const sentFlags =
    appointment?.remindersSent &&
    typeof appointment.remindersSent === "object" ?
      appointment.remindersSent :
      {};
  const reminderWindowMinutes = 35;
  return getAppointmentReminderTargets().find((target) =>
    !sentFlags[target.key] &&
    remainingMinutes <= target.leadMinutes &&
    remainingMinutes > target.leadMinutes - reminderWindowMinutes,
  ) || null;
}

function athensOffsetMillisAt(timestamp) {
  const parts = Object.fromEntries(
      new Intl.DateTimeFormat("en-CA", {
        timeZone: "Europe/Athens",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        hourCycle: "h23",
      }).formatToParts(new Date(timestamp))
          .filter((part) => part.type !== "literal")
          .map((part) => [part.type, part.value]),
  );
  const localAsUtc = Date.UTC(
      Number(parts.year),
      Number(parts.month) - 1,
      Number(parts.day),
      Number(parts.hour),
      Number(parts.minute),
      Number(parts.second),
  );
  return localAsUtc - timestamp;
}

function athensAppointmentTimestamp(dateText, timeText) {
  const date = String(dateText || "").trim();
  const time = String(timeText || "").trim();
  if (!parseDashboardDateKey(date) || timeToMinutes(time) < 0) {
    return Number.NaN;
  }
  const naiveUtc = Date.parse(`${date}T${time}:00.000Z`);
  if (!Number.isFinite(naiveUtc)) {
    return Number.NaN;
  }
  return naiveUtc - athensOffsetMillisAt(naiveUtc);
}

function appointmentReminderIndexKey(shopId, appointmentId) {
  return createHash("sha256")
      .update(`${String(shopId || "").trim()}|${String(appointmentId || "").trim()}`)
      .digest("hex");
}

function buildAppointmentReminderIndexRecord({
  shopId,
  appointmentId,
  appointment,
  now = Date.now(),
}) {
  const status = normalizeAppointmentStatus(appointment?.status);
  const appointmentAt = athensAppointmentTimestamp(
      appointment?.date,
      appointment?.time,
  );
  if (status !== "confirmed" || !Number.isFinite(appointmentAt)) {
    return null;
  }

  const remindersSent = appointment?.remindersSent &&
      typeof appointment.remindersSent === "object" ?
    appointment.remindersSent :
    {};
  const dueAt = {};
  let nextCheckAt = NOTIFICATION_OUTBOX_IDLE_TIMESTAMP;
  for (const target of getAppointmentReminderTargets()) {
    const targetAt = appointmentAt - target.leadMinutes * 60 * 1000;
    dueAt[target.key] = targetAt;
    if (!remindersSent[target.key] && targetAt >= now - 35 * 60 * 1000) {
      nextCheckAt = Math.min(nextCheckAt, targetAt);
    }
  }

  return {
    shopId: String(shopId || "").trim(),
    appointmentId: String(appointmentId || "").trim(),
    nextCheckAt,
    reminder24hAt: dueAt.reminder24h,
    reminder1hAt: dueAt.reminder1h,
    updatedAt: new Date(now).toISOString(),
  };
}

async function ensureAppointmentReminderIndex(db, now = Date.now()) {
  const markerRef = db.ref(APPOINTMENT_REMINDER_INDEX_META_PATH);
  const markerSnapshot = await markerRef.get();
  if (Number(markerSnapshot.val()?.version || 0) >= 1) {
    return;
  }

  // One-time migration for appointments created before the index existed.
  // Future writes are handled by the appointment child trigger below.
  const shopsSnapshot = await db.ref("shops").get();
  const updates = {
    [APPOINTMENT_REMINDER_INDEX_META_PATH]: {
      version: 1,
      bootstrappedAt: new Date(now).toISOString(),
    },
  };
  for (const [shopId, shop] of Object.entries(shopsSnapshot.val() || {})) {
    const appointments = shop?.appointments &&
        typeof shop.appointments === "object" ?
      shop.appointments :
      {};
    for (const [appointmentId, appointment] of Object.entries(appointments)) {
      const record = buildAppointmentReminderIndexRecord({
        shopId,
        appointmentId,
        appointment,
        now,
      });
      if (record) {
        updates[
            `${APPOINTMENT_REMINDER_INDEX_PATH}/${appointmentReminderIndexKey(
                shopId,
                appointmentId,
            )}`
        ] = record;
      }
    }
  }
  await db.ref().update(updates);
}

async function sendCustomerReminderNotification({
  shopId = "",
  shop,
  appointment,
  reminder,
}) {
  const customer = findCustomerRecordForAppointment(shop, appointment);
  const tokens = getCustomerNotificationTokens(customer);
  if (tokens.length === 0) {
    return false;
  }

  const serviceText = notificationServiceLabels(shop, appointment).join(" • ");
  const bodyParts = [
    reminder.label,
    String(appointment.date || "").trim(),
    String(appointment.time || "").trim(),
    String(appointment.barberName || "").trim(),
  ].filter(Boolean);
  if (serviceText) {
    bodyParts.push(serviceText);
  }

  try {
    return await enqueueNotificationOutbox({
      shopId,
      eventType: "appointment_reminder",
      tokens,
      notification: {
        title: "Υπενθύμιση ραντεβού",
        body: bodyParts.join(" • "),
      },
      data: {
        type: "appointment_reminder",
        reminderKey: String(reminder.key || ""),
        appointmentId: String(appointment.id || ""),
        barberId: String(appointment.barberId || ""),
        barberName: String(appointment.barberName || ""),
        date: String(appointment.date || ""),
        time: String(appointment.time || ""),
        status: String(appointment.status || ""),
      },
      androidChannelId: CUSTOMER_NOTIFICATION_CHANNEL_ID,
    });
  } catch (error) {
    console.error("send-customer-reminder-notification-failed", error);
    return false;
  }
}

async function sendOwnerNewBookingNotification({shopId = "", shop, appointment}) {
  const tokens = getShopNotificationTokens(shop);

  const serviceText = notificationServiceLabels(shop, appointment).join(" • ");
  const title = "Νέο ραντεβού";
  const bodyParts = [
    String(appointment.customerName || "").trim(),
    String(appointment.date || "").trim(),
    String(appointment.time || "").trim(),
  ].filter(Boolean);
  if (serviceText) {
    bodyParts.push(serviceText);
  }
  const notification = {
    title,
    body: bodyParts.join(" • "),
  };
  const data = {
    type: "new_booking",
    appointmentId: String(appointment.id || ""),
    customerName: String(appointment.customerName || ""),
    barberName: String(appointment.barberName || ""),
    date: String(appointment.date || ""),
    time: String(appointment.time || ""),
  };

  try {
    await enqueueOwnerNotificationInbox({
      shopId,
      eventType: "new_booking",
      notification,
      data,
    });
    if (tokens.length === 0) {
      return;
    }
    await enqueueNotificationOutbox({
      shopId,
      eventType: "new_booking",
      tokens,
      notification,
      data,
      androidChannelId: "barbero_owner_bookings",
    });
  } catch (error) {
    console.error("send-owner-booking-notification-failed", error);
  }
}

async function sendOwnerAppointmentLifecycleNotification({
  shopId = "",
  shop,
  appointment,
  eventType,
}) {
  const tokens = getShopNotificationTokens(shop);

  let title = "Ενημέρωση ραντεβού";
  if (eventType === "cancelled") {
    title = "Το ραντεβού ακυρώθηκε από τον πελάτη";
  } else if (eventType === "rescheduled") {
    title = "Ο πελάτης άλλαξε το ραντεβού";
  }

  const serviceText = notificationServiceLabels(shop, appointment).join(" • ");
  const bodyParts = [
    String(appointment.customerName || "").trim(),
    String(appointment.date || "").trim(),
    String(appointment.time || "").trim(),
  ].filter(Boolean);
  if (serviceText) {
    bodyParts.push(serviceText);
  }
  const notification = {
    title,
    body: bodyParts.join(" • "),
  };
  const data = {
    type: `appointment_${eventType}`,
    appointmentId: String(appointment.id || ""),
    customerName: String(appointment.customerName || ""),
    barberName: String(appointment.barberName || ""),
    date: String(appointment.date || ""),
    time: String(appointment.time || ""),
    status: String(appointment.status || ""),
  };

  try {
    await enqueueOwnerNotificationInbox({
      shopId,
      eventType: `appointment_${eventType}`,
      notification,
      data,
    });
    if (tokens.length === 0) {
      return;
    }
    await enqueueNotificationOutbox({
      shopId,
      eventType: `appointment_${eventType}`,
      tokens,
      notification,
      data,
      androidChannelId: "barbero_owner_bookings",
    });
  } catch (error) {
    console.error("send-owner-appointment-lifecycle-notification-failed", error);
  }
}

function isAppointmentBlockingStatus(status) {
  return normalizeAppointmentStatus(status) === "pending" ||
    normalizeAppointmentStatus(status) === "confirmed";
}

function normalizeClockValue(value, fallback) {
  const parsed = timeToMinutes(String(value || ""));
  return parsed >= 0 ? minutesToTime(parsed) : fallback;
}

function normalizeServiceAddOns(value) {
  return Array.isArray(value) ?
    value.map((item) => ({
      key: String(item?.key || ""),
      label: String(item?.label || "Λούσιμο").trim() || "Λούσιμο",
      price: Math.max(0, Number.parseInt(item?.price, 10) || 0),
      minutes: Math.min(
          15,
          Math.max(1, Number.parseInt(item?.minutes, 10) || 5),
      ),
      enabled: item?.enabled === true,
      compatibleServiceKeys: Array.isArray(item?.compatibleServiceKeys) ?
        item.compatibleServiceKeys
            .map((key) => String(key || "").trim())
            .filter((key) => key && key !== "beard_trim") :
        [],
    })).filter((item) => item.key) :
    [];
}

function normalizeAppointmentCutoffMinutes(value) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return 0;
  }
  const bounded = Math.min(1440, parsed);
  return APPOINTMENT_CUTOFF_OPTIONS_MINUTES.reduce((closest, option) =>
    Math.abs(option - bounded) < Math.abs(closest - bounded) ? option : closest,
  0);
}

function normalizeAppointmentSettings(value) {
  const source = value && typeof value === "object" ? value : {};
  return {
    autoConfirmAppointments: source.autoConfirmAppointments === true,
    remindersEnabled: source.remindersEnabled !== false,
    customerCancellationCutoffMinutes:
      normalizeAppointmentCutoffMinutes(source.customerCancellationCutoffMinutes),
    customerRescheduleCutoffMinutes:
      normalizeAppointmentCutoffMinutes(source.customerRescheduleCutoffMinutes),
    updatedAt: String(source.updatedAt || "").trim(),
  };
}

function minutesUntilAppointment(appointment) {
  const appointmentDaySerial = dateKeyToDaySerial(appointment?.date);
  const appointmentMinutes = timeToMinutes(appointment?.time);
  if (!Number.isFinite(appointmentDaySerial) || appointmentMinutes < 0) {
    return null;
  }
  const now = getAthensNowInfo();
  return (appointmentDaySerial - now.daySerial) * 24 * 60 +
    appointmentMinutes - now.totalMinutes;
}

function normalizeWeeklySchedulePayload(payload) {
  const source = payload && typeof payload === "object" ? payload : {};
  const slotMinutes = Math.max(
      5,
      Number.parseInt(source.slotMinutes, 10) || 30,
  );
  const appointmentsPerSlot = Math.min(
      10,
      Math.max(1, Number.parseInt(source.appointmentsPerSlot, 10) || 1),
  );
  const slotCapacityOverrides = Array.isArray(source.slotCapacityOverrides) ?
    source.slotCapacityOverrides.map((item) => ({
      dayIndex: Math.min(
          6,
          Math.max(0, Number.parseInt(item?.dayIndex, 10) || 0),
      ),
      start: normalizeClockValue(item?.start, "--:--"),
      end: normalizeClockValue(item?.end, "--:--"),
      appointmentsPerSlot: Math.min(
          10,
          Math.max(1, Number.parseInt(item?.appointmentsPerSlot, 10) || 1),
      ),
    })).filter((item) => timeToMinutes(item.start) >= 0 && timeToMinutes(item.end) > timeToMinutes(item.start)) :
    [];
  const closedDateOverrides = Array.isArray(source.closedDateOverrides) ?
    source.closedDateOverrides.map((item) => ({
      date: String(item?.date || item?.dateKey || "").trim(),
      label: String(item?.label || "").trim(),
      isClosed: item?.isClosed === true,
    })).filter((item) => /^\d{4}-\d{2}-\d{2}$/.test(item.date)) :
    [];

  const serviceDurationsSource = Array.isArray(source.serviceDurations) ?
    source.serviceDurations :
    defaultServiceDurations();
  const serviceDurations = serviceDurationsSource.map((item) => ({
      key: String(item?.key || ""),
      label: String(item?.label || ""),
      minutes: Math.max(5, Number.parseInt(item?.minutes, 10) || 30),
      enabled: item?.enabled !== false,
      barberIds: Array.isArray(item?.barberIds) ?
        item.barberIds.map((barberId) => String(barberId || "").trim()).filter(Boolean) :
        [],
    })).filter((item) => item.key);

  const servicePricesSource = Array.isArray(source.servicePrices) ?
    source.servicePrices :
    defaultServicePrices();
  const servicePrices = servicePricesSource.map((item) => ({
      key: String(item?.key || ""),
      label: String(item?.label || ""),
      price: Math.max(0, Number.parseInt(item?.price, 10) || 0),
    })).filter((item) => item.key);
  const serviceAddOns = normalizeServiceAddOns(
      source.serviceAddOns === undefined ? defaultServiceAddOns() : source.serviceAddOns,
  );
  const showPrices = source.showPrices === true;

  const dayNames = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
  ];
  const days = Array.isArray(source.days) ?
    source.days.slice(0, 7).map((item, index) => ({
      name: String(item?.name || dayNames[index] || "Day"),
      enabled: item?.enabled === true,
      start: normalizeClockValue(item?.start, "--:--"),
      end: normalizeClockValue(item?.end, "--:--"),
      breakStart: normalizeClockValue(item?.breakStart, "--:--"),
      breakEnd: normalizeClockValue(item?.breakEnd, "--:--"),
    })) :
    dayNames.map((name) => ({
      name,
      enabled: false,
      start: "--:--",
      end: "--:--",
      breakStart: "--:--",
      breakEnd: "--:--",
    }));

  while (days.length < 7) {
    days.push({
      name: dayNames[days.length],
      enabled: false,
      start: "--:--",
      end: "--:--",
      breakStart: "--:--",
      breakEnd: "--:--",
    });
  }

  const barberSchedules = Array.isArray(source.barberSchedules) ?
    source.barberSchedules.map((item) => {
      const barberId = String(item?.barberId || "").trim();
      const rawDays = Array.isArray(item?.days) ?
        item.days.slice(0, 7).map((dayItem, index) => ({
          name: String(dayItem?.name || dayNames[index] || "Day"),
          enabled: dayItem?.enabled === true,
          start: normalizeClockValue(dayItem?.start, "--:--"),
          end: normalizeClockValue(dayItem?.end, "--:--"),
          breakStart: normalizeClockValue(dayItem?.breakStart, "--:--"),
          breakEnd: normalizeClockValue(dayItem?.breakEnd, "--:--"),
        })) :
        [];
      while (rawDays.length < 7) {
        rawDays.push({
          name: dayNames[rawDays.length],
          enabled: false,
          start: "--:--",
          end: "--:--",
          breakStart: "--:--",
          breakEnd: "--:--",
        });
      }
      return {
        barberId,
        days: rawDays,
      };
    }).filter((item) => item.barberId) :
    [];

  return {
    slotMinutes,
    appointmentsPerSlot,
    slotCapacityOverrides,
    closedDateOverrides,
    barberSchedules,
    serviceDurations,
    servicePrices,
    serviceAddOns,
    showPrices,
    days,
    updatedAt: new Date().toISOString(),
  };
}

async function authenticateRequest(request) {
  const idToken = request.body?.idToken;
  if (!idToken) {
    throw new Error("missing-auth-token");
  }
  try {
    return await getAuth().verifyIdToken(idToken);
  } catch (error) {
    const code = String(error?.code || "").trim();
    if (code === "auth/id-token-expired") {
      throw new Error("expired-auth-token");
    }
    throw new Error("invalid-auth-token");
  }
}

function safeClientErrorDetails(error) {
  const message = String(error?.message || "").trim();
  if (
    message.length > 0 &&
    message.length <= 96 &&
    /^[A-Za-z0-9_.:-]+$/.test(message)
  ) {
    return message;
  }
  return "request-failed";
}

function isValidEmailAddress(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value || "").trim());
}

function isBarberinPlatformAdmin(decoded) {
  const claims = decoded && typeof decoded === "object" ? decoded : {};
  const roles = claims.roles && typeof claims.roles === "object" ?
    claims.roles :
    {};
  return claims.platformRole === "platform_admin" ||
    claims.platformAdmin === true ||
    roles.platformAdmin === true;
}

async function loadShopContext(shopId) {
  const db = getDatabase();
  const snapshot = await db.ref(`shops/${shopId}`).get();
  if (!snapshot.exists()) {
    throw new Error("shop-not-found");
  }
  const shop = snapshot.val() || {};
  const schedule = normalizeWeeklySchedulePayload(shop.weekly_schedule || {});
  const slotMinutes = Number.parseInt(schedule.slotMinutes, 10) || 30;
  const appointmentsPerSlot =
    Number.parseInt(schedule.appointmentsPerSlot, 10) || 1;
  const slotCapacityOverrides = Array.isArray(schedule.slotCapacityOverrides) ?
    schedule.slotCapacityOverrides :
    [];
  const closedDateOverrides = Array.isArray(schedule.closedDateOverrides) ?
    schedule.closedDateOverrides :
    [];
  const barberSchedules = Array.isArray(schedule.barberSchedules) ?
    schedule.barberSchedules :
    [];
  const serviceDurations = Array.isArray(schedule.serviceDurations) ?
    schedule.serviceDurations :
    defaultServiceDurations();
  const servicePrices = Array.isArray(schedule.servicePrices) ?
    schedule.servicePrices :
    defaultServicePrices();
  const serviceAddOns = normalizeServiceAddOns(
      schedule.serviceAddOns === undefined ? defaultServiceAddOns() : schedule.serviceAddOns,
  );
  const days = Array.isArray(schedule.days) ? schedule.days : [];
  const appointments = normalizeAppointmentMap(shop.appointments, slotMinutes);
  const appointmentSettings = normalizeAppointmentSettings(
      shop.appointmentSettings,
  );

  return {
    db,
    shop,
    days,
    slotMinutes,
    appointmentsPerSlot,
    slotCapacityOverrides,
    closedDateOverrides,
    barberSchedules,
    serviceDurations,
    servicePrices,
    serviceAddOns,
    appointments,
    appointmentSettings,
    autoConfirmAppointments: appointmentSettings.autoConfirmAppointments === true,
  };
}

function hasActiveShopSubscription(shop) {
  const billing = buildBillingSnapshot(shop?.billing);
  return billing.allowsAccess && billing.accessUntilMillis > Date.now();
}

function buildServiceSelection(serviceKeys, serviceDurations, servicePrices) {
  const normalizedServiceKeys = Array.from(new Set(
      serviceKeys.map((key) => String(key || "").trim()).filter(Boolean),
  ));
  const durationByKey = Object.fromEntries(
      serviceDurations.map((item) => [
        item.key,
        Math.max(5, Number(item.minutes) || 30),
      ]),
  );
  const labelByKey = Object.fromEntries(
      serviceDurations
          .filter((item) => String(item.label || '').trim())
          .map((item) => [item.key, String(item.label).trim()]),
  );
  const priceByKey = Object.fromEntries(
      servicePrices.map((item) => [
        item.key,
        Math.max(0, Number(item.price) || 0),
      ]),
  );

  return normalizedServiceKeys
      .map((key) => {
        const duration = serviceDurations.find((item) => item.key === key);
        if (duration?.enabled === false) {
          return null;
        }
        return {
          key,
          label: labelByKey[key] || serviceLabelForKey(key),
          minutes: durationByKey[key] || 30,
          price: priceByKey[key] || 0,
        };
      })
      .filter(Boolean);
}

function buildAddOnSelection(addOnKeys, serviceKeys, serviceAddOns) {
  const selectedServiceKeys = new Set(
      serviceKeys.map((key) => String(key || "").trim()).filter(Boolean),
  );
  const uniqueAddOnKeys = Array.from(new Set(
      addOnKeys.map((key) => String(key || "").trim()).filter(Boolean),
  ));

  return uniqueAddOnKeys.map((key) => {
    const addOn = serviceAddOns.find((item) => String(item.key) === key);
    if (!addOn || addOn.enabled !== true) {
      return null;
    }
    const compatibleServiceKeys = Array.isArray(addOn.compatibleServiceKeys) ?
      addOn.compatibleServiceKeys.filter((serviceKey) => serviceKey !== "beard_trim") :
      [];
    const applies = compatibleServiceKeys.some((serviceKey) =>
      selectedServiceKeys.has(String(serviceKey)),
    );
    if (!applies) return null;
    return {
      key,
      label: String(addOn.label || "Λούσιμο").trim() || "Λούσιμο",
      minutes: Math.min(15, Math.max(1, Number(addOn.minutes) || 5)),
      price: Math.max(0, Number(addOn.price) || 0),
    };
  }).filter(Boolean);
}

function unavailableAddOnKeysForSelection(
    addOnKeys,
    serviceKeys,
    serviceAddOns,
) {
  const selectedServiceKeys = new Set(
      serviceKeys.map((key) => String(key || "").trim()).filter(Boolean),
  );
  return Array.from(new Set(
      addOnKeys.map((key) => String(key || "").trim()).filter(Boolean),
  )).filter((key) => {
    const addOn = serviceAddOns.find((item) => String(item.key) === key);
    if (!addOn || addOn.enabled !== true) return true;
    const compatibleServiceKeys = Array.isArray(addOn.compatibleServiceKeys) ?
      addOn.compatibleServiceKeys.filter((serviceKey) => serviceKey !== "beard_trim") :
      [];
    return !compatibleServiceKeys.some((serviceKey) =>
      selectedServiceKeys.has(String(serviceKey)),
    );
  });
}

function unavailableServiceKeysForBarber(
    serviceKeys,
    serviceDurations,
    barberId,
) {
  const normalizedBarberId = String(barberId || '').trim();
  const normalizedServiceKeys = Array.from(new Set(
      serviceKeys.map((key) => String(key || '').trim()).filter(Boolean),
  ));
  return normalizedServiceKeys.filter((key) => {
    const service = serviceDurations.find((item) => String(item.key) === String(key));
    if (!service || service.enabled === false) {
      return true;
    }
    const assignedBarberIds = Array.isArray(service.barberIds) ?
      service.barberIds.map((item) => String(item).trim()).filter(Boolean) :
      [];
    return assignedBarberIds.length > 0 &&
      !assignedBarberIds.includes(normalizedBarberId);
  });
}

function buildShopBarbers(shop) {
  const barbers = [];
  const rawBarbers = shop?.barbers;

  if (Array.isArray(rawBarbers)) {
    rawBarbers.forEach((item, index) => {
      if (!item || typeof item !== "object") return;
      const fullName = String(
          item.fullName ||
          item.name ||
          `${item.firstName || ""} ${item.lastName || ""}`,
      ).trim();
      const name = fullName;
      if (!name) return;
      barbers.push({
        id: String(item.id || `barber_${index}`),
        name,
        email: String(item.email || "").trim(),
        role: String(item.role || "Barber"),
        status: String(item.status || "active").trim(),
        authUid: String(item.authUid || "").trim(),
        isOwnerBarber: item.isOwnerBarber === true,
        notes: String(item.notes || item.note || "").trim(),
        specialties: Array.isArray(item.specialties) ?
          item.specialties.map((specialty) => String(specialty || "").trim()).filter(Boolean) :
          [],
        photoUrl: String(item.photoUrl || "").trim(),
        expiresAt: String(item.expiresAt || "").trim(),
      });
    });
  }

  if (rawBarbers && typeof rawBarbers === "object" && !Array.isArray(rawBarbers)) {
    Object.entries(rawBarbers).forEach(([key, value]) => {
      if (!value || typeof value !== "object") return;
      const fullName = String(
          value.fullName ||
          value.name ||
          `${value.firstName || ""} ${value.lastName || ""}`,
      ).trim();
      const name = fullName;
      if (!name) return;
      barbers.push({
        id: String(key),
        name,
        email: String(value.email || "").trim(),
        role: String(value.role || "Barber"),
        status: String(value.status || "active").trim(),
        authUid: String(value.authUid || "").trim(),
        isOwnerBarber: value.isOwnerBarber === true,
        notes: String(value.notes || value.note || "").trim(),
        specialties: Array.isArray(value.specialties) ?
          value.specialties.map((specialty) => String(specialty || "").trim()).filter(Boolean) :
          [],
        photoUrl: String(value.photoUrl || "").trim(),
        expiresAt: String(value.expiresAt || "").trim(),
      });
    });
  }

  return barbers;
}

function isActiveCrewEmailConflict(barber, email, ignoredCrewId = "") {
  if (String(barber?.id || "").trim() === String(ignoredCrewId || "").trim()) {
    return false;
  }
  if (String(barber?.email || "").trim().toLowerCase() !== email) {
    return false;
  }
  const status = String(barber?.status || "active").trim().toLowerCase();
  if (status !== "invited") {
    return true;
  }
  const expiresAt = Date.parse(String(barber?.expiresAt || ""));
  return !Number.isFinite(expiresAt) || expiresAt > Date.now();
}

function findCrewInvitesByEmail(shops, email) {
  const normalizedEmail = String(email || "").trim().toLowerCase();
  if (!normalizedEmail) {
    return [];
  }

  const invites = [];
  for (const [shopId, shop] of Object.entries(shops || {})) {
    if (shop?.archivedForTesting === true) {
      continue;
    }
    for (const crewMember of buildShopBarbers(shop)) {
      if (
        String(crewMember.email || "").trim().toLowerCase() !== normalizedEmail
      ) {
        continue;
      }
      const status = String(crewMember.status || "active")
          .trim()
          .toLowerCase();
      const expiresAt = Date.parse(String(crewMember.expiresAt || ""));
      if (
        status !== "invited" ||
        (Number.isFinite(expiresAt) && expiresAt <= Date.now())
      ) {
        continue;
      }
      invites.push({
        shopId,
        shopName: String(shop?.shopName || "").trim(),
        ownerName: String(shop?.ownerName || "").trim(),
        crewId: String(crewMember.id || "").trim(),
        role: resolveBarberoRole(crewMember.role),
        displayName: String(crewMember.name || "").trim(),
        status,
        authUid: String(crewMember.authUid || "").trim(),
        expiresAt: String(crewMember.expiresAt || "").trim(),
      });
    }
  }

  return invites.sort((left, right) => {
    const shopCompare = String(left.shopName || "").localeCompare(
        String(right.shopName || ""),
    );
    if (shopCompare !== 0) {
      return shopCompare;
    }
    return String(left.displayName || "").localeCompare(
        String(right.displayName || ""),
    );
  });
}

function findActiveCrewMembershipsByEmail(shops, email) {
  const normalizedEmail = String(email || "").trim().toLowerCase();
  if (!normalizedEmail) {
    return [];
  }

  const memberships = [];
  for (const [shopId, shop] of Object.entries(shops || {})) {
    if (shop?.archivedForTesting === true) {
      continue;
    }
    for (const crewMember of buildShopBarbers(shop)) {
      const status = String(crewMember.status || "active")
          .trim()
          .toLowerCase();
      const authUid = String(crewMember.authUid || "").trim();
      if (
        String(crewMember.email || "").trim().toLowerCase() !== normalizedEmail ||
        status !== "active" ||
        !authUid
      ) {
        continue;
      }
      memberships.push({
        shopId,
        shopName: String(shop?.shopName || "").trim(),
        ownerName: String(shop?.ownerName || "").trim(),
        crewId: String(crewMember.id || "").trim(),
        role: resolveBarberoRole(crewMember.role),
        displayName: String(crewMember.name || "").trim(),
        status,
        authUid,
        expiresAt: String(crewMember.expiresAt || "").trim(),
      });
    }
  }

  return memberships.sort((left, right) =>
    String(left.shopName || "").localeCompare(String(right.shopName || "")),
  );
}

function resolveBarberoRole(rawRole) {
  const normalized = String(rawRole || "").trim().toLowerCase();
  if (normalized.includes("senior")) {
    return "senior_barber";
  }
  if (normalized.includes("assistant")) {
    return "assistant";
  }
  if (normalized.includes("owner")) {
    return "owner";
  }
  return "barber";
}

async function resolveBarberoSession(decoded) {
  const db = getDatabase();
  const shopsSnapshot = await db.ref("shops").get();
  if (!shopsSnapshot.exists()) {
    throw new Error("shop-not-found");
  }

  const shops = await migrateLegacyOwnerUids(
      decoded,
      shopsSnapshot.val() || {},
  );
  return resolveBarberoSessionFromShops(
      decoded,
      shops,
      String(decoded.activeShopId || "").trim(),
  );
}

function barberoRolePriority(role) {
  switch (resolveBarberoRole(role)) {
    case "owner":
      return 4;
    case "senior_barber":
      return 3;
    case "assistant":
      return 2;
    default:
      return 1;
  }
}

function buildAccessibleBarberoShops(decoded, shops) {
  const accessibleShops = new Map();

  const upsertAccessibleShop = (entry) => {
    const shopId = String(entry?.shopId || "").trim();
    if (!shopId) {
      return;
    }
    const normalizedRole = resolveBarberoRole(entry.role);
    const nextEntry = {
      shopId,
      shopName: String(entry.shopName || "").trim(),
      ownerName: String(entry.ownerName || "").trim(),
      crewId: String(entry.crewId || "").trim(),
      role: normalizedRole,
      displayName: String(entry.displayName || "").trim(),
      status: String(entry.status || "active").trim().toLowerCase(),
      shop: entry.shop || {},
    };
    const current = accessibleShops.get(shopId);
    if (
      !current ||
      barberoRolePriority(nextEntry.role) > barberoRolePriority(current.role)
    ) {
      accessibleShops.set(shopId, nextEntry);
    }
  };

  for (const [shopId, shop] of Object.entries(shops || {})) {
    if (shop?.archivedForTesting === true) {
      continue;
    }
    const ownerUserUid = String(shop?.ownerUserUid || "").trim();
    const isOwnerShop =
      shopId === decoded.uid ||
      ownerUserUid === decoded.uid;

    if (isOwnerShop) {
      upsertAccessibleShop({
        shopId,
        shopName: String(shop?.shopName || "").trim(),
        ownerName: String(shop?.ownerName || "").trim(),
        crewId: "",
        role: "owner",
        displayName: String(shop?.ownerName || "").trim(),
        status: "active",
        shop,
      });
    }

    const crewMember = buildShopBarbers(shop).find((barber) => {
      const barberAuthUid = String(barber.authUid || "").trim();
      const barberStatus = String(barber.status || "active")
          .trim()
          .toLowerCase();
      const authMatches = barberAuthUid && barberAuthUid === decoded.uid;
      if (!authMatches) {
        return false;
      }
      return authMatches && barberStatus === "active";
    });

    if (crewMember) {
      upsertAccessibleShop({
        shopId,
        shopName: String(shop?.shopName || "").trim(),
        ownerName: String(shop?.ownerName || "").trim(),
        crewId: String(crewMember.id || "").trim(),
        role: resolveBarberoRole(crewMember.role),
        displayName: String(crewMember.name || "").trim(),
        status: String(crewMember.status || "active").trim().toLowerCase(),
        shop,
      });
    }
  }

  return Array.from(accessibleShops.values()).sort((left, right) => {
    const roleCompare = barberoRolePriority(right.role) -
      barberoRolePriority(left.role);
    if (roleCompare !== 0) {
      return roleCompare;
    }
    return String(left.shopName || "").localeCompare(String(right.shopName || ""));
  });
}

function resolveBarberoSessionFromShops(decoded, shops, requestedShopId = "") {
  const accessibleShops = buildAccessibleBarberoShops(decoded, shops);
  if (!accessibleShops.length) {
    throw new Error("barbero-session-not-found");
  }

  const normalizedRequestedShopId = String(requestedShopId || "").trim();
  const resolved = normalizedRequestedShopId ?
    accessibleShops.find((entry) => entry.shopId === normalizedRequestedShopId) :
    null;
  const activeShop = resolved || accessibleShops[0];
  if (!activeShop) {
    throw new Error("barbero-session-not-found");
  }

  return {
    ...activeShop,
    accessibleShops,
    shop: activeShop.shop || {},
  };
}

function parseDashboardDateKey(value) {
  const normalized = String(value || "").trim();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(normalized);
  if (!match) {
    return null;
  }
  const date = new Date(
      Number.parseInt(match[1], 10),
      Number.parseInt(match[2], 10) - 1,
      Number.parseInt(match[3], 10),
  );
  return dateKeyFromDateValue(date) === normalized ? date : null;
}

function isValidTimeText(value) {
  const normalized = String(value || "").trim();
  const minutes = timeToMinutes(normalized);
  return /^\d{2}:\d{2}$/.test(normalized) && minutes >= 0 && minutes < 24 * 60;
}

function dashboardDayOpenMinutes(day) {
  if (!day || day.enabled !== true) {
    return 0;
  }
  const start = timeToMinutes(String(day.start || ""));
  const end = timeToMinutes(String(day.end || ""));
  if (start < 0 || end <= start) {
    return 0;
  }
  let openMinutes = end - start;
  const breakStart = timeToMinutes(String(day.breakStart || ""));
  const breakEnd = timeToMinutes(String(day.breakEnd || ""));
  if (breakStart >= start && breakEnd > breakStart && breakEnd <= end) {
    openMinutes -= breakEnd - breakStart;
  }
  return Math.max(0, openMinutes);
}

function buildUnifiedShopDashboard({shopId, shop, startDate, endDate}) {
  const schedule = shop?.weekly_schedule &&
      typeof shop.weekly_schedule === "object" ?
    shop.weekly_schedule :
    {};
  const slotMinutes = Math.max(
      5,
      Number.parseInt(schedule.slotMinutes, 10) || 30,
  );
  const appointmentsPerSlot = Math.min(
      10,
      Math.max(1, Number.parseInt(schedule.appointmentsPerSlot, 10) || 1),
  );
  const generalDays = Array.isArray(schedule.days) ? schedule.days : [];
  const barberSchedules = Array.isArray(schedule.barberSchedules) ?
    schedule.barberSchedules :
    [];
  const closedDateOverrides = Array.isArray(schedule.closedDateOverrides) ?
    schedule.closedDateOverrides :
    [];
  const activeBarbers = buildShopBarbers(shop).filter((barber) =>
    String(barber.status || "active").trim().toLowerCase() === "active",
  );
  const capacityOwners = activeBarbers.length > 0 ?
    activeBarbers.map((barber) => barber.id) :
    [""];
  const startKey = dateKeyFromDateValue(startDate);
  const endKey = dateKeyFromDateValue(endDate);
  let availableMinutes = 0;

  for (
    let cursor = new Date(startDate);
    cursor <= endDate;
    cursor.setDate(cursor.getDate() + 1)
  ) {
    const dateKey = dateKeyFromDateValue(cursor);
    if (isDateClosedForShop(dateKey, closedDateOverrides)) {
      continue;
    }
    const dayIndex = cursor.getDay() === 0 ? 6 : cursor.getDay() - 1;
    for (const barberId of capacityOwners) {
      const barberSchedule = barberSchedules.find((item) =>
        String(item?.barberId || "").trim() === barberId,
      );
      const barberDay = Array.isArray(barberSchedule?.days) ?
        barberSchedule.days[dayIndex] :
        null;
      const generalDay = generalDays[dayIndex];
      const day = barberDay && typeof barberDay === "object" ?
        barberDay :
        generalDay;
      availableMinutes += dashboardDayOpenMinutes(day) * appointmentsPerSlot;
    }
  }

  const rawAppointments = shop?.appointments &&
      typeof shop.appointments === "object" ?
    shop.appointments :
    {};
  const periodAppointments = Object.entries(rawAppointments)
      .map(([id, rawAppointment]) => ({
        id,
        ...(rawAppointment && typeof rawAppointment === "object" ?
          rawAppointment : {}),
      }))
      .filter((appointment) => {
        const date = String(appointment.date || "").trim();
        return date >= startKey && date <= endKey;
      });
  const meaningfulAppointments = periodAppointments.filter((appointment) =>
    appointment.blocked !== true,
  );
  const activeAppointments = meaningfulAppointments.filter((appointment) =>
    ["pending", "confirmed", "completed"].includes(
        normalizeAppointmentStatus(appointment.status),
    ),
  );
  const completedAppointments = meaningfulAppointments.filter((appointment) =>
    normalizeAppointmentStatus(appointment.status) === "completed",
  );
  const cancelledAppointments = meaningfulAppointments.filter((appointment) =>
    normalizeAppointmentStatus(appointment.status) === "cancelled",
  );
  const noShowAppointments = meaningfulAppointments.filter((appointment) =>
    normalizeAppointmentStatus(appointment.status) === "no_show",
  );
  const pendingAppointments = meaningfulAppointments.filter((appointment) =>
    normalizeAppointmentStatus(appointment.status) === "pending",
  );
  const appointmentMinutes = (appointment) => Math.max(
      1,
      Number.parseInt(appointment.totalMinutes, 10) || slotMinutes,
  );
  const estimatedRevenue = activeAppointments.reduce((total, appointment) =>
    total + Math.max(0, Number.parseInt(appointment.totalPrice, 10) || 0), 0,
  );
  const actualRevenue = completedAppointments.reduce((total, appointment) =>
    total + Math.max(0, Number.parseInt(appointment.totalPrice, 10) || 0), 0,
  );
  const occupiedMinutes = activeAppointments.reduce((total, appointment) =>
    total + appointmentMinutes(appointment), 0,
  );
  const occupancyPercent = availableMinutes <= 0 ?
    0 :
    Math.min(100, Math.round((occupiedMinutes / availableMinutes) * 100));
  const alerts = [];
  const addAlert = (type, title, body, severity = "medium") => {
    alerts.push({type, title, body, severity});
  };
  const cancellationRate = meaningfulAppointments.length === 0 ?
    0 :
    (cancelledAppointments.length / meaningfulAppointments.length) * 100;
  if (cancelledAppointments.length >= 2 && cancellationRate >= 15) {
    addAlert(
        "cancellations",
        "Αυξημένες ακυρώσεις",
        `Καταγράφηκαν ${cancelledAppointments.length} ακυρώσεις (${Math.round(cancellationRate)}%).`,
        cancellationRate >= 25 ? "high" : "medium",
    );
  }
  if (noShowAppointments.length >= 2) {
    addAlert(
        "no_show",
        "Επαναλαμβανόμενες μη εμφανίσεις",
        `Καταγράφηκαν ${noShowAppointments.length} μη εμφανίσεις αυτόν τον μήνα.`,
        "medium",
    );
  }
  if (pendingAppointments.length >= 3) {
    addAlert(
        "pending",
        "Ραντεβού σε αναμονή",
        `Υπάρχουν ${pendingAppointments.length} ραντεβού που χρειάζονται επιβεβαίωση.`,
        "medium",
    );
  }
  if (availableMinutes > 0 && occupancyPercent < 40) {
    addAlert(
        "low_occupancy",
        "Χαμηλή πληρότητα",
        `Η πληρότητα του καταστήματος είναι ${occupancyPercent}% για την τρέχουσα περίοδο.`,
        occupancyPercent < 20 ? "high" : "low",
    );
  }

  return {
    shopId: String(shopId || "").trim(),
    shopName: resolveShopDisplayName(shop),
    billingStatus: buildBillingSnapshot(shop?.billing).status,
    totalAppointments: meaningfulAppointments.length,
    completedAppointments: completedAppointments.length,
    pendingAppointments: pendingAppointments.length,
    cancelledAppointments: cancelledAppointments.length,
    noShowAppointments: noShowAppointments.length,
    estimatedRevenue,
    actualRevenue,
    occupancyPercent,
    availableMinutes,
    occupiedMinutes,
    alerts,
  };
}

function buildUnifiedDashboardDateRange(request) {
  const now = new Date();
  const defaultStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const defaultEnd = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate(),
  );
  const requestedStart = parseDashboardDateKey(request.body?.startDate);
  const requestedEnd = parseDashboardDateKey(request.body?.endDate);
  const startDate = requestedStart || defaultStart;
  let endDate = requestedEnd || defaultEnd;
  if (endDate < startDate) {
    endDate = new Date(startDate);
  }
  const maxEndDate = new Date(startDate);
  maxEndDate.setDate(maxEndDate.getDate() + 365);
  if (endDate > maxEndDate) {
    endDate = maxEndDate;
  }
  return {startDate, endDate};
}

exports.barberoGetUnifiedDashboard = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const resolved = await resolveBarberoSession(decoded);
    if (resolved.role !== "owner") {
      return json(response, 403, {ok: false, message: "owner-only"});
    }
    const activeOwnerBilling = (resolved.accessibleShops || [])
        .filter((entry) => entry.role === "owner")
        .filter((entry) => buildBillingSnapshot(entry.shop?.billing).allowsAccess);
    if (activeOwnerBilling.length === 0) {
      throw new Error("subscription-required");
    }
    const ownerShops = activeOwnerBilling;
    const {startDate, endDate} = buildUnifiedDashboardDateRange(request);
    const shopSummaries = ownerShops.map((entry) =>
      buildUnifiedShopDashboard({
        shopId: entry.shopId,
        shop: entry.shop,
        startDate,
        endDate,
      }),
    );
    const totals = shopSummaries.reduce((summary, shop) => ({
      totalAppointments: summary.totalAppointments + shop.totalAppointments,
      completedAppointments:
        summary.completedAppointments + shop.completedAppointments,
      estimatedRevenue: summary.estimatedRevenue + shop.estimatedRevenue,
      actualRevenue: summary.actualRevenue + shop.actualRevenue,
      availableMinutes: summary.availableMinutes + shop.availableMinutes,
      occupiedMinutes: summary.occupiedMinutes + shop.occupiedMinutes,
      alerts: summary.alerts + shop.alerts.length,
    }), {
      totalAppointments: 0,
      completedAppointments: 0,
      estimatedRevenue: 0,
      actualRevenue: 0,
      availableMinutes: 0,
      occupiedMinutes: 0,
      alerts: 0,
    });
    const alerts = shopSummaries.flatMap((shop) =>
      shop.alerts.map((alert) => ({
        ...alert,
        shopId: shop.shopId,
        shopName: shop.shopName,
      })),
    );
    return json(response, 200, {
      ok: true,
      period: {
        startDate: dateKeyFromDateValue(startDate),
        endDate: dateKeyFromDateValue(endDate),
      },
      totals: {
        shopCount: shopSummaries.length,
        totalAppointments: totals.totalAppointments,
        completedAppointments: totals.completedAppointments,
        estimatedRevenue: totals.estimatedRevenue,
        actualRevenue: totals.actualRevenue,
        occupancyPercent: totals.availableMinutes <= 0 ?
          0 :
          Math.min(
              100,
              Math.round(
                  (totals.occupiedMinutes / totals.availableMinutes) * 100,
              ),
          ),
        alerts: totals.alerts,
      },
      shops: shopSummaries,
      alerts,
    });
  } catch (error) {
    console.error(error);
    return json(response, 403, {
      ok: false,
      message: "unified-dashboard-failed",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoGetPlatformAdminOverview = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    if (!isBarberinPlatformAdmin(decoded)) {
      return json(response, 403, {ok: false, message: "platform-admin-only"});
    }

    const period = platformAdminSummaryPeriod();
    const cached = await seedPlatformAdminSummaryIfNeeded(period);
    const items = platformAdminSummaryItems(cached).map((item) => ({
      shopId: String(item.shopId || "").trim(),
      shopName: String(item.shopName || "").trim(),
      ownerName: String(item.ownerName || "").trim(),
      ownerEmail: String(item.ownerEmail || "").trim(),
      createdAt: String(item.createdAt || "").trim(),
      billingStatus: platformAdminBillingStatus(item),
      customerApp: item.customerApp || {},
    }));
    return json(response, 200, {
      ok: true,
      generatedAt: cached.generatedAt,
      shops: items,
    });
  } catch (error) {
    console.error(error);
    return json(response, 403, {
      ok: false,
      message: "platform-admin-overview-failed",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoCreatePlatformShop = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    if (!isBarberinPlatformAdmin(decoded)) {
      return json(response, 403, {ok: false, message: "platform-admin-only"});
    }

    const payload = request.body || {};
    const ownerName = String(payload.ownerName || "").trim();
    const ownerPhone = String(payload.ownerPhone || "").trim();
    const ownerEmail = String(payload.ownerEmail || "").trim().toLowerCase();
    const shopName = String(payload.shopName || "").trim();
    const location = normalizeShopAddress({
      address: String(payload.address || "").trim(),
      city: String(payload.city || "").trim(),
    });
    const logoBase64 = String(payload.logoBase64 || "").trim();
    const logoContentType = String(payload.logoContentType || "")
        .trim()
        .toLowerCase();
    const iconBase64 = String(payload.iconBase64 || "").trim();
    const iconContentType = String(payload.iconContentType || "")
        .trim()
        .toLowerCase();
    const decodeOptionalImage = (base64, contentType) => {
      if (!base64) return null;
      if (!["image/jpeg", "image/png", "image/webp"].includes(contentType)) {
        throw new Error("unsupported-image-type");
      }
      return decodeBase64Image(base64);
    };
    const logoBytes = decodeOptionalImage(logoBase64, logoContentType);
    const iconBytes = decodeOptionalImage(iconBase64, iconContentType);

    if (!ownerName || !ownerPhone || !ownerEmail || !shopName ||
        !location.address) {
      return json(response, 400, {
        ok: false,
        message: "missing-required-fields",
      });
    }

    const db = getDatabase();
    const shopsRef = db.ref("shops");
    const canonicalIdentity = buildCanonicalShopIdentity({
      shopName,
      address: location.address,
      city: location.city,
    });
    if (!canonicalIdentity) {
      return json(response, 400, {
        ok: false,
        message: "invalid-shop-canonical-identity",
      });
    }
    // Shop creation is rare, so use one authoritative read to prevent a
    // duplicate active shop while keeping normal admin refreshes cached.
    const shopsSnapshot = await shopsRef.get();
    const shops = shopsSnapshot.exists() ? shopsSnapshot.val() || {} : {};
    const canonicalConflict = findActiveShopByCanonicalIdentity(
        shops,
        canonicalIdentity,
    );
    if (canonicalConflict) {
      return json(response, 409, {
        ok: false,
        message: "shop-canonical-identity-conflict",
        shopId: canonicalConflict.shopId,
        shopName: String(canonicalConflict.shop?.shopName || "").trim(),
      });
    }
    const now = new Date().toISOString();
    // The canonical duplicate check above is the only full-tree read in this
    // creation path. Key generation still probes only candidate child paths.
    let shopId = "";
    for (let attempt = 0; attempt < 3; attempt++) {
      const digest = createHash("sha256")
          .update(`${shopName}|${location.address}|${ownerEmail}|${now}|${attempt}|${randomUUID()}`)
          .digest("hex")
          .slice(0, 24);
      const candidate = `shop_${digest}`;
      const existing = await shopsRef.child(candidate).get();
      if (!existing.exists()) {
        shopId = candidate;
        break;
      }
    }
    if (!shopId) {
      throw new Error("shop-id-generation-failed");
    }

    let shopLogoUrl = "";
    let shopIconUrl = "";
    if (logoBytes) {
      shopLogoUrl = await uploadImageAndGetUrl({
        path: `shops/${shopId}/branding/logo`,
        bytes: logoBytes,
        contentType: logoContentType,
      });
    }
    if (iconBytes) {
      shopIconUrl = await uploadImageAndGetUrl({
        path: `shops/${shopId}/branding/app-icon`,
        bytes: iconBytes,
        contentType: iconContentType,
      });
    }

    const billing = buildDefaultBillingRecord();
    const customerApp = buildCustomerAppConfiguration({
      shopId,
      shopName,
      existing: {},
    });
    const shopPayload = {
      id: shopId,
      ownerName,
      ownerPhone,
      ownerEmail,
      shopName,
      address: location.address,
      streetAddress: location.streetAddress,
      city: location.city,
      cityKey: location.cityKey,
      canonicalIdentity,
      billing,
      customerApp,
      weekly_schedule: normalizeWeeklySchedulePayload({}),
      createdAt: now,
      updatedAt: now,
      createdByPlatformAdminUid: String(decoded.uid || "").trim(),
      createdByPlatformAdminEmail: String(decoded.email || "").trim(),
    };
    if (shopLogoUrl) shopPayload.shopLogoUrl = shopLogoUrl;
    if (shopIconUrl) shopPayload.shopIconUrl = shopIconUrl;

    await shopsRef.child(shopId).set(shopPayload);
    await db.ref("platformAdminAudit").push().set({
      action: "create_shop",
      shopId,
      shopName,
      ownerEmail,
      adminEmail: String(decoded.email || "").trim(),
      createdAt: now,
    });

    return json(response, 200, {
      ok: true,
      shopId,
      shopName,
      customerAppMode: "separate",
      customerAppStatus: customerApp.status,
    });
  } catch (error) {
    console.error(error);
    return json(response, 400, {
      ok: false,
      message: "platform-shop-create-failed",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoGetPlatformAdminSnapshot = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    if (!isBarberinPlatformAdmin(decoded)) {
      return json(response, 403, {ok: false, message: "platform-admin-only"});
    }

    const period = platformAdminSummaryPeriod();
    const cached = await seedPlatformAdminSummaryIfNeeded(period);
    const shopItems = platformAdminSummaryItems(cached);
    const totals = platformAdminSummaryTotals(shopItems);
    const auditSnapshot = await getDatabase().ref("platformAdminAudit")
        .limitToLast(10)
        .get();
    const rawAudit = auditSnapshot.exists() &&
        typeof auditSnapshot.val() === "object" ?
      auditSnapshot.val() :
      {};
    const activity = Object.entries(rawAudit).map(([id, entry]) => ({
      id,
      ...(entry || {}),
    })).sort((left, right) =>
      String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
    );
    return json(response, 200, {
      ok: true,
      generatedAt: cached.generatedAt,
      period: {
        startDate: period.startKey,
        endDate: period.endKey,
      },
      totals: {
        shopCount: shopItems.length,
        activeShops: totals.activeShops,
        trialingShops: totals.trialingShops,
        expiredShops: totals.expiredShops,
        appsBuilt: totals.appsBuilt,
        appsPending: totals.appsPending,
        notificationTokens: totals.notificationTokens,
        enabledServices: totals.enabledServices,
        totalAppointments: totals.totalAppointments,
        completedAppointments: totals.completedAppointments,
        estimatedRevenue: totals.estimatedRevenue,
        actualRevenue: totals.actualRevenue,
        occupancyPercent: totals.availableMinutes <= 0 ?
          0 :
          Math.min(
              100,
              Math.round(
                  (totals.occupiedMinutes / totals.availableMinutes) * 100,
              ),
          ),
        alerts: totals.alerts,
      },
      shops: shopItems,
      activity,
      provisioningQueue: await readPlatformProvisioningQueue(),
    });
  } catch (error) {
    console.error(error);
    return json(response, 403, {
      ok: false,
      message: "platform-admin-snapshot-failed",
      details: safeClientErrorDetails(error),
    });
  }
});

function platformAdminSummaryPeriod() {
  const now = new Date();
  const startDate = new Date(now.getFullYear(), now.getMonth(), 1);
  const endDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  return {
    now,
    startDate,
    endDate,
    startKey: dateKeyFromDateValue(startDate),
    endKey: dateKeyFromDateValue(endDate),
  };
}

function buildPlatformAdminSummaryShop({shopId, shop, startDate, endDate}) {
  const customerApp = shop?.customerApp &&
      typeof shop.customerApp === "object" ?
    shop.customerApp :
    {};
  const billing = shop?.billing && typeof shop.billing === "object" ?
    shop.billing :
    {};
  const metrics = buildUnifiedShopDashboard({
    shopId,
    shop: shop || {},
    startDate,
    endDate,
  });
  const serviceDurations = Array.isArray(
      shop?.weekly_schedule?.serviceDurations) ?
    shop.weekly_schedule.serviceDurations :
    [];
  return {
    ...metrics,
    archivedForTesting: shop?.archivedForTesting === true,
    ownerName: String(shop?.ownerName || "").trim(),
    ownerEmail: String(shop?.ownerEmail || "").trim(),
    createdAt: String(shop?.createdAt || "").trim(),
    barberCount: Object.keys(shop?.barbers || {}).length,
    customerCount: Object.keys(shop?.customers || {}).length,
    notificationTokenCount: Object.keys(shop?.notificationTokens || {})
        .length,
    hasSchedule: Boolean(shop?.weekly_schedule),
    serviceCount: serviceDurations.length,
    enabledServiceCount: serviceDurations.filter((service) =>
      service?.enabled !== false).length,
    lastUpdatedAt: String(shop?.updatedAt || "").trim(),
    sourceUpdatedAt: String(shop?.updatedAt || "").trim(),
    billing: {
      status: String(billing.status || "setup_required").trim(),
      plan: String(billing.selectedPlan || billing.storeProductId || "")
          .trim(),
      currentPeriodEnd: String(billing.currentPeriodEnd || "").trim(),
      trialEndsAt: String(billing.trialEndsAt || "").trim(),
      platform: String(billing.platform || "").trim(),
    },
    customerApp: {
      mode: configuredCustomerAppMode(shop),
      status: String(customerApp.status || "provisioning_required").trim(),
      displayName: String(customerApp.displayName ||
        resolveShopDisplayName(shop)).trim(),
      packageName: String(customerApp.packageName || "").trim(),
      bundleId: String(customerApp.bundleId || "").trim(),
      workspaceName: String(customerApp.workspaceName || "").trim(),
      templateVersion: String(customerApp.templateVersion || "").trim(),
      provisioningRequestId: String(
          customerApp.provisioningRequestId || "",
      ).trim(),
      provisionedAt: String(customerApp.provisionedAt || "").trim(),
      lastBuildAt: String(customerApp.lastBuildAt || "").trim(),
      lastReleaseAt: String(customerApp.lastReleaseAt || "").trim(),
      updatedAt: String(customerApp.updatedAt || "").trim(),
    },
  };
}

function platformAdminBillingStatus(shop) {
  const billing = shop?.billing && typeof shop.billing === "object" ?
    shop.billing :
    {};
  return String(billing.status || shop?.billingStatus || "setup_required")
      .trim();
}

function aggregatePlatformAdminSummary(shopItems) {
  const totals = shopItems.reduce((summary, shop) => {
    const billingStatus = platformAdminBillingStatus(shop);
    return {
    totalAppointments: summary.totalAppointments + shop.totalAppointments,
    completedAppointments:
      summary.completedAppointments + shop.completedAppointments,
    estimatedRevenue: summary.estimatedRevenue + shop.estimatedRevenue,
    actualRevenue: summary.actualRevenue + shop.actualRevenue,
    availableMinutes: summary.availableMinutes + shop.availableMinutes,
    occupiedMinutes: summary.occupiedMinutes + shop.occupiedMinutes,
    alerts: summary.alerts + shop.alerts.length,
    activeShops: summary.activeShops +
      (billingStatus === "active" ? 1 : 0),
    trialingShops: summary.trialingShops +
      (billingStatus === "trialing" ? 1 : 0),
    expiredShops: summary.expiredShops +
      (["expired", "grace_period"].includes(billingStatus) ? 1 : 0),
    appsBuilt: summary.appsBuilt +
      (["built", "released"].includes(shop.customerApp.status) ? 1 : 0),
    appsPending: summary.appsPending +
      (["provisioning_required", "provisioning", "failed"]
          .includes(shop.customerApp.status) ? 1 : 0),
    notificationTokens: summary.notificationTokens +
      shop.notificationTokenCount,
    enabledServices: summary.enabledServices + shop.enabledServiceCount,
    };
  }, {
    totalAppointments: 0,
    completedAppointments: 0,
    estimatedRevenue: 0,
    actualRevenue: 0,
    availableMinutes: 0,
    occupiedMinutes: 0,
    alerts: 0,
    activeShops: 0,
    trialingShops: 0,
    expiredShops: 0,
    appsBuilt: 0,
    appsPending: 0,
    notificationTokens: 0,
    enabledServices: 0,
  });
  return {
    shopCount: shopItems.length,
    activeShops: totals.activeShops,
    trialingShops: totals.trialingShops,
    expiredShops: totals.expiredShops,
    appsBuilt: totals.appsBuilt,
    appsPending: totals.appsPending,
    notificationTokens: totals.notificationTokens,
    enabledServices: totals.enabledServices,
    totalAppointments: totals.totalAppointments,
    completedAppointments: totals.completedAppointments,
    estimatedRevenue: totals.estimatedRevenue,
    actualRevenue: totals.actualRevenue,
    occupancyPercent: totals.availableMinutes <= 0 ?
      0 :
      Math.min(
          100,
          Math.round(
              (totals.occupiedMinutes / totals.availableMinutes) * 100,
          ),
      ),
    alerts: totals.alerts,
  };
}

async function seedPlatformAdminSummaryIfNeeded(period) {
  const summaryRef = getDatabase().ref("platformAdminSummary");
  const currentSnapshot = await summaryRef.get();
  const current = currentSnapshot.exists() &&
      typeof currentSnapshot.val() === "object" ?
    currentSnapshot.val() :
    {};
  const hasInitializedCache = Boolean(current.seededAt) &&
    current.shops && typeof current.shops === "object";
  if (hasInitializedCache) {
    // The shop-level RTDB trigger keeps this cache current. Do not rebuild it
    // on every new day or month: that would download the entire /shops tree.
    return {
      shops: current.shops && typeof current.shops === "object" ?
        current.shops :
        {},
      generatedAt: String(current.generatedAt || current.seededAt),
    };
  }

  const shopsSnapshot = await getDatabase().ref("shops").get();
  const rawShops = shopsSnapshot.exists() &&
      typeof shopsSnapshot.val() === "object" ?
    shopsSnapshot.val() :
    {};
  const shops = Object.fromEntries(
      Object.entries(rawShops).map(([shopId, shop]) => [
        shopId,
        buildPlatformAdminSummaryShop({
          shopId,
          shop: shop || {},
          startDate: period.startDate,
          endDate: period.endDate,
        }),
      ]));
  const generatedAt = period.now.toISOString();
  await summaryRef.update({
    version: 1,
    seededAt: generatedAt,
    generatedAt,
    period: {
      startDate: period.startKey,
      endDate: period.endKey,
    },
    shops,
  });
  return {shops, generatedAt};
}

function platformAdminSummaryItems(cached) {
  return Object.values(cached.shops || {})
      .filter((item) => item && item.shopId && item.archivedForTesting !== true)
      .sort((left, right) =>
        String(right.customerApp?.updatedAt || right.createdAt || "")
            .localeCompare(String(left.customerApp?.updatedAt ||
              left.createdAt || "")),
      );
}

function platformAdminSummaryTotals(shopItems) {
  return aggregatePlatformAdminSummary(shopItems);
}

async function ensureBillingSyncIndex(db, now = Date.now()) {
  const markerRef = db.ref(BILLING_SYNC_INDEX_META_PATH);
  const markerSnapshot = await markerRef.get();
  if (markerSnapshot.exists()) {
    return;
  }

  const shopsSnapshot = await db.ref("shops").get();
  const updates = {
    [BILLING_SYNC_INDEX_META_PATH]: {
      version: 1,
      bootstrappedAt: new Date(now).toISOString(),
    },
  };
  if (shopsSnapshot.exists()) {
    for (const [shopId, shop] of Object.entries(shopsSnapshot.val() || {})) {
      updates[`${BILLING_SYNC_INDEX_PATH}/${shopId}`] =
        buildBillingSyncIndexRecord(shopId, shop?.billing, now);
    }
  }
  await db.ref().update(updates);
}

async function ensureReminderShopDirectory(db, now = Date.now()) {
  const directoryRef = db.ref(SHOP_DIRECTORY_PATH);
  const directorySnapshot = await directoryRef.get();
  if (directorySnapshot.exists()) {
    return directorySnapshot.val() || {};
  }

  const shopsSnapshot = await db.ref("shops").get();
  if (!shopsSnapshot.exists()) {
    return {};
  }

  const directory = {};
  const updates = {};
  for (const [shopId, rawShop] of Object.entries(shopsSnapshot.val() || {})) {
    const normalizedShopId = String(shopId || "").trim();
    if (!normalizedShopId || rawShop?.archivedForTesting === true) {
      continue;
    }
    const entry = {updatedAt: new Date(now).toISOString()};
    directory[normalizedShopId] = entry;
    updates[`${SHOP_DIRECTORY_PATH}/${normalizedShopId}`] = entry;
  }
  if (Object.keys(updates).length > 0) {
    await db.ref().update(updates);
  }
  return directory;
}

exports.barberoRefreshPlatformAdminShopSummary = onValueWritten(
    {
      ref: "shops/{shopId}",
      instance: "barbero-88d00-default-rtdb",
      region: "us-central1",
      maxInstances: 1,
      retry: true,
    },
    async (event) => {
      const shopId = String(event.params.shopId || "").trim();
      if (!shopId) return;
      const summaryRef = getDatabase().ref(`platformAdminSummary/shops/${shopId}`);
      const billingIndexRef = getDatabase().ref(
          `${BILLING_SYNC_INDEX_PATH}/${shopId}`,
      );
      const shopDirectoryRef = getDatabase().ref(
          `${SHOP_DIRECTORY_PATH}/${shopId}`,
      );
      const beforeShop = event.data.before.exists() ?
        event.data.before.val() || {} :
        {};
      const after = event.data.after;
      if (!after.exists()) {
        await billingIndexRef.remove();
        await shopDirectoryRef.remove();
        const deletedMembershipUserIds = storageMembershipChangedUserIds(
            beforeShop,
            {},
        );
        await syncStorageMembershipIndexForShopData(
            getDatabase(),
            shopId,
            {},
            deletedMembershipUserIds,
        );
        if (deletedMembershipUserIds.size > 0) {
          await refreshStorageMembershipClaimsForShopData(
              shopId,
              {},
              deletedMembershipUserIds,
          );
        }
        await summaryRef.remove();
        return;
      }
      const period = platformAdminSummaryPeriod();
      const shop = after.val() || {};
      if (shop.archivedForTesting === true) {
        const archivedMembershipUserIds = storageMembershipChangedUserIds(
            beforeShop,
            shop,
        );
        await syncStorageMembershipIndexForShopData(
            getDatabase(),
            shopId,
            shop,
            archivedMembershipUserIds,
        );
        if (archivedMembershipUserIds.size > 0) {
          await refreshStorageMembershipClaimsForShopData(
              shopId,
              shop,
              archivedMembershipUserIds,
          );
        }
        await billingIndexRef.remove();
        await shopDirectoryRef.remove();
        await summaryRef.remove();
        return;
      }
      await shopDirectoryRef.set({
        updatedAt: String(shop.updatedAt || new Date().toISOString()),
      });
      if (billingSyncIndexStateChanged(beforeShop, shop)) {
        await billingIndexRef.set(
            buildBillingSyncIndexRecord(shopId, shop.billing),
        );
      }
      const membershipUserIds = storageMembershipChangedUserIds(
          beforeShop,
          shop,
      );
      await syncStorageMembershipIndexForShopData(
          getDatabase(),
          shopId,
          shop,
          membershipUserIds,
      );
      if (membershipUserIds.size > 0) {
        await refreshStorageMembershipClaimsForShopData(
            shopId,
            shop,
            membershipUserIds,
        );
      }
      const next = buildPlatformAdminSummaryShop({
        shopId,
        shop,
        startDate: period.startDate,
        endDate: period.endDate,
      });
      const currentSnapshot = await summaryRef.get();
      const current = currentSnapshot.exists() ? currentSnapshot.val() : {};
      if (String(current?.sourceUpdatedAt || "") >
          String(next.sourceUpdatedAt || "")) {
        return;
      }
      await summaryRef.set(next);
      await getDatabase().ref("platformAdminSummary").update({
        version: 1,
        generatedAt: period.now.toISOString(),
        period: {
          startDate: period.startKey,
          endDate: period.endKey,
        },
      });
    },
);

exports.barberoRefreshAppointmentReminderIndex = onValueWritten(
    {
      ref: "shops/{shopId}/appointments/{appointmentId}",
      instance: "barbero-88d00-default-rtdb",
      region: "us-central1",
      maxInstances: 1,
      retry: true,
    },
    async (event) => {
      const shopId = String(event.params.shopId || "").trim();
      const appointmentId = String(event.params.appointmentId || "").trim();
      if (!shopId || !appointmentId) {
        return;
      }
      const indexRef = getDatabase().ref(
          `${APPOINTMENT_REMINDER_INDEX_PATH}/${appointmentReminderIndexKey(
              shopId,
              appointmentId,
          )}`,
      );
      if (!event.data.after.exists()) {
        await indexRef.remove();
        return;
      }
      const record = buildAppointmentReminderIndexRecord({
        shopId,
        appointmentId,
        appointment: event.data.after.val() || {},
      });
      if (!record) {
        await indexRef.remove();
        return;
      }
      await indexRef.set(record);
    },
);

exports.barberoGetPlatformAdminSummary = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    if (!isBarberinPlatformAdmin(decoded)) {
      return json(response, 403, {ok: false, message: "platform-admin-only"});
    }
    const period = platformAdminSummaryPeriod();
    const cached = await seedPlatformAdminSummaryIfNeeded(period);
    const shopItems = platformAdminSummaryItems(cached);
    const totals = platformAdminSummaryTotals(shopItems);
    const auditSnapshot = await getDatabase().ref("platformAdminAudit")
        .limitToLast(10)
        .get();
    const rawAudit = auditSnapshot.exists() &&
        typeof auditSnapshot.val() === "object" ?
      auditSnapshot.val() :
      {};
    const activity = Object.entries(rawAudit).map(([id, entry]) => ({
      id,
      ...(entry || {}),
    })).sort((left, right) =>
      String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
    );
    return json(response, 200, {
      ok: true,
      generatedAt: cached.generatedAt,
      period: {
        startDate: period.startKey,
        endDate: period.endKey,
      },
      totals,
      shops: shopItems,
      activity,
      provisioningQueue: await readPlatformProvisioningQueue(),
    });
  } catch (error) {
    console.error(error);
    return json(response, 403, {
      ok: false,
      message: "platform-admin-summary-failed",
      details: safeClientErrorDetails(error),
    });
  }
});

async function readPlatformProvisioningQueue() {
  const snapshot = await getDatabase().ref("customerAppProvisioningQueue")
      .orderByChild("updatedAt")
      .limitToLast(20)
      .get();
  const raw = snapshot.exists() && typeof snapshot.val() === "object" ?
    snapshot.val() :
    {};
  return Object.entries(raw).map(([id, entry]) => ({
    id,
    ...(entry || {}),
  })).sort((left, right) =>
    String(right.updatedAt || right.createdAt || "")
        .localeCompare(String(left.updatedAt || left.createdAt || "")),
  );
}

exports.barberoGetPlatformShopDetail = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }
  try {
    const decoded = await authenticateRequest(request);
    if (!isBarberinPlatformAdmin(decoded)) {
      return json(response, 403, {ok: false, message: "platform-admin-only"});
    }
    const shopId = String(request.body?.shopId || "").trim();
    if (!shopId) {
      return json(response, 400, {ok: false, message: "shop-id-required"});
    }
    const snapshot = await getDatabase().ref(`shops/${shopId}`).get();
    if (!snapshot.exists() || typeof snapshot.val() !== "object") {
      return json(response, 404, {ok: false, message: "shop-not-found"});
    }
    const shop = snapshot.val() || {};
    if (shop.archivedForTesting === true) {
      return json(response, 404, {ok: false, message: "shop-not-found"});
    }
    const location = normalizeShopLocation(shop);
    const appointments = Object.entries(shop.appointments || {})
        .map(([id, appointment]) => ({id, ...(appointment || {})}));
    const barbers = Object.entries(shop.barbers || {})
        .map(([id, barber]) => ({id, ...(barber || {})}));
    const customers = Object.entries(shop.customers || {})
        .map(([id, customer]) => ({id, ...(customer || {})}));
    const services = Array.isArray(shop.weekly_schedule?.serviceDurations) ?
      shop.weekly_schedule.serviceDurations :
      [];
    const servicePrices = Array.isArray(shop.weekly_schedule?.servicePrices) ?
      shop.weekly_schedule.servicePrices :
      [];
    return json(response, 200, {
      ok: true,
      shopId,
      shop: {
        shopName: resolveShopDisplayName(shop),
        address: location.address,
        streetAddress: location.streetAddress,
        city: location.city,
        cityKey: location.cityKey,
        ownerName: String(shop.ownerName || "").trim(),
        ownerEmail: String(shop.ownerEmail || "").trim(),
        ownerPhone: String(shop.ownerPhone || "").trim(),
        createdAt: String(shop.createdAt || "").trim(),
        updatedAt: String(shop.updatedAt || "").trim(),
        billing: shop.billing || {},
        customerApp: shop.customerApp || {},
        weeklySchedule: shop.weekly_schedule || {},
        sustainabilityProfile: shop.sustainabilityProfile || {},
        services: services.map((service) => ({
          ...service,
          price: servicePrices.find((entry) =>
            String(entry?.key || "") === String(service?.key || ""),
          )?.price ?? null,
        })),
        barbers,
        customers: customers.map((customer) => ({
          uid: customer.uid || customer.id,
          fullName: customer.fullName || customer.name || "",
          email: customer.email || "",
          phone: customer.phone || "",
          createdAt: customer.createdAt || "",
          updatedAt: customer.updatedAt || "",
          notificationTokenCount: Object.keys(customer.notificationTokens || {})
              .length,
        })),
        appointments,
        notificationTokenCount: Object.keys(shop.notificationTokens || {})
            .length,
      },
    });
  } catch (error) {
    console.error(error);
    return json(response, 403, {
      ok: false,
      message: "platform-shop-detail-failed",
      details: safeClientErrorDetails(error),
    });
  }
});

const PLATFORM_CUSTOMER_APP_STATUSES = new Set([
  "provisioning_required",
  "provisioning",
  "configured",
  "built",
  "released",
  "failed",
]);

exports.barberoManagePlatformCustomerApp = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    if (!isBarberinPlatformAdmin(decoded)) {
      return json(response, 403, {ok: false, message: "platform-admin-only"});
    }

    const shopId = String(request.body?.shopId || "").trim();
    const action = String(request.body?.action || "").trim();
    if (!shopId || !["request_provisioning", "sync_existing", "set_status"].includes(action)) {
      return json(response, 400, {ok: false, message: "invalid-platform-app-action"});
    }

    const shopRef = getDatabase().ref(`shops/${shopId}`);
    const snapshot = await shopRef.get();
    if (!snapshot.exists() || typeof snapshot.val() !== "object") {
      return json(response, 404, {ok: false, message: "shop-not-found"});
    }

    const shop = snapshot.val() || {};
    if (shop.archivedForTesting === true) {
      return json(response, 404, {ok: false, message: "shop-not-found"});
    }
    const current = shop.customerApp && typeof shop.customerApp === "object" ?
      shop.customerApp :
      {};
    const now = new Date().toISOString();
    const displayName = String(
        request.body?.displayName ||
        current.displayName ||
        resolveShopDisplayName(shop),
    ).trim();
    const updates = {
      displayName,
      updatedAt: now,
      updatedBy: String(decoded.uid || "").trim(),
    };

    if (action === "request_provisioning") {
      const previousAttempt = Number.parseInt(
          current.provisioningAttempt,
          10,
      ) || 0;
      const attempt = previousAttempt + 1;
      updates.mode = "separate";
      updates.accessToken = customerAppAccessTokenForShop(shop) ||
        createCustomerAppAccessToken();
      updates.status = "provisioning";
      updates.provisioningPhase = "queued";
      updates.provisioningProgressPercent = 0;
      updates.provisioningErrorReason = "";
      updates.workspacePath = "";
      updates.aabPath = "";
      updates.buildVersion = "";
      updates.provisioningAttempt = attempt;
      updates.retryCount = Math.max(0, attempt - 1);
      updates.provisioningRequestedAt = now;
      updates.provisioningRequestedBy = String(decoded.email || decoded.uid || "").trim();
      updates.provisioningRequestId = `${shopId}-${Date.now()}`;
    } else if (action === "set_status") {
      const status = String(request.body?.status || "").trim();
      if (!PLATFORM_CUSTOMER_APP_STATUSES.has(status)) {
        return json(response, 400, {ok: false, message: "invalid-customer-app-status"});
      }
      updates.status = status;
    } else {
      const packageName = String(request.body?.packageName || "").trim();
      const bundleId = String(request.body?.bundleId || "").trim();
      const workspaceName = String(request.body?.workspaceName || "").trim();
      const templateVersion = String(request.body?.templateVersion || "").trim();
      const status = String(request.body?.status || "").trim();
      if (!packageName || !bundleId || !workspaceName ||
          !PLATFORM_CUSTOMER_APP_STATUSES.has(status) ||
          status === "provisioning_required" || status === "provisioning") {
        return json(response, 400, {ok: false, message: "invalid-existing-app-metadata"});
      }
      Object.assign(updates, {
        mode: "separate",
        accessToken: customerAppAccessTokenForShop(shop) ||
          createCustomerAppAccessToken(),
        packageName,
        bundleId,
        workspaceName,
        templateVersion: templateVersion || "1",
        status,
        provisionedAt: current.provisionedAt || now,
        provisioningPhase: status === "released" ? "released" : "complete",
        provisioningProgressPercent: 100,
        provisioningErrorReason: "",
      });
      if (status === "built") updates.lastBuildAt = now;
      if (status === "released") updates.lastReleaseAt = now;
    }

    await shopRef.child("customerApp").update(updates);
    const auditRef = getDatabase().ref("platformAdminAudit").push();
    await auditRef.set({
      action,
      shopId,
      shopName: displayName,
      status: String(updates.status || current.status || "").trim(),
      adminEmail: String(decoded.email || "").trim(),
      createdAt: now,
    });
    if (action === "request_provisioning") {
      await getDatabase().ref(
          `customerAppProvisioningQueue/${updates.provisioningRequestId}`)
          .set({
            requestId: updates.provisioningRequestId,
            shopId,
            displayName,
            status: "queued",
            phase: "queued",
            progressPercent: 0,
            errorReason: "",
            workspacePath: "",
            aabPath: "",
            buildVersion: "",
            attempt: updates.provisioningAttempt,
            retryCount: updates.retryCount,
            requestedBy: String(decoded.email || decoded.uid || "").trim(),
            createdAt: now,
            updatedAt: now,
          });
      await getDatabase().ref(
          `shops/${shopId}/customerApp/provisioningHistory/${updates.provisioningRequestId}`)
          .set({
            requestId: updates.provisioningRequestId,
            shopId,
            displayName,
            status: "queued",
            phase: "queued",
            progressPercent: 0,
            errorReason: "",
            workspacePath: "",
            aabPath: "",
            buildVersion: "",
            attempt: updates.provisioningAttempt,
            retryCount: updates.retryCount,
            requestedBy: String(decoded.email || decoded.uid || "").trim(),
            createdAt: now,
            updatedAt: now,
          });
    }
    return json(response, 200, {
      ok: true,
      shopId,
      action,
      customerApp: {
        ...current,
        ...updates,
      },
    });
  } catch (error) {
    console.error(error);
    return json(response, 403, {
      ok: false,
      message: "platform-customer-app-action-failed",
      details: safeClientErrorDetails(error),
    });
  }
});

async function migrateLegacyOwnerUids(decoded, shops) {
  const uid = String(decoded?.uid || "").trim();
  if (!uid) {
    return shops;
  }

  const updates = {};
  const migratedShops = {...(shops || {})};
  for (const [shopId, shop] of Object.entries(shops || {})) {
    if (shop?.archivedForTesting === true) {
      continue;
    }
    if (String(shop?.ownerUserUid || "").trim()) {
      continue;
    }
    const legacyShopIdMatch = String(shopId || "").trim() === uid;
    if (!legacyShopIdMatch) {
      continue;
    }
    updates[`shops/${shopId}/ownerUserUid`] = uid;
    migratedShops[shopId] = {
      ...(shop || {}),
      ownerUserUid: uid,
    };
  }

  if (Object.keys(updates).length > 0) {
    await getDatabase().ref().update(updates);
  }
  return migratedShops;
}

function barberoRolePermissions(role) {
  switch (resolveBarberoRole(role)) {
    case "owner":
      return {
        manageCrew: true,
        editSchedule: true,
        editPrices: true,
        viewStats: true,
        manageAllAppointments: true,
        manageOwnAppointments: true,
      };
    case "senior_barber":
      return {
        manageCrew: false,
        editSchedule: true,
        editPrices: false,
        viewStats: true,
        manageAllAppointments: true,
        manageOwnAppointments: true,
      };
    case "assistant":
      return {
        manageCrew: false,
        editSchedule: true,
        editPrices: false,
        viewStats: false,
        manageAllAppointments: true,
        manageOwnAppointments: false,
      };
    default:
      return {
        manageCrew: false,
        editSchedule: false,
        editPrices: false,
        viewStats: false,
        manageAllAppointments: false,
        manageOwnAppointments: true,
      };
  }
}

async function syncBillingAccessMetadata(db, shopId, rawBilling) {
  const billing = rawBilling && typeof rawBilling === "object" ?
    rawBilling :
    buildDefaultBillingRecord();
  const snapshot = buildBillingSnapshot(billing);
  const accessUntilMillis = snapshot.allowsAccess ?
    snapshot.accessUntilMillis :
    0;
  const storedValue = Number(billing.accessUntilMillis || 0);
  if (storedValue === accessUntilMillis) {
    return;
  }
  await db.ref(`shops/${shopId}/billing`).update({
    accessUntilMillis,
    billingAccessUpdatedAt: new Date().toISOString(),
  });
}

function assertActiveBillingAccess(rawBilling) {
  const billing = buildBillingSnapshot(rawBilling);
  if (!billing.allowsAccess || billing.accessUntilMillis <= Date.now()) {
    throw new Error("subscription-required");
  }
  return billing;
}

async function authorizeBarberoAccess(
    decoded,
    requestedShopId,
    {requireActiveBilling = true} = {},
) {
  const resolved = await resolveBarberoSession(decoded);
  const shopId = String(requestedShopId || resolved.shopId || "").trim();
  const targetShop = resolved.accessibleShops?.find(
      (entry) => String(entry.shopId || "").trim() === shopId,
  );
  if (!shopId || !targetShop) {
    throw new Error("forbidden");
  }
  const billing = requireActiveBilling ?
    assertActiveBillingAccess(targetShop.shop?.billing) :
    buildBillingSnapshot(targetShop.shop?.billing);
  return {
    ...targetShop,
    accessibleShops: resolved.accessibleShops,
    billing,
    permissions: barberoRolePermissions(targetShop.role),
  };
}

function shopHasBarber(shop, barberId) {
  const normalizedBarberId = String(barberId || "").trim();
  if (!normalizedBarberId) {
    return false;
  }
  return buildShopBarbers(shop).some(
      (barber) => String(barber.id || "").trim() === normalizedBarberId,
  );
}

function findShopBarberById(shop, barberId) {
  const normalizedBarberId = String(barberId || "").trim();
  if (!normalizedBarberId) {
    return null;
  }
  return buildShopBarbers(shop).find(
      (barber) => String(barber.id || "").trim() === normalizedBarberId,
  ) || null;
}

function isBookableShopBarber(shop, barberId) {
  const barber = findShopBarberById(shop, barberId);
  if (!barber) {
    return false;
  }
  const status = String(barber.status || "active").trim().toLowerCase();
  return status === "active";
}

async function findOrCreateManualCustomer({
  db,
  shopId,
  customerName,
  customerPhone,
  customerEmail,
}) {
  const normalizedName = String(customerName || "").trim();
  const normalizedPhone = String(customerPhone || "").trim();
  const normalizedEmail = String(customerEmail || "").trim().toLowerCase();
  if (!normalizedName) {
    return "";
  }

  const customersRef = db.ref(`shops/${shopId}/customers`);
  const customersSnapshot = await customersRef.get();
  const customers = customersSnapshot.exists() ? customersSnapshot.val() || {} : {};

  let matchedEntry = Object.entries(customers).find(([, customer]) =>
    normalizedEmail &&
      String(customer?.email || "").trim().toLowerCase() === normalizedEmail,
  );
  if (!matchedEntry) {
    matchedEntry = Object.entries(customers).find(([, customer]) =>
      normalizedPhone &&
        String(customer?.phone || "").trim() === normalizedPhone,
    );
  }
  if (!matchedEntry) {
    matchedEntry = Object.entries(customers).find(([, customer]) =>
      String(customer?.fullName || "").trim().toLowerCase() ===
        normalizedName.toLowerCase(),
    );
  }

  const nowIso = new Date().toISOString();
  if (matchedEntry) {
    const [customerUid, current] = matchedEntry;
    await customersRef.child(customerUid).update({
      uid: customerUid,
      fullName: normalizedName,
      phone: normalizedPhone || String(current?.phone || "").trim(),
      email: normalizedEmail || String(current?.email || "").trim(),
      shopId,
      updatedAt: nowIso,
    });
    return customerUid;
  }

  const customerRef = customersRef.push();
  const customerUid = String(customerRef.key || "");
  await customerRef.set({
    uid: customerUid,
    fullName: normalizedName,
    phone: normalizedPhone,
    email: normalizedEmail,
    preferences: "",
    notes: "",
    shopId,
    createdAt: nowIso,
    updatedAt: nowIso,
  });
  return customerUid;
}

function buildRelevantDurations(slotMinutes, serviceDurations, serviceAddOns = []) {
  const durations = new Set([Math.max(5, Number(slotMinutes) || 30)]);
  const serviceMinuteValues = serviceDurations
      .filter((item) => item.enabled !== false)
      .map((item) => Number(item.minutes) || 0)
      .filter((minutes) => minutes > 0);

  let partialSums = new Set([0]);
  for (const minutes of serviceMinuteValues) {
    const next = new Set(partialSums);
    for (const sum of partialSums) {
      next.add(sum + minutes);
    }
    partialSums = next;
  }

  for (const sum of partialSums) {
    if (sum > 0) {
      durations.add(sum);
    }
  }

  const addOnMinutes = normalizeServiceAddOns(serviceAddOns)
      .filter((item) => item.enabled === true)
      .map((item) => item.minutes);
  for (const sum of partialSums) {
    if (sum <= 0) continue;
    for (const minutes of addOnMinutes) {
      durations.add(sum + minutes);
    }
  }

  return Array.from(durations).sort((left, right) => left - right);
}

const MAX_PROFILE_IMAGE_BYTES = 5 * 1024 * 1024;

function decodeBase64Image(value) {
  const source = String(value || "").trim();
  if (!source) {
    throw new Error("missing-image-bytes");
  }
  const normalized = source.includes(",") ? source.split(",").pop() : source;
  if (!normalized || normalized.length % 4 === 1 || !/^[A-Za-z0-9+/]*={0,2}$/.test(normalized)) {
    throw new Error("invalid-image-bytes");
  }
  const bytes = Buffer.from(normalized, "base64");
  if (!bytes.length || bytes.length > MAX_PROFILE_IMAGE_BYTES) {
    throw new Error("image-too-large");
  }
  return bytes;
}

async function uploadImageAndGetUrl({
  path,
  bytes,
  contentType,
}) {
  const normalizedContentType = String(contentType || "").trim().toLowerCase();
  if (!["image/jpeg", "image/png", "image/webp"].includes(normalizedContentType)) {
    throw new Error("unsupported-image-type");
  }
  if (!Buffer.isBuffer(bytes) || bytes.length === 0 || bytes.length > MAX_PROFILE_IMAGE_BYTES) {
    throw new Error("invalid-image-bytes");
  }
  const bucket = getStorage().bucket("barbero-88d00.firebasestorage.app");
  const file = bucket.file(path);
  const downloadToken = randomUUID();
  await file.save(bytes, {
    resumable: false,
    contentType: normalizedContentType,
    metadata: {
      contentType: normalizedContentType,
      cacheControl: "public,max-age=31536000",
      metadata: {
        firebaseStorageDownloadTokens: downloadToken,
      },
    },
  });
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${downloadToken}`;
}

async function sendCrewInvitationEmail({
  email,
  shopName,
  ownerName,
  displayName,
  role,
}) {
  const recipient = String(email || "").trim().toLowerCase();
  if (!recipient) {
    return false;
  }

  const normalizedRole = resolveBarberoRole(role);
  const roleLabel = normalizedRole === "senior_barber" ?
    "Senior Barber" :
    normalizedRole === "assistant" ? "Assistant" : "Barber";
  const safeShopName = String(shopName || "το κατάστημα").trim();
  const safeOwnerName = String(ownerName || "ο ιδιοκτήτης").trim();
  const safeDisplayName = String(displayName || "Barber").trim();

  const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: BARBERIN_EMAIL_SENDER,
      pass: crewInvitationSmtpPassword.value().replace(/\s+/g, ""),
    },
  });

  await transporter.sendMail({
    from: `Barberin <${BARBERIN_EMAIL_SENDER}>`,
    to: recipient,
    replyTo: BARBERIN_SUPPORT_EMAIL,
    subject: `Πρόσκληση στο ${safeShopName} μέσω Barberin`,
    text: [
      `Γεια σου ${safeDisplayName},`,
      "",
      `${safeOwnerName} σε πρόσθεσε ως ${roleLabel} στο ${safeShopName} μέσω του Barberin.`,
      "",
      "Για να συνδεθείς:",
      "1. Άνοιξε την εφαρμογή Barberin.",
      "2. Επίλεξε «Σύνδεση σε υπάρχον κατάστημα».",
      "3. Χρησιμοποίησε αυτό το email και δημιούργησε ή χρησιμοποίησε τον προσωπικό σου κωδικό.",
      "4. Μετά τη σύνδεση, η πρόσβαση στο κατάστημα θα ενεργοποιηθεί αυτόματα.",
      "",
      "Χρησιμοποίησε ακριβώς το email στο οποίο έλαβες αυτή την πρόσκληση.",
      "",
      "Για βοήθεια, απάντησε σε αυτό το email ή επικοινώνησε στο oryn.barberin@gmail.com.",
      "",
      "Barberin",
    ].join("\n"),
  });

  return true;
}

async function sendShopProvisioningStartedEmail({
  email,
  ownerName,
  shopName,
  shopId,
}) {
  const recipient = String(email || "").trim().toLowerCase();
  if (!recipient) {
    return false;
  }

  const safeOwnerName = String(ownerName || "").trim() || "ιδιοκτήτη";
  const safeShopName = String(shopName || "το κατάστημά σου").trim();
  const safeShopId = String(shopId || "").trim();
  const dateText = new Intl.DateTimeFormat("el-GR", {
    dateStyle: "long",
    timeZone: "Europe/Athens",
  }).format(new Date());

  const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: BARBERIN_EMAIL_SENDER,
      pass: crewInvitationSmtpPassword.value().replace(/\s+/g, ""),
    },
  });

  await transporter.sendMail({
    from: `Barberin <${BARBERIN_EMAIL_SENDER}>`,
    to: recipient,
    replyTo: BARBERIN_SUPPORT_EMAIL,
    subject: `Το customer app για το ${safeShopName} βρίσκεται σε προετοιμασία`,
    text: [
      `Γεια σου ${safeOwnerName},`,
      "",
      `Το κατάστημα «${safeShopName}» δημιουργήθηκε επιτυχώς στο Barberin στις ${dateText}.`,
      "",
      "Το εξατομικευμένο customer app του καταστήματος δεν δημιουργείται και δεν δημοσιεύεται αυτόματα σε πραγματικό χρόνο. Χρειάζονται μερικές ημέρες για την προετοιμασία της εφαρμογής, τη δημιουργία της έκδοσης και τους απαραίτητους ελέγχους και δοκιμές πριν γίνει διαθέσιμη.",
      "",
      "Θα ενημερωθείς ξανά με νέο email για την εξέλιξη της διαδικασίας. Δεν χρειάζεται να κάνεις κάτι προς το παρόν.",
      "",
      `Κωδικός καταστήματος: ${safeShopId}`,
      "",
      "Barberin",
    ].join("\n"),
  });

  return true;
}

function buildCustomerShellPayload({shopId, shop, decoded, appointments}) {
  const location = normalizeShopLocation(shop);
  const schedule = normalizeWeeklySchedulePayload(shop?.weekly_schedule || {});
  const serviceDurations = schedule.serviceDurations;
  const servicePrices = schedule.servicePrices;
  const serviceAddOns = schedule.serviceAddOns;
  const appointmentSettings = normalizeAppointmentSettings(
      shop?.appointmentSettings,
  );
  const priceByServiceKey = Object.fromEntries(
      servicePrices.map((item) => [
        String(item?.key || "").trim(),
        Number(item?.price) || 0,
      ]),
  );
  const labelByServiceKey = Object.fromEntries(
      servicePrices.map((item) => [
        String(item?.key || "").trim(),
        String(item?.label || "").trim(),
      ]),
  );
  const configuredServiceKeys = Array.from(new Set([
    ...serviceDurations.map((item) => String(item?.key || "").trim()),
    ...servicePrices.map((item) => String(item?.key || "").trim()),
  ].filter(Boolean)));
  const durationByKey = Object.fromEntries(
      serviceDurations.map((item) => [String(item?.key || ""), Number(item?.minutes) || 30]),
  );
  const services = configuredServiceKeys.map((key) => {
    const duration = serviceDurations.find((candidate) =>
      String(candidate?.key || "") === key,
    ) || {};
    return {
      key,
      label: String(
          duration.label || labelByServiceKey[key] || serviceLabelForKey(key),
      ).trim(),
      price: priceByServiceKey[key] || 0,
      minutes: durationByKey[key] || 30,
      enabled: duration.enabled !== false,
      barberIds: Array.isArray(duration.barberIds) ? duration.barberIds : [],
    };
  }).filter((service) => service.enabled);

  const days = Array.isArray(schedule.days) ? schedule.days : [];
  const barberSchedules = Array.isArray(schedule.barberSchedules) ?
    schedule.barberSchedules :
    [];
  const barbers = buildShopBarbers(shop)
    .filter((barber) =>
      String(barber.status || "active").trim().toLowerCase() === "active",
    )
    .map((barber) => ({
    id: barber.id,
    name: barber.name,
    subtitle: barber.role || "Barber",
    note: barber.notes || "",
    specialties: Array.isArray(barber.specialties) ? barber.specialties : [],
    photoUrl: barber.photoUrl || "",
    days: resolveScheduleDaysForBarber({
      days,
      barberSchedules,
      barberId: barber.id,
    }),
    }));

  const currentCustomerEntry = findCurrentCustomerEntry(shop, decoded);
  const currentCustomer = currentCustomerEntry?.customer || null;

  const fullName = String(
      currentCustomer?.fullName ||
      decoded.name ||
      (decoded.email ? decoded.email.split("@")[0] : "Πελάτης"),
  ).trim();
  const customerName = fullName ? fullName.split(/\s+/)[0] : "Πελάτης";
  const customerPhone = String(currentCustomer?.phone || "").trim();
  const customerEmail = String(
      currentCustomer?.email ||
      decoded.email ||
      "",
  ).trim();
  const customerPhotoUrl = String(currentCustomer?.photoUrl || "").trim();
  const customerPreferences = String(
      currentCustomer?.preferences ||
      currentCustomer?.notes ||
      "",
  ).trim();

  const currentCustomerUid = String(currentCustomerEntry?.uid || "").trim();
  const visibleAppointments = appointments.filter((appointment) =>
    appointmentBelongsToCustomer({
      appointment,
      customerEntry: currentCustomerEntry,
      customerFullName: fullName,
      customerShortName: customerName,
    }),
  );

  return {
    shopId,
    shopName: resolveShopDisplayName(shop),
    shopLogoUrl: String(
        shop?.shopLogoUrl ||
        shop?.logoUrl ||
        shop?.branding?.logoUrl ||
        "",
    ).trim(),
    shopAddress: location.address,
    shopStreetAddress: location.streetAddress,
    shopCity: location.city,
    ownerName: String(shop?.ownerName || resolveShopDisplayName(shop)),
    customerName,
    customerFullName: fullName,
    customerPhone,
    customerEmail,
    customerPhotoUrl,
    customerPreferences,
    slotMinutes: Number.parseInt(schedule.slotMinutes, 10) || 30,
    appointmentsPerSlot:
      Number.parseInt(schedule.appointmentsPerSlot, 10) || 1,
    slotCapacityOverrides: Array.isArray(schedule.slotCapacityOverrides) ?
      schedule.slotCapacityOverrides :
      [],
    showPrices: schedule.showPrices === true,
    appointmentSettings: {
      remindersEnabled: appointmentSettings.remindersEnabled,
      customerCancellationCutoffMinutes:
        appointmentSettings.customerCancellationCutoffMinutes,
      customerRescheduleCutoffMinutes:
        appointmentSettings.customerRescheduleCutoffMinutes,
    },
    services,
    addOns: serviceAddOns,
    barbers,
    days,
    appointments: visibleAppointments.map((appointment) => ({
      id: appointment.id,
      customerUid: appointment.customerUid,
      customerName: appointment.customerName,
      barberId: appointment.barberId,
      barberName: appointment.barberName,
      date: appointment.date,
      time: appointment.time,
      services: appointment.services,
      serviceKeys: appointment.serviceKeys,
      addOnKeys: appointment.addOnKeys,
      status: normalizeAppointmentStatus(appointment.status),
      totalPrice: appointment.totalPrice,
      totalMinutes: appointment.totalMinutes,
      occupiedSlots: appointment.occupiedSlots,
    })),
  };
}

function findCurrentCustomerRecord(shop, decoded) {
  return findCurrentCustomerEntry(shop, decoded)?.customer || null;
}

function normalizeAppointmentCustomerName(value) {
  return String(value || "").trim().toLowerCase();
}

function appointmentBelongsToCustomer({
  appointment,
  customerEntry,
}) {
  const appointmentCustomerUid = String(appointment?.customerUid || "").trim();
  const customerUid = String(customerEntry?.uid || "").trim();
  return Boolean(customerUid && appointmentCustomerUid === customerUid);
}

function findCurrentCustomerEntry(shop, decoded) {
  const rawCustomers = shop?.customers && typeof shop.customers === "object" ?
    shop.customers :
    {};
  const accountUid = String(decoded?.uid || "").trim();
  if (!accountUid) {
    return null;
  }
  const matchedEntry = Object.entries(rawCustomers).find(([recordKey, customer]) =>
    String(recordKey || "").trim() === accountUid ||
    String(customer?.uid || "").trim() === accountUid,
  );
  if (!matchedEntry) {
    return null;
  }
  const [recordKey, currentCustomer] = matchedEntry;
  return {
    recordKey: String(recordKey || "").trim(),
    uid: accountUid || String(recordKey || "").trim(),
    customer: currentCustomer,
  };
}

function customerAppAccessTokenForShop(shop) {
  return String(
      shop?.customerApp?.accessToken || shop?.customerAppAccessToken || "",
  ).trim();
}

function hasCustomerAppAccess({shop, decoded, accessToken}) {
  const configuredToken = customerAppAccessTokenForShop(shop);
  return Boolean(configuredToken && String(accessToken || "").trim() === configuredToken);
}

function configuredCustomerAppMode(shop) {
  // Every customer binary is a branded, shop-specific application. Records
  // created before this rule may not have mode persisted yet, so the token is
  // the migration signal for an already provisioned shop.
  return "separate";
}

function hasConfiguredCustomerAppAccess({
  shop,
  decoded,
  accessToken,
  requestedMode,
}) {
  const configuredMode = configuredCustomerAppMode(shop);
  const normalizedRequestedMode = String(requestedMode || "")
      .trim()
      .toLowerCase();
  if (normalizedRequestedMode !== configuredMode) {
    return false;
  }
  return hasCustomerAppAccess({shop, decoded, accessToken});
}

function validateCustomerAppRequest({
  shop,
  decoded,
  shopId,
  accessToken,
  requestedMode,
  requireCustomerRecord = true,
}) {
  const normalizedShopId = String(shopId || "").trim();
  const normalizedToken = String(accessToken || "").trim();
  const normalizedMode = String(requestedMode || "").trim();
  if (!normalizedShopId || !normalizedToken || !normalizedMode ||
      !hasConfiguredCustomerAppAccess({
        shop,
        decoded,
        accessToken: normalizedToken,
        requestedMode: normalizedMode,
      })) {
    return {
      ok: false,
      message: "customer-app-link-required",
    };
  }

  const customerEntry = findCurrentCustomerEntry(shop, decoded);
  if (requireCustomerRecord && !customerEntry) {
    return {
      ok: false,
      message: "customer-profile-required",
    };
  }
  return {
    ok: true,
    customerEntry,
  };
}

function hasBarberoShopMembership({decoded, shopId, shop}) {
  const uid = String(decoded?.uid || "").trim();
  const normalizedShopId = String(shopId || "").trim();
  if (!uid || !normalizedShopId) {
    return false;
  }
  if (
    normalizedShopId === uid ||
    String(shop?.ownerUserUid || "").trim() === uid
  ) {
    return true;
  }
  return buildShopBarbers(shop).some((barber) =>
    String(barber.authUid || "").trim() === uid &&
    String(barber.status || "active").trim().toLowerCase() === "active"
  );
}

function createCustomerAppAccessToken() {
  return randomUUID().replace(/-/g, "") + randomUUID().replace(/-/g, "");
}

function computeAvailableSlots({
  days,
  appointments,
  appointmentsPerSlot = 1,
  slotCapacityOverrides = [],
  closedDateOverrides = [],
  barberSchedules = [],
  barberId,
  dateText,
  requiredMinutes,
}) {
  const [yearText, monthText, dayText] = String(dateText || "").split("-");
  const date = new Date(
      Number.parseInt(yearText, 10),
      Number.parseInt(monthText, 10) - 1,
      Number.parseInt(dayText, 10),
  );
  if (Number.isNaN(date.getTime())) return [];
  if (isDateClosedForShop(dateText, closedDateOverrides)) return [];
  const resolvedDays = resolveScheduleDaysForBarber({
    days,
    barberSchedules,
    barberId,
  });
  const day = resolvedDays[date.getDay() === 0 ? 6 : date.getDay() - 1];
  if (!day || day.enabled !== true) return [];

  const start = timeToMinutes(day.start);
  const end = timeToMinutes(day.end);
  if (start < 0 || end <= start) return [];

  const breakStart = timeToMinutes(day.breakStart);
  const breakEnd = timeToMinutes(day.breakEnd);
  const appointmentIntervals = appointments
      .filter((appointment) =>
        appointment.date === dateText &&
        appointment.barberId === barberId &&
        isAppointmentBlockingStatus(appointment.status),
      )
      .map((appointment) => {
        const appointmentStart = timeToMinutes(appointment.time);
        const appointmentDuration = appointment.totalMinutes > 0 ?
          appointment.totalMinutes :
          requiredMinutes;
        return {
          start: appointmentStart,
          end: appointmentStart + appointmentDuration,
        };
      })
      .filter((interval) => interval.start >= 0 && interval.end > interval.start)
      .sort((left, right) => left.start - right.start);

  const athensNow = getAthensNowInfo();
  const isToday = athensNow.dateKey === dateText;
  const roundedNow = isToday ?
    roundUpToStep(athensNow.totalMinutes + 1, AVAILABILITY_STEP_MINUTES) :
    0;
  const dayIndex = date.getDay() === 0 ? 6 : date.getDay() - 1;

  const hasCapacityForWindow = (windowStart, windowEnd) => {
    for (
      let minute = windowStart;
      minute < windowEnd;
      minute += AVAILABILITY_STEP_MINUTES
    ) {
      let activeAppointments = 0;
      for (const appointment of appointments) {
        if (
          appointment.date !== dateText ||
          appointment.barberId !== barberId ||
          !isAppointmentBlockingStatus(appointment.status)
        ) {
          continue;
        }
        const appointmentStart = timeToMinutes(appointment.time);
        const appointmentDuration = appointment.totalMinutes > 0 ?
          appointment.totalMinutes :
          requiredMinutes;
        const appointmentEnd = appointmentStart + appointmentDuration;
        const overlapsMinute = appointmentStart < minute + AVAILABILITY_STEP_MINUTES &&
          appointmentEnd > minute;
        if (!overlapsMinute) {
          continue;
        }
        if (appointment.blocked === true) {
          return false;
        }
        activeAppointments += 1;
      }
      const maxAppointments = resolveAppointmentsPerSlotForMinute({
        dayIndex,
        minuteOfDay: minute,
        appointmentsPerSlot,
        slotCapacityOverrides,
      });
      if (activeAppointments >= maxAppointments) {
        return false;
      }
    }
    return true;
  };

  const available = [];
  const segments = breakStart >= 0 && breakEnd > breakStart ?
    [
      {start, end: breakStart},
      {start: breakEnd, end},
    ] :
    [{start, end}];

  for (const segment of segments) {
    let cursor = roundUpToStep(segment.start, AVAILABILITY_STEP_MINUTES);
    if (isToday && roundedNow > cursor) {
      cursor = roundedNow;
    }

    const segmentAppointments = appointmentIntervals
      .filter((appointment) =>
        appointment.start < segment.end && appointment.end > segment.start,
      )
      .sort((left, right) => left.start - right.start);

    for (const appointment of segmentAppointments) {
      if (appointment.start > cursor) {
        for (
          let minute = roundUpToStep(cursor, AVAILABILITY_STEP_MINUTES);
          minute + requiredMinutes <= appointment.start;
          minute += AVAILABILITY_STEP_MINUTES
        ) {
          if (!hasCapacityForWindow(minute, minute + requiredMinutes)) {
            continue;
          }
          available.push({
            startTime: minutesToTime(minute),
            endTime: minutesToTime(minute + requiredMinutes),
            occupiedSlots: buildOccupiedSlotsFallback(
                minutesToTime(minute),
                requiredMinutes,
                AVAILABILITY_STEP_MINUTES,
            ),
          });
        }
      }
      if (appointment.end > cursor) {
        cursor = roundUpToStep(appointment.end, AVAILABILITY_STEP_MINUTES);
      }
    }

    for (
      let minute = roundUpToStep(cursor, AVAILABILITY_STEP_MINUTES);
      minute + requiredMinutes <= segment.end;
      minute += AVAILABILITY_STEP_MINUTES
    ) {
      if (!hasCapacityForWindow(minute, minute + requiredMinutes)) {
        continue;
      }
      available.push({
        startTime: minutesToTime(minute),
        endTime: minutesToTime(minute + requiredMinutes),
        occupiedSlots: buildOccupiedSlotsFallback(
            minutesToTime(minute),
            requiredMinutes,
            AVAILABILITY_STEP_MINUTES,
        ),
      });
    }
  }

  return available;
}

function isDateClosedForShop(dateKey, closedDateOverrides) {
  const normalizedDateKey = String(dateKey || "").trim();
  if (!normalizedDateKey) {
    return false;
  }
  const override = (Array.isArray(closedDateOverrides) ? closedDateOverrides : [])
      .find((item) => String(item?.date || item?.dateKey || "").trim() === normalizedDateKey);
  if (override) {
    return override.isClosed === true;
  }
  const year = Number.parseInt(normalizedDateKey.split("-")[0], 10);
  if (Number.isNaN(year)) {
    return false;
  }
  const holidays = buildGreekHolidayMap(year);
  return Object.prototype.hasOwnProperty.call(holidays, normalizedDateKey);
}

function formatDateKey(date) {
  const year = String(date.getFullYear()).padStart(4, "0");
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function resolveAppointmentsPerSlotForMinute({
  dayIndex,
  minuteOfDay,
  appointmentsPerSlot,
  slotCapacityOverrides,
}) {
  let resolved = Math.max(1, Number.parseInt(appointmentsPerSlot, 10) || 1);
  const overrides = Array.isArray(slotCapacityOverrides) ?
    slotCapacityOverrides :
    [];
  for (const item of overrides) {
    const itemDayIndex = Number.parseInt(item?.dayIndex, 10);
    if (itemDayIndex !== dayIndex) {
      continue;
    }
    const start = timeToMinutes(item?.start);
    const end = timeToMinutes(item?.end);
    if (start < 0 || end <= start) {
      continue;
    }
    if (minuteOfDay >= start && minuteOfDay < end) {
      resolved = Math.min(
          10,
          Math.max(1, Number.parseInt(item?.appointmentsPerSlot, 10) || 1),
      );
    }
  }
  return resolved;
}

function resolveScheduleDaysForBarber({
  days,
  barberSchedules,
  barberId,
}) {
  const normalizedBarberId = String(barberId || "").trim();
  if (!normalizedBarberId) {
    return Array.isArray(days) ? days : [];
  }
  const matching = (Array.isArray(barberSchedules) ? barberSchedules : []).find(
      (item) => String(item?.barberId || "").trim() === normalizedBarberId,
  );
  if (matching && Array.isArray(matching.days) && matching.days.length >= 7) {
    return matching.days;
  }
  return Array.isArray(days) ? days : [];
}

function buildBookingFallbackSuggestions({
  shop,
  days,
  appointments,
  appointmentsPerSlot,
  slotCapacityOverrides,
  closedDateOverrides,
  barberSchedules,
  barberId,
  dateText,
  requiredMinutes,
  preferredStartTime,
}) {
  const barbers = buildShopBarbers(shop);
  const selectedBarber = barbers.find(
      (item) => String(item.id || "").trim() === String(barberId || "").trim(),
  );
  if (!selectedBarber) {
    return [];
  }

  const suggestions = [];
  const seen = new Set();
  const addSuggestion = ({barber, date, startTime, reason}) => {
    const normalizedTime = String(startTime || "").trim();
    if (!barber || !normalizedTime || !date) {
      return;
    }
    const key = `${barber.id}|${date}|${normalizedTime}`;
    if (seen.has(key)) {
      return;
    }
    seen.add(key);
    suggestions.push({
      barberId: barber.id,
      barberName: barber.name,
      date,
      startTime: normalizedTime,
      reason,
    });
  };

  const sameBarberSlots = computeAvailableSlots({
    days,
    appointments,
    appointmentsPerSlot,
    slotCapacityOverrides,
    closedDateOverrides,
    barberSchedules,
    barberId: selectedBarber.id,
    dateText,
    requiredMinutes,
  });
  const preferredMinutes = timeToMinutes(preferredStartTime);
  sameBarberSlots
      .filter((slot) => slot.startTime !== preferredStartTime)
      .sort((left, right) => {
        if (preferredMinutes < 0) {
          return left.startTime.localeCompare(right.startTime);
        }
        return Math.abs(timeToMinutes(left.startTime) - preferredMinutes) -
          Math.abs(timeToMinutes(right.startTime) - preferredMinutes);
      })
      .slice(0, 2)
      .forEach((slot) => {
        addSuggestion({
          barber: selectedBarber,
          date: dateText,
          startTime: slot.startTime,
          reason: "Same barber",
        });
      });

  for (const otherBarber of barbers) {
    if (otherBarber.id === selectedBarber.id) {
      continue;
    }
    const slots = computeAvailableSlots({
      days,
      appointments,
      appointmentsPerSlot,
      slotCapacityOverrides,
      closedDateOverrides,
      barberSchedules,
      barberId: otherBarber.id,
      dateText,
      requiredMinutes,
    });
    if (preferredStartTime) {
      const exactMatch = slots.find((slot) => slot.startTime === preferredStartTime);
      if (exactMatch) {
        addSuggestion({
          barber: otherBarber,
          date: dateText,
          startTime: exactMatch.startTime,
          reason: "Same time",
        });
      }
    }
    if (suggestions.length >= 4) {
      return suggestions.slice(0, 4);
    }
  }

  for (const otherBarber of barbers) {
    if (otherBarber.id === selectedBarber.id) {
      continue;
    }
    const slots = computeAvailableSlots({
      days,
      appointments,
      appointmentsPerSlot,
      slotCapacityOverrides,
      closedDateOverrides,
      barberSchedules,
      barberId: otherBarber.id,
      dateText,
      requiredMinutes,
    });
    if (slots.length > 0) {
      addSuggestion({
        barber: otherBarber,
        date: dateText,
        startTime: slots[0].startTime,
        reason: "Same day",
      });
    }
    if (suggestions.length >= 4) {
      return suggestions.slice(0, 4);
    }
  }

  const [yearText, monthText, dayText] = String(dateText || "").split("-");
  const baseDate = new Date(
      Number.parseInt(yearText, 10),
      Number.parseInt(monthText, 10) - 1,
      Number.parseInt(dayText, 10),
  );
  if (Number.isNaN(baseDate.getTime())) {
    return suggestions.slice(0, 4);
  }

  for (let offset = 1; offset <= 7 && suggestions.length < 4; offset++) {
    const nextDate = new Date(
        baseDate.getFullYear(),
        baseDate.getMonth(),
        baseDate.getDate() + offset,
    );
    const nextDateText = formatDateKey(nextDate);
    const slots = computeAvailableSlots({
      days,
      appointments,
      appointmentsPerSlot,
      slotCapacityOverrides,
      closedDateOverrides,
      barberSchedules,
      barberId: selectedBarber.id,
      dateText: nextDateText,
      requiredMinutes,
    });
    if (slots.length > 0) {
      addSuggestion({
        barber: selectedBarber,
        date: nextDateText,
        startTime: slots[0].startTime,
        reason: "Next available",
      });
    }
  }

  return suggestions.slice(0, 4);
}

async function refreshAvailabilityForDate(_options) {
  // Availability is calculated from the current schedule and appointments.
  // Do not persist a duplicate snapshot under each shop: scheduled scans of the
  // whole shop tree would repeatedly download stale slot data and add RTDB
  // storage/download cost without improving booking correctness.
  return;
}

exports.barberoPing = onRequest((request, response) => {
  const requestedShopId = String(
      request.query?.shopId || request.body?.shopId || "",
  ).trim();
  json(response, 200, {
    ok: true,
    project: "barbero-88d00",
    shopId: requestedShopId,
    message: "Customer booking functions are active.",
    method: request.method,
    timestamp: new Date().toISOString(),
  });
});

exports.barberoSaveWeeklySchedule = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = request.body?.shopId || decoded.uid;
    const access = await authorizeBarberoAccess(decoded, requestedShopId);
    if (!access.permissions.editSchedule) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    const db = getDatabase();
    const shopId = access.shopId;
    const existingSnapshot = await db.ref(`shops/${shopId}/weekly_schedule`).get();
    const existingSchedule = existingSnapshot.exists() ?
      existingSnapshot.val() || {} :
      {};
    const requestedSchedule = request.body?.schedule &&
        typeof request.body.schedule === "object" ?
      request.body.schedule :
      {};
    const schedule = normalizeWeeklySchedulePayload({
      ...existingSchedule,
      ...requestedSchedule,
    });

    await db.ref(`shops/${shopId}/weekly_schedule`).set(schedule);
    await db.ref(`shops/${shopId}/availability`).remove();

    return json(response, 200, {
      ok: true,
      shopId,
      schedule,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoSaveAppointmentSettings = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = request.body?.shopId || decoded.uid;
    const access = await authorizeBarberoAccess(decoded, requestedShopId);
    if (access.role !== "owner") {
      return json(response, 403, {ok: false, message: "owner-only"});
    }

    const settingsRef = getDatabase().ref(
        `shops/${access.shopId}/appointmentSettings`,
    );
    const currentSnapshot = await settingsRef.get();
    const currentSettings = normalizeAppointmentSettings(currentSnapshot.val());
    const requestedSettings = request.body?.appointmentSettings || {};
    const appointmentSettings = normalizeAppointmentSettings({
      ...currentSettings,
      ...(Object.prototype.hasOwnProperty.call(
          requestedSettings,
          "autoConfirmAppointments",
      ) ? {
        autoConfirmAppointments: requestedSettings.autoConfirmAppointments === true,
      } : {}),
      ...(Object.prototype.hasOwnProperty.call(
          requestedSettings,
          "remindersEnabled",
      ) ? {
        remindersEnabled: requestedSettings.remindersEnabled !== false,
      } : {}),
      ...(Object.prototype.hasOwnProperty.call(
          requestedSettings,
          "customerCancellationCutoffMinutes",
      ) ? {
        customerCancellationCutoffMinutes:
          requestedSettings.customerCancellationCutoffMinutes,
      } : {}),
      ...(Object.prototype.hasOwnProperty.call(
          requestedSettings,
          "customerRescheduleCutoffMinutes",
      ) ? {
        customerRescheduleCutoffMinutes:
          requestedSettings.customerRescheduleCutoffMinutes,
      } : {}),
    });
    const updatedAt = new Date().toISOString();
    await settingsRef.set({
      ...appointmentSettings,
      updatedAt,
    });

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      appointmentSettings: {
        ...appointmentSettings,
        updatedAt,
      },
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

function windowsAdapterAppointments(shop) {
  const rawAppointments = shop?.appointments &&
      typeof shop.appointments === "object" ?
    shop.appointments :
    {};
  return Object.entries(rawAppointments).map(([id, appointment]) => ({
    id,
    ...(appointment && typeof appointment === "object" ? appointment : {}),
  }));
}

function windowsAdapterCustomers(shop) {
  const rawCustomers = shop?.customers &&
      typeof shop.customers === "object" ?
    shop.customers :
    {};
  return Object.fromEntries(Object.entries(rawCustomers).map(([id, customer]) => {
    const source = customer && typeof customer === "object" ? customer : {};
    const {notificationTokens, ...safeCustomer} = source;
    return [id, safeCustomer];
  }));
}

function windowsAdapterBarbers(shop) {
  return Object.fromEntries(buildShopBarbers(shop).map((barber) => [
    String(barber.id || "").trim(),
    {
      id: String(barber.id || "").trim(),
      fullName: String(barber.name || "").trim(),
      email: String(barber.email || "").trim(),
      role: String(barber.role || "Barber").trim(),
      status: String(barber.status || "active").trim(),
      isOwnerBarber: barber.isOwnerBarber === true,
      notes: String(barber.notes || "").trim(),
      specialties: Array.isArray(barber.specialties) ? barber.specialties : [],
      photoUrl: String(barber.photoUrl || "").trim(),
    },
  ]).filter(([id]) => id));
}

function windowsAdapterShopPayload(shop) {
  const schedule = normalizeWeeklySchedulePayload(shop?.weekly_schedule || {});
  const appointments = Object.fromEntries(
      windowsAdapterAppointments(shop).map((appointment) => {
        const {id, ...safeAppointment} = appointment;
        return [String(id || "").trim(), safeAppointment];
      }).filter(([id]) => id),
  );
  return {
    shopName: String(shop?.shopName || "").trim(),
    ownerName: String(shop?.ownerName || "").trim(),
    weekly_schedule: schedule,
    appointments,
    customers: windowsAdapterCustomers(shop),
    barbers: windowsAdapterBarbers(shop),
  };
}

exports.barberoWindowsDataAdapter = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const action = String(request.body?.action || "").trim().toLowerCase();
    const requestedShopId = String(request.body?.shopId || "").trim();
    if (!action || !requestedShopId) {
      return json(response, 400, {
        ok: false,
        message: "action-and-shop-required",
      });
    }

    const access = await authorizeBarberoAccess(
        decoded,
        requestedShopId,
        {requireActiveBilling: action !== "billing"},
    );
    const shop = access.shop || {};
    const schedule = normalizeWeeklySchedulePayload(shop.weekly_schedule || {});

    if (action === "billing") {
      if (access.role !== "owner") {
        return json(response, 403, {ok: false, message: "owner-only"});
      }
      return json(response, 200, {
        ok: true,
        shopId: access.shopId,
        billing: buildBillingSnapshot(shop.billing),
      });
    }

    if (action === "reports") {
      if (!access.permissions.viewStats) {
        return json(response, 403, {ok: false, message: "forbidden"});
      }
      const {startDate, endDate} = buildUnifiedDashboardDateRange(request);
      const report = buildUnifiedShopDashboard({
        shopId: access.shopId,
        shop,
        startDate,
        endDate,
      });
      const reportAlerts = (report.alerts || []).map((alert) => ({
        ...alert,
        shopId: access.shopId,
        shopName: report.shopName,
      }));
      return json(response, 200, {
        ok: true,
        period: {
          startDate: dateKeyFromDateValue(startDate),
          endDate: dateKeyFromDateValue(endDate),
        },
        totals: {
          shopCount: 1,
          totalAppointments: report.totalAppointments,
          completedAppointments: report.completedAppointments,
          estimatedRevenue: report.estimatedRevenue,
          actualRevenue: report.actualRevenue,
          occupancyPercent: report.occupancyPercent,
          alerts: reportAlerts.length,
        },
        shops: [{...report, alerts: reportAlerts}],
        alerts: reportAlerts,
      });
    }

    if (action === "notifications") {
      if (resolveBarberoRole(access.role) !== "owner") {
        return json(response, 403, {ok: false, message: "forbidden"});
      }
      const notificationSnapshot = await getDatabase()
          .ref(`${NOTIFICATION_INBOX_PATH}/${access.shopId}`)
          .orderByChild("createdAt")
          .limitToLast(50)
          .get();
      const notifications = Object.entries(notificationSnapshot.val() || {})
          .map(([id, item]) => ({
            id: String(item?.id || id),
            eventType: String(item?.eventType || "general"),
            notification: {
              title: String(item?.notification?.title || "").trim(),
              body: String(item?.notification?.body || "").trim(),
            },
            data: normalizeNotificationData(item?.data),
            createdAt: String(item?.createdAt || ""),
          }))
          .sort((left, right) =>
            Date.parse(right.createdAt || "") -
            Date.parse(left.createdAt || ""));
      return json(response, 200, {
        ok: true,
        shopId: access.shopId,
        notifications,
      });
    }

    if (action === "schedule") {
      return json(response, 200, {
        ok: true,
        shopId: access.shopId,
        schedule,
      });
    }

    if (action === "save_schedule") {
      if (!access.permissions.editSchedule) {
        return json(response, 403, {ok: false, message: "forbidden"});
      }
      const requestedSchedule = request.body?.schedule &&
          typeof request.body.schedule === "object" ?
        request.body.schedule :
        {};
      const nextSchedule = normalizeWeeklySchedulePayload({
        ...shop.weekly_schedule,
        ...requestedSchedule,
      });
      const db = getDatabase();
      await db.ref(`shops/${access.shopId}/weekly_schedule`).set(nextSchedule);
      await db.ref(`shops/${access.shopId}/availability`).remove();
      return json(response, 200, {
        ok: true,
        shopId: access.shopId,
        schedule: nextSchedule,
      });
    }

    if (action === "appointments") {
      return json(response, 200, {
        ok: true,
        shopId: access.shopId,
        appointments: windowsAdapterAppointments(shop),
      });
    }

    if (action === "clients") {
      return json(response, 200, {
        ok: true,
        shopId: access.shopId,
        clients: windowsAdapterCustomers(shop),
      });
    }

    if (action === "services") {
      return json(response, 200, {
        ok: true,
        shopId: access.shopId,
        services: {
          serviceDurations: schedule.serviceDurations,
          servicePrices: schedule.servicePrices,
          serviceAddOns: schedule.serviceAddOns,
        },
      });
    }

    if (action === "snapshot") {
      return json(response, 200, {
        ok: true,
        shopId: access.shopId,
        shop: windowsAdapterShopPayload(shop),
      });
    }

    return json(response, 400, {ok: false, message: "unsupported-action"});
  } catch (error) {
    console.error(error);
    return json(response, 403, {
      ok: false,
      message: "windows-backend-request-failed",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoGetSustainabilityProfile = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = request.body?.shopId || decoded.uid;
    const access = await authorizeBarberoAccess(decoded, requestedShopId);
    if (!access.permissions.viewStats) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    const db = getDatabase();
    const snapshot = await db.ref(`shops/${access.shopId}/sustainabilityProfile`).get();
    const profile = snapshot.exists() ?
      normalizeSustainabilityProfile(snapshot.val()) :
      buildDefaultSustainabilityProfile();
    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      profile,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoSaveSustainabilityProfile = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = request.body?.shopId || decoded.uid;
    const access = await authorizeBarberoAccess(decoded, requestedShopId);
    if (String(access.role || "").trim().toLowerCase() !== "owner") {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    const profile = normalizeSustainabilityProfile(request.body?.profile);
    const db = getDatabase();
    await db.ref(`shops/${access.shopId}/sustainabilityProfile`).set(profile);
    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      profile,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoRegisterShop = onRequest(
    {secrets: [crewInvitationSmtpPassword]},
    async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body?.shop || {};
    const requestedShopId = String(payload.shopId || "").trim();
    if (requestedShopId && requestedShopId !== decoded.uid) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const ownerName = String(payload.ownerName || "").trim();
    const ownerPhone = String(payload.ownerPhone || "").trim();
    const ownerEmail = String(payload.ownerEmail || decoded.email || "").trim();
    const shopName = String(payload.shopName || "").trim();
    const location = normalizeShopAddress({
      address: String(payload.address || "").trim(),
      city: String(payload.city || "").trim(),
    });
    const address = location.address;
    const logoBase64 = String(payload.logoBase64 || "").trim();
    const logoContentType = String(payload.logoContentType || "")
        .trim()
        .toLowerCase();
    let logoBytes = null;

    if (logoBase64) {
      if (![
        "image/jpeg",
        "image/png",
        "image/webp",
      ].includes(logoContentType)) {
        return json(response, 400, {ok: false, message: "unsupported-image-type"});
      }
      logoBytes = decodeBase64Image(logoBase64);
    }

    if (!ownerName || !ownerPhone || !ownerEmail || !shopName || !address) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const db = getDatabase();
    const shopsSnapshot = await db.ref("shops").get();
    const shops = shopsSnapshot.exists() ? shopsSnapshot.val() || {} : {};
    const existingAccess = buildAccessibleBarberoShops(decoded, shops);
    const normalizedShopKey = shopName.toLowerCase()
        .replace(/[^a-z0-9]+/g, "_")
        .replace(/^_+|_+$/g, "");
    const reservedShop = shops.the_cut_society || {};
    const canClaimTheCutSociety = normalizedShopKey === "the_cut_society" &&
      !String(reservedShop.ownerUserUid || "").trim() &&
      !String(reservedShop.ownerEmail || "").trim() &&
      !String(reservedShop.ownerName || "").trim();
    const registrationDigest = createHash("sha256")
        .update(`${decoded.uid}|${shopName.toLowerCase()}|${location.cityKey}|${address.toLowerCase()}`)
        .digest("hex")
        .slice(0, 24);
    const shopId = requestedShopId ||
      (canClaimTheCutSociety ? "the_cut_society" :
        (existingAccess.length ? `shop_${registrationDigest}` : decoded.uid));
    if (!shopId) {
      throw new Error("shop-id-generation-failed");
    }

    const canonicalIdentity = buildCanonicalShopIdentity({
      shopName,
      address,
      city: location.city,
    });
    if (!canonicalIdentity) {
      return json(response, 400, {
        ok: false,
        message: "invalid-shop-canonical-identity",
      });
    }
    const canonicalConflict = findActiveShopByCanonicalIdentity(
        shops,
        canonicalIdentity,
    );
    if (canonicalConflict && canonicalConflict.shopId !== shopId) {
      return json(response, 409, {
        ok: false,
        message: "shop-canonical-identity-conflict",
        shopId: canonicalConflict.shopId,
        shopName: String(canonicalConflict.shop?.shopName || "").trim(),
      });
    }

    const existingSnapshot = await db.ref(`shops/${shopId}/billing`).get();
    const existingShopSnapshot = await db.ref(`shops/${shopId}`).get();
    const existingShop = existingShopSnapshot.exists() &&
        typeof existingShopSnapshot.val() === "object" ?
      existingShopSnapshot.val() :
      {};
    if (existingShop.archivedForTesting === true) {
      return json(response, 410, {ok: false, message: "shop-archived"});
    }
    const existingOwnerUid = String(existingShop.ownerUserUid || "").trim();
    const existingOwnerEmail = String(existingShop.ownerEmail || "")
        .trim()
        .toLowerCase();
    const normalizedOwnerEmail = ownerEmail.toLowerCase();
    if (
      (existingOwnerUid && existingOwnerUid !== decoded.uid) ||
      (!existingOwnerUid && existingOwnerEmail &&
        existingOwnerEmail !== normalizedOwnerEmail)
    ) {
      return json(response, 403, {ok: false, message: "shop-owner-mismatch"});
    }
    const isNewShop = !existingShopSnapshot.exists() || !existingOwnerUid;
    const existingProvisioningNoticeStatus = String(
        existingShop.customerApp?.provisioningNoticeStatus || "",
    ).trim();
    const shouldSendProvisioningNotice = isNewShop ||
      existingProvisioningNoticeStatus === "failed";
    const billingRecord = existingSnapshot.exists() ?
      {
        ...buildDefaultBillingRecord(),
        ...(existingSnapshot.val() || {}),
        updatedAt: new Date().toISOString(),
      } :
      buildDefaultBillingRecord();
    const scheduleRef = db.ref(`shops/${shopId}/weekly_schedule`);
    const scheduleSnapshot = await scheduleRef.get();
    const customerApp = buildCustomerAppConfiguration({
      shopId,
      shopName,
      existing: existingShop.customerApp,
    });
    if (shouldSendProvisioningNotice) {
      customerApp.provisioningNoticeStatus = "pending";
      customerApp.provisioningNoticeUpdatedAt = new Date().toISOString();
    }
    let shopLogoUrl = "";
    if (logoBytes) {
      shopLogoUrl = await uploadImageAndGetUrl({
        path: `shops/${shopId}/branding/logo`,
        bytes: logoBytes,
        contentType: logoContentType,
      });
    }
    const shopPayload = {
      id: shopId,
      ownerName,
      ownerPhone,
      ownerEmail,
      ownerUserUid: decoded.uid,
      shopName,
      address,
      streetAddress: location.streetAddress,
      city: location.city,
      cityKey: location.cityKey,
      canonicalIdentity,
      billing: billingRecord,
      customerApp,
      createdAt: String(existingShop.createdAt || new Date().toISOString()).trim(),
      updatedAt: new Date().toISOString(),
    };
    if (shopLogoUrl) {
      shopPayload.shopLogoUrl = shopLogoUrl;
    }
    if (!scheduleSnapshot.exists()) {
      shopPayload.weekly_schedule = normalizeWeeklySchedulePayload({});
    }
    await db.ref(`shops/${shopId}`).update(shopPayload);

    let provisioningNoticeEmailSent = false;
    if (shouldSendProvisioningNotice) {
      try {
        provisioningNoticeEmailSent = await sendShopProvisioningStartedEmail({
          email: ownerEmail,
          ownerName,
          shopName,
          shopId,
        });
        await db.ref(`shops/${shopId}`).update({
          "customerApp/provisioningNoticeStatus": "sent",
          "customerApp/provisioningNoticeSentAt": new Date().toISOString(),
          "customerApp/provisioningNoticeUpdatedAt": new Date().toISOString(),
        });
      } catch (emailError) {
        console.error("shop-provisioning-email-failed", emailError);
        try {
          await db.ref(`shops/${shopId}`).update({
            "customerApp/provisioningNoticeStatus": "failed",
            "customerApp/provisioningNoticeLastError": String(
                emailError?.message || emailError,
            ).slice(0, 240),
            "customerApp/provisioningNoticeUpdatedAt": new Date().toISOString(),
          });
        } catch (statusError) {
          console.error("shop-provisioning-email-status-failed", statusError);
        }
      }
    }

    return json(response, 200, {
      ok: true,
      shopId,
      customerApp: shopPayload.customerApp,
      provisioningNoticeEmailSent,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
  },
);

exports.barberoSaveOwnerPhotoUrl = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body || {};
    const shopId = String(payload.shopId || decoded.uid).trim();
    const ownerPhotoUrl = String(payload.ownerPhotoUrl || "").trim();
    const access = await authorizeBarberoAccess(decoded, shopId);
    if (access.role !== "owner") {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    if (!ownerPhotoUrl) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const db = getDatabase();
    await db.ref(`shops/${access.shopId}`).update({
      ownerPhotoUrl,
      updatedAt: new Date().toISOString(),
    });

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      ownerPhotoUrl,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoUploadOwnerPhoto = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body || {};
    const shopId = String(payload.shopId || decoded.uid).trim();
    const contentType = String(payload.contentType || "image/jpeg").trim();
    const bytes = decodeBase64Image(payload.imageBase64);
    const access = await authorizeBarberoAccess(decoded, shopId);
    if (access.role !== "owner") {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const ownerPhotoUrl = await uploadImageAndGetUrl({
      path: `shops/${access.shopId}/owner/${decoded.uid}/profile.jpg`,
      bytes,
      contentType,
    });

    const db = getDatabase();
    await db.ref(`shops/${access.shopId}`).update({
      ownerPhotoUrl,
      updatedAt: new Date().toISOString(),
    });

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      ownerPhotoUrl,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoSaveCrewMember = onRequest(
    {secrets: [crewInvitationSmtpPassword]},
    async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body?.crew || {};
    const shopId = String(payload.shopId || "").trim();
    const access = await authorizeBarberoAccess(decoded, shopId);
    if (!access.permissions.manageCrew) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const firstName = String(payload.firstName || "").trim();
    const lastName = String(payload.lastName || "").trim();
    const phone = String(payload.phone || "").trim();
    const email = String(payload.email || "").trim().toLowerCase();
    const role = String(payload.role || "Barber").trim();
    const notes = String(payload.notes || "").trim();
    const specialties = Array.isArray(payload.specialties) ?
      payload.specialties.map((item) => String(item || "").trim()).filter(Boolean) :
      [];
    const fullName = `${firstName} ${lastName}`.trim();

    if (!firstName || !lastName || !phone) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }
    if (email && !isValidEmailAddress(email)) {
      return json(response, 400, {ok: false, message: "invalid-email"});
    }

    const db = getDatabase();
    if (email) {
      const barbersSnapshot = await db.ref(`shops/${access.shopId}/barbers`).get();
      const duplicate = buildShopBarbers({barbers: barbersSnapshot.val()})
          .find((barber) => isActiveCrewEmailConflict(barber, email));
      if (duplicate) {
        return json(response, 409, {
          ok: false,
          message: duplicate.status === "invited" ?
            "crew-invite-already-exists" :
            "crew-member-already-exists",
        });
      }
    }
    const crewRef = db.ref(`shops/${access.shopId}/barbers`).push();
    const crewId = crewRef.key;
    const crew = {
      id: crewId,
      firstName,
      lastName,
      fullName,
      name: fullName,
      phone,
      email,
      role,
      notes,
      specialties,
      photoUrl: "",
      status: email ? "invited" : "active",
       invitedAt: email ? new Date().toISOString() : null,
       expiresAt: email ? new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString() : null,
      authUid: "",
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    await crewRef.set(crew);
    await db.ref(`shops/${access.shopId}`).update({
      updatedAt: new Date().toISOString(),
    });

    let invitationEmailSent = false;
    if (email) {
      try {
        invitationEmailSent = await sendCrewInvitationEmail({
          email,
          shopName: String(access.shopName || "").trim(),
          ownerName: String(access.ownerName || "").trim(),
          displayName: fullName,
          role,
        });
      } catch (emailError) {
        console.error("crew-invitation-email-failed", emailError);
      }
    }

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      crewId,
      crew,
      invitationEmailSent,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
  },
);

exports.barberoGetCrewMembers = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const shopId = String(request.body?.shopId || "").trim();
    const access = await authorizeBarberoAccess(decoded, shopId);
    if (!access.permissions.manageCrew) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      crew: buildShopBarbers(access.shop).filter((barber) =>
        String(barber.status || "active").trim().toLowerCase() !== "inactive",
      ),
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoSetOwnerBarberStatus = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const shopId = String(request.body?.shopId || "").trim();
    const enabled = request.body?.enabled === true;
    const access = await authorizeBarberoAccess(decoded, shopId);
    if (access.role !== "owner") {
      return json(response, 403, {ok: false, message: "owner-only"});
    }

    const db = getDatabase();
    const ownerBarberId = `owner_${decoded.uid}`;
    const ownerBarberRef = db.ref(
        `shops/${access.shopId}/barbers/${ownerBarberId}`,
    );

    if (!enabled) {
      const currentSnapshot = await ownerBarberRef.get();
      if (currentSnapshot.exists()) {
        await ownerBarberRef.update({
          status: "inactive",
          isOwnerBarber: false,
          updatedAt: new Date().toISOString(),
        });
      }
      return json(response, 200, {
        ok: true,
        enabled: false,
        barberId: ownerBarberId,
      });
    }

    const ownerName = String(access.shop?.ownerName || decoded.name || "")
        .trim();
    const nameParts = ownerName.split(/\s+/).filter(Boolean);
    const currentSnapshot = await ownerBarberRef.get();
    const current = currentSnapshot.exists() &&
        currentSnapshot.val() && typeof currentSnapshot.val() === "object" ?
      currentSnapshot.val() : {};
    const nowIso = new Date().toISOString();
    const existingFullName = String(
        current.fullName || current.name || "",
    ).trim();
    const existingFirstName = String(current.firstName || "").trim();
    const existingLastName = String(current.lastName || "").trim();
    const existingEmail = String(current.email || "").trim();
    const existingPhone = String(current.phone || "").trim();
    const ownerBarber = {
      ...current,
      id: ownerBarberId,
      authUid: decoded.uid,
      firstName: existingFirstName || nameParts[0] || ownerName,
      lastName: existingLastName || nameParts.slice(1).join(" "),
      fullName: existingFullName || ownerName,
      name: existingFullName || ownerName,
      email: existingEmail ||
        String(access.shop?.ownerEmail || decoded.email || "").trim(),
      phone: existingPhone || String(access.shop?.ownerPhone || "").trim(),
      role: "Barber",
      status: "active",
      isOwnerBarber: true,
      updatedAt: nowIso,
      createdAt: String(current.createdAt || nowIso),
    };
    await ownerBarberRef.set(ownerBarber);

    return json(response, 200, {
      ok: true,
      enabled: true,
      barberId: ownerBarberId,
      barber: ownerBarber,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoUploadCrewMemberPhoto = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body || {};
    const shopId = String(payload.shopId || "").trim();
    const crewId = String(payload.crewId || "").trim();
    const contentType = String(payload.contentType || "image/jpeg").trim();
    const bytes = decodeBase64Image(payload.imageBase64);

    const access = await authorizeBarberoAccess(decoded, shopId);
    if (!access.permissions.manageCrew) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    if (!crewId) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const photoUrl = await uploadImageAndGetUrl({
      path: `shops/${access.shopId}/barbers/${crewId}/profile.jpg`,
      bytes,
      contentType,
    });

    const db = getDatabase();
    await db.ref(`shops/${access.shopId}/barbers/${crewId}`).update({
      photoUrl,
      updatedAt: new Date().toISOString(),
    });
    await db.ref(`shops/${access.shopId}`).update({
      updatedAt: new Date().toISOString(),
    });

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      crewId,
      photoUrl,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoDeleteCrewMember = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body || {};
    const shopId = String(payload.shopId || "").trim();
    const crewId = String(payload.crewId || "").trim();

    const access = await authorizeBarberoAccess(decoded, shopId);
    if (!access.permissions.manageCrew) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    if (!crewId) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const db = getDatabase();
    const crewRef = db.ref(`shops/${access.shopId}/barbers/${crewId}`);
    const crewSnapshot = await crewRef.get();
    if (crewSnapshot.val()?.isOwnerBarber === true) {
      return json(response, 400, {
        ok: false,
        message: "use-owner-barber-toggle",
      });
    }
    const removedAuthUid = String(crewSnapshot.val()?.authUid || "").trim();
    await crewRef.remove();
    await db.ref(`shops/${access.shopId}`).update({
      updatedAt: new Date().toISOString(),
    });

    const bucket = getStorage().bucket("barbero-88d00.firebasestorage.app");
    await bucket.deleteFiles({
      prefix: `shops/${access.shopId}/barbers/${crewId}/`,
      force: true,
    }).catch(() => {});
    if (removedAuthUid) {
      await refreshStorageMembershipClaimsForUid(removedAuthUid);
    }

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      crewId,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoUpdateCrewMember = onRequest(
    {secrets: [crewInvitationSmtpPassword]},
    async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body?.crew || {};
    const shopId = String(payload.shopId || "").trim();
    const crewId = String(payload.crewId || "").trim();
    const access = await authorizeBarberoAccess(decoded, shopId);
    if (!access.permissions.manageCrew) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const firstName = String(payload.firstName || "").trim();
    const lastName = String(payload.lastName || "").trim();
    const phone = String(payload.phone || "").trim();
    const email = String(payload.email || "").trim().toLowerCase();
    const role = String(payload.role || "Barber").trim();
    const notes = String(payload.notes || "").trim();
    const specialties = Array.isArray(payload.specialties) ?
      payload.specialties.map((item) => String(item || "").trim()).filter(Boolean) :
      [];
    const fullName = `${firstName} ${lastName}`.trim();

    if (!crewId || !firstName || !lastName || !phone) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }
    if (email && !isValidEmailAddress(email)) {
      return json(response, 400, {ok: false, message: "invalid-email"});
    }

    const db = getDatabase();
    const crewRef = db.ref(`shops/${access.shopId}/barbers/${crewId}`);
    const crewSnapshot = await crewRef.get();
    if (!crewSnapshot.exists()) {
      return json(response, 404, {ok: false, message: "crew-not-found"});
    }
    const current = crewSnapshot.val() || {};
    const authUid = String(current.authUid || "").trim();
    const status = authUid ? "active" : (email ? "invited" : "active");
    const previousEmail = String(current.email || "").trim().toLowerCase();
    if (email && email !== previousEmail) {
      const barbersSnapshot = await db.ref(`shops/${access.shopId}/barbers`).get();
      const duplicate = buildShopBarbers({barbers: barbersSnapshot.val()})
          .find((barber) => isActiveCrewEmailConflict(barber, email, crewId));
      if (duplicate) {
        return json(response, 409, {
          ok: false,
          message: duplicate.status === "invited" ?
            "crew-invite-already-exists" :
            "crew-member-already-exists",
        });
      }
    }
    const invitationEmailChanged =
      !authUid && status === "invited" && email !== previousEmail;

    const crew = {
      id: crewId,
      firstName,
      lastName,
      fullName,
      name: fullName,
      phone,
      email,
      role,
      notes,
      specialties,
      photoUrl: String(current.photoUrl || "").trim(),
      status,
       invitedAt: status === "invited" ?
         (invitationEmailChanged ? new Date().toISOString() :
           String(current.invitedAt || new Date().toISOString())) :
         null,
       expiresAt: status === "invited" ?
         (invitationEmailChanged ?
           new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString() :
           String(current.expiresAt || new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString())) :
         null,
      authUid,
      isOwnerBarber: current.isOwnerBarber === true,
      createdAt: String(current.createdAt || new Date().toISOString()),
      updatedAt: new Date().toISOString(),
    };

    await crewRef.update(crew);
    await db.ref(`shops/${access.shopId}`).update({
      updatedAt: new Date().toISOString(),
    });
    if (authUid) {
      await refreshStorageMembershipClaimsForUid(authUid);
    }

    let invitationEmailSent = false;
    if (invitationEmailChanged) {
      try {
        invitationEmailSent = await sendCrewInvitationEmail({
          email,
          shopName: String(access.shopName || "").trim(),
          ownerName: String(access.ownerName || "").trim(),
          displayName: fullName,
          role,
        });
      } catch (emailError) {
        console.error("crew-invitation-email-failed", emailError);
      }
    }

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      crewId,
      crew,
      invitationEmailSent,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
    },
);

exports.barberoUpdateCustomerProfile = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body?.customer || {};
    const shopId = String(payload.shopId || "").trim();
    const customerUid = String(payload.customerUid || "").trim();
    const access = await authorizeBarberoAccess(decoded, shopId);
    if (!access.permissions.viewClients) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    if (!customerUid) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const db = getDatabase();
    const customerRef = db.ref(`shops/${access.shopId}/customers/${customerUid}`);
    const customerSnapshot = await customerRef.get();
    if (!customerSnapshot.exists()) {
      return json(response, 404, {ok: false, message: "customer-not-found"});
    }

    const preferences = normalizeCustomerPreferencesRaw(payload.preferences);
    const notes = String(payload.notes || "").trim();
    await customerRef.update({
      preferences,
      notes,
      updatedAt: new Date().toISOString(),
    });

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      customerUid,
      preferences,
      notes,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoMergeCustomers = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body || {};
    const shopId = String(payload.shopId || "").trim();
    const sourceCustomerUid = String(payload.sourceCustomerUid || "").trim();
    const targetCustomerUid = String(payload.targetCustomerUid || "").trim();
    const access = await authorizeBarberoAccess(decoded, shopId);
    if (!access.permissions.manageCrew) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    if (!sourceCustomerUid || !targetCustomerUid || sourceCustomerUid === targetCustomerUid) {
      return json(response, 400, {ok: false, message: "invalid-merge-request"});
    }

    const {
      db,
      shop,
      appointments,
    } = await loadShopContext(access.shopId);
    const customers = shop?.customers && typeof shop.customers === "object" ?
      shop.customers :
      {};
    const sourceCustomer = customers[sourceCustomerUid];
    const targetCustomer = customers[targetCustomerUid];
    if (!sourceCustomer || !targetCustomer) {
      return json(response, 404, {ok: false, message: "customer-not-found"});
    }

    const mergedPreferences = mergeUniqueStrings(
        normalizeCustomerPreferencesRaw(targetCustomer.preferences),
        normalizeCustomerPreferencesRaw(sourceCustomer.preferences),
    );
    const mergedNotes = mergeUniqueStrings(
        String(targetCustomer.notes || "").trim(),
        String(sourceCustomer.notes || "").trim(),
    ).join("\n\n");
    const mergedCustomer = {
      ...targetCustomer,
      uid: targetCustomerUid,
      fullName: String(
          targetCustomer.fullName ||
          targetCustomer.name ||
          sourceCustomer.fullName ||
          sourceCustomer.name ||
          "",
      ).trim(),
      phone: String(targetCustomer.phone || sourceCustomer.phone || "").trim(),
      email: String(targetCustomer.email || sourceCustomer.email || "").trim(),
      photoUrl: String(targetCustomer.photoUrl || sourceCustomer.photoUrl || "").trim(),
      preferences: mergedPreferences,
      notes: mergedNotes,
      notificationTokens: {
        ...(sourceCustomer.notificationTokens || {}),
        ...(targetCustomer.notificationTokens || {}),
      },
      updatedAt: new Date().toISOString(),
    };

    await db.ref(`shops/${access.shopId}/customers/${targetCustomerUid}`).update(mergedCustomer);

    const sourceName = String(
        sourceCustomer.fullName ||
        sourceCustomer.name ||
        "",
    ).trim().toLowerCase();
    const sourceEmail = String(sourceCustomer.email || "").trim().toLowerCase();
    const sourcePhone = String(sourceCustomer.phone || "").trim();
    const targetName = String(
        mergedCustomer.fullName ||
        mergedCustomer.name ||
        "",
    ).trim();
    const targetEmail = String(mergedCustomer.email || "").trim();
    const targetPhone = String(mergedCustomer.phone || "").trim();

    let movedAppointments = 0;
    for (const appointment of appointments) {
      const matchesSource =
        String(appointment.customerUid || "").trim() === sourceCustomerUid ||
        (!String(appointment.customerUid || "").trim() &&
          (
            (sourceName &&
              String(appointment.customerName || "").trim().toLowerCase() === sourceName) ||
            (sourceEmail &&
              String(appointment.customerEmail || "").trim().toLowerCase() === sourceEmail) ||
            (sourcePhone &&
              String(appointment.customerPhone || "").trim() === sourcePhone)
          ));
      if (!matchesSource) {
        continue;
      }
      movedAppointments += 1;
      await db.ref(`shops/${access.shopId}/appointments/${appointment.id}`).update({
        customerUid: targetCustomerUid,
        customerName: targetName,
        customerEmail: targetEmail,
        customerPhone: targetPhone,
        updatedAt: new Date().toISOString(),
      });
    }

    await db.ref(`shops/${access.shopId}/customers/${sourceCustomerUid}`).remove();
    await db.ref(`shops/${access.shopId}`).update({
      updatedAt: new Date().toISOString(),
    });

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      sourceCustomerUid,
      targetCustomerUid,
      movedAppointments,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoRepairCorruptedRecords = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const shopId = String(request.body?.shopId || "").trim();
    const access = await authorizeBarberoAccess(decoded, shopId);
    if (!access.permissions.manageCrew) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const db = getDatabase();
    const shopRef = db.ref(`shops/${access.shopId}`);
    const snapshot = await shopRef.get();
    const shop = snapshot.exists() ? snapshot.val() || {} : {};
    const updates = {};
    let repairedAppointments = 0;
    let repairedCustomers = 0;
    let repairedBarbers = 0;

    const appointments = shop?.appointments && typeof shop.appointments === "object" ?
      shop.appointments :
      {};
    for (const [appointmentId, rawAppointment] of Object.entries(appointments)) {
      const nextServices = buildNormalizedAppointmentServices(rawAppointment);
      if (
        nextServices.length > 0 &&
        JSON.stringify(nextServices) !==
          JSON.stringify(Array.isArray(rawAppointment?.services) ? rawAppointment.services : [])
      ) {
        updates[`appointments/${appointmentId}/services`] = nextServices;
        repairedAppointments += 1;
      }
      const normalizedCustomerName = normalizePossiblyCorruptedText(rawAppointment?.customerName);
      if (
        normalizedCustomerName &&
        normalizedCustomerName !== String(rawAppointment?.customerName || "").trim()
      ) {
        updates[`appointments/${appointmentId}/customerName`] = normalizedCustomerName;
        repairedAppointments += 1;
      }
      const normalizedBarberName = normalizePossiblyCorruptedText(rawAppointment?.barberName);
      if (
        normalizedBarberName &&
        normalizedBarberName !== String(rawAppointment?.barberName || "").trim()
      ) {
        updates[`appointments/${appointmentId}/barberName`] = normalizedBarberName;
        repairedAppointments += 1;
      }
    }

    const customers = shop?.customers && typeof shop.customers === "object" ?
      shop.customers :
      {};
    for (const [customerUid, rawCustomer] of Object.entries(customers)) {
      const normalizedFullName = normalizePossiblyCorruptedText(
          rawCustomer?.fullName || rawCustomer?.name,
      );
      if (
        normalizedFullName &&
        normalizedFullName !== String(rawCustomer?.fullName || rawCustomer?.name || "").trim()
      ) {
        updates[`customers/${customerUid}/fullName`] = normalizedFullName;
        updates[`customers/${customerUid}/name`] = normalizedFullName;
        repairedCustomers += 1;
      }
      const normalizedNotes = normalizePossiblyCorruptedText(rawCustomer?.notes);
      if (
        normalizedNotes &&
        normalizedNotes !== String(rawCustomer?.notes || "").trim()
      ) {
        updates[`customers/${customerUid}/notes`] = normalizedNotes;
        repairedCustomers += 1;
      }
      const preferences = normalizeCustomerPreferencesRaw(rawCustomer?.preferences)
          .map(normalizePossiblyCorruptedText);
      if (
        preferences.length > 0 &&
        JSON.stringify(preferences) !==
          JSON.stringify(normalizeCustomerPreferencesRaw(rawCustomer?.preferences))
      ) {
        updates[`customers/${customerUid}/preferences`] = preferences;
        repairedCustomers += 1;
      }
    }

    const barbers = shop?.barbers && typeof shop.barbers === "object" ?
      shop.barbers :
      {};
    for (const [crewId, rawBarber] of Object.entries(barbers)) {
      const normalizedFirstName = normalizePossiblyCorruptedText(rawBarber?.firstName);
      if (
        normalizedFirstName &&
        normalizedFirstName !== String(rawBarber?.firstName || "").trim()
      ) {
        updates[`barbers/${crewId}/firstName`] = normalizedFirstName;
        repairedBarbers += 1;
      }
      const normalizedLastName = normalizePossiblyCorruptedText(rawBarber?.lastName);
      if (
        normalizedLastName &&
        normalizedLastName !== String(rawBarber?.lastName || "").trim()
      ) {
        updates[`barbers/${crewId}/lastName`] = normalizedLastName;
        repairedBarbers += 1;
      }
      const normalizedFullName = normalizePossiblyCorruptedText(
          rawBarber?.fullName || rawBarber?.name,
      );
      if (
        normalizedFullName &&
        normalizedFullName !== String(rawBarber?.fullName || rawBarber?.name || "").trim()
      ) {
        updates[`barbers/${crewId}/fullName`] = normalizedFullName;
        updates[`barbers/${crewId}/name`] = normalizedFullName;
        repairedBarbers += 1;
      }
      const normalizedNotes = normalizePossiblyCorruptedText(rawBarber?.notes);
      if (
        normalizedNotes &&
        normalizedNotes !== String(rawBarber?.notes || "").trim()
      ) {
        updates[`barbers/${crewId}/notes`] = normalizedNotes;
        repairedBarbers += 1;
      }
    }

    if (Object.keys(updates).length > 0) {
      updates.updatedAt = new Date().toISOString();
      await shopRef.update(updates);
    }

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      repairedAppointments,
      repairedCustomers,
      repairedBarbers,
      changedPaths: Object.keys(updates).length,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoLookupCrewInvite = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const email = String(request.body?.email || "").trim().toLowerCase();
    if (!email) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }
    const db = getDatabase();
    const shopsSnapshot = await db.ref("shops").get();
    const shops = shopsSnapshot.exists() ? shopsSnapshot.val() || {} : {};
    const requestedShopId = String(request.body?.shopId || "").trim();
    const requestedCrewId = String(request.body?.crewId || "").trim();
    const invites = findCrewInvitesByEmail(shops, email).filter((invite) =>
      (!requestedShopId || invite.shopId === requestedShopId) &&
      (!requestedCrewId || invite.crewId === requestedCrewId),
    );
    const activeMemberships = invites.length === 0 ?
      findActiveCrewMembershipsByEmail(shops, email) :
      [];
    const matches = invites.length > 0 ? invites : activeMemberships;
    if (matches.length === 0) {
      return json(response, 404, {ok: false, message: "invite-not-found"});
    }
    const serializedInvites = matches.map((invite) => ({
      shopId: invite.shopId,
      shopName: invite.shopName,
      ownerName: invite.ownerName,
      crewId: invite.crewId,
      role: invite.role,
      displayName: invite.displayName,
      status: invite.status,
    }));
    return json(response, 200, {
      ok: true,
      invites: serializedInvites,
      // Keep the singular field for older Barberin builds.
      invite: serializedInvites.length === 1 ? serializedInvites[0] : null,
      requiresSelection: serializedInvites.length > 1,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoActivateCrewInvite = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = String(request.body?.shopId || "").trim();
    const requestedCrewId = String(request.body?.crewId || "").trim();
    const db = getDatabase();
    const shopsSnapshot = await db.ref("shops").get();
    const shops = shopsSnapshot.exists() ? shopsSnapshot.val() || {} : {};
    let matchingInvites = findCrewInvitesByEmail(shops, decoded.email || "")
        .filter((invite) =>
          (!requestedShopId || invite.shopId === requestedShopId) &&
          (!requestedCrewId || invite.crewId === requestedCrewId),
        );
    if (matchingInvites.length === 0) {
      const activeMembership = findActiveCrewMembershipsByEmail(
          shops,
          decoded.email || "",
      ).find((membership) =>
        membership.authUid === decoded.uid &&
        (!requestedShopId || membership.shopId === requestedShopId) &&
        (!requestedCrewId || membership.crewId === requestedCrewId),
      );
      if (activeMembership) {
        return json(response, 200, {
          ok: true,
          alreadyActive: true,
          session: {
            shopId: activeMembership.shopId,
            role: activeMembership.role,
            crewId: activeMembership.crewId,
            displayName: activeMembership.displayName,
          },
        });
      }
      return json(response, 404, {ok: false, message: "invite-not-found"});
    }
    if (!requestedShopId && !requestedCrewId && matchingInvites.length > 1) {
      return json(response, 409, {
        ok: false,
        message: "multiple-invites",
        invites: matchingInvites.map((invite) => ({
          shopId: invite.shopId,
          shopName: invite.shopName,
          ownerName: invite.ownerName,
          crewId: invite.crewId,
          role: invite.role,
          displayName: invite.displayName,
          status: invite.status,
        })),
      });
    }
    const invite = matchingInvites[0];
    if (invite.authUid && invite.authUid !== decoded.uid) {
      return json(response, 409, {ok: false, message: "invite-already-used"});
    }

    await db.ref(`shops/${invite.shopId}/barbers/${invite.crewId}`).update({
      status: "active",
      authUid: decoded.uid,
      joinedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    await refreshStorageMembershipClaimsForUid(decoded.uid);

    return json(response, 200, {
      ok: true,
      session: {
        shopId: invite.shopId,
        role: invite.role,
        crewId: invite.crewId,
        displayName: invite.displayName,
      },
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoResolveSession = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const resolved = await resolveBarberoSession({
      ...decoded,
      activeShopId: String(request.body?.activeShopId || "").trim(),
    });
    const db = getDatabase();
    await Promise.all(
        (resolved.accessibleShops || []).map((entry) =>
          syncBillingAccessMetadata(db, entry.shopId, entry.shop?.billing),
        ),
    );
    // The shop trigger maintains the multi-shop index. Refresh only the
    // active shop here, avoiding a second full /shops read on every login.
    await syncStorageMembershipClaimForShop(
        decoded.uid,
        resolved.shopId,
        resolved.shop,
    );
    return json(response, 200, {
      ok: true,
      session: {
        shopId: resolved.shopId,
        shopName: String(resolved.shopName || "").trim(),
        role: resolved.role,
        crewId: resolved.crewId,
        displayName: resolved.displayName,
      },
      shops: (resolved.accessibleShops || []).map((entry) => ({
        shopId: entry.shopId,
        shopName: entry.shopName,
        ownerName: entry.ownerName,
      role: entry.role,
      crewId: entry.crewId,
      displayName: entry.displayName,
      billing: entry.role === "owner" ?
        buildBillingSnapshot(entry.shop?.billing) :
        null,
      customerApp: entry.role === "owner" ?
        entry.shop?.customerApp || null :
        null,
    })),
      billing: buildBillingSnapshot(resolved.shop?.billing),
    });
  } catch (error) {
    console.error(error);
    return json(response, 403, {
      ok: false,
      message: "forbidden",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoGetBillingStatus = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = String(request.body?.shopId || "").trim();
    const access = await authorizeBarberoAccess(
        decoded,
        requestedShopId,
        {requireActiveBilling: false},
    );
    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      billing: buildBillingSnapshot(access.shop?.billing),
    });
  } catch (error) {
    console.error(error);
    return json(response, 403, {
      ok: false,
      message: "forbidden",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoSaveBillingPlan = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = String(request.body?.shopId || "").trim();
    const access = await authorizeBarberoAccess(
        decoded,
        requestedShopId,
        {requireActiveBilling: false},
    );
    if (access.role !== "owner") {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    const selectedPlan = normalizeBillingPlan(request.body?.selectedPlan);
    const db = getDatabase();
    const billingRef = db.ref(`shops/${access.shopId}/billing`);
    const snapshot = await billingRef.get();
    const nextBilling = {
      ...buildDefaultBillingRecord(),
      ...(snapshot.exists() ? snapshot.val() || {} : {}),
      pendingPlan: selectedPlan,
      updatedAt: new Date().toISOString(),
    };
    nextBilling.accessUntilMillis = billingAccessUntilMillis(
        nextBilling,
        nextBilling.status,
    );
    await billingRef.set(nextBilling);
    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      billing: buildBillingSnapshot(nextBilling),
    });
  } catch (error) {
    console.error(error);
    return json(response, 400, {
      ok: false,
      message: "billing-plan-save-failed",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoStartSubscriptionTrial = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }
  return json(response, 410, {
    ok: false,
    message: "native-store-trial-required",
  });
});

exports.barberoProcessStorePurchase = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = String(request.body?.shopId || "").trim();
    const access = await authorizeBarberoAccess(
        decoded,
        requestedShopId,
        {requireActiveBilling: false},
    );
    if (access.role !== "owner") {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    const db = getDatabase();

    const purchase = request.body?.purchase || {};
    const requestedPlan = normalizeBillingPlan(
        purchase.selectedPlan || purchase.productId,
    );
    const requestedProductId = String(purchase.productId || "").trim();
    const productId = requestedProductId ||
      billingProductIdForPlan(requestedPlan);
    const purchaseId = String(purchase.purchaseId || "").trim();
    const platform = normalizeBillingPlatform(purchase.platform);
    const transactionDateRaw = String(purchase.transactionDate || "").trim();
    const verificationData =
      purchase.verificationData && typeof purchase.verificationData === "object" ?
        purchase.verificationData :
        {};
    const serverVerificationData = String(
        verificationData.serverVerificationData || "",
    ).trim();
    const verificationDigest = buildVerificationDigest(serverVerificationData);

    if (!billingPlanFromProductId(productId) ||
      !platform ||
      !serverVerificationData
    ) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const verifiedPurchase = await verifyStorePurchaseOrThrow({
      platform,
      productId,
      purchaseToken: serverVerificationData,
    });

    const purchaseDate = transactionDateRaw ?
      new Date(Number.parseInt(transactionDateRaw, 10)) :
      new Date();
    const normalizedPurchaseDate =
      Number.isNaN(purchaseDate.getTime()) ? new Date() : purchaseDate;
    const currentPeriodEnd = String(
        verifiedPurchase.currentPeriodEnd || "",
    ).trim();
    if (!currentPeriodEnd) {
      throw new Error("missing-verified-current-period-end");
    }

    const verifiedProductId = String(
        verifiedPurchase.storeProductId || "",
    ).trim();
    const verifiedPlan = billingPlanFromProductId(verifiedProductId);
    if (!verifiedPlan ||
      (!isAppleBillingPlatform(platform) && verifiedProductId !== productId)) {
      throw new Error("verified-product-mismatch");
    }

    // Google purchase ids contain dots (for example GPA....), which are not
    // valid Realtime Database path keys. Use the verification digest as the
    // stable idempotency key and keep the original purchase id as data.
    const purchaseRecordId = verificationDigest || randomUUID();

    // A lost response must be safe to retry. Re-apply the verified provider
    // state instead of returning stale billing data. This is important when a
    // restore event arrives after a renewal, refund, revocation, or expiry.
    let existingPurchase = null;
    if (purchaseRecordId) {
      const existingPurchaseSnapshot = await db.ref(
          `shops/${access.shopId}/billingPurchases/${purchaseRecordId}`,
      ).get();
      if (existingPurchaseSnapshot.exists()) {
        existingPurchase = existingPurchaseSnapshot.val() || {};
        if ((existingPurchase.verificationDigest &&
          existingPurchase.verificationDigest !== verificationDigest) ||
          normalizeBillingPlatform(existingPurchase.platform) !== platform) {
          throw new Error("purchase-id-already-bound");
        }
      }
    }

    await claimBillingToken({
      shopId: access.shopId,
      platform,
      productId: verifiedProductId,
      purchaseToken: serverVerificationData,
    });

    const billingRef = db.ref(`shops/${access.shopId}/billing`);
    const snapshot = await billingRef.get();
    const currentBilling = {
      ...buildDefaultBillingRecord(),
      ...(snapshot.exists() ? snapshot.val() || {} : {}),
    };
    const nextBilling = buildVerifiedBillingRecord({
      currentBilling,
      selectedPlan: verifiedPlan,
      verifiedPurchase,
      verificationSource: String(verificationData.source || "").trim(),
      purchaseId: purchaseRecordId,
      transactionDate: normalizedPurchaseDate.toISOString(),
    });
    nextBilling.latestVerificationDigest = verificationDigest;

    await billingRef.set(nextBilling);
    await saveBillingCredential(access.shopId, {
      platform,
      productId: verifiedProductId,
      purchaseToken: serverVerificationData,
      updatedAt: new Date().toISOString(),
    });
    await db.ref(`shops/${access.shopId}/billingPurchases/${purchaseRecordId}`).set({
      ...(existingPurchase || {}),
      id: purchaseRecordId,
      platform,
      productId: verifiedProductId,
      selectedPlan: verifiedPlan,
      purchaseId,
      transactionDate: transactionDateRaw,
      processedAt: new Date().toISOString(),
      verificationSource: String(verificationData.source || "").trim(),
      verificationDigest,
      storeStatus: String(verifiedPurchase.storeStatus || "").trim(),
      cancellationAt: String(verifiedPurchase.cancellationAt || "").trim(),
      revokedAt: String(verifiedPurchase.revokedAt || "").trim(),
      refundedAt: String(verifiedPurchase.refundedAt || "").trim(),
    });
    await removeRawBillingVerificationResults(db, access.shopId);
    await db.ref(`shops/${access.shopId}`).update({
      updatedAt: new Date().toISOString(),
    });

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      billing: buildBillingSnapshot(nextBilling),
    });
  } catch (error) {
    console.error(error);
    return json(response, 400, {
      ok: false,
      message: "store-purchase-processing-failed",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoDeleteAccount = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = request.body?.shopId || decoded.uid;
    const access = await authorizeBarberoAccess(
        decoded,
        requestedShopId,
        {requireActiveBilling: false},
    );
    const db = getDatabase();
    const deletedAt = new Date().toISOString();

    const finalizeRemainingAccess = async () => {
      const shopsSnapshot = await db.ref("shops").get();
      const remainingShops = shopsSnapshot.exists() ? shopsSnapshot.val() || {} : {};
      const remainingAccess = buildAccessibleBarberoShops(decoded, remainingShops);
      await refreshStorageMembershipClaimsForUid(decoded.uid);
      if (!remainingAccess.length) {
        await getAuth().deleteUser(decoded.uid);
      }
      return remainingAccess;
    };

    if (access.role === "owner") {
      const shopSnapshot = await db.ref(`shops/${access.shopId}`).get();
      if (!shopSnapshot.exists()) {
        throw new Error("shop-not-found");
      }
      const auditRef = db.ref(`${DELETION_AUDIT_PATH}/${randomUUID()}`);
      await auditRef.set({
        type: "owner_shop_deletion",
        status: "started",
        createdAt: deletedAt,
        expiresAt: deletionAuditExpiresAt(deletedAt),
        source: "barbero_app",
      });
      const bucket = getStorage().bucket("barbero-88d00.firebasestorage.app");
      await bucket.deleteFiles({
        prefix: `shops/${access.shopId}/`,
        force: true,
      });
      await db.ref(`shops/${access.shopId}`).remove();
      await deleteBillingCredential(access.shopId);
      const remainingAccess = await finalizeRemainingAccess();
      await auditRef.update({
        status: "completed",
        completedAt: new Date().toISOString(),
        remainingShopCount: remainingAccess.length,
      });
      return json(response, 200, {
        ok: true,
        mode: "owner",
        remainingShopCount: remainingAccess.length,
        nextShopId: remainingAccess[0]?.shopId || "",
      });
    }

    const crewId = String(access.crewId || "").trim();
    if (!crewId) {
      throw new Error("crew-account-not-found");
    }

    const crewRef = db.ref(`shops/${access.shopId}/barbers/${crewId}`);
    const crewSnapshot = await crewRef.get();
    if (!crewSnapshot.exists()) {
      throw new Error("crew-account-not-found");
    }
    const auditRef = db.ref(`${DELETION_AUDIT_PATH}/${randomUUID()}`);
    await auditRef.set({
      type: "crew_account_deletion",
      status: "started",
      createdAt: deletedAt,
      expiresAt: deletionAuditExpiresAt(deletedAt),
      source: "barbero_app",
    });

    await crewRef.update({
      authUid: "",
      email: "",
      phone: "",
      photoUrl: "",
      notes: "",
      inviteStatus: "deleted_account",
      status: "deleted_account",
      deletedAccountAt: deletedAt,
      updatedAt: deletedAt,
    });
    await refreshStorageMembershipClaimsForUid(decoded.uid);
    const bucket = getStorage().bucket("barbero-88d00.firebasestorage.app");
    await bucket.deleteFiles({
      prefix: `shops/${access.shopId}/barbers/${crewId}/`,
      force: true,
    }).catch(() => {});
    const remainingAccess = await finalizeRemainingAccess();
    await auditRef.update({
      status: "completed",
      completedAt: new Date().toISOString(),
      remainingShopCount: remainingAccess.length,
    });
    return json(response, 200, {
      ok: true,
      mode: "crew",
      remainingShopCount: remainingAccess.length,
      nextShopId: remainingAccess[0]?.shopId || "",
    });
  } catch (error) {
    console.error(error);
    return json(response, 400, {
      ok: false,
      message: "delete-account-failed",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoDeleteCustomerAccount = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = String(request.body?.shopId || "").trim();
    if (!requestedShopId) {
      throw new Error("missing-shop-id");
    }

    const db = getDatabase();
    const accountUid = String(decoded.uid || "").trim();
    const accountEmail = String(decoded.email || "").trim().toLowerCase();
    const deletedAt = new Date().toISOString();

    const shopsSnapshot = await db.ref("shops").get();
    const rawShops = shopsSnapshot.exists() ? shopsSnapshot.val() || {} : {};
    const shopContexts = [];

    for (const [candidateShopId, rawShop] of Object.entries(rawShops)) {
      const rawCustomers = rawShop?.customers &&
        typeof rawShop.customers === "object" ?
        rawShop.customers :
        {};
      const customerEntries = Object.entries(rawCustomers);
      const matchingCustomerEntries = customerEntries.filter(([recordKey, customer]) => {
        const recordUid = String(customer?.uid || "").trim();
        const matchesUid = accountUid && (
          String(recordKey || "").trim() === accountUid ||
          recordUid === accountUid
        );
        const matchesEmail = accountEmail &&
          String(customer?.email || "").trim().toLowerCase() === accountEmail;
        return matchesUid || matchesEmail;
      });

      if (matchingCustomerEntries.length === 0 &&
          String(candidateShopId) !== requestedShopId) {
        const rawAppointments = rawShop?.appointments &&
          typeof rawShop.appointments === "object" ?
          rawShop.appointments :
          {};
        const hasMatchingAppointment = Object.values(rawAppointments).some(
            (appointment) => {
              const appointmentUid = String(
                  appointment?.customerUid || "",
              ).trim();
              const appointmentEmail = String(
                  appointment?.customerEmail || "",
              ).trim().toLowerCase();
              return (accountUid && appointmentUid === accountUid) ||
                (accountEmail && appointmentEmail === accountEmail);
            },
        );
        if (!hasMatchingAppointment) {
          continue;
        }
      }

      const context = await loadShopContext(candidateShopId);
      const matchedCustomerIds = new Set([
        accountUid,
        ...matchingCustomerEntries.flatMap(([recordKey, customer]) => [
          String(recordKey || "").trim(),
          String(customer?.uid || "").trim(),
        ]),
      ].filter(Boolean));
      const appointmentsToDelete = context.appointments.filter((appointment) => {
        const appointmentCustomerUid = String(
            appointment.customerUid || "",
        ).trim();
        const appointmentEmail = String(
            appointment.customerEmail || "",
        ).trim().toLowerCase();
        return (
          (appointmentCustomerUid && matchedCustomerIds.has(appointmentCustomerUid)) ||
          (accountEmail && appointmentEmail === accountEmail)
        );
      });

      const affectedDates = new Map();
      for (const appointment of appointmentsToDelete) {
        const dateText = String(appointment.date || "").trim();
        const barberId = String(appointment.barberId || "").trim();
        if (!dateText || !barberId) {
          continue;
        }
        if (!affectedDates.has(dateText)) {
          affectedDates.set(dateText, new Set());
        }
        affectedDates.get(dateText).add(barberId);
      }

      shopContexts.push({
        ...context,
        shopId: candidateShopId,
        customerKeys: matchingCustomerEntries.map(([recordKey]) => recordKey),
        customerRecords: matchingCustomerEntries.map(([recordKey, customer]) => ({
          recordKey,
          customer,
        })),
        appointmentsToDelete,
        remainingAppointments: context.appointments.filter((appointment) =>
          !appointmentsToDelete.some((removed) => removed.id === appointment.id),
        ),
        affectedDates,
      });
    }

    const shopIds = shopContexts.map((context) => context.shopId);
    const deletedCustomerRecordCount = shopContexts.reduce(
        (total, context) => total + context.customerRecords.length,
        0,
    );
    const deletedAppointmentCount = shopContexts.reduce(
        (total, context) => total + context.appointmentsToDelete.length,
        0,
    );
    const auditRef = db.ref(`${DELETION_AUDIT_PATH}/${randomUUID()}`);
    await auditRef.set({
      type: "customer_account_deletion",
      status: "started",
      createdAt: deletedAt,
      expiresAt: deletionAuditExpiresAt(deletedAt),
      source: "barbero_customer_app",
      shopCount: shopIds.length,
      customerRecordCount: deletedCustomerRecordCount,
      appointmentCount: deletedAppointmentCount,
    });

    const cleanupUpdates = {};
    for (const context of shopContexts) {
      for (const customerKey of context.customerKeys) {
        cleanupUpdates[`shops/${context.shopId}/customers/${customerKey}`] = null;
      }
      for (const appointment of context.appointmentsToDelete) {
        const appointmentId = String(appointment.id || "").trim();
        if (appointmentId) {
          cleanupUpdates[
              `shops/${context.shopId}/appointments/${appointmentId}`
          ] = null;
        }
      }
    }
    if (Object.keys(cleanupUpdates).length > 0) {
      await db.ref().update(cleanupUpdates);
    }

    const bucket = getStorage().bucket("barbero-88d00.firebasestorage.app");
    for (const context of shopContexts) {
      const storageCustomerKeys = new Set([
        accountUid,
        ...context.customerKeys.map((key) => String(key || "").trim()),
      ].filter(Boolean));
      for (const customerKey of storageCustomerKeys) {
        await bucket.deleteFiles({
          prefix: `shops/${context.shopId}/customers/${customerKey}/`,
          force: true,
        });
      }

      for (const [dateText, barberIds] of context.affectedDates.entries()) {
        await refreshAvailabilityForDate({
          db,
          shopId: context.shopId,
          shop: context.shop,
          days: context.days,
          slotMinutes: context.slotMinutes,
          appointmentsPerSlot: context.appointmentsPerSlot,
          slotCapacityOverrides: context.slotCapacityOverrides,
          closedDateOverrides: context.closedDateOverrides,
          barberSchedules: context.barberSchedules,
          serviceDurations: context.serviceDurations,
          appointments: context.remainingAppointments,
          dateText,
          barberIds: Array.from(barberIds),
        });
      }
    }

    await getAuth().deleteUser(accountUid);
    await auditRef.update({
      status: "completed",
      completedAt: new Date().toISOString(),
    });
    return json(response, 200, {
      ok: true,
      deletedShops: shopIds.length,
      deletedAppointments: deletedAppointmentCount,
    });
  } catch (error) {
    console.error(error);
    return json(response, 400, {
      ok: false,
      message: "delete-account-failed",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoSaveCustomerProfile = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body || {};
    const shopId = String(payload.shopId || "").trim();
    const fullName = String(payload.fullName || "").trim();
    const phone = String(payload.phone || "").trim();
    const email = String(payload.email || decoded.email || "").trim();
    const preferences = String(payload.preferences || "").trim();
    const shopAccessToken = String(payload.shopAccessToken || "").trim();
    const customerAppMode = String(payload.customerAppMode || "").trim();

    if (!shopId || !fullName || !phone || !email) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const db = getDatabase();
    const shopSnapshot = await db.ref(`shops/${shopId}`).get();
    if (!shopSnapshot.exists()) {
      return json(response, 404, {ok: false, message: "shop-not-found"});
    }
    const shop = shopSnapshot.exists() ? shopSnapshot.val() || {} : {};
    if (!hasActiveShopSubscription(shop)) {
      return json(response, 402, {
        ok: false,
        message: "subscription-required",
      });
    }
    const existingCustomer = findCurrentCustomerEntry(shop, decoded);
    if (!hasConfiguredCustomerAppAccess({
      shop,
      decoded,
      accessToken: shopAccessToken,
      requestedMode: customerAppMode,
    })) {
      return json(response, 403, {
        ok: false,
        message: "customer-app-link-required",
      });
    }
    const customerKey = String(existingCustomer?.recordKey || decoded.uid).trim();
    const nowIso = new Date().toISOString();
    await db.ref(`shops/${shopId}/customers/${customerKey}`).update({
      uid: decoded.uid,
      fullName,
      phone,
      email,
      preferences,
      shopId,
      shopName: resolveShopDisplayName(shop),
      createdAt: String(existingCustomer?.customer?.createdAt || nowIso).trim(),
      updatedAt: nowIso,
    });

    return json(response, 200, {
      ok: true,
      shopId,
      customerUid: decoded.uid,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoGetCustomerAppLink = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = String(request.body?.shopId || "").trim();
    const access = await authorizeBarberoAccess(decoded, requestedShopId);
    if (!access.permissions.manageCrew) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const db = getDatabase();
    const shopRef = db.ref(`shops/${access.shopId}`);
    const shopSnapshot = await shopRef.get();
    const shop = shopSnapshot.exists() ? shopSnapshot.val() || {} : {};
    const configuredApp = shop.customerApp &&
      typeof shop.customerApp === "object" ? shop.customerApp : {};

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      shopName: resolveShopDisplayName(shop),
      message: "shop-specific-customer-app",
      customerApp: {
        mode: "separate",
        status: String(configuredApp.status || "provisioning_required").trim(),
        displayName: String(
            configuredApp.displayName || resolveShopDisplayName(shop),
        ).trim(),
        packageName: String(configuredApp.packageName || "").trim(),
        bundleId: String(configuredApp.bundleId || "").trim(),
        firebaseAndroidAppId: String(
            configuredApp.firebaseAndroidAppId || "",
        ).trim(),
        firebaseIosAppId: String(configuredApp.firebaseIosAppId || "").trim(),
        workspaceName: String(configuredApp.workspaceName || "").trim(),
        playStoreUrl: String(configuredApp.playStoreUrl || "").trim(),
        appStoreUrl: String(configuredApp.appStoreUrl || "").trim(),
      },
    });
  } catch (error) {
    console.error(error);
    return json(response, 400, {
      ok: false,
      message: "customer-app-link-failed",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoSaveNotificationToken = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body || {};
    const shopId = String(payload.shopId || "").trim();
    const tokenKey = String(payload.tokenKey || "").trim();
    const token = String(payload.token || "").trim();

    if (!shopId || !tokenKey || !token) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const db = getDatabase();
    const shopSnapshot = await db.ref(`shops/${shopId}`).get();
    if (!shopSnapshot.exists()) {
      return json(response, 404, {ok: false, message: "shop-not-found"});
    }
    const shop = shopSnapshot.val() || {};
    if (!hasActiveShopSubscription(shop)) {
      return json(response, 402, {
        ok: false,
        message: "subscription-required",
      });
    }
    const customerEntry = findCurrentCustomerEntry(shop, decoded);
    if (!customerEntry) {
      return json(response, 404, {ok: false, message: "customer-not-found"});
    }
    const requestedPlatform = String(payload.platform || "")
        .trim()
        .toLowerCase();
    const platform = ["android", "ios", "web"].includes(requestedPlatform) ?
      requestedPlatform :
      "unknown";
    await db.ref(
        `shops/${shopId}/customers/${customerEntry.recordKey}/notificationTokens/${tokenKey}`,
    ).set({
      token,
      platform,
      updatedAt: new Date().toISOString(),
    });

    return json(response, 200, {
      ok: true,
      shopId,
      customerUid: decoded.uid,
      tokenKey,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoSaveCustomerPhotoUrl = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body || {};
    const shopId = String(payload.shopId || "").trim();
    const customerUid = String(payload.customerUid || decoded.uid).trim();
    const photoUrl = String(payload.photoUrl || "").trim();

    if (!shopId || !customerUid || !photoUrl) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    if (customerUid !== decoded.uid) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const db = getDatabase();
    const shopSnapshot = await db.ref(`shops/${shopId}`).get();
    if (!shopSnapshot.exists()) {
      return json(response, 404, {ok: false, message: "shop-not-found"});
    }
    const shop = shopSnapshot.val() || {};
    if (!hasActiveShopSubscription(shop)) {
      return json(response, 402, {
        ok: false,
        message: "subscription-required",
      });
    }
    const customerEntry = findCurrentCustomerEntry(shop, decoded);
    if (!customerEntry) {
      return json(response, 404, {ok: false, message: "customer-not-found"});
    }
    await db.ref(`shops/${shopId}/customers/${customerEntry.recordKey}`).update({
      photoUrl,
      updatedAt: new Date().toISOString(),
    });

    return json(response, 200, {
      ok: true,
      shopId,
      customerUid,
      photoUrl,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoUploadCustomerPhoto = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body || {};
    const shopId = String(payload.shopId || "").trim();
    const customerUid = String(payload.customerUid || decoded.uid).trim();
    const contentType = String(payload.contentType || "image/jpeg").trim();
    const bytes = decodeBase64Image(payload.imageBase64);

    if (!shopId || !customerUid) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }
    if (customerUid !== decoded.uid) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const db = getDatabase();
    const shopSnapshot = await db.ref(`shops/${shopId}`).get();
    if (!shopSnapshot.exists()) {
      return json(response, 404, {ok: false, message: "shop-not-found"});
    }
    const shop = shopSnapshot.val() || {};
    if (!hasActiveShopSubscription(shop)) {
      return json(response, 402, {
        ok: false,
        message: "subscription-required",
      });
    }
    const customerEntry = findCurrentCustomerEntry(shop, decoded);
    if (!customerEntry) {
      return json(response, 404, {ok: false, message: "customer-not-found"});
    }

    const photoUrl = await uploadImageAndGetUrl({
      path: `shops/${shopId}/customers/${customerUid}/profile.jpg`,
      bytes,
      contentType,
    });

    await db.ref(`shops/${shopId}/customers/${customerEntry.recordKey}`).update({
      photoUrl,
      updatedAt: new Date().toISOString(),
    });

    return json(response, 200, {
      ok: true,
      shopId,
      customerUid,
      photoUrl,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoGetCustomerShell = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const shopId = String(request.body?.shopId || "").trim();
    const shopAccessToken = String(request.body?.shopAccessToken || "").trim();
    const customerAppMode = String(
        request.body?.customerAppMode || "",
    ).trim();
    if (!shopId) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const {
      shop,
      appointments,
    } = await loadShopContext(shopId);
    if (!hasActiveShopSubscription(shop)) {
      return json(response, 402, {
        ok: false,
        message: "subscription-required",
      });
    }
    if (!hasConfiguredCustomerAppAccess({
      shop,
      decoded,
      accessToken: shopAccessToken,
      requestedMode: customerAppMode,
    })) {
      return json(response, 403, {
        ok: false,
        message: "customer-app-link-required",
      });
    }
    // The current shop is enough to make the just-opened app consistent. A
    // scheduled reconciler keeps claims for other shops up to date without
    // forcing every app launch to read the entire multi-shop tree.
    await syncStorageMembershipClaimForShop(decoded.uid, shopId, shop);

    return json(response, 200, {
      ok: true,
      shell: buildCustomerShellPayload({
        shopId,
        shop,
        decoded,
        appointments,
      }),
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoGetAvailability = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const shopId = request.body?.shopId;
    const shopAccessToken = String(request.body?.shopAccessToken || "").trim();
    const customerAppMode = String(
        request.body?.customerAppMode || "",
    ).trim();
    const barberId = request.body?.barberId;
    const dateText = request.body?.date;
    const serviceKeys = Array.isArray(request.body?.serviceKeys) ?
      Array.from(new Set(
          request.body.serviceKeys.map((item) => String(item || "").trim())
              .filter(Boolean),
      )) :
      [];
    const addOnKeys = Array.isArray(request.body?.addOnKeys) ?
      Array.from(new Set(
          request.body.addOnKeys.map((item) => String(item || "").trim())
              .filter(Boolean),
      )) :
      [];
    const explicitMinutes = Number.parseInt(request.body?.requiredMinutes, 10);

    if (!shopId || !barberId || !dateText || !parseDashboardDateKey(dateText)) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const {
      db,
      shop,
      days,
      slotMinutes,
      appointmentsPerSlot,
      slotCapacityOverrides,
      closedDateOverrides,
      barberSchedules,
      serviceDurations,
      servicePrices,
      serviceAddOns,
      appointments,
    } = await loadShopContext(shopId);

    if (!hasActiveShopSubscription(shop)) {
      return json(response, 402, {
        ok: false,
        message: "subscription-required",
      });
    }

    if (shopAccessToken || customerAppMode) {
      const customerAccess = validateCustomerAppRequest({
        shop,
        decoded,
        shopId,
        accessToken: shopAccessToken,
        requestedMode: customerAppMode,
      });
      if (!customerAccess.ok) {
        return json(response, 403, {
          ok: false,
          message: customerAccess.message,
        });
      }
    } else if (!hasBarberoShopMembership({decoded, shopId, shop})) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    if (!isBookableShopBarber(shop, barberId)) {
      return json(response, 404, {ok: false, message: "barber-not-found"});
    }
    const unavailableServiceKeys = unavailableServiceKeysForBarber(
        serviceKeys,
        serviceDurations,
        barberId,
    );
    if (unavailableServiceKeys.length > 0) {
      return json(response, 409, {
        ok: false,
        message: "service-not-available-for-barber",
        serviceKeys: unavailableServiceKeys,
      });
    }

    const unavailableAddOnKeys = unavailableAddOnKeysForSelection(
        addOnKeys,
        serviceKeys,
        serviceAddOns,
    );
    if (unavailableAddOnKeys.length > 0) {
      return json(response, 409, {
        ok: false,
        message: "add-on-not-available",
        addOnKeys: unavailableAddOnKeys,
      });
    }

    let requiredMinutes = explicitMinutes;
    const selectedServices = buildServiceSelection(
        serviceKeys,
        serviceDurations,
        servicePrices,
    );
    const selectedAddOns = buildAddOnSelection(
        addOnKeys,
        serviceKeys,
        serviceAddOns,
    );
    const configuredMinutes = [...selectedServices, ...selectedAddOns].reduce(
        (sum, item) => sum + item.minutes,
        0,
    );
    requiredMinutes = configuredMinutes || requiredMinutes || slotMinutes;

    const slots = computeAvailableSlots({
      days,
      appointments,
      appointmentsPerSlot,
      slotCapacityOverrides,
      closedDateOverrides,
      barberSchedules,
      barberId,
      dateText,
      requiredMinutes,
    });

    return json(response, 200, {
      ok: true,
      shopId,
      barberId,
      date: dateText,
      requiredMinutes,
      slots,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoBookAppointment = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const shopId = request.body?.shopId;
    const shopAccessToken = String(request.body?.shopAccessToken || "").trim();
    const customerAppMode = String(
        request.body?.customerAppMode || "",
    ).trim();
    const barberId = request.body?.barberId;
    const dateText = request.body?.date;
    const startTime = request.body?.startTime;
    const serviceKeys = Array.isArray(request.body?.serviceKeys) ?
      Array.from(new Set(
          request.body.serviceKeys.map((item) => String(item || "").trim())
              .filter(Boolean),
      )) :
      [];
    const addOnKeys = Array.isArray(request.body?.addOnKeys) ?
      Array.from(new Set(
          request.body.addOnKeys.map((item) => String(item || "").trim())
              .filter(Boolean),
      )) :
      [];

    if (!shopId || !barberId || !dateText || !parseDashboardDateKey(dateText) ||
        !isValidTimeText(startTime) || serviceKeys.length === 0) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const {
      db,
      shop,
      days,
      slotMinutes,
      appointmentsPerSlot,
      slotCapacityOverrides,
      closedDateOverrides,
      barberSchedules,
      serviceDurations,
      servicePrices,
      serviceAddOns,
      appointments,
      autoConfirmAppointments,
    } = await loadShopContext(shopId);

    if (!hasActiveShopSubscription(shop)) {
      return json(response, 402, {
        ok: false,
        message: "subscription-required",
      });
    }

    const customerAccess = validateCustomerAppRequest({
      shop,
      decoded,
      shopId,
      accessToken: shopAccessToken,
      requestedMode: customerAppMode,
    });
    if (!customerAccess.ok) {
      return json(response, 403, {
        ok: false,
        message: customerAccess.message,
      });
    }

    if (!isBookableShopBarber(shop, barberId)) {
      return json(response, 404, {ok: false, message: "barber-not-found"});
    }
    const barber = findShopBarberById(shop, barberId);

    const unavailableServiceKeys = unavailableServiceKeysForBarber(
        serviceKeys,
        serviceDurations,
        barberId,
    );
    if (unavailableServiceKeys.length > 0) {
      return json(response, 409, {
        ok: false,
        message: "service-not-available-for-barber",
        serviceKeys: unavailableServiceKeys,
      });
    }

    const unavailableAddOnKeys = unavailableAddOnKeysForSelection(
        addOnKeys,
        serviceKeys,
        serviceAddOns,
    );
    if (unavailableAddOnKeys.length > 0) {
      return json(response, 409, {
        ok: false,
        message: "add-on-not-available",
        addOnKeys: unavailableAddOnKeys,
      });
    }

    const selectedServices = buildServiceSelection(
        serviceKeys,
        serviceDurations,
        servicePrices,
    );
    const selectedAddOns = buildAddOnSelection(
        addOnKeys,
        serviceKeys,
        serviceAddOns,
    );
    const totalMinutes = [...selectedServices, ...selectedAddOns].reduce(
        (sum, item) => sum + item.minutes,
        0,
    ) || slotMinutes;
    const totalPrice = [...selectedServices, ...selectedAddOns].reduce(
        (sum, item) => sum + item.price,
        0,
    );
    const customer = findCurrentCustomerRecord(shop, decoded);
    const customerName = String(customer?.fullName || "").trim();
    const customerPhone = String(customer?.phone || "").trim();
    const customerEmail = String(customer?.email || decoded.email || "").trim();

    if (!customer || !customerName || !customerPhone) {
      return json(response, 409, {
        ok: false,
        message: "customer-profile-missing",
      });
    }

    const appointmentRef = db.ref(`shops/${shopId}/appointments`).push();
    const appointmentId = String(appointmentRef.key || "");
    const barberName = String(barber?.name || "").trim();
    const serviceLabels = [
      ...selectedServices.map((item) => item.label),
      ...selectedAddOns.map((item) => item.label),
    ];
    const appointmentRecord = {
      id: appointmentId,
      customerUid: decoded.uid,
      customerName,
      customerPhone,
      customerEmail,
      barberId,
      barberName,
      date: dateText,
      time: startTime,
      services: serviceLabels,
      serviceKeys,
      addOnKeys,
      totalPrice,
      totalMinutes,
      status: autoConfirmAppointments ? "confirmed" : "pending",
      ...(autoConfirmAppointments ? {confirmedAt: new Date().toISOString()} : {}),
      occupiedSlots: [],
      createdAt: new Date().toISOString(),
      shopId,
      shopName: resolveShopDisplayName(shop),
    };

    // Re-check and write inside one RTDB transaction. A separate availability
    // read followed by set() lets two simultaneous customers reserve a slot.
    let matchedSlot = null;
    const appointmentsRef = db.ref(`shops/${shopId}/appointments`);
    const transactionResult = await appointmentsRef.transaction((currentRaw) => {
      const currentAppointments = normalizeAppointmentMap(currentRaw, slotMinutes);
      const availableSlots = computeAvailableSlots({
        days,
        appointments: currentAppointments,
        appointmentsPerSlot,
        slotCapacityOverrides,
        closedDateOverrides,
        barberSchedules,
        barberId,
        dateText,
        requiredMinutes: totalMinutes,
      });
      matchedSlot = availableSlots.find((slot) => slot.startTime === startTime) ||
        null;
      if (!matchedSlot) {
        return currentRaw;
      }
      return {
        ...(currentRaw && typeof currentRaw === "object" ? currentRaw : {}),
        [appointmentId]: {
          ...appointmentRecord,
          occupiedSlots: matchedSlot.occupiedSlots,
        },
      };
    });

    if (!transactionResult.committed || !matchedSlot) {
      const currentAppointments = normalizeAppointmentMap(
          transactionResult.snapshot.val(),
          slotMinutes,
      );
      return json(response, 409, {
        ok: false,
        message: "slot-no-longer-available",
        suggestions: buildBookingFallbackSuggestions({
          shop,
          days,
          appointments: currentAppointments,
          appointmentsPerSlot,
          slotCapacityOverrides,
          closedDateOverrides,
          barberSchedules,
          barberId,
          dateText,
          requiredMinutes: totalMinutes,
          preferredStartTime: startTime,
        }),
      });
    }

    const refreshedAppointments = normalizeAppointmentMap(
        transactionResult.snapshot.val(),
        slotMinutes,
    );

    await refreshAvailabilityForDate({
      db,
      shopId,
      shop,
      days,
      slotMinutes,
      appointmentsPerSlot,
      slotCapacityOverrides,
      closedDateOverrides,
      barberSchedules,
      serviceDurations,
      appointments: refreshedAppointments,
      dateText,
      barberIds: [barberId],
    });

    await sendOwnerNewBookingNotification({
      shopId,
      shop,
      appointment: {
        id: appointmentId,
        customerName,
        barberName,
        date: dateText,
        time: startTime,
        services: serviceLabels,
      },
    });

    if (autoConfirmAppointments) {
      await sendCustomerLifecycleNotification({
        shopId,
        shop,
        appointment: appointmentRecord,
        eventType: "confirmed",
      });
    }

    return json(response, 200, {
      ok: true,
      appointmentId,
      status: appointmentRecord.status,
      occupiedSlots: matchedSlot.occupiedSlots,
      totalMinutes,
      totalPrice,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});
exports.barberoCancelAppointment = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const shopId = request.body?.shopId;
    const appointmentId = request.body?.appointmentId;
    const shopAccessToken = String(request.body?.shopAccessToken || "").trim();
    const customerAppMode = String(
        request.body?.customerAppMode || "",
    ).trim();

    if (!shopId || !appointmentId) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const {
      db,
      shop,
      days,
      slotMinutes,
      appointmentsPerSlot,
      slotCapacityOverrides,
      closedDateOverrides,
      barberSchedules,
      serviceDurations,
      appointments,
      appointmentSettings,
    } = await loadShopContext(shopId);

    if (!hasActiveShopSubscription(shop)) {
      return json(response, 402, {
        ok: false,
        message: "subscription-required",
      });
    }

    const customerAccess = validateCustomerAppRequest({
      shop,
      decoded,
      shopId,
      accessToken: shopAccessToken,
      requestedMode: customerAppMode,
    });
    if (!customerAccess.ok) {
      return json(response, 403, {
        ok: false,
        message: customerAccess.message,
      });
    }

    const appointment = appointments.find((item) => item.id === appointmentId);
    if (!appointment) {
      return json(response, 404, {ok: false, message: "appointment-not-found"});
    }

    const currentCustomerEntry = findCurrentCustomerEntry(shop, decoded);
    if (!appointmentBelongsToCustomer({
      appointment,
      customerEntry: currentCustomerEntry,
      customerFullName: currentCustomerEntry?.customer?.fullName || decoded.name || "",
      customerShortName: currentCustomerEntry?.customer?.fullName ?
        String(currentCustomerEntry.customer.fullName).trim().split(/\s+/)[0] :
        (decoded.name ? String(decoded.name).trim().split(/\s+/)[0] : ""),
    })) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const appointmentStatus = normalizeAppointmentStatus(appointment.status);
    if (appointmentStatus === "cancelled") {
      return json(response, 200, {
        ok: true,
        appointmentId,
        status: "cancelled",
      });
    }
    if (!['pending', 'confirmed'].includes(appointmentStatus)) {
      return json(response, 409, {
        ok: false,
        message: "appointment-cannot-be-cancelled",
      });
    }

    const cancellationCutoffMinutes =
      appointmentSettings.customerCancellationCutoffMinutes;
    const remainingMinutes = minutesUntilAppointment(appointment);
    if (cancellationCutoffMinutes > 0 &&
        (remainingMinutes === null || remainingMinutes < cancellationCutoffMinutes)) {
      return json(response, 409, {
        ok: false,
        message: "cancellation-window-closed",
        cutoffMinutes: cancellationCutoffMinutes,
      });
    }

    let updatedAppointment = null;
    let cancellationConflict = false;
    const cancelTransaction = await db.ref(
        `shops/${shopId}/appointments/${appointmentId}`,
    ).transaction((currentRaw) => {
      if (!currentRaw || typeof currentRaw !== "object") {
        cancellationConflict = true;
        return currentRaw;
      }
      const currentStatus = normalizeAppointmentStatus(currentRaw.status);
      if (!isAllowedAppointmentStatusTransition(currentStatus, "cancelled")) {
        cancellationConflict = true;
        return currentRaw;
      }
      const nowIso = new Date().toISOString();
      const nextRecord = {
        ...currentRaw,
        status: "cancelled",
        cancelledAt: nowIso,
        cancelledBy: "customer",
        updatedAt: nowIso,
      };
      updatedAppointment = normalizeAppointmentRecord(
          appointmentId,
          nextRecord,
          slotMinutes,
      );
      return nextRecord;
    });
    if (!cancelTransaction.committed || !updatedAppointment) {
      return json(response, 409, {
        ok: false,
        message: cancellationConflict ?
          "appointment-cannot-be-cancelled" :
          "appointment-cancellation-failed",
      });
    }

    const refreshedAppointments = appointments
        .filter((item) => item.id !== appointmentId)
        .concat([updatedAppointment]);
    await refreshAvailabilityForDate({
      db,
      shopId,
      shop,
      days,
      slotMinutes,
      appointmentsPerSlot,
      slotCapacityOverrides,
      closedDateOverrides,
      barberSchedules,
      serviceDurations,
      appointments: refreshedAppointments,
      dateText: appointment.date,
      barberIds: [appointment.barberId],
    });

    await sendOwnerAppointmentLifecycleNotification({
      shopId,
      shop,
      appointment: {
        ...updatedAppointment,
      },
      eventType: "cancelled",
    });

    return json(response, 200, {
      ok: true,
      appointmentId,
      status: "cancelled",
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoCreateManualAppointment = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = request.body?.shopId || decoded.uid;
    const payload = request.body?.appointment || {};
    const requestedBarberId = String(payload.barberId || "").trim();
    const dateText = String(payload.date || "").trim();
    const startTime = String(payload.startTime || "").trim();
    const blocked = payload.blocked === true;
    const customerName = String(payload.customerName || "").trim();
    const customerPhone = String(payload.customerPhone || "").trim();
    const customerEmail = String(payload.customerEmail || "").trim().toLowerCase();
    const serviceKey = String(payload.serviceKey || "").trim();
    const addOnKeys = Array.isArray(payload.addOnKeys) ?
      payload.addOnKeys.map((item) => String(item || "").trim()).filter(Boolean) :
      [];
    const serviceLabel = String(payload.serviceLabel || "").trim();
    const blockReason = String(payload.blockReason || "").trim();
    const explicitMinutes = Number.parseInt(payload.totalMinutes, 10);
    const explicitPrice = Number.parseInt(payload.totalPrice, 10);

    if (!requestedBarberId || !dateText || !parseDashboardDateKey(dateText) ||
        !isValidTimeText(startTime)) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const access = await authorizeBarberoAccess(decoded, requestedShopId);
    if (!access.permissions.manageAllAppointments &&
        !access.permissions.manageOwnAppointments) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    if (!access.permissions.manageAllAppointments &&
        requestedBarberId !== String(access.crewId || "").trim()) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    const shopId = access.shopId;

    const {
      db,
      shop,
      days,
      slotMinutes,
      appointmentsPerSlot,
      slotCapacityOverrides,
      closedDateOverrides,
      barberSchedules,
      serviceDurations,
      servicePrices,
      serviceAddOns,
      appointments,
    } = await loadShopContext(shopId);

    const barber = findShopBarberById(shop, requestedBarberId);
    if (!isBookableShopBarber(shop, requestedBarberId)) {
      return json(response, 404, {ok: false, message: "barber-not-found"});
    }

    const unavailableServiceKeys = blocked ? [] : unavailableServiceKeysForBarber(
        serviceKey ? [serviceKey] : [],
        serviceDurations,
        requestedBarberId,
    );
    if (unavailableServiceKeys.length > 0) {
      return json(response, 409, {
        ok: false,
        message: "service-not-available-for-barber",
        serviceKeys: unavailableServiceKeys,
      });
    }

    const unavailableAddOnKeys = blocked ? [] : unavailableAddOnKeysForSelection(
        addOnKeys,
        serviceKey ? [serviceKey] : [],
        serviceAddOns,
    );
    if (unavailableAddOnKeys.length > 0) {
      return json(response, 409, {
        ok: false,
        message: "add-on-not-available",
        addOnKeys: unavailableAddOnKeys,
      });
    }

    const selectedServices = blocked ? [] : buildServiceSelection(
        serviceKey ? [serviceKey] : [],
        serviceDurations,
        servicePrices,
    );
    const selectedAddOns = blocked ? [] : buildAddOnSelection(
        addOnKeys,
        serviceKey ? [serviceKey] : [],
        serviceAddOns,
    );
    const configuredMinutes = [...selectedServices, ...selectedAddOns].reduce(
        (sum, item) => sum + item.minutes,
        0,
    );
    const configuredPrice = [...selectedServices, ...selectedAddOns].reduce(
        (sum, item) => sum + item.price,
        0,
    );
    const totalMinutes = Math.max(
        5,
        configuredMinutes > 0 ?
          configuredMinutes :
        explicitMinutes > 0 ?
          explicitMinutes :
          slotMinutes,
    );
    const fallbackPrice = Number.isFinite(explicitPrice) && explicitPrice >= 0 ?
      explicitPrice :
      0;
    const totalPrice = blocked ?
      0 :
      configuredMinutes > 0 ? configuredPrice : fallbackPrice;
    const availableSlots = computeAvailableSlots({
      days,
      appointments,
      appointmentsPerSlot,
      slotCapacityOverrides,
      closedDateOverrides,
      barberSchedules,
      barberId: requestedBarberId,
      dateText,
      requiredMinutes: totalMinutes,
    });
    const matchedSlot = availableSlots.find((slot) => slot.startTime === startTime);
    if (!matchedSlot) {
      return json(response, 409, {
        ok: false,
        message: "slot-no-longer-available",
      });
    }

    const appointmentRef = db.ref(`shops/${shopId}/appointments`).push();
    const appointmentId = String(appointmentRef.key || "");
    let customerUid = "";
    const selectedLabels = [
      ...selectedServices.map((item) => item.label),
      ...selectedAddOns.map((item) => item.label),
    ];
    const effectiveServiceLabel = blocked ?
      "Blocked Slot" :
      (selectedLabels.join(" + ") || serviceLabel || "Manual Appointment");
    const nowIso = new Date().toISOString();
    const appointmentRecord = {
      id: appointmentId,
      customerUid,
      customerName: blocked ? "Blocked Slot" : customerName,
      customerPhone: blocked ? "" : customerPhone,
      customerEmail: blocked ? "" : customerEmail,
      barberId: requestedBarberId,
      barberName: barber.name,
      date: dateText,
      time: startTime,
      services: [effectiveServiceLabel],
      serviceKeys: blocked || !serviceKey ? [] : [serviceKey],
      addOnKeys: blocked ? [] : addOnKeys,
      totalPrice,
      totalMinutes,
      occupiedSlots: matchedSlot.occupiedSlots,
      status: "confirmed",
      blocked,
      blockReason,
      createdAt: nowIso,
      updatedAt: nowIso,
      manualCreatedBy: String(decoded.uid || "").trim(),
    };

    // Manual appointments use the same atomic slot check as online bookings.
    // This prevents two staff devices from creating overlapping appointments.
    const appointmentsRef = db.ref(`shops/${shopId}/appointments`);
    let committedSlot = matchedSlot;
    const transactionResult = await appointmentsRef.transaction((currentRaw) => {
      const currentAppointments = normalizeAppointmentMap(currentRaw, slotMinutes);
      const availableSlots = computeAvailableSlots({
        days,
        appointments: currentAppointments,
        appointmentsPerSlot,
        slotCapacityOverrides,
        closedDateOverrides,
        barberSchedules,
        barberId: requestedBarberId,
        dateText,
        requiredMinutes: totalMinutes,
      });
      committedSlot = availableSlots.find((slot) => slot.startTime === startTime) ||
        null;
      if (!committedSlot) {
        return currentRaw;
      }
      return {
        ...(currentRaw && typeof currentRaw === "object" ? currentRaw : {}),
        [appointmentId]: {
          ...appointmentRecord,
          occupiedSlots: committedSlot.occupiedSlots,
        },
      };
    });

    if (!transactionResult.committed || !committedSlot) {
      return json(response, 409, {
        ok: false,
        message: "slot-no-longer-available",
      });
    }

    if (!blocked) {
      try {
        customerUid = await findOrCreateManualCustomer({
          db,
          shopId,
          customerName,
          customerPhone,
          customerEmail,
        });
        if (customerUid) {
          await appointmentRef.update({customerUid});
        }
      } catch (error) {
        await appointmentRef.remove().catch(() => {});
        throw error;
      }
    }

    const refreshedAppointments = normalizeAppointmentMap(
        transactionResult.snapshot.val(),
        slotMinutes,
    );

    await refreshAvailabilityForDate({
      db,
      shopId,
      shop,
      days,
      slotMinutes,
      appointmentsPerSlot,
      slotCapacityOverrides,
      barberSchedules,
      serviceDurations,
      appointments: refreshedAppointments,
      dateText,
      barberIds: [requestedBarberId],
    });

    return json(response, 200, {
      ok: true,
       appointmentId,
      blocked,
      customerUid,
      barberId: requestedBarberId,
      barberName: barber.name,
      date: dateText,
      startTime,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoUpdateAppointmentStatus = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = request.body?.shopId || decoded.uid;
    const appointmentId = request.body?.appointmentId;
    const requestedStatus = String(request.body?.status || "").trim().toLowerCase();
    if (!isKnownAppointmentStatus(requestedStatus)) {
      return json(response, 400, {ok: false, message: "invalid-appointment-status"});
    }
    const nextStatus = requestedStatus;

    if (!requestedShopId || !appointmentId) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const access = await authorizeBarberoAccess(decoded, requestedShopId);
    if (!access.permissions.manageAllAppointments &&
        !access.permissions.manageOwnAppointments) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    const shopId = access.shopId;

    const {
      db,
      shop,
      days,
      slotMinutes,
      appointmentsPerSlot,
      slotCapacityOverrides,
      closedDateOverrides,
      barberSchedules,
      serviceDurations,
      appointments,
    } = await loadShopContext(shopId);

    if (!hasActiveShopSubscription(shop)) {
      return json(response, 402, {
        ok: false,
        message: "subscription-required",
      });
    }

    const appointment = appointments.find((item) => item.id === appointmentId);
    if (!appointment) {
      return json(response, 404, {ok: false, message: "appointment-not-found"});
    }
    if (!access.permissions.manageAllAppointments &&
        String(appointment.barberId || "").trim() !== String(access.crewId || "").trim()) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    let previousAppointment = appointment;
    let updatedAppointment = null;
    let statusConflict = false;
    const statusTransaction = await db.ref(
        `shops/${shopId}/appointments/${appointmentId}`,
    ).transaction((currentRaw) => {
      if (!currentRaw || typeof currentRaw !== "object") {
        previousAppointment = null;
        statusConflict = true;
        return currentRaw;
      }
      const currentStatus = normalizeAppointmentStatus(currentRaw.status);
      if (!isAllowedAppointmentStatusTransition(currentStatus, nextStatus)) {
        previousAppointment = normalizeAppointmentRecord(
            appointmentId,
            currentRaw,
            slotMinutes,
        );
        statusConflict = true;
        return currentRaw;
      }
      const nowIso = new Date().toISOString();
      const nextRecord = {
        ...currentRaw,
        status: nextStatus,
        updatedAt: nowIso,
        ...(nextStatus === "cancelled" ? {
          cancelledAt: nowIso,
          cancelledBy: "owner",
        } : {}),
        ...(nextStatus === "confirmed" ? {
          confirmedAt: nowIso,
        } : {}),
      };
      updatedAppointment = normalizeAppointmentRecord(
          appointmentId,
          nextRecord,
          slotMinutes,
      );
      previousAppointment = normalizeAppointmentRecord(
          appointmentId,
          currentRaw,
          slotMinutes,
      );
      return nextRecord;
    });
    if (!statusTransaction.committed || !updatedAppointment) {
      if (!previousAppointment) {
        return json(response, 404, {ok: false, message: "appointment-not-found"});
      }
      return json(response, 409, {
        ok: false,
        message: statusConflict ? "appointment-status-conflict" : "appointment-status-update-failed",
      });
    }

    const refreshedAppointments = appointments
        .filter((item) => item.id !== appointmentId)
        .concat([updatedAppointment]);

    if (
       isAppointmentBlockingStatus(previousAppointment.status) !==
       isAppointmentBlockingStatus(nextStatus)
    ) {
      await refreshAvailabilityForDate({
        db,
        shopId,
        shop,
        days,
        slotMinutes,
        appointmentsPerSlot,
        slotCapacityOverrides,
        barberSchedules,
        serviceDurations,
        appointments: refreshedAppointments,
         dateText: previousAppointment.date,
         barberIds: [previousAppointment.barberId],
      });
    }

    if (
      nextStatus === "confirmed" ||
      nextStatus === "cancelled" ||
      nextStatus === "completed" ||
      nextStatus === "no_show"
    ) {
      await sendCustomerLifecycleNotification({
        shopId,
        shop,
        appointment: {
          ...updatedAppointment,
        },
        eventType: nextStatus,
      });
    }

    return json(response, 200, {
      ok: true,
      appointmentId,
      status: nextStatus,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoCustomerRescheduleAppointment = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const shopId = request.body?.shopId;
    const appointmentId = request.body?.appointmentId;
    const shopAccessToken = String(request.body?.shopAccessToken || "").trim();
    const customerAppMode = String(
        request.body?.customerAppMode || "",
    ).trim();
    const nextBarberId = request.body?.barberId;
    const nextDateText = request.body?.date;
    const nextStartTime = request.body?.startTime;

    if (!shopId || !appointmentId || !nextBarberId || !nextDateText ||
        !parseDashboardDateKey(nextDateText) || !isValidTimeText(nextStartTime)) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const {
      db,
      shop,
      days,
      slotMinutes,
      appointmentsPerSlot,
      slotCapacityOverrides,
      closedDateOverrides,
      barberSchedules,
      serviceDurations,
      appointments,
      appointmentSettings,
    } = await loadShopContext(shopId);

    if (!hasActiveShopSubscription(shop)) {
      return json(response, 402, {
        ok: false,
        message: "subscription-required",
      });
    }

    const customerAccess = validateCustomerAppRequest({
      shop,
      decoded,
      shopId,
      accessToken: shopAccessToken,
      requestedMode: customerAppMode,
    });
    if (!customerAccess.ok) {
      return json(response, 403, {
        ok: false,
        message: customerAccess.message,
      });
    }

    const appointment = appointments.find((item) => item.id === appointmentId);
    if (!appointment) {
      return json(response, 404, {ok: false, message: "appointment-not-found"});
    }

    const currentCustomerEntry = findCurrentCustomerEntry(shop, decoded);
    if (!appointmentBelongsToCustomer({
      appointment,
      customerEntry: currentCustomerEntry,
      customerFullName: currentCustomerEntry?.customer?.fullName || decoded.name || "",
      customerShortName: currentCustomerEntry?.customer?.fullName ?
        String(currentCustomerEntry.customer.fullName).trim().split(/\s+/)[0] :
        (decoded.name ? String(decoded.name).trim().split(/\s+/)[0] : ""),
    })) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const appointmentStatus = normalizeAppointmentStatus(appointment.status);
    if (!['pending', 'confirmed'].includes(appointmentStatus)) {
      return json(response, 409, {
        ok: false,
        message: "appointment-cannot-be-rescheduled",
      });
    }
    const rescheduleCutoffMinutes =
      appointmentSettings.customerRescheduleCutoffMinutes;
    const remainingMinutes = minutesUntilAppointment(appointment);
    if (rescheduleCutoffMinutes > 0 &&
        (remainingMinutes === null || remainingMinutes < rescheduleCutoffMinutes)) {
      return json(response, 409, {
        ok: false,
        message: "reschedule-window-closed",
        cutoffMinutes: rescheduleCutoffMinutes,
      });
    }
    if (!isBookableShopBarber(shop, nextBarberId)) {
      return json(response, 404, {ok: false, message: "barber-not-found"});
    }

    const requiredMinutes = appointment.totalMinutes > 0 ?
      appointment.totalMinutes :
      slotMinutes;
    const nextBarberName = String(
        findShopBarberById(shop, nextBarberId)?.name || "",
    ).trim();
    const appointmentsRef = db.ref(`shops/${shopId}/appointments`);
    let matchedSlot = null;
    const transactionResult = await appointmentsRef.transaction((currentRaw) => {
      const currentAppointments = normalizeAppointmentMap(currentRaw, slotMinutes);
      const currentAppointment = currentAppointments.find(
          (item) => item.id === appointmentId,
      );
      if (!currentAppointment || !['pending', 'confirmed'].includes(
          normalizeAppointmentStatus(currentAppointment.status))) {
        matchedSlot = null;
        return currentRaw;
      }
      const appointmentsWithoutCurrent = currentAppointments.filter(
          (item) => item.id !== appointmentId,
      );
      const availableSlots = computeAvailableSlots({
        days,
        appointments: appointmentsWithoutCurrent,
        appointmentsPerSlot,
        slotCapacityOverrides,
        closedDateOverrides,
        barberSchedules,
        barberId: nextBarberId,
        dateText: nextDateText,
        requiredMinutes,
      });
      matchedSlot = availableSlots.find(
          (slot) => slot.startTime === nextStartTime,
      ) || null;
      if (!matchedSlot) {
        return currentRaw;
      }
      return {
        ...(currentRaw && typeof currentRaw === "object" ? currentRaw : {}),
        [appointmentId]: {
          ...(currentRaw?.[appointmentId] || {}),
          barberId: nextBarberId,
          barberName: nextBarberName,
          date: nextDateText,
          time: nextStartTime,
          totalMinutes: requiredMinutes,
          occupiedSlots: matchedSlot.occupiedSlots,
          remindersSent: null,
          updatedAt: new Date().toISOString(),
        },
      };
    });
    if (!transactionResult.committed || !matchedSlot) {
      return json(response, 409, {
        ok: false,
        message: "slot-no-longer-available",
      });
    }
    const refreshedAppointments = normalizeAppointmentMap(
        transactionResult.snapshot.val(),
        slotMinutes,
    );

    const datesToRefresh = Array.from(new Set([appointment.date, nextDateText]));
    for (const dateText of datesToRefresh) {
      await refreshAvailabilityForDate({
        db,
        shopId,
        shop,
        days,
        slotMinutes,
        appointmentsPerSlot,
        slotCapacityOverrides,
        barberSchedules,
        serviceDurations,
        appointments: refreshedAppointments,
        dateText,
        barberIds: [appointment.barberId, nextBarberId],
      });
    }

    await sendCustomerLifecycleNotification({
      shopId,
      shop,
      appointment: {
        ...appointment,
        barberId: nextBarberId,
        barberName: nextBarberName,
        date: nextDateText,
        time: nextStartTime,
        totalMinutes: requiredMinutes,
        occupiedSlots: matchedSlot.occupiedSlots,
      },
      eventType: "rescheduled",
    });
    await sendOwnerAppointmentLifecycleNotification({
      shopId,
      shop,
      appointment: {
        ...appointment,
        barberId: nextBarberId,
        barberName: nextBarberName,
        date: nextDateText,
        time: nextStartTime,
        totalMinutes: requiredMinutes,
        occupiedSlots: matchedSlot.occupiedSlots,
      },
      eventType: "rescheduled",
    });

    return json(response, 200, {
      ok: true,
      appointmentId,
      barberId: nextBarberId,
      date: nextDateText,
      startTime: nextStartTime,
      occupiedSlots: matchedSlot.occupiedSlots,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoRescheduleAppointment = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = request.body?.shopId || decoded.uid;
    const appointmentId = request.body?.appointmentId;
    const nextBarberId = request.body?.barberId;
    const nextDateText = request.body?.date;
    const nextStartTime = request.body?.startTime;

    if (!requestedShopId || !appointmentId || !nextBarberId || !nextDateText ||
        !parseDashboardDateKey(nextDateText) || !isValidTimeText(nextStartTime)) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const access = await authorizeBarberoAccess(decoded, requestedShopId);
    if (!access.permissions.manageAllAppointments &&
        !access.permissions.manageOwnAppointments) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    const shopId = access.shopId;

    const {
      db,
      shop,
      days,
      slotMinutes,
      appointmentsPerSlot,
      slotCapacityOverrides,
      closedDateOverrides,
      barberSchedules,
      serviceDurations,
      appointments,
    } = await loadShopContext(shopId);

    const appointment = appointments.find((item) => item.id === appointmentId);
    if (!appointment) {
      return json(response, 404, {ok: false, message: "appointment-not-found"});
    }
    const appointmentStatus = normalizeAppointmentStatus(appointment.status);
    if (!['pending', 'confirmed'].includes(appointmentStatus)) {
      return json(response, 409, {
        ok: false,
        message: "appointment-cannot-be-rescheduled",
      });
    }
    if (!isBookableShopBarber(shop, nextBarberId)) {
      return json(response, 404, {ok: false, message: "barber-not-found"});
    }
    if (!access.permissions.manageAllAppointments &&
        String(appointment.barberId || "").trim() !== String(access.crewId || "").trim()) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const requiredMinutes = appointment.totalMinutes > 0 ?
      appointment.totalMinutes :
      slotMinutes;
    const nextBarberName = String(
        findShopBarberById(shop, nextBarberId)?.name || "",
    ).trim();
    const appointmentsRef = db.ref(`shops/${shopId}/appointments`);
    let matchedSlot = null;
    const transactionResult = await appointmentsRef.transaction((currentRaw) => {
      const currentAppointments = normalizeAppointmentMap(currentRaw, slotMinutes);
      const currentAppointment = currentAppointments.find(
          (item) => item.id === appointmentId,
      );
      if (!currentAppointment || !['pending', 'confirmed'].includes(
          normalizeAppointmentStatus(currentAppointment.status))) {
        matchedSlot = null;
        return currentRaw;
      }
      const appointmentsWithoutCurrent = currentAppointments.filter(
          (item) => item.id !== appointmentId,
      );
      const availableSlots = computeAvailableSlots({
        days,
        appointments: appointmentsWithoutCurrent,
        appointmentsPerSlot,
        slotCapacityOverrides,
        closedDateOverrides,
        barberSchedules,
        barberId: nextBarberId,
        dateText: nextDateText,
        requiredMinutes,
      });
      matchedSlot = availableSlots.find(
          (slot) => slot.startTime === nextStartTime,
      ) || null;
      if (!matchedSlot) {
        return currentRaw;
      }
      return {
        ...(currentRaw && typeof currentRaw === "object" ? currentRaw : {}),
        [appointmentId]: {
          ...(currentRaw?.[appointmentId] || {}),
          barberId: nextBarberId,
          barberName: nextBarberName,
          date: nextDateText,
          time: nextStartTime,
          totalMinutes: requiredMinutes,
          occupiedSlots: matchedSlot.occupiedSlots,
          remindersSent: null,
          updatedAt: new Date().toISOString(),
        },
      };
    });
    if (!transactionResult.committed || !matchedSlot) {
      return json(response, 409, {
        ok: false,
        message: "slot-no-longer-available",
      });
    }
    const refreshedAppointments = normalizeAppointmentMap(
        transactionResult.snapshot.val(),
        slotMinutes,
    );

    const datesToRefresh = Array.from(new Set([appointment.date, nextDateText]));
    for (const dateText of datesToRefresh) {
      await refreshAvailabilityForDate({
        db,
        shopId,
        shop,
        days,
        slotMinutes,
        appointmentsPerSlot,
        slotCapacityOverrides,
        barberSchedules,
        serviceDurations,
        appointments: refreshedAppointments,
        dateText,
        barberIds: [appointment.barberId, nextBarberId],
      });
    }

    await sendCustomerLifecycleNotification({
      shopId,
      shop,
      appointment: {
        ...appointment,
        barberId: nextBarberId,
        barberName: nextBarberName,
        date: nextDateText,
        time: nextStartTime,
        totalMinutes: requiredMinutes,
        occupiedSlots: matchedSlot.occupiedSlots,
      },
      eventType: "rescheduled",
    });

    return json(response, 200, {
      ok: true,
      appointmentId,
      barberId: nextBarberId,
      date: nextDateText,
      startTime: nextStartTime,
      occupiedSlots: matchedSlot.occupiedSlots,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: safeClientErrorDetails(error),
    });
  }
});

exports.barberoSyncStoreSubscriptions = onSchedule(
    {
      schedule: "every 15 minutes",
      timeZone: "Europe/Athens",
      retryCount: 3,
      maxInstances: 1,
    },
    async () => {
      const db = getDatabase();
      const now = Date.now();
      await ensureBillingSyncIndex(db, now);
      const indexRef = db.ref(BILLING_SYNC_INDEX_PATH);
      const dueSnapshot = await indexRef
          .orderByChild("nextCheckAt")
          .startAt(1)
          .endAt(now)
          .limitToFirst(100)
          .get();
      if (!dueSnapshot.exists()) {
        return;
      }

      for (const [shopId, indexEntry] of Object.entries(
          dueSnapshot.val() || {},
      )) {
        const normalizedShopId = String(shopId || "").trim();
        if (!normalizedShopId || !indexEntry || typeof indexEntry !== "object") {
          continue;
        }
        const shopSnapshot = await db.ref(`shops/${normalizedShopId}`).get();
        if (!shopSnapshot.exists()) {
          await indexRef.child(normalizedShopId).remove();
          continue;
        }
        const shop = shopSnapshot.val() || {};
        const billing = shop.billing && typeof shop.billing === "object" ?
          shop.billing :
          {};
        const shopIndexRef = indexRef.child(normalizedShopId);
        try {
          // Rules use this numeric field because RTDB rules cannot parse ISO dates.
          // Refresh it even when the store credential is unavailable, so an expired
          // legacy record cannot keep direct reads open indefinitely.
          await syncBillingAccessMetadata(db, normalizedShopId, billing);
        } catch (error) {
          console.error(
              `Billing access metadata sync failed for shop ${normalizedShopId}`,
              error,
          );
        }
        let credential;
        try {
          credential = await loadBillingCredential(normalizedShopId);
        } catch (error) {
          console.error(
              `Billing credential load failed for shop ${normalizedShopId}`,
              error,
          );
          await shopIndexRef.update({
            nextCheckAt: Date.now() + BILLING_SYNC_ERROR_RETRY_MS,
            lastError: "billing-credential-load-failed",
            updatedAt: new Date().toISOString(),
          });
          continue;
        }
        if (!credential) {
          const nextIndex = buildBillingSyncIndexRecord(
              normalizedShopId,
              billing,
          );
          nextIndex.nextCheckAt = Date.now() + BILLING_SYNC_EXPIRED_RETRY_MS;
          await shopIndexRef.set(nextIndex);
          continue;
        }
        const platform = normalizeBillingPlatform(
            credential.platform || billing.platform || "",
        );
        const purchaseToken = String(credential.purchaseToken || "").trim();
        const productId = String(
            credential.productId || billing.storeProductId || "",
        ).trim();

        if (!billing.planConfirmed || !platform || !purchaseToken || !productId) {
          const nextIndex = buildBillingSyncIndexRecord(
              normalizedShopId,
              billing,
          );
          nextIndex.nextCheckAt = 0;
          await shopIndexRef.set(nextIndex);
          continue;
        }
        const verifiedPlan = billingPlanFromProductId(productId);
        if (!verifiedPlan) {
          const nextIndex = buildBillingSyncIndexRecord(
              normalizedShopId,
              billing,
          );
          nextIndex.nextCheckAt = Date.now() + BILLING_SYNC_EXPIRED_RETRY_MS;
          nextIndex.lastError = "billing-product-invalid";
          await shopIndexRef.set(nextIndex);
          continue;
        }

        try {
          await claimBillingToken({
            shopId: normalizedShopId,
            platform,
            productId,
            purchaseToken,
          });
          const verifiedPurchase = await verifyStorePurchaseOrThrow({
            platform,
            productId,
            purchaseToken,
          });
          const currentBilling = {
            ...buildDefaultBillingRecord(),
            ...billing,
          };
          const nextBilling = buildVerifiedBillingRecord({
            currentBilling,
            selectedPlan: verifiedPlan,
            verifiedPurchase,
            verificationSource: `${platform}_scheduled_sync`,
            purchaseId: currentBilling.latestPurchaseId,
            transactionDate: currentBilling.latestPurchaseAt,
          });
          nextBilling.latestVerificationDigest =
            buildVerificationDigest(purchaseToken);
          await db.ref(`shops/${normalizedShopId}/billing`).set(nextBilling);
          await shopIndexRef.set(
              buildBillingSyncIndexRecord(normalizedShopId, nextBilling),
          );
        } catch (error) {
          console.error(
              `Subscription sync failed for shop ${normalizedShopId}`,
              error,
          );
          const nowIso = new Date().toISOString();
          await db.ref(`shops/${normalizedShopId}/billing`).update({
            lastStoreSyncAt: new Date().toISOString(),
            lastStoreSyncStatus: error.message ===
              "subscription-token-already-bound" ?
              "token_conflict" :
              "error",
          });
          const nextIndex = buildBillingSyncIndexRecord(
              normalizedShopId,
              billing,
          );
          nextIndex.nextCheckAt = Date.now() + (
            error.message === "subscription-token-already-bound" ?
              BILLING_SYNC_EXPIRED_RETRY_MS :
              BILLING_SYNC_ERROR_RETRY_MS
          );
          nextIndex.lastError = String(error?.message || "subscription-sync-failed")
              .slice(0, 160);
          nextIndex.updatedAt = nowIso;
          await shopIndexRef.set(nextIndex);
        }
      }
    },
);

// Storage rules use custom claims and cannot read the RTDB billing record.
// Membership and billing writes are reconciled by the shop trigger above. Keep
// a daily sweep as a low-cost repair path for time-based expiry or missed events.
exports.barberoRefreshStorageMembershipClaims = onSchedule(
    {
      schedule: "every day 04:10",
      timeZone: "Europe/Athens",
      retryCount: 3,
    },
    async () => {
      try {
        // Read only the compact membership index. The full shops tree is
        // reserved for the one-time index bootstrap and never downloaded by
        // the daily repair path.
        await refreshStorageMembershipClaimsFromIndex(getDatabase());
      } catch (error) {
        console.error("Storage membership claim refresh failed", error);
      }
    },
);

exports.barberoProcessNotificationOutbox = onSchedule(
    {
      schedule: "every 5 minutes",
      timeZone: "Europe/Athens",
      retryCount: 3,
    },
    async () => {
      const db = getDatabase();
      const now = Date.now();
      const outboxRef = db.ref(NOTIFICATION_OUTBOX_PATH);

      const pendingSnapshot = await outboxRef
          .orderByChild("nextAttemptAt")
          .endAt(now)
          .limitToFirst(100)
          .get();
      const staleProcessingSnapshot = await outboxRef
          .orderByChild("lockExpiresAt")
          .endAt(now)
          .limitToFirst(100)
          .get();

      for (const [notificationId, item] of Object.entries(
          pendingSnapshot.val() || {},
      )) {
        if (String(item?.status || "").trim().toLowerCase() !== "pending") {
          continue;
        }
        await processNotificationOutboxItem(
            outboxRef.child(notificationId),
        );
      }

      for (const [notificationId, item] of Object.entries(
          staleProcessingSnapshot.val() || {},
      )) {
        if (String(item?.status || "").trim().toLowerCase() !== "processing") {
          continue;
        }
        await processNotificationOutboxItem(
            outboxRef.child(notificationId),
        );
      }
    },
);

exports.barberoPurgeNotificationOutbox = onSchedule(
    {
      schedule: "every day 03:40",
      timeZone: "Europe/Athens",
      retryCount: 3,
    },
    async () => {
      const db = getDatabase();
      const now = Date.now();
      await ensureNotificationCleanupIndex(db, now);
      const cleanupRef = db.ref(NOTIFICATION_CLEANUP_INDEX_PATH);
      const dueSnapshot = await cleanupRef
          .orderByChild("cleanupAt")
          .startAt(1)
          .endAt(now)
          .limitToFirst(500)
          .get();
      if (!dueSnapshot.exists()) {
        return;
      }

      const deletions = {};
      for (const [indexKey, item] of Object.entries(dueSnapshot.val() || {})) {
        const targetPath = String(item?.targetPath || "").trim();
        if (!targetPath) {
          deletions[`${NOTIFICATION_CLEANUP_INDEX_PATH}/${indexKey}`] = null;
          continue;
        }
        deletions[targetPath] = null;
        deletions[`${NOTIFICATION_CLEANUP_INDEX_PATH}/${indexKey}`] = null;
      }
      if (Object.keys(deletions).length > 0) {
        await db.ref().update(deletions);
      }
    },
);

exports.barberoSendScheduledReminders = onSchedule(
    {
      schedule: "every 30 minutes",
      timeZone: "Europe/Athens",
    },
    async () => {
      const db = getDatabase();
      const now = Date.now();
      await ensureAppointmentReminderIndex(db, now);
      const nowInfo = getAthensNowInfo();

      const dueSnapshot = await db.ref(APPOINTMENT_REMINDER_INDEX_PATH)
          .orderByChild("nextCheckAt")
          .startAt(1)
          .endAt(now)
          .limitToFirst(100)
          .get();
      if (!dueSnapshot.exists()) {
        return;
      }

      const dueByShop = new Map();
      for (const [indexKey, item] of Object.entries(dueSnapshot.val() || {})) {
        const shopId = String(item?.shopId || "").trim();
        const appointmentId = String(item?.appointmentId || "").trim();
        if (!shopId || !appointmentId) {
          continue;
        }
        if (!dueByShop.has(shopId)) {
          dueByShop.set(shopId, []);
        }
        dueByShop.get(shopId).push({indexKey, appointmentId});
      }

      for (const [shopId, dueItems] of dueByShop.entries()) {
        const shopSnapshot = await db.ref(`shops/${shopId}`).get();
        if (!shopSnapshot.exists()) {
          const missingShopUpdates = {};
          for (const {indexKey} of dueItems) {
            missingShopUpdates[
                `${APPOINTMENT_REMINDER_INDEX_PATH}/${indexKey}`
            ] = null;
          }
          await db.ref().update(missingShopUpdates);
          continue;
        }
        const shop = shopSnapshot.val() || {};
        const appointmentSettings = normalizeAppointmentSettings(
            shop.appointmentSettings,
        );
        if (!appointmentSettings.remindersEnabled ||
            !hasActiveShopSubscription(shop)) {
          continue;
        }

        const appointmentsMap = shop.appointments &&
            typeof shop.appointments === "object" ?
          shop.appointments :
          {};
        for (const {indexKey, appointmentId} of dueItems) {
          const rawAppointment = appointmentsMap[appointmentId];
          const appointment = rawAppointment && typeof rawAppointment === "object" ?
            {id: appointmentId, ...rawAppointment} :
            null;
          if (!appointment) {
            await db.ref(
                `${APPOINTMENT_REMINDER_INDEX_PATH}/${indexKey}`,
            ).remove();
            continue;
          }
          appointment.status = normalizeAppointmentStatus(appointment.status);
          appointment.remindersSent = appointment.remindersSent &&
              typeof appointment.remindersSent === "object" ?
            appointment.remindersSent :
            {};
          const reminder = getAppointmentReminderDue(appointment, nowInfo);
          const nextIndex = buildAppointmentReminderIndexRecord({
            shopId,
            appointmentId,
            appointment,
            now,
          });
          if (!nextIndex) {
            await db.ref(
                `${APPOINTMENT_REMINDER_INDEX_PATH}/${indexKey}`,
            ).remove();
            continue;
          }
          if (!reminder) {
            await db.ref(
                `${APPOINTMENT_REMINDER_INDEX_PATH}/${indexKey}`,
            ).set(nextIndex);
            continue;
          }

          const sent = await sendCustomerReminderNotification({
            shopId,
            shop,
            appointment,
            reminder,
          });
          if (!sent) {
            continue;
          }

          const sentAt = new Date().toISOString();
          await db.ref(
              `shops/${shopId}/appointments/${appointment.id}/remindersSent/${reminder.key}`,
          ).set(sentAt);
          const updatedIndex = buildAppointmentReminderIndexRecord({
            shopId,
            appointmentId,
            appointment: {
              ...appointment,
              remindersSent: {
                ...appointment.remindersSent,
                [reminder.key]: sentAt,
              },
            },
            now,
          });
          const indexPath = `${APPOINTMENT_REMINDER_INDEX_PATH}/${indexKey}`;
          if (updatedIndex) {
            await db.ref(indexPath).set(updatedIndex);
          } else {
            await db.ref(indexPath).remove();
          }
        }
      }
    },
);

exports.barberoPurgeDeletionAudit = onSchedule(
    {
      schedule: "every 24 hours",
      timeZone: "Europe/Athens",
      retryCount: 3,
    },
    async () => {
      const db = getDatabase();
      const auditSnapshot = await db.ref(DELETION_AUDIT_PATH).get();
      const cleanupUpdates = {};
      const now = Date.now();

      if (auditSnapshot.exists()) {
        const auditEntries = auditSnapshot.val() || {};
        for (const [auditId, audit] of Object.entries(auditEntries)) {
          const expiresAt = Date.parse(String(audit?.expiresAt || ""));
          if (!Number.isFinite(expiresAt) || expiresAt <= now) {
            cleanupUpdates[`${DELETION_AUDIT_PATH}/${auditId}`] = null;
          }
        }
      }

      // Remove archives written by older versions. New deletion flows never
      // write full account, shop, customer, appointment or billing records.
      for (const legacyPath of LEGACY_DELETION_ARCHIVE_PATHS) {
        cleanupUpdates[legacyPath] = null;
      }

      if (Object.keys(cleanupUpdates).length > 0) {
        await db.ref().update(cleanupUpdates);
      }
    },
);

// Legacy customer endpoint aliases were intentionally retired. All active
// clients use the barbero* functions above.


