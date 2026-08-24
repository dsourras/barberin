const {onRequest} = require("firebase-functions/v2/https");
const {setGlobalOptions} = require("firebase-functions/v2");
const {initializeApp} = require("firebase-admin/app");
const {getDatabase} = require("firebase-admin/database");
const {defineSecret} = require("firebase-functions/params");
const {randomUUID} = require("node:crypto");
const nodemailer = require("nodemailer");

initializeApp();

setGlobalOptions({
  region: "europe-west1",
  maxInstances: 10,
});

const SENDER_EMAIL = "dsourras@gmail.com";
const CONTACT_EMAIL = "oryn.barberin@gmail.com";
const contactSmtpPassword = defineSecret("CONTACT_SMTP_PASSWORD_DSOURRAS");

function json(response, status, body) {
  response.status(status).json(body);
}

function setCorsHeaders(request, response) {
  const allowedOrigins = new Set([
    "https://dsourras.github.io",
    "https://barbero-88d00.web.app",
    "https://barbero-88d00.firebaseapp.com",
  ]);
  const origin = String(request.get("origin") || "").trim();
  if (allowedOrigins.has(origin)) {
    response.set("Access-Control-Allow-Origin", origin);
  }
  response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  response.set("Access-Control-Allow-Headers", "Content-Type");
  response.set("Vary", "Origin");
}

exports.barberoSubmitContactRequest = onRequest(
  {secrets: [contactSmtpPassword]},
  async (request, response) => {
  setCorsHeaders(request, response);

  if (request.method === "OPTIONS") {
    return response.status(204).send("");
  }
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const body = request.body && typeof request.body === "object" ?
      request.body : {};

    // Ignore the hidden honeypot field without exposing whether a submission was stored.
    if (String(body.companyWebsite || "").trim()) {
      return json(response, 200, {ok: true});
    }

    const fullName = String(body.fullName || "").trim();
    const shopName = String(body.shopName || "").trim();
    const email = String(body.email || "").trim().toLowerCase();
    const phone = String(body.phone || "").trim();
    const shopCount = String(body.shopCount || "").trim();
    const preferredContact = String(body.preferredContact || "").trim();
    const message = String(body.message || "").trim();

    if (!fullName || !shopName || !email || !message) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return json(response, 400, {ok: false, message: "invalid-email"});
    }
    if ([fullName, shopName, email, phone, shopCount, preferredContact, message]
        .some((value) => value.length > 500)) {
      return json(response, 400, {ok: false, message: "field-too-long"});
    }

    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: {
        user: SENDER_EMAIL,
        pass: contactSmtpPassword.value().replace(/\s+/g, ""),
      },
    });
    await transporter.sendMail({
      from: `Barberin Website <${SENDER_EMAIL}>`,
      to: CONTACT_EMAIL,
      replyTo: email,
      subject: `Νέο αίτημα παρουσίασης από ${shopName}`,
      text: [
        `Όνομα: ${fullName}`,
        `Barber shop: ${shopName}`,
        `Email: ${email}`,
        `Τηλέφωνο: ${phone || "Δεν δόθηκε"}`,
        `Καταστήματα: ${shopCount || "Δεν δόθηκε"}`,
        `Προτιμώμενη επικοινωνία: ${preferredContact || "Δεν δόθηκε"}`,
        "",
        "Μήνυμα:",
        message,
      ].join("\n"),
    });

    const requestId = randomUUID();
    await getDatabase().ref(`contactRequests/${requestId}`).set({
      id: requestId,
      fullName,
      shopName,
      email,
      phone,
      shopCount,
      preferredContact,
      message,
      source: "barberin-website",
      status: "new",
      emailSentAt: new Date().toISOString(),
      createdAt: new Date().toISOString(),
    });

    return json(response, 200, {ok: true});
  } catch (error) {
    console.error(error);
    return json(response, 500, {ok: false, message: "server-error"});
  }
  },
);

exports.barberoSubmitAccountDeletionRequest = onRequest(
  {secrets: [contactSmtpPassword]},
  async (request, response) => {
  setCorsHeaders(request, response);

  if (request.method === "OPTIONS") {
    return response.status(204).send("");
  }
  if (request.method !== "POST") {
    return json(response, 405, {ok: false, message: "method-not-allowed"});
  }

  try {
    const body = request.body && typeof request.body === "object" ?
      request.body : {};

    if (String(body.companyWebsite || "").trim()) {
      return json(response, 200, {ok: true});
    }

    const email = String(body.email || "").trim().toLowerCase();
    const fullName = String(body.fullName || "").trim();
    const accountType = String(body.accountType || "").trim();
    const message = String(body.message || "").trim();
    const confirmed = body.confirmed === true || body.confirmed === "true";

    if (!email || !confirmed) {
      return json(response, 400, {ok: false, message: "missing-required-fields"});
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return json(response, 400, {ok: false, message: "invalid-email"});
    }
    if ([email, fullName, accountType, message].some((value) => value.length > 1000)) {
      return json(response, 400, {ok: false, message: "field-too-long"});
    }

    const requestId = randomUUID();
    const createdAt = new Date().toISOString();
    const requestRef = getDatabase().ref(`accountDeletionRequests/${requestId}`);
    await requestRef.set({
      id: requestId,
      email,
      fullName,
      accountType,
      message,
      source: "barberin-public-web-form",
      status: "requested",
      createdAt,
    });

    try {
      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SENDER_EMAIL,
          pass: contactSmtpPassword.value().replace(/\s+/g, ""),
        },
      });
      await transporter.sendMail({
        from: `Barberin Website <${SENDER_EMAIL}>`,
        to: CONTACT_EMAIL,
        replyTo: email,
        subject: "Barberin account deletion request",
        text: [
          "A user requested account and associated data deletion.",
          `Request ID: ${requestId}`,
          `Email: ${email}`,
          `Name: ${fullName || "Not provided"}`,
          `Account type: ${accountType || "Not provided"}`,
          `Details: ${message || "Not provided"}`,
        ].join("\n"),
      });
      await requestRef.update({
        status: "received",
        emailSentAt: new Date().toISOString(),
      });
    } catch (emailError) {
      console.error("account-deletion-request-email-failed", emailError);
      await requestRef.update({
        status: "received_email_pending",
        emailError: String(emailError?.message || emailError).slice(0, 500),
      });
    }

    return json(response, 200, {ok: true, requestId});
  } catch (error) {
    console.error(error);
    return json(response, 500, {ok: false, message: "server-error"});
  }
  },
);
