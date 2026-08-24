/* eslint-disable no-console */
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getDatabase} = require("firebase-admin/database");

const PROJECT_ID = String(
    process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "",
).trim();
const AUTH_EMULATOR_HOST = String(
    process.env.FIREBASE_AUTH_EMULATOR_HOST || "",
).trim();
const DATABASE_EMULATOR_HOST = String(
    process.env.FIREBASE_DATABASE_EMULATOR_HOST || "",
).trim();
const FUNCTIONS_EMULATOR = String(
    process.env.FUNCTIONS_EMULATOR || "",
).trim();

if (PROJECT_ID !== "demo-barberin-e2e" ||
    !AUTH_EMULATOR_HOST ||
    !DATABASE_EMULATOR_HOST ||
    !FUNCTIONS_EMULATOR) {
  throw new Error(
      "E2E tests require the demo-barberin-e2e Auth, Database and Functions emulators.",
  );
}

const databaseUrl = `http://${DATABASE_EMULATOR_HOST}?ns=${PROJECT_ID}`;
const functionsBaseUrl =
  `http://127.0.0.1:5001/${PROJECT_ID}/europe-west1`;
const authApiBaseUrl =
  `http://${AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts`;
const shopAId = "e2e_shop_a";
const shopBId = "e2e_shop_b";
const customerEmail = "customer-a@e2e.invalid";
const customerPassword = "E2e-Customer-Password-123!";
const ownerEmail = "owner-a@e2e.invalid";
const ownerPassword = "E2e-Owner-Password-123!";
const customerAppMode = "separate";
const shopAAccessToken = "e2e-shop-a-access-token";
const shopBAccessToken = "e2e-shop-b-access-token";
const barberId = "e2e_barber_a";
const firstDate = "2099-01-03";
const rescheduledDate = "2099-01-04";

const firebaseApp = initializeApp({
  projectId: PROJECT_ID,
  databaseURL: databaseUrl,
});
const db = getDatabase(firebaseApp);
const auth = getAuth(firebaseApp);

function activeBilling() {
  return {
    status: "trialing",
    planConfirmed: false,
    selectedPlan: "monthly",
    trialEndsAt: "2099-12-31T23:59:59.000Z",
    accessUntilMillis: Date.parse("2099-12-31T23:59:59.000Z"),
    currentPeriodEnd: "2099-12-31T23:59:59.000Z",
    graceUntil: "",
  };
}

function weeklySchedule() {
  const names = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
  ];
  return {
    slotMinutes: 30,
    appointmentsPerSlot: 1,
    showPrices: true,
    days: names.map((name) => ({
      name,
      enabled: true,
      start: "09:00",
      end: "17:00",
      breakStart: "--:--",
      breakEnd: "--:--",
    })),
    serviceDurations: [{
      key: "classic_haircut",
      label: "Classic Haircut",
      minutes: 30,
      enabled: true,
    }],
    servicePrices: [{
      key: "classic_haircut",
      label: "Classic Haircut",
      price: 15,
    }],
    serviceAddOns: [],
  };
}

function shopRecord({shopId, shopName, ownerUid, customerUid, accessToken}) {
  return {
    id: shopId,
    shopName,
    ownerName: "E2E Owner",
    ownerEmail,
    ownerUserUid: ownerUid,
    address: `${shopName} Street 1, Athens`,
    city: "Athens",
    billing: activeBilling(),
    customerApp: {
      mode: customerAppMode,
      accessToken,
      status: "built",
      displayName: shopName,
    },
    notificationTokens: {
      e2eOwnerToken: {
        token: "e2e-owner-fcm-token",
        platform: "android",
      },
    },
    appointmentSettings: {
      autoConfirmAppointments: true,
      remindersEnabled: false,
      customerCancellationCutoffMinutes: 0,
      customerRescheduleCutoffMinutes: 0,
    },
    weekly_schedule: weeklySchedule(),
    barbers: {
      [barberId]: {
        id: barberId,
        authUid: ownerUid,
        name: "E2E Barber",
        email: ownerEmail,
        role: "Owner",
        status: "active",
        specialties: ["classic_haircut"],
      },
    },
    customers: {
      [customerUid]: {
        uid: customerUid,
        fullName: "E2E Customer",
        email: customerEmail,
        phone: "6900000000",
        shopId,
        shopName,
      },
    },
    appointments: {},
  };
}

