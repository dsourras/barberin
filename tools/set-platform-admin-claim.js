const path = require("node:path");
const {
  applicationDefault,
  cert,
  initializeApp,
} = require(path.join(
    __dirname,
    "..",
    "functions",
    "node_modules",
    "firebase-admin",
    "app",
));
const {getAuth} = require(path.join(
    __dirname,
    "..",
    "functions",
    "node_modules",
    "firebase-admin",
    "auth",
));

const projectId = process.env.FIREBASE_PROJECT_ID || "barbero-88d00";
const uid = String(process.argv[2] || "").trim();
const revoke = process.argv.includes("--revoke");

if (!uid) {
  console.error("Usage: node tools/set-platform-admin-claim.js <firebase-uid> [--revoke]");
  process.exit(1);
}

function buildCredential() {
  const rawServiceAccount = String(
      process.env.FIREBASE_SERVICE_ACCOUNT_JSON || "",
  ).trim();
  if (rawServiceAccount) {
    return cert(JSON.parse(rawServiceAccount));
  }
  return applicationDefault();
}

async function main() {
  initializeApp({
    credential: buildCredential(),
    projectId,
  });

  const auth = getAuth();
  const user = await auth.getUser(uid);
  const currentClaims = user.customClaims &&
      typeof user.customClaims === "object" ?
    {...user.customClaims} :
    {};
  const currentRoles = currentClaims.roles &&
      typeof currentClaims.roles === "object" ?
    {...currentClaims.roles} :
    {};

  if (revoke) {
    delete currentClaims.platformRole;
    delete currentClaims.platformAdmin;
    delete currentRoles.platformAdmin;
  } else {
    currentClaims.platformRole = "platform_admin";
    currentClaims.platformAdmin = true;
  }

  if (Object.keys(currentRoles).length > 0) {
    currentClaims.roles = currentRoles;
  } else {
    delete currentClaims.roles;
  }

  await auth.setCustomUserClaims(uid, currentClaims);
  console.log(JSON.stringify({
    ok: true,
    uid,
    email: user.email || "",
    role: revoke ? "revoked" : "platform_admin",
    refreshRequired: true,
  }, null, 2));
}

main().catch((error) => {
  console.error(error?.message || error);
  process.exit(1);
});
