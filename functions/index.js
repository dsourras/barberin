const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {setGlobalOptions} = require("firebase-functions/v2");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getDatabase} = require("firebase-admin/database");
const {getMessaging} = require("firebase-admin/messaging");
const {getStorage} = require("firebase-admin/storage");
const {randomUUID} = require("node:crypto");

initializeApp();

setGlobalOptions({
  region: "europe-west1",
  maxInstances: 10,
});

const DEFAULT_CUSTOMER_APP_NAME = "Customer Booking App";
const CUSTOMER_NOTIFICATION_CHANNEL_ID = "barbero_customer_updates";
const AVAILABILITY_STEP_MINUTES = 5;
const BILLING_TRIAL_DAYS = 30;
const BILLING_MONTHLY_PRICE_EUR = 29;
const BILLING_YEARLY_PRICE_EUR = 290;
const BILLING_YEARLY_SAVINGS_EUR = 58;
const BILLING_MONTHLY_PRODUCT_ID = "barbero_monthly";
const BILLING_YEARLY_PRODUCT_ID = "barbero_yearly";

function json(response, status, body) {
  response.status(status).json(body);
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

function buildDefaultBillingRecord() {
  return {
    status: "setup_required",
    selectedPlan: "monthly",
    planConfirmed: false,
    trialEligible: true,
    trialStartedAt: "",
    trialEndsAt: "",
    currentPeriodEnd: "",
    graceUntil: "",
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

function buildBillingSnapshot(rawBilling) {
  const fallback = buildDefaultBillingRecord();
  const billing = rawBilling && typeof rawBilling === "object" ?
    rawBilling :
    fallback;
  const selectedPlan = normalizeBillingPlan(
      billing.selectedPlan || fallback.selectedPlan,
  );
  const now = new Date();
  const trialEndsAt = String(billing.trialEndsAt || "").trim();
  const currentPeriodEnd = String(billing.currentPeriodEnd || "").trim();
  const graceUntil = String(billing.graceUntil || "").trim();
  const trialEndsDate = trialEndsAt ? new Date(trialEndsAt) : null;
  const currentPeriodEndDate = currentPeriodEnd ? new Date(currentPeriodEnd) : null;
  const graceUntilDate = graceUntil ? new Date(graceUntil) : null;
  let status = String(billing.status || "setup_required").trim().toLowerCase();

  if (status === "trialing") {
    if (!trialEndsDate || Number.isNaN(trialEndsDate.getTime()) || trialEndsDate < now) {
      status = "expired";
    }
  } else if (status === "active") {
    if (!currentPeriodEndDate ||
      Number.isNaN(currentPeriodEndDate.getTime()) ||
      currentPeriodEndDate < now
    ) {
      status = "expired";
    }
  } else if (status === "grace_period") {
    if (!graceUntilDate ||
      Number.isNaN(graceUntilDate.getTime()) ||
      graceUntilDate < now
    ) {
      status = "expired";
    }
  }

  const allowsAccess = ["trialing", "active", "grace_period"].includes(status);
  const requiresOwnerAction = !allowsAccess;
  const catalog =
    billing.catalog && typeof billing.catalog === "object" ?
      billing.catalog :
      {};

  return {
    status,
    selectedPlan,
    planConfirmed: billing.planConfirmed === true,
    allowsAccess,
    requiresOwnerAction,
    trialStartedAt: String(billing.trialStartedAt || "").trim(),
    trialEndsAt,
    currentPeriodEnd,
    platform: String(billing.platform || "").trim(),
    storeProductId: String(
        billing.storeProductId ||
        (selectedPlan === "yearly" ?
          BILLING_YEARLY_PRODUCT_ID :
          BILLING_MONTHLY_PRODUCT_ID),
    ).trim(),
    monthlyPriceEur:
      Number.parseInt(catalog.monthlyPriceEur, 10) || BILLING_MONTHLY_PRICE_EUR,
    yearlyPriceEur:
      Number.parseInt(catalog.yearlyPriceEur, 10) || BILLING_YEARLY_PRICE_EUR,
    yearlySavingsEur:
      Number.parseInt(catalog.yearlySavingsEur, 10) || BILLING_YEARLY_SAVINGS_EUR,
    monthlyProductId: String(catalog.monthlyProductId || BILLING_MONTHLY_PRODUCT_ID),
    yearlyProductId: String(catalog.yearlyProductId || BILLING_YEARLY_PRODUCT_ID),
    trialDays:
      Number.parseInt(catalog.trialDays, 10) || BILLING_TRIAL_DAYS,
  };
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

function serviceLabelForKey(key) {
  switch (key) {
    case "classic_haircut":
      return "Classic Haircut";
    case "beard_trim":
      return "Beard Trim";
    case "haircut_and_beard":
      return "Haircut & Beard";
    case "fade_and_beard":
      return "Fade & Beard";
    case "kids_haircut":
      return "Kids Haircut";
    default:
      return String(key || "").replaceAll("_", " ");
  }
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

async function sendCustomerLifecycleNotification({shop, appointment, eventType}) {
  const customer = findCustomerRecordForAppointment(shop, appointment);
  const tokens = getCustomerNotificationTokens(customer);
  if (tokens.length === 0) {
    return;
  }

  let title = "Appointment update";
  switch (eventType) {
    case "confirmed":
      title = "Appointment confirmed";
      break;
    case "cancelled":
      title = "Appointment cancelled";
      break;
    case "rescheduled":
      title = "Appointment rescheduled";
      break;
  }

  const serviceText = Array.isArray(appointment.services) ?
    appointment.services.filter(Boolean).join(" • ") :
    "";
  const bodyParts = [
    String(appointment.barberName || "").trim(),
    String(appointment.date || "").trim(),
    String(appointment.time || "").trim(),
  ].filter(Boolean);
  if (serviceText) {
    bodyParts.push(serviceText);
  }

  try {
    await getMessaging().sendEachForMulticast({
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
      android: {
        priority: "high",
        notification: {
          channelId: CUSTOMER_NOTIFICATION_CHANNEL_ID,
        },
      },
    });
  } catch (error) {
    console.error("send-customer-lifecycle-notification-failed", error);
  }
}

function getAppointmentReminderTargets() {
  return [
    {key: "reminder24h", leadMinutes: 24 * 60, label: "Tomorrow"},
    {key: "reminder2h", leadMinutes: 2 * 60, label: "In 2 hours"},
    {key: "reminder30m", leadMinutes: 30, label: "In 30 minutes"},
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

async function sendCustomerReminderNotification({shop, appointment, reminder}) {
  const customer = findCustomerRecordForAppointment(shop, appointment);
  const tokens = getCustomerNotificationTokens(customer);
  if (tokens.length === 0) {
    return false;
  }

  const serviceText = Array.isArray(appointment.services) ?
    appointment.services.filter(Boolean).join(" • ") :
    "";
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
    await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: "Appointment reminder",
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
      android: {
        priority: "high",
        notification: {
          channelId: CUSTOMER_NOTIFICATION_CHANNEL_ID,
        },
      },
    });
    return true;
  } catch (error) {
    console.error("send-customer-reminder-notification-failed", error);
    return false;
  }
}

async function sendOwnerNewBookingNotification({shop, appointment}) {
  const tokens = getShopNotificationTokens(shop);
  if (tokens.length === 0) {
    return;
  }

  const serviceText = Array.isArray(appointment.services) ?
    appointment.services.filter(Boolean).join(" • ") :
    "";
  const title = "New booking";
  const bodyParts = [
    String(appointment.customerName || "").trim(),
    String(appointment.date || "").trim(),
    String(appointment.time || "").trim(),
  ].filter(Boolean);
  if (serviceText) {
    bodyParts.push(serviceText);
  }

  try {
    await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title,
        body: bodyParts.join(" • "),
      },
      data: {
        type: "new_booking",
        appointmentId: String(appointment.id || ""),
        customerName: String(appointment.customerName || ""),
        barberName: String(appointment.barberName || ""),
        date: String(appointment.date || ""),
        time: String(appointment.time || ""),
      },
      android: {
        priority: "high",
        notification: {
          channelId: "barbero_owner_bookings",
        },
      },
    });
  } catch (error) {
    console.error("send-owner-booking-notification-failed", error);
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

  const serviceDurations = Array.isArray(source.serviceDurations) ?
    source.serviceDurations.map((item) => ({
      key: String(item?.key || ""),
      label: String(item?.label || ""),
      minutes: Math.max(5, Number.parseInt(item?.minutes, 10) || 30),
    })).filter((item) => item.key) :
    [];

  const servicePrices = Array.isArray(source.servicePrices) ?
    source.servicePrices.map((item) => ({
      key: String(item?.key || ""),
      label: String(item?.label || ""),
      price: Math.max(0, Number.parseInt(item?.price, 10) || 0),
    })).filter((item) => item.key) :
    [];
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
    barberSchedules,
    serviceDurations,
    servicePrices,
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
  return getAuth().verifyIdToken(idToken);
}

async function loadShopContext(shopId) {
  const db = getDatabase();
  const snapshot = await db.ref(`shops/${shopId}`).get();
  if (!snapshot.exists()) {
    throw new Error("shop-not-found");
  }
  const shop = snapshot.val() || {};
  const schedule = shop.weekly_schedule || {};
  const slotMinutes = Number.parseInt(schedule.slotMinutes, 10) || 30;
  const appointmentsPerSlot =
    Number.parseInt(schedule.appointmentsPerSlot, 10) || 1;
  const slotCapacityOverrides = Array.isArray(schedule.slotCapacityOverrides) ?
    schedule.slotCapacityOverrides :
    [];
  const barberSchedules = Array.isArray(schedule.barberSchedules) ?
    schedule.barberSchedules :
    [];
  const serviceDurations = Array.isArray(schedule.serviceDurations) ?
    schedule.serviceDurations :
    [];
  const servicePrices = Array.isArray(schedule.servicePrices) ?
    schedule.servicePrices :
    [];
  const days = Array.isArray(schedule.days) ? schedule.days : [];
  const appointmentsMap = shop.appointments || {};
  const appointments = Object.entries(appointmentsMap).map(([id, value]) => {
    const appointment = value || {};
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
  });

  return {
    db,
    shop,
    days,
    slotMinutes,
    appointmentsPerSlot,
    slotCapacityOverrides,
    barberSchedules,
    serviceDurations,
    servicePrices,
    appointments,
  };
}

function buildServiceSelection(serviceKeys, serviceDurations, servicePrices) {
  const durationByKey = Object.fromEntries(
      serviceDurations.map((item) => [item.key, Number(item.minutes) || 30]),
  );
  const priceByKey = Object.fromEntries(
      servicePrices.map((item) => [item.key, Number(item.price) || 0]),
  );

  return serviceKeys.map((key) => ({
    key,
    label: serviceLabelForKey(key),
    minutes: durationByKey[key] || 30,
    price: priceByKey[key] || 0,
  }));
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
        notes: String(item.notes || item.note || "").trim(),
        specialties: Array.isArray(item.specialties) ?
          item.specialties.map((specialty) => String(specialty || "").trim()).filter(Boolean) :
          [],
        photoUrl: String(item.photoUrl || "").trim(),
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
        notes: String(value.notes || value.note || "").trim(),
        specialties: Array.isArray(value.specialties) ?
          value.specialties.map((specialty) => String(specialty || "").trim()).filter(Boolean) :
          [],
        photoUrl: String(value.photoUrl || "").trim(),
      });
    });
  }

  return barbers;
}