async function signIn(email, password) {
  const response = await fetch(
      `${authApiBaseUrl}:signInWithPassword?key=fake-api-key`,
      {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({email, password, returnSecureToken: true}),
      },
  );
  const body = await response.json();
  assert.equal(
      response.ok,
      true,
      `emulator login failed for ${email}: ${JSON.stringify(body)}`,
  );
  return body.idToken;
}

async function callFunction(name, idToken, payload = {}) {
  const response = await fetch(`${functionsBaseUrl}/${name}`, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({idToken, ...payload}),
  });
  const rawBody = await response.text();
  let body = {};
  try {
    body = JSON.parse(rawBody);
  } catch (_) {
    body = {raw: rawBody};
  }
  return {status: response.status, body};
}

function customerRequest(shopId, accessToken, extra = {}) {
  return {
    shopId,
    shopAccessToken: accessToken,
    customerAppMode,
    ...extra,
  };
}

async function createUsers() {
  const owner = await auth.createUser({
    email: ownerEmail,
    password: ownerPassword,
    displayName: "E2E Owner",
  });
  const customer = await auth.createUser({
    email: customerEmail,
    password: customerPassword,
    displayName: "E2E Customer",
  });
  return {owner, customer};
}

async function seedFixture(owner, customer) {
  await db.ref().set({
    shops: {
      [shopAId]: shopRecord({
        shopId: shopAId,
        shopName: "E2E Shop A",
        ownerUid: owner.uid,
        customerUid: customer.uid,
        accessToken: shopAAccessToken,
      }),
      [shopBId]: shopRecord({
        shopId: shopBId,
        shopName: "E2E Shop B",
        ownerUid: owner.uid,
        customerUid: "e2e_other_customer",
        accessToken: shopBAccessToken,
      }),
    },
  });
}