function findCrewInviteByEmail(shops, email) {
  const normalizedEmail = String(email || "").trim().toLowerCase();
  if (!normalizedEmail) {
    return null;
  }

  for (const [shopId, shop] of Object.entries(shops || {})) {
    const crewMember = buildShopBarbers(shop).find((barber) =>
      String(barber.email || "").trim().toLowerCase() === normalizedEmail,
    );
    if (!crewMember) {
      continue;
    }
    return {
      shopId,
      shopName: String(shop?.shopName || "").trim(),
      ownerName: String(shop?.ownerName || "").trim(),
      crewId: String(crewMember.id || "").trim(),
      role: resolveBarberoRole(crewMember.role),
      displayName: String(crewMember.name || "").trim(),
      status: String(crewMember.status || "active").trim().toLowerCase(),
      authUid: String(crewMember.authUid || "").trim(),
    };
  }

  return null;
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

  const shops = shopsSnapshot.val() || {};
  const normalizedEmail = String(decoded.email || "").trim().toLowerCase();

  if (shops[decoded.uid]) {
    const ownerShop = shops[decoded.uid] || {};
    return {
      shopId: decoded.uid,
      role: "owner",
      crewId: "",
      displayName: String(ownerShop.ownerName || "").trim(),
      shop: ownerShop,
    };
  }

  for (const [shopId, shop] of Object.entries(shops)) {
    const ownerEmail = String(shop?.ownerEmail || "").trim().toLowerCase();
    if (normalizedEmail && ownerEmail === normalizedEmail) {
      return {
        shopId,
        role: "owner",
        crewId: "",
        displayName: String(shop?.ownerName || "").trim(),
        shop,
      };
    }

    const crewMember = buildShopBarbers(shop).find((barber) => {
      const barberEmail = String(barber.email || "").trim().toLowerCase();
      if (!normalizedEmail || barberEmail !== normalizedEmail) {
        return false;
      }
      const barberStatus = String(barber.status || "active")
          .trim()
          .toLowerCase();
      const barberAuthUid = String(barber.authUid || "").trim();
      return barberStatus == "active" || barberAuthUid === decoded.uid;
    });
    if (crewMember) {
      return {
        shopId,
        role: resolveBarberoRole(crewMember.role),
        crewId: String(crewMember.id || "").trim(),
        displayName: String(crewMember.name || "").trim(),
        shop,
      };
    }
  }

  throw new Error("barbero-session-not-found");
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

async function authorizeBarberoAccess(decoded, requestedShopId) {
  const resolved = await resolveBarberoSession(decoded);
  const shopId = String(requestedShopId || resolved.shopId || "").trim();
  if (!shopId || shopId !== resolved.shopId) {
    throw new Error("forbidden");
  }
  return {
    ...resolved,
    permissions: barberoRolePermissions(resolved.role),
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

function buildRelevantDurations(slotMinutes, serviceDurations) {
  const durations = new Set([Math.max(5, Number(slotMinutes) || 30)]);
  const serviceMinuteValues = serviceDurations
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

  return Array.from(durations).sort((left, right) => left - right);
}

function buildAvailabilityCachePath(shopId, barberId, dateText, requiredMinutes) {
  return `shops/${shopId}/availability/${dateText}/${barberId}/${requiredMinutes}`;
}

function decodeBase64Image(value) {
  const source = String(value || "").trim();
  if (!source) {
    throw new Error("missing-image-bytes");
  }
  const normalized = source.includes(",") ? source.split(",").pop() : source;
  return Buffer.from(normalized, "base64");
}

async function uploadImageAndGetUrl({
  path,
  bytes,
  contentType,
}) {
  const bucket = getStorage().bucket("barbero-88d00.firebasestorage.app");
  const file = bucket.file(path);
  const downloadToken = randomUUID();
  await file.save(bytes, {
    resumable: false,
    contentType,
    metadata: {
      contentType,
      cacheControl: "public,max-age=31536000",
      metadata: {
        firebaseStorageDownloadTokens: downloadToken,
      },
    },
  });
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${downloadToken}`;
}

function buildCustomerShellPayload({shopId, shop, decoded, appointments}) {
  const schedule = shop?.weekly_schedule || {};
  const serviceDurations = Array.isArray(schedule.serviceDurations) ?
    schedule.serviceDurations :
    [];
  const servicePrices = Array.isArray(schedule.servicePrices) ?
    schedule.servicePrices :
    [];
  const durationByKey = Object.fromEntries(
      serviceDurations.map((item) => [String(item?.key || ""), Number(item?.minutes) || 30]),
  );
  const services = servicePrices.map((item) => {
    const key = String(item?.key || "");
    return {
      key,
      label: String(item?.label || serviceLabelForKey(key)),
      price: Number(item?.price) || 0,
      minutes: durationByKey[key] || 30,
    };
  });

  const days = Array.isArray(schedule.days) ? schedule.days : [];
  const barbers = buildShopBarbers(shop).map((barber) => ({
    id: barber.id,
    name: barber.name,
    subtitle: barber.role || "Barber",
    note: barber.notes || "",
    specialties: Array.isArray(barber.specialties) ? barber.specialties : [],
    photoUrl: barber.photoUrl || "",
  }));

  const currentCustomer = findCurrentCustomerRecord(shop, decoded);

  const fullName = String(
      currentCustomer?.fullName ||
      decoded.name ||
      (decoded.email ? decoded.email.split("@")[0] : "Ξ ΞµΞ»Ξ¬Ο„Ξ·Ο‚"),
  ).trim();
  const customerName = fullName ? fullName.split(/\s+/)[0] : "Ξ ΞµΞ»Ξ¬Ο„Ξ·Ο‚";
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

  return {
    shopId,
    shopName: resolveShopDisplayName(shop),
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
    services,
    barbers,
    days,
    appointments: appointments.map((appointment) => ({
      id: appointment.id,
      customerUid: appointment.customerUid,
      customerName: appointment.customerName,
      barberId: appointment.barberId,
      barberName: appointment.barberName,
      date: appointment.date,
      time: appointment.time,
      services: appointment.services,
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

function findCurrentCustomerEntry(shop, decoded) {
  const rawCustomers = shop?.customers && typeof shop.customers === "object" ?
    shop.customers :
    {};
  let customerUid = "";
  let currentCustomer = rawCustomers[decoded.uid] || null;
  if (currentCustomer) {
    customerUid = String(decoded.uid || "").trim();
  }
  if (!currentCustomer && decoded.email) {
    const matchedEntry = Object.entries(rawCustomers).find(([, customer]) =>
      String(customer?.email || "").trim().toLowerCase() ===
        String(decoded.email || "").trim().toLowerCase(),
    ) || null;
    if (matchedEntry) {
      customerUid = String(matchedEntry[0] || "").trim();
      currentCustomer = matchedEntry[1] || null;
    }
  }
  if (!currentCustomer && Object.keys(rawCustomers).length === 1) {
    const [firstKey, firstCustomer] = Object.entries(rawCustomers)[0];
    customerUid = String(firstKey || "").trim();
    currentCustomer = firstCustomer || null;
  }
  if (!currentCustomer) {
    return null;
  }
  return {
    uid: customerUid || String(currentCustomer?.uid || "").trim(),
    customer: currentCustomer,
  };
}

function computeAvailableSlots({
  days,
  appointments,
  appointmentsPerSlot = 1,
  slotCapacityOverrides = [],
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
      const activeAppointments = appointments.filter((appointment) => {
        if (
          appointment.date !== dateText ||
          !isAppointmentBlockingStatus(appointment.status)
        ) {
          return false;
        }
        const appointmentStart = timeToMinutes(appointment.time);
        const appointmentDuration = appointment.totalMinutes > 0 ?
          appointment.totalMinutes :
          requiredMinutes;
        const appointmentEnd = appointmentStart + appointmentDuration;
        return appointmentStart < minute + AVAILABILITY_STEP_MINUTES &&
          appointmentEnd > minute;
      }).length;
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

async function writeAvailabilitySnapshot({
  db,
  shopId,
  barberId,
  dateText,
  requiredMinutes,
  slots,
}) {
  await db.ref(buildAvailabilityCachePath(
      shopId,
      barberId,
      dateText,
      requiredMinutes,
  )).set({
    shopId,
    barberId,
    date: dateText,
    requiredMinutes,
    slots,
    updatedAt: new Date().toISOString(),
  });
}

async function refreshAvailabilityForBarberDate({
  db,
  shopId,
  shop,
  days,
  slotMinutes,
  serviceDurations,
  appointments,
  barberId,
  dateText,
}) {
  const durations = buildRelevantDurations(slotMinutes, serviceDurations);
  const availabilityRef = db.ref(`shops/${shopId}/availability/${dateText}/${barberId}`);
  const existingSnapshot = await availabilityRef.get();
  const existingKeys = existingSnapshot.exists() ?
    Object.keys(existingSnapshot.val() || {}) :
    [];
  const keepKeys = new Set(durations.map((minutes) => String(minutes)));
  const cleanup = {};

  for (const key of existingKeys) {
    if (!keepKeys.has(String(key))) {
      cleanup[key] = null;
    }
  }

  if (Object.keys(cleanup).length > 0) {
    await availabilityRef.update(cleanup);
  }

  for (const requiredMinutes of durations) {
    const slots = computeAvailableSlots({
      days,
      appointments,
      barberId,
      dateText,
      requiredMinutes,
    });
    await writeAvailabilitySnapshot({
      db,
      shopId,
      barberId,
      dateText,
      requiredMinutes,
      slots,
    });
  }
}

async function refreshAvailabilityForDate({
  db,
  shopId,
  shop,
  days,
  slotMinutes,
  serviceDurations,
  appointments,
  dateText,
  barberIds,
}) {
  const derivedBarberIds = Array.isArray(barberIds) && barberIds.length > 0 ?
    barberIds :
    buildShopBarbers(shop).map((barber) => barber.id);
  const uniqueBarberIds = Array.from(new Set([
    ...derivedBarberIds,
    ...appointments
        .filter((appointment) => appointment.date === dateText)
        .map((appointment) => appointment.barberId)
        .filter((barberId) => String(barberId || "").trim().length > 0),
  ]));

  for (const barberId of uniqueBarberIds) {
    await refreshAvailabilityForBarberDate({
      db,
      shopId,
      shop,
      days,
      slotMinutes,
      serviceDurations,
      appointments,
      barberId,
      dateText,
    });
  }
}

exports.atelier22Ping = onRequest((request, response) => {
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
    const shopId = access.shopId;
    const schedule = normalizeWeeklySchedulePayload(request.body?.schedule);
    const db = getDatabase();

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
      details: error.message || String(error),
    });
  }
});

exports.barberoRegisterShop = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body?.shop || {};
    const shopId = String(payload.shopId || decoded.uid);

    if (shopId !== decoded.uid) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const ownerName = String(payload.ownerName || "").trim();
    const ownerPhone = String(payload.ownerPhone || "").trim();
    const ownerEmail = String(payload.ownerEmail || decoded.email || "").trim();
    const shopName = String(payload.shopName || "").trim();
    const address = String(payload.address || "").trim();

    if (!ownerName || !ownerPhone || !ownerEmail || !shopName || !address) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const db = getDatabase();
    const existingSnapshot = await db.ref(`shops/${shopId}/billing`).get();
    const billingRecord = existingSnapshot.exists() ?
      {
        ...buildDefaultBillingRecord(),
        ...(existingSnapshot.val() || {}),
        updatedAt: new Date().toISOString(),
      } :
      buildDefaultBillingRecord();
    await db.ref(`shops/${shopId}`).update({
      id: shopId,
      ownerName,
      ownerPhone,
      ownerEmail,
      shopName,
      address,
      billing: billingRecord,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });

    return json(response, 200, {
      ok: true,
      shopId,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: error.message || String(error),
    });
  }
});

exports.barberoSaveOwnerPhotoUrl = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const payload = request.body || {};
    const shopId = String(payload.shopId || decoded.uid);
    const ownerPhotoUrl = String(payload.ownerPhotoUrl || "").trim();

    if (shopId !== decoded.uid) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    if (!ownerPhotoUrl) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const db = getDatabase();
    await db.ref(`shops/${shopId}`).update({
      ownerPhotoUrl,
      updatedAt: new Date().toISOString(),
    });

    return json(response, 200, {
      ok: true,
      shopId,
      ownerPhotoUrl,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: error.message || String(error),
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

    if (shopId !== decoded.uid) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const ownerPhotoUrl = await uploadImageAndGetUrl({
      path: `shops/${shopId}/owner/${shopId}/profile.jpg`,
      bytes,
      contentType,
    });

    const db = getDatabase();
    await db.ref(`shops/${shopId}`).update({
      ownerPhotoUrl,
      updatedAt: new Date().toISOString(),
    });

    return json(response, 200, {
      ok: true,
      shopId,
      ownerPhotoUrl,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: error.message || String(error),
    });
  }
});

exports.barberoSaveCrewMember = onRequest(async (request, response) => {
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

    const db = getDatabase();
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
      authUid: "",
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    await crewRef.set(crew);
    await db.ref(`shops/${access.shopId}`).update({
      updatedAt: new Date().toISOString(),
    });

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      crewId,
      crew,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: error.message || String(error),
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
      details: error.message || String(error),
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
    await db.ref(`shops/${access.shopId}/barbers/${crewId}`).remove();
    await db.ref(`shops/${access.shopId}`).update({
      updatedAt: new Date().toISOString(),
    });

    const bucket = getStorage().bucket("barbero-88d00.firebasestorage.app");
    await bucket.deleteFiles({
      prefix: `shops/${access.shopId}/barbers/${crewId}/`,
      force: true,
    }).catch(() => {});

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
      details: error.message || String(error),
    });
  }
});

exports.barberoUpdateCrewMember = onRequest(async (request, response) => {
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

    const db = getDatabase();
    const crewRef = db.ref(`shops/${access.shopId}/barbers/${crewId}`);
    const crewSnapshot = await crewRef.get();
    if (!crewSnapshot.exists()) {
      return json(response, 404, {ok: false, message: "crew-not-found"});
    }
    const current = crewSnapshot.val() || {};
    const authUid = String(current.authUid || "").trim();
    const status = authUid ? "active" : (email ? "invited" : "active");

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
        String(current.invitedAt || new Date().toISOString()) :
        null,
      authUid,
      createdAt: String(current.createdAt || new Date().toISOString()),
      updatedAt: new Date().toISOString(),
    };

    await crewRef.update(crew);
    await db.ref(`shops/${access.shopId}`).update({
      updatedAt: new Date().toISOString(),
    });

    return json(response, 200, {
      ok: true,
      shopId: access.shopId,
      crewId,
      crew,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: error.message || String(error),
    });
  }
});

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
      details: error.message || String(error),
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
      details: error.message || String(error),
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
      details: error.message || String(error),
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
    const invite = findCrewInviteByEmail(shops, email);
    if (!invite) {
      return json(response, 404, {ok: false, message: "invite-not-found"});
    }
    return json(response, 200, {
      ok: true,
      invite: {
        shopId: invite.shopId,
        shopName: invite.shopName,
        ownerName: invite.ownerName,
        crewId: invite.crewId,
        role: invite.role,
        displayName: invite.displayName,
        status: invite.status,
      },
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: error.message || String(error),
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
    const db = getDatabase();
    const shopsSnapshot = await db.ref("shops").get();
    const shops = shopsSnapshot.exists() ? shopsSnapshot.val() || {} : {};
    const invite = findCrewInviteByEmail(shops, decoded.email || "");
    if (!invite) {
      return json(response, 404, {ok: false, message: "invite-not-found"});
    }
    if (requestedShopId && requestedShopId !== invite.shopId) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    if (invite.authUid && invite.authUid !== decoded.uid) {
      return json(response, 409, {ok: false, message: "invite-already-used"});
    }

    await db.ref(`shops/${invite.shopId}/barbers/${invite.crewId}`).update({
      status: "active",
      authUid: decoded.uid,
      joinedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });

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
      details: error.message || String(error),
    });
  }
});

exports.barberoResolveSession = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const resolved = await resolveBarberoSession(decoded);
    return json(response, 200, {
      ok: true,
      session: {
        shopId: resolved.shopId,
        role: resolved.role,
        crewId: resolved.crewId,
        displayName: resolved.displayName,
      },
      billing: buildBillingSnapshot(resolved.shop?.billing),
    });
  } catch (error) {
    console.error(error);
    return json(response, 403, {
      ok: false,
      message: "forbidden",
      details: error.message || String(error),
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
    const access = await authorizeBarberoAccess(decoded, requestedShopId);
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
      details: error.message || String(error),
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
    const access = await authorizeBarberoAccess(decoded, requestedShopId);
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
      selectedPlan,
      storeProductId:
        selectedPlan === "yearly" ?
          BILLING_YEARLY_PRODUCT_ID :
          BILLING_MONTHLY_PRODUCT_ID,
      updatedAt: new Date().toISOString(),
    };
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
      details: error.message || String(error),
    });
  }
});

exports.barberoStartSubscriptionTrial = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = String(request.body?.shopId || "").trim();
    const access = await authorizeBarberoAccess(decoded, requestedShopId);
    if (access.role !== "owner") {
      return json(response, 403, {ok: false, message: "forbidden"});
    }
    const selectedPlan = normalizeBillingPlan(request.body?.selectedPlan);
    const db = getDatabase();
    const billingRef = db.ref(`shops/${access.shopId}/billing`);
    const snapshot = await billingRef.get();
    const currentBilling = {
      ...buildDefaultBillingRecord(),
      ...(snapshot.exists() ? snapshot.val() || {} : {}),
    };
    if (currentBilling.trialStartedAt) {
      return json(response, 409, {
        ok: false,
        message: "trial-already-started",
      });
    }
    const trialStartedAt = new Date().toISOString();
    const trialEndsAt = addDaysToIso(trialStartedAt, BILLING_TRIAL_DAYS);
    const nextBilling = {
      ...currentBilling,
      status: "trialing",
      selectedPlan,
      planConfirmed: true,
      trialEligible: false,
      trialStartedAt,
      trialEndsAt,
      currentPeriodEnd: trialEndsAt,
      storeProductId:
        selectedPlan === "yearly" ?
          BILLING_YEARLY_PRODUCT_ID :
          BILLING_MONTHLY_PRODUCT_ID,
      updatedAt: new Date().toISOString(),
    };
    await billingRef.set(nextBilling);
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
      message: "billing-trial-start-failed",
      details: error.message || String(error),
    });
  }
});

exports.barberoProcessStorePurchase = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const requestedShopId = String(request.body?.shopId || "").trim();
    const access = await authorizeBarberoAccess(decoded, requestedShopId);
    if (access.role !== "owner") {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const purchase = request.body?.purchase || {};
    const selectedPlan = normalizeBillingPlan(
        purchase.selectedPlan || purchase.productId,
    );
    const productId = String(
        purchase.productId ||
        (selectedPlan === "yearly" ?
          BILLING_YEARLY_PRODUCT_ID :
          BILLING_MONTHLY_PRODUCT_ID),
    ).trim();
    const purchaseId = String(purchase.purchaseId || "").trim();
    const platform = String(purchase.platform || "").trim().toLowerCase();
    const transactionDateRaw = String(purchase.transactionDate || "").trim();
    const verificationData =
      purchase.verificationData && typeof purchase.verificationData === "object" ?
        purchase.verificationData :
        {};
    const serverVerificationData = String(
        verificationData.serverVerificationData || "",
    ).trim();

    if (!productId || !platform || !serverVerificationData) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const purchaseDate = transactionDateRaw ?
      new Date(Number.parseInt(transactionDateRaw, 10)) :
      new Date();
    const normalizedPurchaseDate =
      Number.isNaN(purchaseDate.getTime()) ? new Date() : purchaseDate;
    const currentPeriodEnd =
      selectedPlan === "yearly" ?
        addYearsToIso(normalizedPurchaseDate, 1) :
        addMonthsToIso(normalizedPurchaseDate, 1);

    const db = getDatabase();
    const billingRef = db.ref(`shops/${access.shopId}/billing`);
    const snapshot = await billingRef.get();
    const currentBilling = {
      ...buildDefaultBillingRecord(),
      ...(snapshot.exists() ? snapshot.val() || {} : {}),
    };
    const purchaseRecordId = purchaseId || randomUUID();
    const nextBilling = {
      ...currentBilling,
      status: "active",
      selectedPlan,
      planConfirmed: true,
      platform,
      trialEligible: false,
      currentPeriodEnd,
      graceUntil: "",
      storeProductId: productId,
      latestPurchaseId: purchaseRecordId,
      latestPurchaseAt: normalizedPurchaseDate.toISOString(),
      latestVerificationSource: String(verificationData.source || "").trim(),
      latestVerificationData: serverVerificationData,
      updatedAt: new Date().toISOString(),
    };

    await billingRef.set(nextBilling);
    await db.ref(`shops/${access.shopId}/billingPurchases/${purchaseRecordId}`).set({
      id: purchaseRecordId,
      platform,
      productId,
      selectedPlan,
      purchaseId,
      transactionDate: transactionDateRaw,
      processedAt: new Date().toISOString(),
      verificationData,
    });
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
      details: error.message || String(error),
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
    const access = await authorizeBarberoAccess(decoded, requestedShopId);
    const db = getDatabase();
    const deletedAt = new Date().toISOString();

    if (access.role === "owner") {
      const shopSnapshot = await db.ref(`shops/${access.shopId}`).get();
      if (!shopSnapshot.exists()) {
        throw new Error("shop-not-found");
      }
      const shop = shopSnapshot.val() || {};
      await db.ref(`deleted/shops/${access.shopId}`).set({
        originalShopId: access.shopId,
        deletedAt,
        deletedByUid: decoded.uid,
        deletedByEmail: String(decoded.email || "").trim().toLowerCase(),
        source: "barbero_app",
        reason: "owner_account_deletion",
        shop,
      });
      await db.ref(`shops/${access.shopId}`).remove();
      await getAuth().deleteUser(decoded.uid);
      return json(response, 200, {
        ok: true,
        mode: "owner",
      });
    }

    const crewId = String(access.crewId || "").trim();
    if (!crewId) {
      throw new Error("crew-account-not-found");
    }

    const crewRef = db.ref(`shops/${access.shopId}/barbers/${crewId}`);
    const crewSnapshot = await crewRef.get();
    const crewRecord = crewSnapshot.exists() ? crewSnapshot.val() || {} : {};

    await db.ref(`deleted/barberoAccounts/${decoded.uid}`).set({
      deletedAt,
      deletedByUid: decoded.uid,
      deletedByEmail: String(decoded.email || "").trim().toLowerCase(),
      shopId: access.shopId,
      crewId,
      role: access.role,
      displayName: access.displayName,
      source: "barbero_app",
      crew: crewRecord,
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
    await getAuth().deleteUser(decoded.uid);
    return json(response, 200, {
      ok: true,
      mode: "crew",
    });
  } catch (error) {
    console.error(error);
    return json(response, 400, {
      ok: false,
      message: "delete-account-failed",
      details: error.message || String(error),
    });
  }
});

exports.atelier22DeleteCustomerAccount = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const shopId = String(request.body?.shopId || "").trim();
    if (!shopId) {
      throw new Error("missing-shop-id");
    }

    const {
      db,
      shop,
      days,
      slotMinutes,
      serviceDurations,
      appointments,
    } = await loadShopContext(shopId);
    const customerEntry = findCurrentCustomerEntry(shop, decoded);
    const customerUid = String(customerEntry?.uid || decoded.uid || "").trim();
    const customer = customerEntry?.customer || null;
    const normalizedEmail = String(
        customer?.email || decoded.email || "",
    ).trim().toLowerCase();
    const deletedAt = new Date().toISOString();

    const appointmentsToDelete = appointments.filter((appointment) => {
      const appointmentCustomerUid = String(appointment.customerUid || "").trim();
      const appointmentCustomerEmail = String(
          appointment.customerEmail || "",
      ).trim().toLowerCase();
      if (customerUid && appointmentCustomerUid === customerUid) {
        return true;
      }
      return normalizedEmail &&
        appointmentCustomerEmail &&
        appointmentCustomerEmail === normalizedEmail;
    });

    await db.ref(`deleted/customerAccounts/${decoded.uid}`).set({
      deletedAt,
      deletedByUid: decoded.uid,
      deletedByEmail: String(decoded.email || "").trim().toLowerCase(),
      source: "atelier22_app",
      shopId,
      customerUid,
      customer,
      appointments: appointmentsToDelete,
    });

    if (customerUid) {
      await db.ref(`shops/${shopId}/customers/${customerUid}`).remove();
    }

    const appointmentCleanup = {};
    for (const appointment of appointmentsToDelete) {
      appointmentCleanup[String(appointment.id || "").trim()] = null;
    }
    if (Object.keys(appointmentCleanup).length > 0) {
      await db.ref(`shops/${shopId}/appointments`).update(appointmentCleanup);
    }

    const remainingAppointments = appointments.filter((appointment) =>
      !appointmentsToDelete.some((removed) => removed.id === appointment.id),
    );
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

    for (const [dateText, barberIds] of affectedDates.entries()) {
      await refreshAvailabilityForDate({
        db,
        shopId,
        shop,
        days,
        slotMinutes,
        serviceDurations,
        appointments: remainingAppointments,
        dateText,
        barberIds: Array.from(barberIds),
      });
    }

    await getAuth().deleteUser(decoded.uid);
    return json(response, 200, {
      ok: true,
      deletedAppointments: appointmentsToDelete.length,
    });
  } catch (error) {
    console.error(error);
    return json(response, 400, {
      ok: false,
      message: "delete-account-failed",
      details: error.message || String(error),
    });
  }
});

exports.atelier22SaveCustomerProfile = onRequest(async (request, response) => {
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

    if (!shopId || !fullName || !phone || !email) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const db = getDatabase();
    const shopSnapshot = await db.ref(`shops/${shopId}`).get();
    const shop = shopSnapshot.exists() ? shopSnapshot.val() || {} : {};
    await db.ref(`shops/${shopId}/customers/${decoded.uid}`).update({
      uid: decoded.uid,
      fullName,
      phone,
      email,
      preferences,
      shopId,
      shopName: resolveShopDisplayName(shop),
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
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
      details: error.message || String(error),
    });
  }
});

exports.atelier22SaveNotificationToken = onRequest(async (request, response) => {
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
    await db.ref(
        `shops/${shopId}/customers/${decoded.uid}/notificationTokens/${tokenKey}`,
    ).set({
      token,
      platform: "android",
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
      details: error.message || String(error),
    });
  }
});

exports.atelier22SaveCustomerPhotoUrl = onRequest(async (request, response) => {
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
    await db.ref(`shops/${shopId}/customers/${customerUid}`).update({
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
      details: error.message || String(error),
    });
  }
});

exports.atelier22UploadCustomerPhoto = onRequest(async (request, response) => {
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

    const photoUrl = await uploadImageAndGetUrl({
      path: `shops/${shopId}/customers/${customerUid}/profile.jpg`,
      bytes,
      contentType,
    });

    const db = getDatabase();
    await db.ref(`shops/${shopId}/customers/${customerUid}`).update({
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
      details: error.message || String(error),
    });
  }
});

exports.atelier22GetCustomerShell = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const shopId = String(request.body?.shopId || "").trim();
    if (!shopId) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const {
      shop,
      appointments,
    } = await loadShopContext(shopId);

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
      details: error.message || String(error),
    });
  }
});

exports.atelier22GetAvailability = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const shopId = request.body?.shopId;
    const barberId = request.body?.barberId;
    const dateText = request.body?.date;
    const serviceKeys = Array.isArray(request.body?.serviceKeys) ?
      request.body.serviceKeys.map((item) => String(item)) :
      [];
    const explicitMinutes = Number.parseInt(request.body?.requiredMinutes, 10);

    if (!shopId || !barberId || !dateText) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const {
      db,
      shop,
      days,
      slotMinutes,
      serviceDurations,
      servicePrices,
      appointments,
    } = await loadShopContext(shopId);

    if (!shopHasBarber(shop, barberId)) {
      return json(response, 404, {ok: false, message: "barber-not-found"});
    }

    let requiredMinutes = explicitMinutes;
    if (!requiredMinutes || requiredMinutes <= 0) {
      const selectedServices = buildServiceSelection(
          serviceKeys,
          serviceDurations,
          servicePrices,
      );
      requiredMinutes = selectedServices.reduce(
          (sum, item) => sum + item.minutes,
          0,
      ) || slotMinutes;
    }

    const slots = computeAvailableSlots({
      days,
      appointments,
      appointmentsPerSlot,
      slotCapacityOverrides,
      barberSchedules,
      barberId,
      dateText,
      requiredMinutes,
    });

    await writeAvailabilitySnapshot({
      db,
      shopId,
      barberId,
      dateText,
      requiredMinutes,
      slots,
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
      details: error.message || String(error),
    });
  }
});

exports.atelier22BookAppointment = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const shopId = request.body?.shopId;
    const barberId = request.body?.barberId;
    const dateText = request.body?.date;
    const startTime = request.body?.startTime;
    const serviceKeys = Array.isArray(request.body?.serviceKeys) ?
      request.body.serviceKeys.map((item) => String(item)) :
      [];

    if (!shopId || !barberId || !dateText || !startTime || serviceKeys.length === 0) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const {
      db,
      shop,
      days,
      slotMinutes,
      serviceDurations,
      servicePrices,
      appointments,
    } = await loadShopContext(shopId);

    if (!shopHasBarber(shop, barberId)) {
      return json(response, 404, {ok: false, message: "barber-not-found"});
    }

    const selectedServices = buildServiceSelection(
        serviceKeys,
        serviceDurations,
        servicePrices,
    );
    const totalMinutes = selectedServices.reduce(
        (sum, item) => sum + item.minutes,
        0,
    ) || slotMinutes;
    const totalPrice = selectedServices.reduce((sum, item) => sum + item.price, 0);
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

    const availableSlots = computeAvailableSlots({
      days,
      appointments,
      appointmentsPerSlot,
      slotCapacityOverrides,
      barberSchedules,
      barberId,
      dateText,
      requiredMinutes: totalMinutes,
    });
    const matchedSlot = availableSlots.find((slot) => slot.startTime === startTime);
    if (!matchedSlot) {
      return json(response, 409, {
        ok: false,
        message: "slot-no-longer-available",
        suggestions: buildBookingFallbackSuggestions({
          shop,
          days,
          appointments,
          appointmentsPerSlot,
          slotCapacityOverrides,
          barberSchedules,
          barberId,
          dateText,
          requiredMinutes: totalMinutes,
          preferredStartTime: startTime,
        }),
      });
    }

    const appointmentRef = db.ref(`shops/${shopId}/appointments`).push();
    const barberName = request.body?.barberName || "";
    const serviceLabels = selectedServices.map((item) => item.label);

    await appointmentRef.set({
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
      totalPrice,
      totalMinutes,
      status: "pending",
      occupiedSlots: matchedSlot.occupiedSlots,
      createdAt: new Date().toISOString(),
      shopId,
      shopName: resolveShopDisplayName(shop),
    });

    const refreshedAppointments = appointments.concat([
      {
        id: appointmentRef.key,
        customerUid: decoded.uid,
        customerName,
        customerPhone,
        customerEmail,
        barberId,
        barberName,
        date: dateText,
        time: startTime,
        services: serviceLabels,
        status: "pending",
        totalPrice,
        totalMinutes,
        occupiedSlots: matchedSlot.occupiedSlots,
      },
    ]);

    await refreshAvailabilityForDate({
      db,
      shopId,
      shop,
      days,
      slotMinutes,
      serviceDurations,
      appointments: refreshedAppointments,
      dateText,
      barberIds: [barberId],
    });

    await sendOwnerNewBookingNotification({
      shop,
      appointment: {
        id: appointmentRef.key,
        customerName,
        barberName,
        date: dateText,
        time: startTime,
        services: serviceLabels,
      },
    });

    return json(response, 200, {
      ok: true,
      appointmentId: appointmentRef.key,
      occupiedSlots: matchedSlot.occupiedSlots,
      totalMinutes,
      totalPrice,
    });
  } catch (error) {
    console.error(error);
    return json(response, 500, {
      ok: false,
      message: "server-error",
      details: error.message || String(error),
    });
  }
});
exports.atelier22CancelAppointment = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const shopId = request.body?.shopId;
    const appointmentId = request.body?.appointmentId;

    if (!shopId || !appointmentId) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const {
      db,
      shop,
      days,
      slotMinutes,
      serviceDurations,
      appointments,
    } = await loadShopContext(shopId);

    const appointment = appointments.find((item) => item.id === appointmentId);
    if (!appointment) {
      return json(response, 404, {ok: false, message: "appointment-not-found"});
    }

    if (appointment.customerUid !== decoded.uid) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    if (normalizeAppointmentStatus(appointment.status) === "cancelled") {
      return json(response, 200, {
        ok: true,
        appointmentId,
        status: "cancelled",
      });
    }

    await db.ref(`shops/${shopId}/appointments/${appointmentId}`).update({
      status: "cancelled",
      cancelledAt: new Date().toISOString(),
      cancelledBy: "customer",
      updatedAt: new Date().toISOString(),
    });

    const refreshedAppointments = appointments
        .filter((item) => item.id !== appointmentId)
        .concat([
          {
            ...appointment,
            status: "cancelled",
          },
        ]);
    await refreshAvailabilityForDate({
      db,
      shopId,
      shop,
      days,
      slotMinutes,
      serviceDurations,
      appointments: refreshedAppointments,
      dateText: appointment.date,
      barberIds: [appointment.barberId],
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
      details: error.message || String(error),
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
    const serviceLabel = String(payload.serviceLabel || "").trim();
    const blockReason = String(payload.blockReason || "").trim();
    const explicitMinutes = Number.parseInt(payload.totalMinutes, 10);
    const explicitPrice = Number.parseInt(payload.totalPrice, 10);

    if (!requestedBarberId || !dateText || !startTime) {
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
      serviceDurations,
      servicePrices,
      appointments,
    } = await loadShopContext(shopId);

    const barber = findShopBarberById(shop, requestedBarberId);
    if (!barber) {
      return json(response, 404, {ok: false, message: "barber-not-found"});
    }

    if (!blocked && !customerName) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const selectedServices = blocked ? [] : buildServiceSelection(
        serviceKey ? [serviceKey] : [],
        serviceDurations,
        servicePrices,
    );
    const totalMinutes = Math.max(
        5,
        explicitMinutes > 0 ?
          explicitMinutes :
          (selectedServices.reduce((sum, item) => sum + item.minutes, 0) || slotMinutes),
    );
    const totalPrice = blocked ?
      0 :
      Math.max(
          0,
          explicitPrice >= 0 ?
            explicitPrice :
            selectedServices.reduce((sum, item) => sum + item.price, 0),
      );
    const availableSlots = computeAvailableSlots({
      days,
      appointments,
      appointmentsPerSlot,
      slotCapacityOverrides,
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
    const customerUid = blocked ? "" : await findOrCreateManualCustomer({
      db,
      shopId,
      customerName,
      customerPhone,
      customerEmail,
    });
    const effectiveServiceLabel = blocked ?
      "Blocked Slot" :
      (selectedServices[0]?.label || serviceLabel || "Manual Appointment");
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

    await appointmentRef.set(appointmentRecord);

    const refreshedAppointments = appointments.concat([
      {
        id: appointmentId,
        customerUid,
        customerName: appointmentRecord.customerName,
        customerPhone: appointmentRecord.customerPhone,
        customerEmail: appointmentRecord.customerEmail,
        barberId: requestedBarberId,
        barberName: barber.name,
        date: dateText,
        time: startTime,
        services: appointmentRecord.services,
        totalPrice,
        totalMinutes,
        status: "confirmed",
        blocked,
        blockReason,
        remindersSent: {},
        occupiedSlots: matchedSlot.occupiedSlots,
      },
    ]);

    await refreshAvailabilityForDate({
      db,
      shopId,
      shop,
      days,
      slotMinutes,
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
      details: error.message || String(error),
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
    const nextStatus = normalizeAppointmentStatus(request.body?.status);

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
      serviceDurations,
      appointments,
    } = await loadShopContext(shopId);

    const appointment = appointments.find((item) => item.id === appointmentId);
    if (!appointment) {
      return json(response, 404, {ok: false, message: "appointment-not-found"});
    }
    if (!access.permissions.manageAllAppointments &&
        String(appointment.barberId || "").trim() !== String(access.crewId || "").trim()) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    await db.ref(`shops/${shopId}/appointments/${appointmentId}`).update({
      status: nextStatus,
      updatedAt: new Date().toISOString(),
      ...(nextStatus === "cancelled" ? {
        cancelledAt: new Date().toISOString(),
        cancelledBy: "owner",
      } : {}),
      ...(nextStatus === "confirmed" ? {
        confirmedAt: new Date().toISOString(),
      } : {}),
    });

    const refreshedAppointments = appointments
        .filter((item) => item.id !== appointmentId)
        .concat([
          {
            ...appointment,
            status: nextStatus,
          },
        ]);

    if (
      isAppointmentBlockingStatus(appointment.status) !==
      isAppointmentBlockingStatus(nextStatus)
    ) {
      await refreshAvailabilityForDate({
        db,
        shopId,
        shop,
        days,
        slotMinutes,
        serviceDurations,
        appointments: refreshedAppointments,
        dateText: appointment.date,
        barberIds: [appointment.barberId],
      });
    }

    if (nextStatus === "confirmed" || nextStatus === "cancelled") {
      await sendCustomerLifecycleNotification({
        shop,
        appointment: {
          ...appointment,
          status: nextStatus,
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
      details: error.message || String(error),
    });
  }
});

exports.atelier22RescheduleAppointment = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const decoded = await authenticateRequest(request);
    const shopId = request.body?.shopId;
    const appointmentId = request.body?.appointmentId;
    const nextBarberId = request.body?.barberId;
    const nextDateText = request.body?.date;
    const nextStartTime = request.body?.startTime;

    if (!shopId || !appointmentId || !nextBarberId || !nextDateText || !nextStartTime) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }

    const {
      db,
      shop,
      days,
      slotMinutes,
      serviceDurations,
      appointments,
    } = await loadShopContext(shopId);

    const appointment = appointments.find((item) => item.id === appointmentId);
    if (!appointment) {
      return json(response, 404, {ok: false, message: "appointment-not-found"});
    }

    if (appointment.customerUid !== decoded.uid) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const appointmentsWithoutCurrent = appointments.filter(
        (item) => item.id !== appointmentId,
    );
    const requiredMinutes = appointment.totalMinutes > 0 ?
      appointment.totalMinutes :
      slotMinutes;
    const availableSlots = computeAvailableSlots({
      days,
      appointments: appointmentsWithoutCurrent,
      appointmentsPerSlot,
      slotCapacityOverrides,
      barberSchedules,
      barberId: nextBarberId,
      dateText: nextDateText,
      requiredMinutes,
    });
    const matchedSlot = availableSlots.find(
        (slot) => slot.startTime === nextStartTime,
    );
    if (!matchedSlot) {
      return json(response, 409, {
        ok: false,
        message: "slot-no-longer-available",
      });
    }

    const nextBarberName = request.body?.barberName || appointment.barberName || "";
    await db.ref(`shops/${shopId}/appointments/${appointmentId}`).update({
      barberId: nextBarberId,
      barberName: nextBarberName,
      date: nextDateText,
      time: nextStartTime,
      totalMinutes: requiredMinutes,
      occupiedSlots: matchedSlot.occupiedSlots,
      remindersSent: null,
      updatedAt: new Date().toISOString(),
    });

    const refreshedAppointments = appointmentsWithoutCurrent.concat([
      {
        ...appointment,
        barberId: nextBarberId,
        barberName: nextBarberName,
        date: nextDateText,
        time: nextStartTime,
        totalMinutes: requiredMinutes,
        occupiedSlots: matchedSlot.occupiedSlots,
      },
    ]);

    const datesToRefresh = Array.from(new Set([appointment.date, nextDateText]));
    for (const dateText of datesToRefresh) {
      await refreshAvailabilityForDate({
        db,
        shopId,
        shop,
        days,
        slotMinutes,
        serviceDurations,
        appointments: refreshedAppointments,
        dateText,
        barberIds: [appointment.barberId, nextBarberId],
      });
    }

    await sendCustomerLifecycleNotification({
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
      details: error.message || String(error),
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

    if (!requestedShopId || !appointmentId || !nextBarberId || !nextDateText || !nextStartTime) {
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
      serviceDurations,
      appointments,
    } = await loadShopContext(shopId);

    const appointment = appointments.find((item) => item.id === appointmentId);
    if (!appointment) {
      return json(response, 404, {ok: false, message: "appointment-not-found"});
    }
    if (!access.permissions.manageAllAppointments &&
        String(appointment.barberId || "").trim() !== String(access.crewId || "").trim()) {
      return json(response, 403, {ok: false, message: "forbidden"});
    }

    const appointmentsWithoutCurrent = appointments.filter(
        (item) => item.id !== appointmentId,
    );
    const requiredMinutes = appointment.totalMinutes > 0 ?
      appointment.totalMinutes :
      slotMinutes;
    const availableSlots = computeAvailableSlots({
      days,
      appointments: appointmentsWithoutCurrent,
      appointmentsPerSlot,
      slotCapacityOverrides,
      barberSchedules,
      barberId: nextBarberId,
      dateText: nextDateText,
      requiredMinutes,
    });
    const matchedSlot = availableSlots.find(
        (slot) => slot.startTime === nextStartTime,
    );
    if (!matchedSlot) {
      return json(response, 409, {
        ok: false,
        message: "slot-no-longer-available",
      });
    }

    const nextBarberName = request.body?.barberName || appointment.barberName || "";
    await db.ref(`shops/${shopId}/appointments/${appointmentId}`).update({
      barberId: nextBarberId,
      barberName: nextBarberName,
      date: nextDateText,
      time: nextStartTime,
      totalMinutes: requiredMinutes,
      occupiedSlots: matchedSlot.occupiedSlots,
      remindersSent: null,
      updatedAt: new Date().toISOString(),
    });

    const refreshedAppointments = appointmentsWithoutCurrent.concat([
      {
        ...appointment,
        barberId: nextBarberId,
        barberName: nextBarberName,
        date: nextDateText,
        time: nextStartTime,
        totalMinutes: requiredMinutes,
        occupiedSlots: matchedSlot.occupiedSlots,
      },
    ]);

    const datesToRefresh = Array.from(new Set([appointment.date, nextDateText]));
    for (const dateText of datesToRefresh) {
      await refreshAvailabilityForDate({
        db,
        shopId,
        shop,
        days,
        slotMinutes,
        serviceDurations,
        appointments: refreshedAppointments,
        dateText,
        barberIds: [appointment.barberId, nextBarberId],
      });
    }

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
      details: error.message || String(error),
    });
  }
});

exports.atelier22SendScheduledReminders = onSchedule(
    {
      schedule: "every 30 minutes",
      timeZone: "Europe/Athens",
    },
    async () => {
      const db = getDatabase();
      const shopsSnapshot = await db.ref("shops").get();
      if (!shopsSnapshot.exists()) {
        return;
      }

      const shops = shopsSnapshot.val() || {};
      const nowInfo = getAthensNowInfo();

      for (const [shopId, shop] of Object.entries(shops)) {
        const appointmentsMap =
          shop?.appointments && typeof shop.appointments === "object" ?
            shop.appointments :
            {};

        for (const [appointmentId, rawAppointment] of Object.entries(appointmentsMap)) {
          const appointment = {
            id: appointmentId,
            customerUid: rawAppointment?.customerUid || "",
            customerName: rawAppointment?.customerName || "",
            customerEmail: rawAppointment?.customerEmail || "",
            barberId: rawAppointment?.barberId || "",
            barberName: rawAppointment?.barberName || "",
            date: rawAppointment?.date || "",
            time: rawAppointment?.time || "",
            services: Array.isArray(rawAppointment?.services) ?
              rawAppointment.services :
              [],
            status: normalizeAppointmentStatus(rawAppointment?.status),
            remindersSent:
              rawAppointment?.remindersSent &&
              typeof rawAppointment.remindersSent === "object" ?
                rawAppointment.remindersSent :
                {},
          };

          if (appointment.status !== "confirmed") {
            continue;
          }

          const reminder = getAppointmentReminderDue(appointment, nowInfo);
          if (!reminder) {
            continue;
          }

          const sent = await sendCustomerReminderNotification({
            shop,
            appointment,
            reminder,
          });
          if (!sent) {
            continue;
          }

          await db.ref(
              `shops/${shopId}/appointments/${appointmentId}/remindersSent/${reminder.key}`,
          ).set(new Date().toISOString());
        }
      }
    },
);