async function run() {
  let owner;
  let customer;
  try {
    ({owner, customer} = await createUsers());
    await seedFixture(owner, customer);

    // Login and owner shell/session resolution.
    const ownerToken = await signIn(ownerEmail, ownerPassword);
    const ownerSession = await callFunction(
        "barberoResolveSession",
        ownerToken,
        {activeShopId: shopAId},
    );
    assert.equal(ownerSession.status, 200, JSON.stringify(ownerSession.body));
    assert.equal(ownerSession.body.session.shopId, shopAId);
    assert.deepEqual(
        ownerSession.body.shops.map((shop) => shop.shopId).sort(),
        [shopAId, shopBId].sort(),
    );

    // Customer login and branded shell loading.
    const customerToken = await signIn(customerEmail, customerPassword);
    const shell = await callFunction(
        "barberoGetCustomerShell",
        customerToken,
        customerRequest(shopAId, shopAAccessToken),
    );
    assert.equal(shell.status, 200);
    assert.equal(shell.body.shell.shopId, shopAId);

    // Availability before booking contains the selected slot.
    const availabilityBefore = await callFunction(
        "barberoGetAvailability",
        customerToken,
        customerRequest(shopAId, shopAAccessToken, {
          barberId,
          date: firstDate,
          serviceKeys: ["classic_haircut"],
        }),
    );
    assert.equal(availabilityBefore.status, 200);
    assert.ok(
        availabilityBefore.body.slots.some((slot) => slot.startTime === "10:00"),
    );

    // Register a notification token before booking.
    const notificationToken = await callFunction(
        "barberoSaveNotificationToken",
        customerToken,
        customerRequest(shopAId, shopAAccessToken, {
          tokenKey: "e2e-token-key",
          token: "e2e-fcm-token",
          platform: "android",
        }),
    );
    assert.equal(notificationToken.status, 200);

    // Booking uses the customer profile and auto-confirms in the fixture.
    const booking = await callFunction(
        "barberoBookAppointment",
        customerToken,
        customerRequest(shopAId, shopAAccessToken, {
          barberId,
          date: firstDate,
          startTime: "10:00",
          serviceKeys: ["classic_haircut"],
        }),
    );
    assert.equal(booking.status, 200);
    assert.equal(booking.body.status, "confirmed");
    assert.ok(booking.body.appointmentId);
    const appointmentId = booking.body.appointmentId;

    const availabilityAfterBooking = await callFunction(
        "barberoGetAvailability",
        customerToken,
        customerRequest(shopAId, shopAAccessToken, {
          barberId,
          date: firstDate,
          serviceKeys: ["classic_haircut"],
        }),
    );
    assert.equal(availabilityAfterBooking.status, 200);
    assert.equal(
        availabilityAfterBooking.body.slots.some((slot) => slot.startTime === "10:00"),
        false,
    );

    // Reschedule and then cancel the same appointment.
    const reschedule = await callFunction(
        "barberoCustomerRescheduleAppointment",
        customerToken,
        customerRequest(shopAId, shopAAccessToken, {
          appointmentId,
          barberId,
          date: rescheduledDate,
          startTime: "11:00",
        }),
    );
    assert.equal(reschedule.status, 200);
    assert.equal(reschedule.body.date, rescheduledDate);

    const cancel = await callFunction(
        "barberoCancelAppointment",
        customerToken,
        customerRequest(shopAId, shopAAccessToken, {appointmentId}),
    );
    assert.equal(cancel.status, 200);
    assert.equal(cancel.body.status, "cancelled");

    const shopA = (await db.ref(`shops/${shopAId}`).get()).val();
    const shopB = (await db.ref(`shops/${shopBId}`).get()).val();
    const eventTypes = Object.values(
        (await db.ref(`notificationInbox/${shopAId}`).get()).val() || {},
    ).map((entry) => entry.eventType).sort();
    assert.deepEqual(
        eventTypes,
        ["appointment_cancelled", "appointment_rescheduled", "new_booking"],
    );
    const notificationOutbox =
      (await db.ref("notificationOutbox").get()).val() || {};
    const shopOutboxItems = Object.values(notificationOutbox).filter(
        (item) => item?.shopId === shopAId,
    );
    assert.equal(
        shopOutboxItems.length > 0,
        true,
        JSON.stringify(notificationOutbox),
    );
    assert.equal(
        shopA.appointments[appointmentId].status,
        "cancelled",
    );
    assert.equal(
        shopB.appointments && shopB.appointments[appointmentId],
        undefined,
    );

    // A customer token/app binding cannot cross into another shop.
    const crossShell = await callFunction(
        "barberoGetCustomerShell",
        customerToken,
        customerRequest(shopBId, shopBAccessToken),
    );
    assert.equal(crossShell.status, 200, JSON.stringify(crossShell.body));
    assert.equal(crossShell.body.shell.shopId, shopBId);
    assert.equal(crossShell.body.shell.customerPhone, "");
    assert.deepEqual(crossShell.body.shell.appointments, []);

    const crossAvailability = await callFunction(
        "barberoGetAvailability",
        customerToken,
        customerRequest(shopBId, shopBAccessToken, {
          barberId,
          date: firstDate,
          serviceKeys: ["classic_haircut"],
        }),
    );
    assert.equal(
        crossAvailability.status,
        403,
        JSON.stringify(crossAvailability.body),
    );
    assert.equal(crossAvailability.body.message, "customer-profile-required");

    const wrongAppBinding = await callFunction(
        "barberoGetAvailability",
        customerToken,
        customerRequest(shopBId, shopAAccessToken, {
          barberId,
          date: firstDate,
          serviceKeys: ["classic_haircut"],
        }),
    );
    assert.equal(wrongAppBinding.status, 403);
    assert.equal(wrongAppBinding.body.message, "customer-app-link-required");

    console.log("Barberin E2E tests passed: login, shell, availability, booking, cancel, reschedule, notifications, shop isolation");
  } finally {
    // This cleanup only targets the emulator project guarded at the top.
    await db.ref().remove();
    for (const user of [owner, customer]) {
      if (user?.uid) {
        try {
          await auth.deleteUser(user.uid);
        } catch (_) {
          // Keep cleanup idempotent if an earlier assertion already removed it.
        }
      }
    }
    await deleteApp(firebaseApp);
  }
}

run().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
