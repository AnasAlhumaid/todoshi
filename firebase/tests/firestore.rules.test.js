/**
 * Mandatory Firestore security rule tests for Todoshi collaboration.
 *
 * Run:
 *   cd firebase && npm install
 *   JAVA_HOME=… npm run test:rules
 *
 * Requires Firebase CLI, JDK 21+, and a Firestore emulator.
 */
const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { describe, it, before, after, beforeEach } = require("mocha");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  collectionGroup,
  getDocs,
  query,
  where,
  writeBatch,
  runTransaction,
} = require("firebase/firestore");

const PROJECT_ID = "todoshi-rules-test";
const RULES = fs.readFileSync(path.join(__dirname, "..", "firestore.rules"), "utf8");

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: RULES },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seedProject("p1", "frank", ["bob"], {
    carol: { role: "member" },
    frank: { role: "owner" },
  });
});

async function seedProject(projectId, ownerId, memberIds, memberships) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const adminDb = context.firestore();
    await adminDb.collection("projects").doc(projectId).set({
      id: projectId,
      ownerId,
      title: "Shared",
      description: "",
      color: "#5B8DEF",
      memberIds,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
    });
    for (const [uid, member] of Object.entries(memberships)) {
      await adminDb
        .collection("projects")
        .doc(projectId)
        .collection("members")
        .doc(uid)
        .set({
          userId: uid,
          role: member.role,
          displayName: null,
          joinedAt: new Date(),
        });
    }
    await adminDb.collection("projects").doc(projectId).collection("tasks").doc("t1").set({
      title: "Task",
      statusRaw: "todo",
      priorityRaw: "none",
      position: 1000,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  });
}

async function adminGet(pathSegments) {
  let snap;
  await testEnv.withSecurityRulesDisabled(async (context) => {
    snap = await context.firestore().doc(pathSegments.join("/")).get();
  });
  return snap;
}

function authedDb(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

function anonDb() {
  return testEnv.unauthenticatedContext().firestore();
}

function bootstrapProjectData(projectId, ownerId, overrides = {}) {
  return {
    id: projectId,
    ownerId,
    title: "Roadmap",
    description: "Notes",
    color: "#5B8DEF",
    memberIds: [ownerId],
    projectType: "tasks",
    createdAt: new Date(),
    updatedAt: new Date(),
    deletedAt: null,
    ...overrides,
  };
}

function bootstrapMemberData(ownerId, overrides = {}) {
  return {
    userId: ownerId,
    role: "owner",
    displayName: "Anas",
    joinedAt: new Date(),
    accessLevel: "full",
    ...overrides,
  };
}

async function commitOwnerBootstrap(db, projectId, ownerId, projectOverrides = {}, memberOverrides = {}) {
  const batch = writeBatch(db);
  const projectRef = doc(db, "projects", projectId);
  const memberRef = doc(db, "projects", projectId, "members", ownerId);
  batch.set(projectRef, bootstrapProjectData(projectId, ownerId, projectOverrides));
  batch.set(memberRef, bootstrapMemberData(ownerId, memberOverrides));
  return batch.commit();
}

describe("Todoshi Firestore rules — baseline", () => {
  it("1 anonymous cannot read shared project", async () => {
    await assertFails(getDoc(doc(anonDb(), "projects", "p1")));
  });

  it("2 non-member cannot read project", async () => {
    await assertFails(getDoc(doc(authedDb("alice"), "projects", "p1")));
  });

  it("3 memberIds only does not authorize", async () => {
    const db = authedDb("bob");
    await assertFails(getDoc(doc(db, "projects", "p1")));
    await assertFails(getDoc(doc(db, "projects", "p1", "tasks", "t1")));
  });

  it("4 membership document authorizes project read", async () => {
    await assertSucceeds(getDoc(doc(authedDb("carol"), "projects", "p1")));
  });

  it("5 member can read task", async () => {
    await assertSucceeds(getDoc(doc(authedDb("carol"), "projects", "p1", "tasks", "t1")));
  });

  it("6 non-member cannot read task", async () => {
    await assertFails(getDoc(doc(authedDb("dave"), "projects", "p1", "tasks", "t1")));
  });

  it("7 client cannot self-create membership on existing project", async () => {
    await assertFails(
      setDoc(doc(authedDb("eve"), "projects", "p1", "members", "eve"), {
        userId: "eve",
        role: "member",
        displayName: null,
        joinedAt: new Date(),
      })
    );
  });

  it("8 owner cannot directly mutate memberIds", async () => {
    await assertFails(
      updateDoc(doc(authedDb("frank"), "projects", "p1"), {
        memberIds: ["frank", "bob", "extra"],
      })
    );
  });

  it("9 owner cannot directly change ownerId", async () => {
    await assertFails(
      updateDoc(doc(authedDb("frank"), "projects", "p1"), {
        ownerId: "someone-else",
      })
    );
  });

  it("10 authenticated user can create own profile", async () => {
    await assertSucceeds(
      setDoc(doc(authedDb("self-user"), "users", "self-user"), {
        displayName: "Self",
        createdAt: new Date(),
        updatedAt: new Date(),
      })
    );
  });

  it("11 authenticated user cannot write another user profile", async () => {
    await assertFails(
      setDoc(doc(authedDb("self-user"), "users", "other-user"), {
        displayName: "Nope",
        updatedAt: new Date(),
      })
    );
  });

  it("12 authenticated user can update own profile", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("users").doc("self-user").set({
        displayName: "Existing",
        createdAt: new Date(),
        updatedAt: new Date(),
      });
    });
    await assertSucceeds(
      setDoc(
        doc(authedDb("self-user"), "users", "self-user"),
        { displayName: "Updated", updatedAt: new Date() },
        { merge: true }
      )
    );
  });

  it("15 member can read membership list", async () => {
    const db = authedDb("carol");
    await assertSucceeds(getDocs(collection(db, "projects", "p1", "members")));
    await assertSucceeds(getDoc(doc(db, "projects", "p1", "members", "carol")));
  });

  it("16 non-member cannot read memberships", async () => {
    const db = authedDb("alice");
    await assertFails(getDocs(collection(db, "projects", "p1", "members")));
    await assertFails(getDoc(doc(db, "projects", "p1", "members", "carol")));
  });
});

describe("Todoshi Firestore rules — Phase 2 owner bootstrap", () => {
  it("A1 authenticated user can atomically create own project + owner membership", async () => {
    const db = authedDb("owner-1");
    await assertSucceeds(commitOwnerBootstrap(db, "proj-new-1", "owner-1"));
  });

  it("A2 bootstrap project can be read afterward by owner", async () => {
    const db = authedDb("owner-1");
    await commitOwnerBootstrap(db, "proj-new-2", "owner-1");
    await assertSucceeds(getDoc(doc(db, "projects", "proj-new-2")));
  });

  it("A3 owner membership can be read afterward", async () => {
    const db = authedDb("owner-1");
    await commitOwnerBootstrap(db, "proj-new-3", "owner-1");
    await assertSucceeds(getDoc(doc(db, "projects", "proj-new-3", "members", "owner-1")));
  });

  it("D4 project create without owner membership in same batch is denied and commits nothing", async () => {
    const db = authedDb("owner-1");
    const projectId = "proj-only-project";
    await assertFails(
      setDoc(doc(db, "projects", projectId), bootstrapProjectData(projectId, "owner-1"))
    );
    const snap = await adminGet(["projects", projectId]);
    if (snap.exists) {
      throw new Error("Atomicity failure: project document was committed without membership");
    }
  });

  it("D5 owner membership create without project in same batch is denied and commits nothing", async () => {
    const db = authedDb("owner-1");
    const projectId = "proj-only-member";
    await assertFails(
      setDoc(
        doc(db, "projects", projectId, "members", "owner-1"),
        bootstrapMemberData("owner-1")
      )
    );
    const memberSnap = await adminGet(["projects", projectId, "members", "owner-1"]);
    const projectSnap = await adminGet(["projects", projectId]);
    if (memberSnap.exists || projectSnap.exists) {
      throw new Error("Atomicity failure: membership/project committed without paired bootstrap");
    }
  });

  it("D6 create project with ownerId != auth.uid is denied", async () => {
    const db = authedDb("owner-1");
    await assertFails(
      commitOwnerBootstrap(db, "proj-bad-owner", "owner-1", { ownerId: "other-user" })
    );
  });

  it("D7 create project with extra/different memberIds is denied", async () => {
    const db = authedDb("owner-1");
    await assertFails(
      commitOwnerBootstrap(db, "proj-bad-members", "owner-1", {
        memberIds: ["owner-1", "intruder"],
      })
    );
    await assertFails(
      commitOwnerBootstrap(db, "proj-bad-members-2", "owner-1", {
        memberIds: ["someone-else"],
      })
    );
  });

  it("D8 create initial membership with role != owner is denied", async () => {
    const db = authedDb("owner-1");
    await assertFails(
      commitOwnerBootstrap(db, "proj-bad-role", "owner-1", {}, { role: "member" })
    );
  });

  it("D9 create membership for another UID is denied", async () => {
    const db = authedDb("owner-1");
    const projectId = "proj-other-member";
    const batch = writeBatch(db);
    batch.set(doc(db, "projects", projectId), bootstrapProjectData(projectId, "owner-1"));
    batch.set(
      doc(db, "projects", projectId, "members", "other-user"),
      bootstrapMemberData("other-user")
    );
    await assertFails(batch.commit());
  });

  it("D10 add membership to an already-existing project is denied", async () => {
    await assertFails(
      setDoc(doc(authedDb("alice"), "projects", "p1", "members", "alice"), {
        userId: "alice",
        role: "owner",
        displayName: "Alice",
        joinedAt: new Date(),
      })
    );
  });

  it("D11 add self to someone else's project is denied", async () => {
    await assertFails(
      setDoc(doc(authedDb("eve"), "projects", "p1", "members", "eve"), {
        userId: "eve",
        role: "member",
        displayName: "Eve",
        joinedAt: new Date(),
      })
    );
  });

  it("D12 directly mutate memberIds after bootstrap is denied", async () => {
    const db = authedDb("owner-1");
    await commitOwnerBootstrap(db, "proj-mutate-members", "owner-1");
    await assertFails(
      updateDoc(doc(db, "projects", "proj-mutate-members"), {
        memberIds: ["owner-1", "extra"],
      })
    );
  });

  it("D13 directly mutate ownerId after bootstrap is denied", async () => {
    const db = authedDb("owner-1");
    await commitOwnerBootstrap(db, "proj-mutate-owner", "owner-1");
    await assertFails(
      updateDoc(doc(db, "projects", "proj-mutate-owner"), {
        ownerId: "hijacker",
      })
    );
  });

  it("D14 anonymous bootstrap is denied", async () => {
    const db = anonDb();
    await assertFails(commitOwnerBootstrap(db, "proj-anon", "anon-uid"));
  });

  it("D15 memberIds-only access without membership document is denied", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("projects").doc("proj-ids-only").set({
        id: "proj-ids-only",
        ownerId: "listed-user",
        title: "Listed",
        description: "",
        color: "#5B8DEF",
        memberIds: ["listed-user"],
        createdAt: new Date(),
        updatedAt: new Date(),
        deletedAt: null,
      });
    });
    await assertFails(getDoc(doc(authedDb("listed-user"), "projects", "proj-ids-only")));
  });

  it("atomicity: failed paired batch leaves neither document", async () => {
    const db = authedDb("owner-1");
    const projectId = "proj-atomic-fail";
    // Mismatched membership role forces membership create to fail → whole batch fails.
    await assertFails(
      commitOwnerBootstrap(db, projectId, "owner-1", {}, { role: "member" })
    );
    const projectSnap = await adminGet(["projects", projectId]);
    const memberSnap = await adminGet(["projects", projectId, "members", "owner-1"]);
    if (projectSnap.exists || memberSnap.exists) {
      throw new Error("Atomicity failure: partial bootstrap documents were committed");
    }
  });
});

const {
  arrayUnion,
  arrayRemove,
  serverTimestamp,
  Timestamp,
} = require("firebase/firestore");

/** ~43-char URL-safe token shape matching iOS SecRandom Base64url output. */
function makeInviteToken(tag) {
  const raw = `tok_${tag}_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijk`;
  return raw.replace(/[^A-Za-z0-9_-]/g, "x").slice(0, 43).padEnd(43, "x");
}

function futureExpiry(days = 6) {
  return new Date(Date.now() + days * 24 * 60 * 60 * 1000);
}

function pastExpiry() {
  return new Date(Date.now() - 60 * 1000);
}

function inviteCreateData(projectId, createdBy, overrides = {}) {
  return {
    projectId,
    createdBy,
    role: "member",
    projectTitle: "Shared",
    inviterDisplayName: "Owner",
    createdAt: new Date(),
    expiresAt: futureExpiry(),
    acceptedAt: null,
    acceptedBy: null,
    revokedAt: null,
    ...overrides,
  };
}

async function seedInvite(token, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection("projectInvites").doc(token).set(data);
  });
}

async function commitInviteAcceptance(db, token, projectId, uid, memberOverrides = {}, projectUpdate = null) {
  const batch = writeBatch(db);
  const inviteRef = doc(db, "projectInvites", token);
  const memberRef = doc(db, "projects", projectId, "members", uid);
  const projectRef = doc(db, "projects", projectId);
  batch.update(inviteRef, {
    acceptedBy: uid,
    acceptedAt: serverTimestamp(),
  });
  batch.set(memberRef, {
    userId: uid,
    role: "member",
    displayName: "Joiner",
    joinedAt: new Date(),
    acceptedInviteId: token,
    accessLevel: "restricted",
    ...memberOverrides,
  });
  if (projectUpdate) {
    batch.update(projectRef, projectUpdate);
  } else {
    batch.update(projectRef, { memberIds: arrayUnion(uid) });
  }
  return batch.commit();
}

/** Owner promotes a restricted invitee to full task collaboration (legacy Phase 4/5 test helper). */
async function promoteMemberToFull(ownerId, projectId, memberId) {
  await assertSucceeds(
    updateDoc(doc(authedDb(ownerId), "projects", projectId, "members", memberId), {
      accessLevel: "full",
    })
  );
}

describe("Todoshi Firestore rules — Phase 3 invites", () => {
  const TOKEN = () => makeInviteToken("owner");

  it("1 owner can create valid invite", async () => {
    const token = makeInviteToken("c1");
    await assertSucceeds(
      setDoc(doc(authedDb("frank"), "projectInvites", token), inviteCreateData("p1", "frank"))
    );
  });

  it("2 member cannot create invite", async () => {
    const token = makeInviteToken("c2");
    await assertFails(
      setDoc(doc(authedDb("carol"), "projectInvites", token), inviteCreateData("p1", "carol"))
    );
  });

  it("3 non-member cannot create invite", async () => {
    const token = makeInviteToken("c3");
    await assertFails(
      setDoc(doc(authedDb("alice"), "projectInvites", token), inviteCreateData("p1", "alice"))
    );
  });

  it("4 anonymous cannot create invite", async () => {
    const token = makeInviteToken("c4");
    await assertFails(
      setDoc(doc(anonDb(), "projectInvites", token), inviteCreateData("p1", "anon"))
    );
  });

  it("5 owner cannot create owner-role invite", async () => {
    const token = makeInviteToken("c5");
    await assertFails(
      setDoc(
        doc(authedDb("frank"), "projectInvites", token),
        inviteCreateData("p1", "frank", { role: "owner" })
      )
    );
  });

  it("6 invalid expiration denied", async () => {
    const token = makeInviteToken("c6a");
    await assertFails(
      setDoc(
        doc(authedDb("frank"), "projectInvites", token),
        inviteCreateData("p1", "frank", { expiresAt: pastExpiry() })
      )
    );
    const tokenFar = makeInviteToken("c6b");
    await assertFails(
      setDoc(
        doc(authedDb("frank"), "projectInvites", tokenFar),
        inviteCreateData("p1", "frank", {
          expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
        })
      )
    );
  });

  it("7 unexpected fields denied", async () => {
    const token = makeInviteToken("c7");
    await assertFails(
      setDoc(doc(authedDb("frank"), "projectInvites", token), {
        ...inviteCreateData("p1", "frank"),
        token: "must-not-exist",
      })
    );
  });

  it("8 valid signed-in bearer-token GET allowed", async () => {
    const token = makeInviteToken("r8");
    await seedInvite(token, inviteCreateData("p1", "frank"));
    await assertSucceeds(getDoc(doc(authedDb("alice"), "projectInvites", token)));
  });

  it("9 invite collection LIST denied to random user", async () => {
    const token = makeInviteToken("r9");
    await seedInvite(token, inviteCreateData("p1", "frank"));
    await assertFails(getDocs(collection(authedDb("alice"), "projectInvites")));
  });

  it("10 expired invite cannot authorize acceptance", async () => {
    await commitOwnerBootstrap(authedDb("owner-exp"), "proj-exp", "owner-exp");
    const token = makeInviteToken("exp10");
    await seedInvite(
      token,
      inviteCreateData("proj-exp", "owner-exp", { expiresAt: pastExpiry() })
    );
    await assertFails(commitInviteAcceptance(authedDb("joiner-exp"), token, "proj-exp", "joiner-exp"));
  });

  it("11 revoked invite cannot authorize acceptance", async () => {
    await commitOwnerBootstrap(authedDb("owner-rev"), "proj-rev", "owner-rev");
    const token = makeInviteToken("rev11");
    await seedInvite(
      token,
      inviteCreateData("proj-rev", "owner-rev", { revokedAt: new Date() })
    );
    await assertFails(commitInviteAcceptance(authedDb("joiner-rev"), token, "proj-rev", "joiner-rev"));
  });

  it("12 valid three-write batch succeeds", async () => {
    await commitOwnerBootstrap(authedDb("owner-ok"), "proj-ok", "owner-ok");
    const token = makeInviteToken("ok12");
    await seedInvite(token, inviteCreateData("proj-ok", "owner-ok"));
    await assertSucceeds(commitInviteAcceptance(authedDb("member-a"), token, "proj-ok", "member-a"));
  });

  it("13 membership created as member", async () => {
    await commitOwnerBootstrap(authedDb("owner-m"), "proj-m", "owner-m");
    const token = makeInviteToken("m13");
    await seedInvite(token, inviteCreateData("proj-m", "owner-m"));
    await commitInviteAcceptance(authedDb("member-b"), token, "proj-m", "member-b");
    const snap = await adminGet(["projects", "proj-m", "members", "member-b"]);
    if (!snap.exists || snap.data().role !== "member") {
      throw new Error("Expected member role membership");
    }
  });

  it("14 project memberIds adds exactly current UID", async () => {
    await commitOwnerBootstrap(authedDb("owner-ids"), "proj-ids", "owner-ids");
    const token = makeInviteToken("ids14");
    await seedInvite(token, inviteCreateData("proj-ids", "owner-ids"));
    await commitInviteAcceptance(authedDb("member-c"), token, "proj-ids", "member-c");
    const snap = await adminGet(["projects", "proj-ids"]);
    const ids = snap.data().memberIds || [];
    if (!(ids.includes("owner-ids") && ids.includes("member-c") && ids.length === 2)) {
      throw new Error(`Unexpected memberIds: ${JSON.stringify(ids)}`);
    }
  });

  it("15 invite becomes accepted by UID", async () => {
    await commitOwnerBootstrap(authedDb("owner-acc"), "proj-acc", "owner-acc");
    const token = makeInviteToken("acc15");
    await seedInvite(token, inviteCreateData("proj-acc", "owner-acc"));
    await commitInviteAcceptance(authedDb("member-d"), token, "proj-acc", "member-d");
    const snap = await adminGet(["projectInvites", token]);
    if (snap.data().acceptedBy !== "member-d" || !snap.data().acceptedAt) {
      throw new Error("Invite not marked accepted");
    }
  });

  it("16 reuse same invite denied", async () => {
    await commitOwnerBootstrap(authedDb("owner-reuse"), "proj-reuse", "owner-reuse");
    const token = makeInviteToken("reuse16");
    await seedInvite(token, inviteCreateData("proj-reuse", "owner-reuse"));
    await commitInviteAcceptance(authedDb("member-e"), token, "proj-reuse", "member-e");
    await assertFails(
      commitInviteAcceptance(authedDb("member-f"), token, "proj-reuse", "member-f")
    );
  });

  it("17 accept membership without invite update denied", async () => {
    await commitOwnerBootstrap(authedDb("owner-17"), "proj-17", "owner-17");
    const token = makeInviteToken("t17");
    await seedInvite(token, inviteCreateData("proj-17", "owner-17"));
    const db = authedDb("join-17");
    const batch = writeBatch(db);
    batch.set(doc(db, "projects", "proj-17", "members", "join-17"), {
      userId: "join-17",
      role: "member",
      displayName: null,
      joinedAt: new Date(),
      acceptedInviteId: token,
    });
    batch.update(doc(db, "projects", "proj-17"), { memberIds: arrayUnion("join-17") });
    await assertFails(batch.commit());
  });

  it("18 accept invite without membership creation denied", async () => {
    await commitOwnerBootstrap(authedDb("owner-18"), "proj-18", "owner-18");
    const token = makeInviteToken("t18");
    await seedInvite(token, inviteCreateData("proj-18", "owner-18"));
    const db = authedDb("join-18");
    const batch = writeBatch(db);
    batch.update(doc(db, "projectInvites", token), {
      acceptedBy: "join-18",
      acceptedAt: serverTimestamp(),
    });
    batch.update(doc(db, "projects", "proj-18"), { memberIds: arrayUnion("join-18") });
    await assertFails(batch.commit());
  });

  it("19 accept invite without project memberIds update denied", async () => {
    await commitOwnerBootstrap(authedDb("owner-19"), "proj-19", "owner-19");
    const token = makeInviteToken("t19");
    await seedInvite(token, inviteCreateData("proj-19", "owner-19"));
    const db = authedDb("join-19");
    const batch = writeBatch(db);
    batch.update(doc(db, "projectInvites", token), {
      acceptedBy: "join-19",
      acceptedAt: serverTimestamp(),
    });
    batch.set(doc(db, "projects", "proj-19", "members", "join-19"), {
      userId: "join-19",
      role: "member",
      displayName: null,
      joinedAt: new Date(),
      acceptedInviteId: token,
    });
    await assertFails(batch.commit());
  });

  it("20 add another arbitrary UID denied", async () => {
    await commitOwnerBootstrap(authedDb("owner-20"), "proj-20", "owner-20");
    const token = makeInviteToken("t20");
    await seedInvite(token, inviteCreateData("proj-20", "owner-20"));
    await assertFails(
      commitInviteAcceptance(authedDb("join-20"), token, "proj-20", "join-20", {}, {
        memberIds: ["owner-20", "join-20", "intruder"],
      })
    );
  });

  it("21 role owner/admin escalation denied", async () => {
    await commitOwnerBootstrap(authedDb("owner-21"), "proj-21", "owner-21");
    const token = makeInviteToken("t21");
    await seedInvite(token, inviteCreateData("proj-21", "owner-21"));
    await assertFails(
      commitInviteAcceptance(authedDb("join-21"), token, "proj-21", "join-21", { role: "owner" })
    );
    await assertFails(
      commitInviteAcceptance(authedDb("join-21b"), token, "proj-21", "join-21b", { role: "admin" })
    );
  });

  it("22 accept invitation for wrong project denied", async () => {
    await commitOwnerBootstrap(authedDb("owner-22a"), "proj-22a", "owner-22a");
    await commitOwnerBootstrap(authedDb("owner-22b"), "proj-22b", "owner-22b");
    const token = makeInviteToken("t22");
    await seedInvite(token, inviteCreateData("proj-22a", "owner-22a"));
    await assertFails(
      commitInviteAcceptance(authedDb("join-22"), token, "proj-22b", "join-22")
    );
  });

  it("23 change project owner during acceptance denied", async () => {
    await commitOwnerBootstrap(authedDb("owner-23"), "proj-23", "owner-23");
    const token = makeInviteToken("t23");
    await seedInvite(token, inviteCreateData("proj-23", "owner-23"));
    await assertFails(
      commitInviteAcceptance(authedDb("join-23"), token, "proj-23", "join-23", {}, {
        memberIds: arrayUnion("join-23"),
        ownerId: "join-23",
      })
    );
  });

  it("24 modify unrelated project field denied", async () => {
    await commitOwnerBootstrap(authedDb("owner-24"), "proj-24", "owner-24");
    const token = makeInviteToken("t24");
    await seedInvite(token, inviteCreateData("proj-24", "owner-24"));
    await assertFails(
      commitInviteAcceptance(authedDb("join-24"), token, "proj-24", "join-24", {}, {
        memberIds: arrayUnion("join-24"),
        title: "Hijacked",
      })
    );
  });

  it("25 direct self-membership without invite denied", async () => {
    await commitOwnerBootstrap(authedDb("owner-25"), "proj-25", "owner-25");
    await assertFails(
      setDoc(doc(authedDb("join-25"), "projects", "proj-25", "members", "join-25"), {
        userId: "join-25",
        role: "member",
        displayName: null,
        joinedAt: new Date(),
        acceptedInviteId: makeInviteToken("missing"),
      })
    );
  });

  it("26 memberIds-only access remains unauthorized", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("projects").doc("proj-midsonly").set({
        id: "proj-midsonly",
        ownerId: "listed",
        title: "Listed",
        description: "",
        color: "#5B8DEF",
        memberIds: ["listed"],
        createdAt: new Date(),
        updatedAt: new Date(),
        deletedAt: null,
      });
    });
    await assertFails(getDoc(doc(authedDb("listed"), "projects", "proj-midsonly")));
  });

  it("27 failed membership validation leaves invite unchanged", async () => {
    await commitOwnerBootstrap(authedDb("owner-27"), "proj-27", "owner-27");
    const token = makeInviteToken("t27");
    await seedInvite(token, inviteCreateData("proj-27", "owner-27"));
    await assertFails(
      commitInviteAcceptance(authedDb("join-27"), token, "proj-27", "join-27", { role: "owner" })
    );
    const snap = await adminGet(["projectInvites", token]);
    if (snap.data().acceptedBy != null) {
      throw new Error("Atomicity failure: invite accepted despite failed membership");
    }
  });

  it("28 failed project update leaves no membership", async () => {
    await commitOwnerBootstrap(authedDb("owner-28"), "proj-28", "owner-28");
    const token = makeInviteToken("t28");
    await seedInvite(token, inviteCreateData("proj-28", "owner-28"));
    await assertFails(
      commitInviteAcceptance(authedDb("join-28"), token, "proj-28", "join-28", {}, {
        memberIds: arrayUnion("join-28"),
        title: "Nope",
      })
    );
    const memberSnap = await adminGet(["projects", "proj-28", "members", "join-28"]);
    if (memberSnap.exists) {
      throw new Error("Atomicity failure: membership committed without valid project update");
    }
  });

  it("29 failed invite validation leaves no partial writes", async () => {
    await commitOwnerBootstrap(authedDb("owner-29"), "proj-29", "owner-29");
    const token = makeInviteToken("t29");
    await seedInvite(
      token,
      inviteCreateData("proj-29", "owner-29", { expiresAt: pastExpiry() })
    );
    await assertFails(commitInviteAcceptance(authedDb("join-29"), token, "proj-29", "join-29"));
    const memberSnap = await adminGet(["projects", "proj-29", "members", "join-29"]);
    const projectSnap = await adminGet(["projects", "proj-29"]);
    if (memberSnap.exists) {
      throw new Error("Atomicity failure: membership written for expired invite");
    }
    if ((projectSnap.data().memberIds || []).includes("join-29")) {
      throw new Error("Atomicity failure: memberIds mutated for expired invite");
    }
  });

  it("owner can revoke unused invite", async () => {
    const token = makeInviteToken("revoke");
    await seedInvite(token, inviteCreateData("p1", "frank"));
    await assertSucceeds(
      updateDoc(doc(authedDb("frank"), "projectInvites", token), {
        revokedAt: serverTimestamp(),
      })
    );
  });

  it("discovery list query allows memberIds arrayContains when listed", async () => {
    await commitOwnerBootstrap(authedDb("owner-disc"), "proj-disc", "owner-disc");
    const db = authedDb("owner-disc");
    const { query, where, getDocs: getDocsQuery } = require("firebase/firestore");
    await assertSucceeds(
      getDocsQuery(query(collection(db, "projects"), where("memberIds", "array-contains", "owner-disc")))
    );
  });
});

describe("Todoshi Firestore rules — Phase 4 content sync", () => {
  async function seedOwnedProject(ownerId, projectId) {
    await commitOwnerBootstrap(authedDb(ownerId), projectId, ownerId);
  }

  function validTask(projectId, taskId, overrides = {}) {
    return {
      id: taskId,
      projectId,
      title: "Task",
      description: "",
      notes: "",
      statusRaw: "todo",
      priorityRaw: "none",
      position: 1000,
      parentTaskId: null,
      dueDate: null,
      reminderDate: null,
      completedAt: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
      labelIds: [],
      recurrenceRuleRaw: null,
      recurrenceInterval: null,
      recurrenceSeriesID: null,
      recurrenceGeneration: 0,
      nextOccurrenceID: null,
      previousOccurrenceID: null,
      ...overrides,
    };
  }

  it("P4-1 non-member cannot read/write tasks", async () => {
    await seedOwnedProject("owner-p4", "proj-p4");
    await assertFails(getDoc(doc(authedDb("stranger"), "projects", "proj-p4", "tasks", "t1")));
    await assertFails(
      setDoc(doc(authedDb("stranger"), "projects", "proj-p4", "tasks", "t1"), validTask("proj-p4", "t1"))
    );
  });

  it("P4-2 member can create valid task", async () => {
    await seedOwnedProject("owner-p4b", "proj-p4b");
    const token = makeInviteToken("p4b");
    await seedInvite(token, inviteCreateData("proj-p4b", "owner-p4b"));
    await commitInviteAcceptance(authedDb("member-p4b"), token, "proj-p4b", "member-p4b");
    await promoteMemberToFull("owner-p4b", "proj-p4b", "member-p4b");
    await assertSucceeds(
      setDoc(doc(authedDb("member-p4b"), "projects", "proj-p4b", "tasks", "task-1"), validTask("proj-p4b", "task-1"))
    );
  });

  it("P4-3 invalid status denied", async () => {
    await seedOwnedProject("owner-p4c", "proj-p4c");
    await assertFails(
      setDoc(
        doc(authedDb("owner-p4c"), "projects", "proj-p4c", "tasks", "bad"),
        validTask("proj-p4c", "bad", { statusRaw: "flying" })
      )
    );
  });

  it("P4-4 wrong projectId denied", async () => {
    await seedOwnedProject("owner-p4d", "proj-p4d");
    await assertFails(
      setDoc(
        doc(authedDb("owner-p4d"), "projects", "proj-p4d", "tasks", "t"),
        validTask("other-project", "t")
      )
    );
  });

  it("P4-5 checklist member write allowed; stranger denied", async () => {
    await seedOwnedProject("owner-p4e", "proj-p4e");
    await setDoc(doc(authedDb("owner-p4e"), "projects", "proj-p4e", "tasks", "t2"), validTask("proj-p4e", "t2"));
    await assertSucceeds(
      setDoc(doc(authedDb("owner-p4e"), "projects", "proj-p4e", "tasks", "t2", "checklist", "c1"), {
        id: "c1",
        title: "Item",
        isCompleted: false,
        position: 1,
        createdAt: new Date(),
        updatedAt: new Date(),
        deletedAt: null,
      })
    );
    await assertFails(
      setDoc(doc(authedDb("stranger"), "projects", "proj-p4e", "tasks", "t2", "checklist", "c2"), {
        id: "c2",
        title: "Nope",
        isCompleted: false,
        position: 1,
        createdAt: new Date(),
        updatedAt: new Date(),
        deletedAt: null,
      })
    );
  });

  it("P4-6 binary resource kind denied; link allowed", async () => {
    await seedOwnedProject("owner-p4f", "proj-p4f");
    await setDoc(doc(authedDb("owner-p4f"), "projects", "proj-p4f", "tasks", "t3"), validTask("proj-p4f", "t3"));
    await assertFails(
      setDoc(doc(authedDb("owner-p4f"), "projects", "proj-p4f", "tasks", "t3", "resources", "r1"), {
        id: "r1",
        kindRaw: "image",
        title: "Photo",
        position: 1,
        createdAt: new Date(),
        updatedAt: new Date(),
        deletedAt: null,
      })
    );
    await assertSucceeds(
      setDoc(doc(authedDb("owner-p4f"), "projects", "proj-p4f", "tasks", "t3", "resources", "r2"), {
        id: "r2",
        kindRaw: "link",
        title: "Docs",
        body: null,
        externalURLString: "https://example.com",
        languageIdentifier: null,
        position: 1,
        createdAt: new Date(),
        updatedAt: new Date(),
        deletedAt: null,
      })
    );
  });

  it("P4-7 label member write; soft-delete task fields", async () => {
    await seedOwnedProject("owner-p4g", "proj-p4g");
    await assertSucceeds(
      setDoc(doc(authedDb("owner-p4g"), "projects", "proj-p4g", "labels", "lab1"), {
        id: "lab1",
        name: "Bug",
        color: "#5B8DEF",
        createdAt: new Date(),
        updatedAt: new Date(),
        deletedAt: null,
      })
    );
    const taskId = "del-task";
    await setDoc(doc(authedDb("owner-p4g"), "projects", "proj-p4g", "tasks", taskId), validTask("proj-p4g", taskId));
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p4g"), "projects", "proj-p4g", "tasks", taskId),
        validTask("proj-p4g", taskId, { deletedAt: new Date(), statusRaw: "done" })
      )
    );
  });

  it("P4-S1 member creates root then subtask with parentTaskId", async () => {
    await seedOwnedProject("owner-sub", "proj-sub");
    const token = makeInviteToken("sub1");
    await seedInvite(token, inviteCreateData("proj-sub", "owner-sub"));
    await commitInviteAcceptance(authedDb("member-sub"), token, "proj-sub", "member-sub");
    await promoteMemberToFull("owner-sub", "proj-sub", "member-sub");

    await assertSucceeds(
      setDoc(doc(authedDb("member-sub"), "projects", "proj-sub", "tasks", "root-1"), validTask("proj-sub", "root-1"))
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-sub"), "projects", "proj-sub", "tasks", "child-1"),
        validTask("proj-sub", "child-1", { parentTaskId: "root-1", title: "Subtask A" })
      )
    );
    const snap = await getDoc(doc(authedDb("member-sub"), "projects", "proj-sub", "tasks", "child-1"));
    if (!snap.exists() || snap.data().parentTaskId !== "root-1") {
      throw new Error("Subtask missing parentTaskId");
    }
  });

  it("P4-S2 another member can read subtask; non-member cannot", async () => {
    await seedOwnedProject("owner-sub2", "proj-sub2");
    const tokenA = makeInviteToken("sub2a");
    const tokenB = makeInviteToken("sub2b");
    await seedInvite(tokenA, inviteCreateData("proj-sub2", "owner-sub2"));
    await seedInvite(tokenB, inviteCreateData("proj-sub2", "owner-sub2"));
    await commitInviteAcceptance(authedDb("member-a"), tokenA, "proj-sub2", "member-a");
    await commitInviteAcceptance(authedDb("member-b"), tokenB, "proj-sub2", "member-b");
    await promoteMemberToFull("owner-sub2", "proj-sub2", "member-a");

    await setDoc(doc(authedDb("member-a"), "projects", "proj-sub2", "tasks", "root-2"), validTask("proj-sub2", "root-2"));
    await setDoc(
      doc(authedDb("member-a"), "projects", "proj-sub2", "tasks", "child-2"),
      validTask("proj-sub2", "child-2", { parentTaskId: "root-2" })
    );
    await assertSucceeds(getDoc(doc(authedDb("member-b"), "projects", "proj-sub2", "tasks", "child-2")));
    await assertFails(getDoc(doc(authedDb("stranger-sub"), "projects", "proj-sub2", "tasks", "child-2")));
  });

  it("P4-S3 cross-project parentTaskId denied", async () => {
    await seedOwnedProject("owner-xa", "proj-xa");
    await seedOwnedProject("owner-xb", "proj-xb");
    await setDoc(doc(authedDb("owner-xa"), "projects", "proj-xa", "tasks", "root-xa"), validTask("proj-xa", "root-xa"));
    await assertFails(
      setDoc(
        doc(authedDb("owner-xb"), "projects", "proj-xb", "tasks", "child-xb"),
        validTask("proj-xb", "child-xb", { parentTaskId: "root-xa" })
      )
    );
  });

  it("P4-S4 member updates subtask title/status and soft-deletes", async () => {
    await seedOwnedProject("owner-su", "proj-su");
    await setDoc(doc(authedDb("owner-su"), "projects", "proj-su", "tasks", "root-su"), validTask("proj-su", "root-su"));
    await setDoc(
      doc(authedDb("owner-su"), "projects", "proj-su", "tasks", "child-su"),
      validTask("proj-su", "child-su", { parentTaskId: "root-su" })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-su"), "projects", "proj-su", "tasks", "child-su"),
        validTask("proj-su", "child-su", { parentTaskId: "root-su", title: "Renamed", statusRaw: "done" })
      )
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-su"), "projects", "proj-su", "tasks", "child-su"),
        validTask("proj-su", "child-su", {
          parentTaskId: "root-su",
          title: "Renamed",
          statusRaw: "done",
          deletedAt: new Date(),
        })
      )
    );
  });

  it("P4-S5 missing parent reference denied", async () => {
    await seedOwnedProject("owner-miss", "proj-miss");
    await assertFails(
      setDoc(
        doc(authedDb("owner-miss"), "projects", "proj-miss", "tasks", "orphan"),
        validTask("proj-miss", "orphan", { parentTaskId: "does-not-exist" })
      )
    );
  });
});

describe("Todoshi Firestore rules — Phase 5 comments", () => {
  async function seedOwnedProject(ownerId, projectId) {
    await commitOwnerBootstrap(authedDb(ownerId), projectId, ownerId);
  }

  async function addMember(ownerId, projectId, memberId) {
    const token = makeInviteToken(`c-${memberId}`);
    await seedInvite(token, inviteCreateData(projectId, ownerId));
    await commitInviteAcceptance(authedDb(memberId), token, projectId, memberId);
    await promoteMemberToFull(ownerId, projectId, memberId);
  }

  function validTask(projectId, taskId, overrides = {}) {
    return {
      id: taskId,
      projectId,
      title: "Task",
      description: "",
      notes: "",
      statusRaw: "todo",
      priorityRaw: "none",
      position: 1000,
      parentTaskId: null,
      dueDate: null,
      reminderDate: null,
      completedAt: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
      labelIds: [],
      recurrenceRuleRaw: null,
      recurrenceInterval: null,
      recurrenceSeriesID: null,
      recurrenceGeneration: 0,
      nextOccurrenceID: null,
      previousOccurrenceID: null,
      ...overrides,
    };
  }

  function validComment(commentId, authorUID, overrides = {}) {
    const now = new Date();
    return {
      id: commentId,
      authorUID,
      authorDisplayName: "Display",
      body: "Hello",
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      ...overrides,
    };
  }

  async function seedLiveTask(ownerId, projectId, taskId) {
    await seedOwnedProject(ownerId, projectId);
    await setDoc(doc(authedDb(ownerId), "projects", projectId, "tasks", taskId), validTask(projectId, taskId));
  }

  it("P5-1 owner reads comments", async () => {
    await seedLiveTask("owner-c1", "proj-c1", "task-c1");
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc("projects/proj-c1/tasks/task-c1/comments/cm1")
        .set(validComment("cm1", "owner-c1"));
    });
    await assertSucceeds(
      getDoc(doc(authedDb("owner-c1"), "projects", "proj-c1", "tasks", "task-c1", "comments", "cm1"))
    );
  });

  it("P5-2 member reads comments", async () => {
    await seedLiveTask("owner-c2", "proj-c2", "task-c2");
    await addMember("owner-c2", "proj-c2", "member-c2");
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc("projects/proj-c2/tasks/task-c2/comments/cm2")
        .set(validComment("cm2", "owner-c2"));
    });
    await assertSucceeds(
      getDoc(doc(authedDb("member-c2"), "projects", "proj-c2", "tasks", "task-c2", "comments", "cm2"))
    );
  });

  it("P5-3 non-member cannot read comments", async () => {
    await seedLiveTask("owner-c3", "proj-c3", "task-c3");
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc("projects/proj-c3/tasks/task-c3/comments/cm3")
        .set(validComment("cm3", "owner-c3"));
    });
    await assertFails(
      getDoc(doc(authedDb("stranger-c3"), "projects", "proj-c3", "tasks", "task-c3", "comments", "cm3"))
    );
  });

  it("P5-4 member creates valid comment", async () => {
    await seedLiveTask("owner-c4", "proj-c4", "task-c4");
    await addMember("owner-c4", "proj-c4", "member-c4");
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-c4"), "projects", "proj-c4", "tasks", "task-c4", "comments", "cm4"),
        validComment("cm4", "member-c4")
      )
    );
  });

  it("P5-5 owner creates valid comment", async () => {
    await seedLiveTask("owner-c5", "proj-c5", "task-c5");
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-c5"), "projects", "proj-c5", "tasks", "task-c5", "comments", "cm5"),
        validComment("cm5", "owner-c5")
      )
    );
  });

  it("P5-6 empty body denied", async () => {
    await seedLiveTask("owner-c6", "proj-c6", "task-c6");
    await assertFails(
      setDoc(
        doc(authedDb("owner-c6"), "projects", "proj-c6", "tasks", "task-c6", "comments", "cm6"),
        validComment("cm6", "owner-c6", { body: "" })
      )
    );
  });

  it("P5-7 oversized body denied", async () => {
    await seedLiveTask("owner-c7", "proj-c7", "task-c7");
    await assertFails(
      setDoc(
        doc(authedDb("owner-c7"), "projects", "proj-c7", "tasks", "task-c7", "comments", "cm7"),
        validComment("cm7", "owner-c7", { body: "x".repeat(4001) })
      )
    );
  });

  it("P5-8 spoofed authorUID denied", async () => {
    await seedLiveTask("owner-c8", "proj-c8", "task-c8");
    await addMember("owner-c8", "proj-c8", "member-c8");
    await assertFails(
      setDoc(
        doc(authedDb("member-c8"), "projects", "proj-c8", "tasks", "task-c8", "comments", "cm8"),
        validComment("cm8", "owner-c8")
      )
    );
  });

  it("P5-9 member edits own comment", async () => {
    await seedLiveTask("owner-c9", "proj-c9", "task-c9");
    await addMember("owner-c9", "proj-c9", "member-c9");
    const base = validComment("cm9", "member-c9", {
      createdAt: new Date("2026-01-01T00:00:00Z"),
      updatedAt: new Date("2026-01-01T00:00:00Z"),
    });
    await setDoc(doc(authedDb("member-c9"), "projects", "proj-c9", "tasks", "task-c9", "comments", "cm9"), base);
    await assertSucceeds(
      setDoc(doc(authedDb("member-c9"), "projects", "proj-c9", "tasks", "task-c9", "comments", "cm9"), {
        ...base,
        body: "Edited",
        updatedAt: new Date("2026-01-02T00:00:00Z"),
      })
    );
  });

  it("P5-10 member cannot edit another member's comment", async () => {
    await seedLiveTask("owner-c10", "proj-c10", "task-c10");
    await addMember("owner-c10", "proj-c10", "member-a10");
    await addMember("owner-c10", "proj-c10", "member-b10");
    const base = validComment("cm10", "member-a10", {
      createdAt: new Date("2026-01-01T00:00:00Z"),
      updatedAt: new Date("2026-01-01T00:00:00Z"),
    });
    await setDoc(doc(authedDb("member-a10"), "projects", "proj-c10", "tasks", "task-c10", "comments", "cm10"), base);
    await assertFails(
      setDoc(doc(authedDb("member-b10"), "projects", "proj-c10", "tasks", "task-c10", "comments", "cm10"), {
        ...base,
        body: "Hijack",
        updatedAt: new Date(),
      })
    );
  });

  it("P5-11 owner cannot rewrite another member's comment body", async () => {
    await seedLiveTask("owner-c11", "proj-c11", "task-c11");
    await addMember("owner-c11", "proj-c11", "member-c11");
    const base = validComment("cm11", "member-c11", {
      createdAt: new Date("2026-01-01T00:00:00Z"),
      updatedAt: new Date("2026-01-01T00:00:00Z"),
    });
    await setDoc(doc(authedDb("member-c11"), "projects", "proj-c11", "tasks", "task-c11", "comments", "cm11"), base);
    await assertFails(
      setDoc(doc(authedDb("owner-c11"), "projects", "proj-c11", "tasks", "task-c11", "comments", "cm11"), {
        ...base,
        body: "Owner rewrite",
        updatedAt: new Date(),
      })
    );
  });

  it("P5-12 owner can soft-delete another member's comment", async () => {
    await seedLiveTask("owner-c12", "proj-c12", "task-c12");
    await addMember("owner-c12", "proj-c12", "member-c12");
    const base = validComment("cm12", "member-c12", {
      createdAt: new Date("2026-01-01T00:00:00Z"),
      updatedAt: new Date("2026-01-01T00:00:00Z"),
    });
    await setDoc(doc(authedDb("member-c12"), "projects", "proj-c12", "tasks", "task-c12", "comments", "cm12"), base);
    await assertSucceeds(
      setDoc(doc(authedDb("owner-c12"), "projects", "proj-c12", "tasks", "task-c12", "comments", "cm12"), {
        ...base,
        deletedAt: new Date(),
        updatedAt: new Date(),
      })
    );
  });

  it("P5-13 member can delete own comment", async () => {
    await seedLiveTask("owner-c13", "proj-c13", "task-c13");
    await addMember("owner-c13", "proj-c13", "member-c13");
    const base = validComment("cm13", "member-c13", {
      createdAt: new Date("2026-01-01T00:00:00Z"),
      updatedAt: new Date("2026-01-01T00:00:00Z"),
    });
    await setDoc(doc(authedDb("member-c13"), "projects", "proj-c13", "tasks", "task-c13", "comments", "cm13"), base);
    await assertSucceeds(
      setDoc(doc(authedDb("member-c13"), "projects", "proj-c13", "tasks", "task-c13", "comments", "cm13"), {
        ...base,
        deletedAt: new Date(),
        updatedAt: new Date(),
      })
    );
  });

  it("P5-14 member cannot delete another member's comment", async () => {
    await seedLiveTask("owner-c14", "proj-c14", "task-c14");
    await addMember("owner-c14", "proj-c14", "member-a14");
    await addMember("owner-c14", "proj-c14", "member-b14");
    const base = validComment("cm14", "member-a14", {
      createdAt: new Date("2026-01-01T00:00:00Z"),
      updatedAt: new Date("2026-01-01T00:00:00Z"),
    });
    await setDoc(doc(authedDb("member-a14"), "projects", "proj-c14", "tasks", "task-c14", "comments", "cm14"), base);
    await assertFails(
      setDoc(doc(authedDb("member-b14"), "projects", "proj-c14", "tasks", "task-c14", "comments", "cm14"), {
        ...base,
        deletedAt: new Date(),
        updatedAt: new Date(),
      })
    );
  });

  it("P5-15 non-member cannot create", async () => {
    await seedLiveTask("owner-c15", "proj-c15", "task-c15");
    await assertFails(
      setDoc(
        doc(authedDb("stranger-c15"), "projects", "proj-c15", "tasks", "task-c15", "comments", "cm15"),
        validComment("cm15", "stranger-c15")
      )
    );
  });

  it("P5-16 author metadata immutable on edit", async () => {
    await seedLiveTask("owner-c16", "proj-c16", "task-c16");
    const base = validComment("cm16", "owner-c16", {
      createdAt: new Date("2026-01-01T00:00:00Z"),
      updatedAt: new Date("2026-01-01T00:00:00Z"),
    });
    await setDoc(doc(authedDb("owner-c16"), "projects", "proj-c16", "tasks", "task-c16", "comments", "cm16"), base);
    await assertFails(
      setDoc(doc(authedDb("owner-c16"), "projects", "proj-c16", "tasks", "task-c16", "comments", "cm16"), {
        ...base,
        authorDisplayName: "Hacked",
        body: "Still mine",
        updatedAt: new Date(),
      })
    );
  });

  it("P5-17 comment under invalid task denied", async () => {
    await seedOwnedProject("owner-c17", "proj-c17");
    await assertFails(
      setDoc(
        doc(authedDb("owner-c17"), "projects", "proj-c17", "tasks", "missing-task", "comments", "cm17"),
        validComment("cm17", "owner-c17")
      )
    );
  });

  it("P5-18 comment on soft-deleted task create denied", async () => {
    await seedLiveTask("owner-c18", "proj-c18", "task-c18");
    await setDoc(
      doc(authedDb("owner-c18"), "projects", "proj-c18", "tasks", "task-c18"),
      validTask("proj-c18", "task-c18", { deletedAt: new Date() })
    );
    await assertFails(
      setDoc(
        doc(authedDb("owner-c18"), "projects", "proj-c18", "tasks", "task-c18", "comments", "cm18"),
        validComment("cm18", "owner-c18")
      )
    );
  });

  it("P5-19 memberIds without membership doc grants no comment access", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc("projects/proj-c19").set({
        id: "proj-c19",
        ownerId: "owner-c19",
        title: "Shared",
        description: "",
        color: "#5B8DEF",
        memberIds: ["listed-only"],
        createdAt: new Date(),
        updatedAt: new Date(),
        deletedAt: null,
      });
      await db.doc("projects/proj-c19/members/owner-c19").set({
        userId: "owner-c19",
        role: "owner",
        displayName: null,
        joinedAt: new Date(),
      });
      await db.doc("projects/proj-c19/tasks/task-c19").set(validTask("proj-c19", "task-c19"));
      await db
        .doc("projects/proj-c19/tasks/task-c19/comments/cm19")
        .set(validComment("cm19", "owner-c19"));
    });
    await assertFails(
      getDoc(doc(authedDb("listed-only"), "projects", "proj-c19", "tasks", "task-c19", "comments", "cm19"))
    );
    await assertFails(
      setDoc(
        doc(authedDb("listed-only"), "projects", "proj-c19", "tasks", "task-c19", "comments", "cm19b"),
        validComment("cm19b", "listed-only")
      )
    );
  });
});

describe("Todoshi Firestore rules — Phase 5.1 member task mutations", () => {
  async function seedOwnedProject(ownerId, projectId) {
    await commitOwnerBootstrap(authedDb(ownerId), projectId, ownerId);
  }

  async function addMember(ownerId, projectId, memberId) {
    const token = makeInviteToken(`m-${memberId}`);
    await seedInvite(token, inviteCreateData(projectId, ownerId));
    await commitInviteAcceptance(authedDb(memberId), token, projectId, memberId);
    await promoteMemberToFull(ownerId, projectId, memberId);
  }

  function validTask(projectId, taskId, overrides = {}) {
    return {
      id: taskId,
      projectId,
      title: "Task",
      description: "",
      notes: "",
      statusRaw: "todo",
      priorityRaw: "none",
      position: 1000,
      parentTaskId: null,
      dueDate: null,
      reminderDate: null,
      completedAt: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
      labelIds: [],
      recurrenceRuleRaw: null,
      recurrenceInterval: null,
      recurrenceSeriesID: null,
      recurrenceGeneration: 0,
      nextOccurrenceID: null,
      previousOccurrenceID: null,
      ...overrides,
    };
  }

  async function seedTask(ownerId, projectId, taskId, overrides = {}) {
    await seedOwnedProject(ownerId, projectId);
    await setDoc(
      doc(authedDb(ownerId), "projects", projectId, "tasks", taskId),
      validTask(projectId, taskId, overrides)
    );
  }

  it("P5M-1 owner can update task", async () => {
    await seedTask("owner-m1", "proj-m1", "task-m1");
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-m1"), "projects", "proj-m1", "tasks", "task-m1"),
        validTask("proj-m1", "task-m1", { title: "Owner edit", statusRaw: "inProgress" })
      )
    );
  });

  it("P5M-2 member can update task", async () => {
    await seedTask("owner-m2", "proj-m2", "task-m2");
    await addMember("owner-m2", "proj-m2", "member-m2");
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-m2"), "projects", "proj-m2", "tasks", "task-m2"),
        validTask("proj-m2", "task-m2", { title: "Member edit" })
      )
    );
  });

  it("P5M-3 non-member cannot update task", async () => {
    await seedTask("owner-m3", "proj-m3", "task-m3");
    await assertFails(
      setDoc(
        doc(authedDb("stranger-m3"), "projects", "proj-m3", "tasks", "task-m3"),
        validTask("proj-m3", "task-m3", { title: "Nope" })
      )
    );
  });

  it("P5M-4 member can change status progression", async () => {
    await seedTask("owner-m4", "proj-m4", "task-m4");
    await addMember("owner-m4", "proj-m4", "member-m4");
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-m4"), "projects", "proj-m4", "tasks", "task-m4"),
        validTask("proj-m4", "task-m4", { statusRaw: "inProgress" })
      )
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-m4"), "projects", "proj-m4", "tasks", "task-m4"),
        validTask("proj-m4", "task-m4", { statusRaw: "review" })
      )
    );
  });

  it("P5M-5 member can complete task", async () => {
    await seedTask("owner-m5", "proj-m5", "task-m5");
    await addMember("owner-m5", "proj-m5", "member-m5");
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-m5"), "projects", "proj-m5", "tasks", "task-m5"),
        validTask("proj-m5", "task-m5", { statusRaw: "done", completedAt: new Date() })
      )
    );
  });

  it("P5M-6 member can edit subtask", async () => {
    await seedTask("owner-m6", "proj-m6", "root-m6");
    await addMember("owner-m6", "proj-m6", "member-m6");
    await setDoc(
      doc(authedDb("member-m6"), "projects", "proj-m6", "tasks", "child-m6"),
      validTask("proj-m6", "child-m6", { parentTaskId: "root-m6", title: "Sub" })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-m6"), "projects", "proj-m6", "tasks", "child-m6"),
        validTask("proj-m6", "child-m6", { parentTaskId: "root-m6", title: "Sub edited", statusRaw: "done" })
      )
    );
  });

  it("P5M-7 member can soft-delete task", async () => {
    await seedTask("owner-m7", "proj-m7", "task-m7");
    await addMember("owner-m7", "proj-m7", "member-m7");
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-m7"), "projects", "proj-m7", "tasks", "task-m7"),
        validTask("proj-m7", "task-m7", { deletedAt: new Date() })
      )
    );
  });

  it("P5M-8 member can update checklist", async () => {
    await seedTask("owner-m8", "proj-m8", "task-m8");
    await addMember("owner-m8", "proj-m8", "member-m8");
    await assertSucceeds(
      setDoc(doc(authedDb("member-m8"), "projects", "proj-m8", "tasks", "task-m8", "checklist", "c1"), {
        id: "c1",
        title: "Item",
        isCompleted: true,
        position: 1,
        createdAt: new Date(),
        updatedAt: new Date(),
        deletedAt: null,
      })
    );
  });

  it("P5M-9 member cannot update project metadata", async () => {
    await seedTask("owner-m9", "proj-m9", "task-m9");
    await addMember("owner-m9", "proj-m9", "member-m9");
    await assertFails(
      updateDoc(doc(authedDb("member-m9"), "projects", "proj-m9"), {
        title: "Hijacked",
      })
    );
  });

  it("P5M-10 member cannot update ownerId/memberIds", async () => {
    await seedTask("owner-m10", "proj-m10", "task-m10");
    await addMember("owner-m10", "proj-m10", "member-m10");
    await assertFails(
      updateDoc(doc(authedDb("member-m10"), "projects", "proj-m10"), {
        ownerId: "member-m10",
      })
    );
    await assertFails(
      updateDoc(doc(authedDb("member-m10"), "projects", "proj-m10"), {
        memberIds: ["member-m10"],
      })
    );
  });
});

describe("Todoshi Firestore rules — Phase 6 task permissions", () => {
  async function seedOwnedProject(ownerId, projectId) {
    await commitOwnerBootstrap(authedDb(ownerId), projectId, ownerId);
  }

  async function addRestrictedMember(ownerId, projectId, memberId) {
    const token = makeInviteToken(`r-${memberId}`);
    await seedInvite(token, inviteCreateData(projectId, ownerId));
    await commitInviteAcceptance(authedDb(memberId), token, projectId, memberId);
  }

  async function addFullMember(ownerId, projectId, memberId) {
    await addRestrictedMember(ownerId, projectId, memberId);
    await promoteMemberToFull(ownerId, projectId, memberId);
  }

  function p6Task(projectId, taskId, overrides = {}) {
    return {
      id: taskId,
      projectId,
      title: "Task",
      description: "",
      notes: "",
      statusRaw: "todo",
      priorityRaw: "none",
      position: 1000,
      parentTaskId: null,
      dueDate: null,
      reminderDate: null,
      completedAt: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
      labelIds: [],
      recurrenceRuleRaw: null,
      recurrenceInterval: null,
      recurrenceSeriesID: null,
      recurrenceGeneration: 0,
      nextOccurrenceID: null,
      previousOccurrenceID: null,
      editorUIDs: [],
      ...overrides,
    };
  }

  it("P6-1 owner full task access", async () => {
    await seedOwnedProject("owner-p61", "proj-p61");
    await assertSucceeds(
      setDoc(doc(authedDb("owner-p61"), "projects", "proj-p61", "tasks", "t1"), p6Task("proj-p61", "t1"))
    );
    await assertSucceeds(
      setDoc(doc(authedDb("owner-p61"), "projects", "proj-p61", "tasks", "t1"), p6Task("proj-p61", "t1", { title: "Renamed" }))
    );
  });

  it("P6-2 full member edits any task", async () => {
    await seedOwnedProject("owner-p62", "proj-p62");
    await addFullMember("owner-p62", "proj-p62", "member-p62");
    await setDoc(doc(authedDb("owner-p62"), "projects", "proj-p62", "tasks", "t2"), p6Task("proj-p62", "t2"));
    await assertSucceeds(
      setDoc(doc(authedDb("member-p62"), "projects", "proj-p62", "tasks", "t2"), p6Task("proj-p62", "t2", { title: "ByFull" }))
    );
  });

  it("P6-3 restricted member edits allowed task", async () => {
    await seedOwnedProject("owner-p63", "proj-p63");
    await addRestrictedMember("owner-p63", "proj-p63", "member-p63");
    await setDoc(
      doc(authedDb("owner-p63"), "projects", "proj-p63", "tasks", "t3"),
      p6Task("proj-p63", "t3", { editorUIDs: ["member-p63"] })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p63"), "projects", "proj-p63", "tasks", "t3"),
        p6Task("proj-p63", "t3", { title: "Ok", editorUIDs: ["member-p63"] })
      )
    );
  });

  it("P6-4 restricted member cannot edit unallowed task", async () => {
    await seedOwnedProject("owner-p64", "proj-p64");
    await addRestrictedMember("owner-p64", "proj-p64", "member-p64");
    await setDoc(doc(authedDb("owner-p64"), "projects", "proj-p64", "tasks", "t4"), p6Task("proj-p64", "t4"));
    await assertFails(
      setDoc(doc(authedDb("member-p64"), "projects", "proj-p64", "tasks", "t4"), p6Task("proj-p64", "t4", { title: "Nope" }))
    );
  });

  it("P6-5 non-member cannot edit", async () => {
    await seedOwnedProject("owner-p65", "proj-p65");
    await setDoc(doc(authedDb("owner-p65"), "projects", "proj-p65", "tasks", "t5"), p6Task("proj-p65", "t5"));
    await assertFails(
      setDoc(doc(authedDb("stranger-p65"), "projects", "proj-p65", "tasks", "t5"), p6Task("proj-p65", "t5", { title: "X" }))
    );
  });

  it("P6-6 legacy member without accessLevel treated as full", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc("projects/proj-p66").set(bootstrapProjectData("proj-p66", "owner-p66", {
        memberIds: ["owner-p66", "legacy-p66"],
      }));
      await db.doc("projects/proj-p66/members/owner-p66").set(bootstrapMemberData("owner-p66"));
      await db.doc("projects/proj-p66/members/legacy-p66").set({
        userId: "legacy-p66",
        role: "member",
        displayName: "Legacy",
        joinedAt: new Date(),
      });
      await db.doc("projects/proj-p66/tasks/t6").set(p6Task("proj-p66", "t6"));
    });
    await assertSucceeds(
      setDoc(doc(authedDb("legacy-p66"), "projects", "proj-p66", "tasks", "t6"), p6Task("proj-p66", "t6", { title: "LegacyOk" }))
    );
  });

  it("P6-7 member cannot change own accessLevel", async () => {
    await seedOwnedProject("owner-p67", "proj-p67");
    await addRestrictedMember("owner-p67", "proj-p67", "member-p67");
    await assertFails(
      updateDoc(doc(authedDb("member-p67"), "projects", "proj-p67", "members", "member-p67"), {
        accessLevel: "full",
      })
    );
  });

  it("P6-8 member cannot change another member accessLevel", async () => {
    await seedOwnedProject("owner-p68", "proj-p68");
    await addRestrictedMember("owner-p68", "proj-p68", "member-a68");
    await addRestrictedMember("owner-p68", "proj-p68", "member-b68");
    await assertFails(
      updateDoc(doc(authedDb("member-a68"), "projects", "proj-p68", "members", "member-b68"), {
        accessLevel: "full",
      })
    );
  });

  it("P6-9 owner can change full → restricted", async () => {
    await seedOwnedProject("owner-p69", "proj-p69");
    await addFullMember("owner-p69", "proj-p69", "member-p69");
    await assertSucceeds(
      updateDoc(doc(authedDb("owner-p69"), "projects", "proj-p69", "members", "member-p69"), {
        accessLevel: "restricted",
      })
    );
  });

  it("P6-10 owner can change restricted → full", async () => {
    await seedOwnedProject("owner-p610", "proj-p610");
    await addRestrictedMember("owner-p610", "proj-p610", "member-p610");
    await assertSucceeds(
      updateDoc(doc(authedDb("owner-p610"), "projects", "proj-p610", "members", "member-p610"), {
        accessLevel: "full",
      })
    );
  });

  it("P6-11/12/13 members cannot modify editorUIDs; P6-14 owner can", async () => {
    await seedOwnedProject("owner-p611", "proj-p611");
    await addFullMember("owner-p611", "proj-p611", "full-p611");
    await addRestrictedMember("owner-p611", "proj-p611", "rest-p611");
    await setDoc(
      doc(authedDb("owner-p611"), "projects", "proj-p611", "tasks", "t11"),
      p6Task("proj-p611", "t11", { editorUIDs: [] })
    );
    await assertFails(
      setDoc(
        doc(authedDb("full-p611"), "projects", "proj-p611", "tasks", "t11"),
        p6Task("proj-p611", "t11", { editorUIDs: ["full-p611"] })
      )
    );
    await assertFails(
      setDoc(
        doc(authedDb("rest-p611"), "projects", "proj-p611", "tasks", "t11"),
        p6Task("proj-p611", "t11", { editorUIDs: ["rest-p611"] })
      )
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p611"), "projects", "proj-p611", "tasks", "t11"),
        p6Task("proj-p611", "t11", { editorUIDs: ["rest-p611"] })
      )
    );
  });

  it("P6-15/16 restricted can edit authorized root and its subtask", async () => {
    await seedOwnedProject("owner-p615", "proj-p615");
    await addRestrictedMember("owner-p615", "proj-p615", "member-p615");
    await setDoc(
      doc(authedDb("owner-p615"), "projects", "proj-p615", "tasks", "root15"),
      p6Task("proj-p615", "root15", { editorUIDs: ["member-p615"] })
    );
    await setDoc(
      doc(authedDb("owner-p615"), "projects", "proj-p615", "tasks", "child15"),
      p6Task("proj-p615", "child15", { parentTaskId: "root15" })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p615"), "projects", "proj-p615", "tasks", "root15"),
        p6Task("proj-p615", "root15", { title: "RootEdit", editorUIDs: ["member-p615"] })
      )
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p615"), "projects", "proj-p615", "tasks", "child15"),
        p6Task("proj-p615", "child15", { parentTaskId: "root15", title: "ChildEdit" })
      )
    );
  });

  it("P6-17 restricted cannot edit subtask of unauthorized root", async () => {
    await seedOwnedProject("owner-p617", "proj-p617");
    await addRestrictedMember("owner-p617", "proj-p617", "member-p617");
    await setDoc(doc(authedDb("owner-p617"), "projects", "proj-p617", "tasks", "root17"), p6Task("proj-p617", "root17"));
    await setDoc(
      doc(authedDb("owner-p617"), "projects", "proj-p617", "tasks", "child17"),
      p6Task("proj-p617", "child17", { parentTaskId: "root17" })
    );
    await assertFails(
      setDoc(
        doc(authedDb("member-p617"), "projects", "proj-p617", "tasks", "child17"),
        p6Task("proj-p617", "child17", { parentTaskId: "root17", title: "Nope" })
      )
    );
  });

  it("P6-18/19/20 restricted create subtask under authorized root only; no arbitrary root", async () => {
    await seedOwnedProject("owner-p618", "proj-p618");
    await addRestrictedMember("owner-p618", "proj-p618", "member-p618");
    await setDoc(
      doc(authedDb("owner-p618"), "projects", "proj-p618", "tasks", "root18"),
      p6Task("proj-p618", "root18", { editorUIDs: ["member-p618"] })
    );
    await setDoc(doc(authedDb("owner-p618"), "projects", "proj-p618", "tasks", "rootDenied"), p6Task("proj-p618", "rootDenied"));
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p618"), "projects", "proj-p618", "tasks", "child18"),
        p6Task("proj-p618", "child18", { parentTaskId: "root18", title: "Sub" })
      )
    );
    await assertFails(
      setDoc(
        doc(authedDb("member-p618"), "projects", "proj-p618", "tasks", "childDenied"),
        p6Task("proj-p618", "childDenied", { parentTaskId: "rootDenied", title: "Sub" })
      )
    );
    await assertFails(
      setDoc(doc(authedDb("member-p618"), "projects", "proj-p618", "tasks", "newRoot"), p6Task("proj-p618", "newRoot"))
    );
  });

  it("P6-21 full member can create root", async () => {
    await seedOwnedProject("owner-p621", "proj-p621");
    await addFullMember("owner-p621", "proj-p621", "member-p621");
    await assertSucceeds(
      setDoc(doc(authedDb("member-p621"), "projects", "proj-p621", "tasks", "root21"), p6Task("proj-p621", "root21"))
    );
  });

  it("P6-22/23 checklist follows task ACL", async () => {
    await seedOwnedProject("owner-p622", "proj-p622");
    await addRestrictedMember("owner-p622", "proj-p622", "member-p622");
    await setDoc(
      doc(authedDb("owner-p622"), "projects", "proj-p622", "tasks", "ok22"),
      p6Task("proj-p622", "ok22", { editorUIDs: ["member-p622"] })
    );
    await setDoc(doc(authedDb("owner-p622"), "projects", "proj-p622", "tasks", "no22"), p6Task("proj-p622", "no22"));
    const item = {
      id: "c1",
      title: "Item",
      isCompleted: false,
      position: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
    };
    await assertSucceeds(
      setDoc(doc(authedDb("member-p622"), "projects", "proj-p622", "tasks", "ok22", "checklist", "c1"), item)
    );
    await assertFails(
      setDoc(doc(authedDb("member-p622"), "projects", "proj-p622", "tasks", "no22", "checklist", "c2"), {
        ...item,
        id: "c2",
      })
    );
  });

  it("P6-24/25 cloud-safe resource follows task ACL", async () => {
    await seedOwnedProject("owner-p624", "proj-p624");
    await addRestrictedMember("owner-p624", "proj-p624", "member-p624");
    await setDoc(
      doc(authedDb("owner-p624"), "projects", "proj-p624", "tasks", "ok24"),
      p6Task("proj-p624", "ok24", { editorUIDs: ["member-p624"] })
    );
    await setDoc(doc(authedDb("owner-p624"), "projects", "proj-p624", "tasks", "no24"), p6Task("proj-p624", "no24"));
    const resource = {
      id: "r1",
      kindRaw: "link",
      title: "Link",
      body: null,
      externalURLString: "https://example.com",
      languageIdentifier: null,
      position: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
    };
    await assertSucceeds(
      setDoc(doc(authedDb("member-p624"), "projects", "proj-p624", "tasks", "ok24", "resources", "r1"), resource)
    );
    await assertFails(
      setDoc(doc(authedDb("member-p624"), "projects", "proj-p624", "tasks", "no24", "resources", "r2"), {
        ...resource,
        id: "r2",
      })
    );
  });

  it("P6-26 restricted without edit can still create comment", async () => {
    await seedOwnedProject("owner-p626", "proj-p626");
    await addRestrictedMember("owner-p626", "proj-p626", "member-p626");
    await setDoc(doc(authedDb("owner-p626"), "projects", "proj-p626", "tasks", "t26"), p6Task("proj-p626", "t26"));
    const now = new Date();
    await assertSucceeds(
      setDoc(doc(authedDb("member-p626"), "projects", "proj-p626", "tasks", "t26", "comments", "cm26"), {
        id: "cm26",
        authorUID: "member-p626",
        authorDisplayName: "M",
        body: "Still commenting",
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      })
    );
  });

  it("P6-28/29 members cannot edit project ownership/security; P6-30 only owner manages ACL", async () => {
    await seedOwnedProject("owner-p628", "proj-p628");
    await addFullMember("owner-p628", "proj-p628", "full-p628");
    await addRestrictedMember("owner-p628", "proj-p628", "rest-p628");
    await assertFails(
      updateDoc(doc(authedDb("full-p628"), "projects", "proj-p628"), { ownerId: "full-p628" })
    );
    await assertFails(
      updateDoc(doc(authedDb("rest-p628"), "projects", "proj-p628"), { title: "Hijack" })
    );
    await setDoc(doc(authedDb("owner-p628"), "projects", "proj-p628", "tasks", "t30"), p6Task("proj-p628", "t30"));
    await assertFails(
      setDoc(
        doc(authedDb("full-p628"), "projects", "proj-p628", "tasks", "t30"),
        p6Task("proj-p628", "t30", { editorUIDs: ["full-p628"] })
      )
    );
  });
});

describe("Todoshi Firestore rules — Phase 7 task assignment", () => {
  async function seedOwnedProject(ownerId, projectId) {
    await commitOwnerBootstrap(authedDb(ownerId), projectId, ownerId);
  }

  async function addRestrictedMember(ownerId, projectId, memberId) {
    const token = makeInviteToken(`a-${memberId}`);
    await seedInvite(token, inviteCreateData(projectId, ownerId));
    await commitInviteAcceptance(authedDb(memberId), token, projectId, memberId);
  }

  async function addFullMember(ownerId, projectId, memberId) {
    await addRestrictedMember(ownerId, projectId, memberId);
    await promoteMemberToFull(ownerId, projectId, memberId);
  }

  function p7Task(projectId, taskId, overrides = {}) {
    return {
      id: taskId,
      projectId,
      title: "Task",
      description: "",
      notes: "",
      statusRaw: "todo",
      priorityRaw: "none",
      position: 1000,
      parentTaskId: null,
      dueDate: null,
      reminderDate: null,
      completedAt: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
      labelIds: [],
      recurrenceRuleRaw: null,
      recurrenceInterval: null,
      recurrenceSeriesID: null,
      recurrenceGeneration: 0,
      nextOccurrenceID: null,
      previousOccurrenceID: null,
      editorUIDs: [],
      assigneeUID: null,
      ...overrides,
    };
  }

  // --- Assignment authority ---

  it("P7-1 owner assigns a valid member", async () => {
    await seedOwnedProject("owner-p71", "proj-p71");
    await addFullMember("owner-p71", "proj-p71", "member-p71");
    await setDoc(doc(authedDb("owner-p71"), "projects", "proj-p71", "tasks", "t1"), p7Task("proj-p71", "t1"));
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p71"), "projects", "proj-p71", "tasks", "t1"),
        p7Task("proj-p71", "t1", { assigneeUID: "member-p71" })
      )
    );
  });

  it("P7-2 owner assigns self", async () => {
    await seedOwnedProject("owner-p72", "proj-p72");
    await setDoc(doc(authedDb("owner-p72"), "projects", "proj-p72", "tasks", "t2"), p7Task("proj-p72", "t2"));
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p72"), "projects", "proj-p72", "tasks", "t2"),
        p7Task("proj-p72", "t2", { assigneeUID: "owner-p72" })
      )
    );
  });

  it("P7-3 owner unassigns", async () => {
    await seedOwnedProject("owner-p73", "proj-p73");
    await addFullMember("owner-p73", "proj-p73", "member-p73");
    await setDoc(
      doc(authedDb("owner-p73"), "projects", "proj-p73", "tasks", "t3"),
      p7Task("proj-p73", "t3", { assigneeUID: "member-p73" })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p73"), "projects", "proj-p73", "tasks", "t3"),
        p7Task("proj-p73", "t3", { assigneeUID: null })
      )
    );
  });

  it("P7-4 owner reassigns B → C", async () => {
    await seedOwnedProject("owner-p74", "proj-p74");
    await addFullMember("owner-p74", "proj-p74", "member-b74");
    await addFullMember("owner-p74", "proj-p74", "member-c74");
    await setDoc(
      doc(authedDb("owner-p74"), "projects", "proj-p74", "tasks", "t4"),
      p7Task("proj-p74", "t4", { assigneeUID: "member-b74" })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p74"), "projects", "proj-p74", "tasks", "t4"),
        p7Task("proj-p74", "t4", { assigneeUID: "member-c74" })
      )
    );
  });

  it("P7-5 full member cannot assign", async () => {
    await seedOwnedProject("owner-p75", "proj-p75");
    await addFullMember("owner-p75", "proj-p75", "member-p75");
    await setDoc(doc(authedDb("owner-p75"), "projects", "proj-p75", "tasks", "t5"), p7Task("proj-p75", "t5"));
    await assertFails(
      setDoc(
        doc(authedDb("member-p75"), "projects", "proj-p75", "tasks", "t5"),
        p7Task("proj-p75", "t5", { assigneeUID: "member-p75" })
      )
    );
  });

  it("P7-6 restricted member cannot assign", async () => {
    await seedOwnedProject("owner-p76", "proj-p76");
    await addRestrictedMember("owner-p76", "proj-p76", "member-p76");
    await setDoc(
      doc(authedDb("owner-p76"), "projects", "proj-p76", "tasks", "t6"),
      p7Task("proj-p76", "t6", { editorUIDs: ["member-p76"] })
    );
    await assertFails(
      setDoc(
        doc(authedDb("member-p76"), "projects", "proj-p76", "tasks", "t6"),
        p7Task("proj-p76", "t6", { editorUIDs: ["member-p76"], assigneeUID: "member-p76" })
      )
    );
  });

  it("P7-7 member cannot unassign themselves", async () => {
    await seedOwnedProject("owner-p77", "proj-p77");
    await addFullMember("owner-p77", "proj-p77", "member-p77");
    await setDoc(
      doc(authedDb("owner-p77"), "projects", "proj-p77", "tasks", "t7"),
      p7Task("proj-p77", "t7", { assigneeUID: "member-p77" })
    );
    await assertFails(
      setDoc(
        doc(authedDb("member-p77"), "projects", "proj-p77", "tasks", "t7"),
        p7Task("proj-p77", "t7", { assigneeUID: null })
      )
    );
  });

  it("P7-8 non-member cannot assign", async () => {
    await seedOwnedProject("owner-p78", "proj-p78");
    await setDoc(doc(authedDb("owner-p78"), "projects", "proj-p78", "tasks", "t8"), p7Task("proj-p78", "t8"));
    await assertFails(
      setDoc(
        doc(authedDb("stranger-p78"), "projects", "proj-p78", "tasks", "t8"),
        p7Task("proj-p78", "t8", { assigneeUID: "stranger-p78" })
      )
    );
  });

  // --- Integrity ---

  it("P7-9 unknown UID assignment denied", async () => {
    await seedOwnedProject("owner-p79", "proj-p79");
    await setDoc(doc(authedDb("owner-p79"), "projects", "proj-p79", "tasks", "t9"), p7Task("proj-p79", "t9"));
    await assertFails(
      setDoc(
        doc(authedDb("owner-p79"), "projects", "proj-p79", "tasks", "t9"),
        p7Task("proj-p79", "t9", { assigneeUID: "ghost-p79" })
      )
    );
  });

  it("P7-10 member of another project denied", async () => {
    await seedOwnedProject("owner-p710", "proj-p710a");
    await seedOwnedProject("owner-p710", "proj-p710b");
    await addFullMember("owner-p710", "proj-p710b", "outsider-p710");
    await setDoc(doc(authedDb("owner-p710"), "projects", "proj-p710a", "tasks", "t10"), p7Task("proj-p710a", "t10"));
    await assertFails(
      setDoc(
        doc(authedDb("owner-p710"), "projects", "proj-p710a", "tasks", "t10"),
        p7Task("proj-p710a", "t10", { assigneeUID: "outsider-p710" })
      )
    );
  });

  it("P7-11 root assignment valid on create", async () => {
    await seedOwnedProject("owner-p711", "proj-p711");
    await addFullMember("owner-p711", "proj-p711", "member-p711");
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p711"), "projects", "proj-p711", "tasks", "t11"),
        p7Task("proj-p711", "t11", { assigneeUID: "member-p711" })
      )
    );
  });

  it("P7-12 subtask with non-null assignee denied", async () => {
    await seedOwnedProject("owner-p712", "proj-p712");
    await addFullMember("owner-p712", "proj-p712", "member-p712");
    await setDoc(doc(authedDb("owner-p712"), "projects", "proj-p712", "tasks", "root12"), p7Task("proj-p712", "root12"));
    await assertFails(
      setDoc(
        doc(authedDb("owner-p712"), "projects", "proj-p712", "tasks", "sub12"),
        p7Task("proj-p712", "sub12", { parentTaskId: "root12", assigneeUID: "member-p712" })
      )
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p712"), "projects", "proj-p712", "tasks", "sub12"),
        p7Task("proj-p712", "sub12", { parentTaskId: "root12", assigneeUID: null })
      )
    );
  });

  it("P7-13 member ordinary edit must preserve assigneeUID", async () => {
    await seedOwnedProject("owner-p713", "proj-p713");
    await addFullMember("owner-p713", "proj-p713", "member-b713");
    await addFullMember("owner-p713", "proj-p713", "member-c713");
    await setDoc(
      doc(authedDb("owner-p713"), "projects", "proj-p713", "tasks", "t13"),
      p7Task("proj-p713", "t13", { assigneeUID: "member-b713" })
    );
    await assertFails(
      setDoc(
        doc(authedDb("member-b713"), "projects", "proj-p713", "tasks", "t13"),
        p7Task("proj-p713", "t13", { title: "Edited", assigneeUID: "member-c713" })
      )
    );
  });

  it("P7-14 member status update preserving assignment succeeds", async () => {
    await seedOwnedProject("owner-p714", "proj-p714");
    await addRestrictedMember("owner-p714", "proj-p714", "member-p714");
    await setDoc(
      doc(authedDb("owner-p714"), "projects", "proj-p714", "tasks", "t14"),
      p7Task("proj-p714", "t14", { assigneeUID: "member-p714", editorUIDs: ["member-p714"] })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p714"), "projects", "proj-p714", "tasks", "t14"),
        p7Task("proj-p714", "t14", {
          statusRaw: "inProgress",
          assigneeUID: "member-p714",
          editorUIDs: ["member-p714"],
        })
      )
    );
  });

  it("P7-15 owner can create an already-assigned root task", async () => {
    await seedOwnedProject("owner-p715", "proj-p715");
    await addRestrictedMember("owner-p715", "proj-p715", "member-p715");
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p715"), "projects", "proj-p715", "tasks", "t15"),
        p7Task("proj-p715", "t15", { assigneeUID: "member-p715", editorUIDs: ["member-p715"] })
      )
    );
  });

  it("P7-16 full member root creation requires assignee null", async () => {
    await seedOwnedProject("owner-p716", "proj-p716");
    await addFullMember("owner-p716", "proj-p716", "member-p716");
    await assertFails(
      setDoc(
        doc(authedDb("member-p716"), "projects", "proj-p716", "tasks", "t16a"),
        p7Task("proj-p716", "t16a", { assigneeUID: "member-p716" })
      )
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p716"), "projects", "proj-p716", "tasks", "t16b"),
        p7Task("proj-p716", "t16b", { assigneeUID: null })
      )
    );
  });

  // --- ACL interaction ---

  it("P7-17 restricted assignee with editorUIDs can edit", async () => {
    await seedOwnedProject("owner-p717", "proj-p717");
    await addRestrictedMember("owner-p717", "proj-p717", "member-p717");
    await setDoc(
      doc(authedDb("owner-p717"), "projects", "proj-p717", "tasks", "t17"),
      p7Task("proj-p717", "t17", { assigneeUID: "member-p717", editorUIDs: ["member-p717"] })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p717"), "projects", "proj-p717", "tasks", "t17"),
        p7Task("proj-p717", "t17", {
          title: "Working",
          assigneeUID: "member-p717",
          editorUIDs: ["member-p717"],
        })
      )
    );
  });

  it("P7-18 assignment alone does not bypass canEditTask", async () => {
    await seedOwnedProject("owner-p718", "proj-p718");
    await addRestrictedMember("owner-p718", "proj-p718", "member-p718");
    await setDoc(
      doc(authedDb("owner-p718"), "projects", "proj-p718", "tasks", "t18"),
      p7Task("proj-p718", "t18", { assigneeUID: "member-p718", editorUIDs: [] })
    );
    await assertFails(
      setDoc(
        doc(authedDb("member-p718"), "projects", "proj-p718", "tasks", "t18"),
        p7Task("proj-p718", "t18", { title: "Nope", assigneeUID: "member-p718", editorUIDs: [] })
      )
    );
  });

  it("P7-19 memberIds-only fake user cannot be assignee", async () => {
    await seedOwnedProject("owner-p719", "proj-p719");
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc("projects/proj-p719")
        .update({ memberIds: ["owner-p719", "fake-p719"] });
    });
    await setDoc(doc(authedDb("owner-p719"), "projects", "proj-p719", "tasks", "t19"), p7Task("proj-p719", "t19"));
    await assertFails(
      setDoc(
        doc(authedDb("owner-p719"), "projects", "proj-p719", "tasks", "t19"),
        p7Task("proj-p719", "t19", { assigneeUID: "fake-p719" })
      )
    );
  });

  it("P7-20 assignment write cannot smuggle security field changes", async () => {
    await seedOwnedProject("owner-p720", "proj-p720");
    await addFullMember("owner-p720", "proj-p720", "member-p720");
    await setDoc(doc(authedDb("owner-p720"), "projects", "proj-p720", "tasks", "t20"), p7Task("proj-p720", "t20"));
    await assertFails(
      updateDoc(doc(authedDb("member-p720"), "projects", "proj-p720"), {
        ownerId: "member-p720",
      })
    );
    await assertFails(
      setDoc(
        doc(authedDb("member-p720"), "projects", "proj-p720", "tasks", "t20"),
        p7Task("proj-p720", "t20", { assigneeUID: "member-p720", editorUIDs: ["member-p720"] })
      )
    );
  });
});

describe("Todoshi Firestore rules — Phase 8 project types + checklist", () => {
  async function seedOwnedProject(ownerId, projectId, projectType = "tasks") {
    await commitOwnerBootstrap(authedDb(ownerId), projectId, ownerId, { projectType });
  }

  async function addRestrictedMember(ownerId, projectId, memberId) {
    const token = makeInviteToken(`c-${memberId}`);
    await seedInvite(token, inviteCreateData(projectId, ownerId));
    await commitInviteAcceptance(authedDb(memberId), token, projectId, memberId);
  }

  async function addFullMember(ownerId, projectId, memberId) {
    await addRestrictedMember(ownerId, projectId, memberId);
    await promoteMemberToFull(ownerId, projectId, memberId);
  }

  function p8Task(projectId, taskId, overrides = {}) {
    return {
      id: taskId,
      projectId,
      title: "Item",
      description: "",
      notes: "",
      statusRaw: "todo",
      priorityRaw: "none",
      position: 1000,
      parentTaskId: null,
      dueDate: null,
      reminderDate: null,
      completedAt: null,
      completedByUID: null,
      completedByDisplayName: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
      labelIds: [],
      recurrenceRuleRaw: null,
      recurrenceInterval: null,
      recurrenceSeriesID: null,
      recurrenceGeneration: 0,
      nextOccurrenceID: null,
      previousOccurrenceID: null,
      editorUIDs: [],
      assigneeUID: null,
      ...overrides,
    };
  }

  // --- Project type ---

  it("P8-1 create Tasks project valid", async () => {
    await assertSucceeds(commitOwnerBootstrap(authedDb("owner-p81"), "proj-p81", "owner-p81", { projectType: "tasks" }));
  });

  it("P8-2 create Checklist project valid", async () => {
    await assertSucceeds(
      commitOwnerBootstrap(authedDb("owner-p82"), "proj-p82", "owner-p82", { projectType: "checklist" })
    );
  });

  it("P8-3 invalid project type denied", async () => {
    await assertFails(
      commitOwnerBootstrap(authedDb("owner-p83"), "proj-p83", "owner-p83", { projectType: "kanban" })
    );
  });

  it("P8-4 legacy project without type behaves as Tasks (backlog ok)", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc("projects/proj-p84").set({
        id: "proj-p84",
        ownerId: "owner-p84",
        title: "Legacy",
        description: "",
        color: "#5B8DEF",
        memberIds: ["owner-p84"],
        createdAt: new Date(),
        updatedAt: new Date(),
        deletedAt: null,
      });
      await db.doc("projects/proj-p84/members/owner-p84").set(bootstrapMemberData("owner-p84"));
    });
    await assertSucceeds(
      setDoc(doc(authedDb("owner-p84"), "projects", "proj-p84", "tasks", "t84"), p8Task("proj-p84", "t84", { statusRaw: "backlog" }))
    );
  });

  it("P8-5 owner cannot change Tasks → Checklist", async () => {
    await seedOwnedProject("owner-p85", "proj-p85", "tasks");
    await assertFails(
      updateDoc(doc(authedDb("owner-p85"), "projects", "proj-p85"), { projectType: "checklist" })
    );
  });

  it("P8-6 owner cannot change Checklist → Tasks", async () => {
    await seedOwnedProject("owner-p86", "proj-p86", "checklist");
    await assertFails(
      updateDoc(doc(authedDb("owner-p86"), "projects", "proj-p86"), { projectType: "tasks" })
    );
  });

  it("P8-7 member cannot mutate project type", async () => {
    await seedOwnedProject("owner-p87", "proj-p87", "tasks");
    await addFullMember("owner-p87", "proj-p87", "member-p87");
    await assertFails(
      updateDoc(doc(authedDb("member-p87"), "projects", "proj-p87"), { projectType: "checklist" })
    );
  });

  // --- Checklist items ---

  it("P8-8/9/10 owner creates todo/inProgress/done checklist items", async () => {
    await seedOwnedProject("owner-p88", "proj-p88", "checklist");
    await assertSucceeds(
      setDoc(doc(authedDb("owner-p88"), "projects", "proj-p88", "tasks", "t8"), p8Task("proj-p88", "t8", { statusRaw: "todo" }))
    );
    await assertSucceeds(
      setDoc(doc(authedDb("owner-p88"), "projects", "proj-p88", "tasks", "t9"), p8Task("proj-p88", "t9", { statusRaw: "inProgress" }))
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p88"), "projects", "proj-p88", "tasks", "t10"),
        p8Task("proj-p88", "t10", {
          statusRaw: "done",
          completedAt: new Date(),
          completedByUID: "owner-p88",
          completedByDisplayName: "Anas",
        })
      )
    );
  });

  it("P8-11 checklist backlog denied", async () => {
    await seedOwnedProject("owner-p811", "proj-p811", "checklist");
    await assertFails(
      setDoc(doc(authedDb("owner-p811"), "projects", "proj-p811", "tasks", "t11"), p8Task("proj-p811", "t11", { statusRaw: "backlog" }))
    );
  });

  it("P8-12 checklist review denied", async () => {
    await seedOwnedProject("owner-p812", "proj-p812", "checklist");
    await assertFails(
      setDoc(doc(authedDb("owner-p812"), "projects", "proj-p812", "tasks", "t12"), p8Task("proj-p812", "t12", { statusRaw: "review" }))
    );
  });

  it("P8-13 checklist subtask denied", async () => {
    await seedOwnedProject("owner-p813", "proj-p813", "checklist");
    await setDoc(doc(authedDb("owner-p813"), "projects", "proj-p813", "tasks", "root13"), p8Task("proj-p813", "root13"));
    await assertFails(
      setDoc(
        doc(authedDb("owner-p813"), "projects", "proj-p813", "tasks", "sub13"),
        p8Task("proj-p813", "sub13", { parentTaskId: "root13" })
      )
    );
  });

  it("P8-14 full member creates checklist item", async () => {
    await seedOwnedProject("owner-p814", "proj-p814", "checklist");
    await addFullMember("owner-p814", "proj-p814", "member-p814");
    await assertSucceeds(
      setDoc(doc(authedDb("member-p814"), "projects", "proj-p814", "tasks", "t14"), p8Task("proj-p814", "t14"))
    );
  });

  it("P8-15 restricted member cannot create checklist item", async () => {
    await seedOwnedProject("owner-p815", "proj-p815", "checklist");
    await addRestrictedMember("owner-p815", "proj-p815", "member-p815");
    await assertFails(
      setDoc(doc(authedDb("member-p815"), "projects", "proj-p815", "tasks", "t15"), p8Task("proj-p815", "t15"))
    );
  });

  it("P8-16 authorized restricted member updates allowed item", async () => {
    await seedOwnedProject("owner-p816", "proj-p816", "checklist");
    await addRestrictedMember("owner-p816", "proj-p816", "member-p816");
    await setDoc(
      doc(authedDb("owner-p816"), "projects", "proj-p816", "tasks", "t16"),
      p8Task("proj-p816", "t16", { editorUIDs: ["member-p816"] })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p816"), "projects", "proj-p816", "tasks", "t16"),
        p8Task("proj-p816", "t16", { statusRaw: "inProgress", editorUIDs: ["member-p816"] })
      )
    );
  });

  it("P8-17 unauthorized restricted member denied", async () => {
    await seedOwnedProject("owner-p817", "proj-p817", "checklist");
    await addRestrictedMember("owner-p817", "proj-p817", "member-p817");
    await setDoc(doc(authedDb("owner-p817"), "projects", "proj-p817", "tasks", "t17"), p8Task("proj-p817", "t17"));
    await assertFails(
      setDoc(doc(authedDb("member-p817"), "projects", "proj-p817", "tasks", "t17"), p8Task("proj-p817", "t17", { title: "Nope" }))
    );
  });

  it("P8-18 full member changes checklist status", async () => {
    await seedOwnedProject("owner-p818", "proj-p818", "checklist");
    await addFullMember("owner-p818", "proj-p818", "member-p818");
    await setDoc(doc(authedDb("owner-p818"), "projects", "proj-p818", "tasks", "t18"), p8Task("proj-p818", "t18"));
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p818"), "projects", "proj-p818", "tasks", "t18"),
        p8Task("proj-p818", "t18", {
          statusRaw: "done",
          completedAt: new Date(),
          completedByUID: "member-p818",
          completedByDisplayName: "Self",
        })
      )
    );
  });

  it("P8-19 assignment rules still valid on checklist", async () => {
    await seedOwnedProject("owner-p819", "proj-p819", "checklist");
    await addFullMember("owner-p819", "proj-p819", "member-p819");
    await setDoc(doc(authedDb("owner-p819"), "projects", "proj-p819", "tasks", "t19"), p8Task("proj-p819", "t19"));
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p819"), "projects", "proj-p819", "tasks", "t19"),
        p8Task("proj-p819", "t19", { assigneeUID: "member-p819" })
      )
    );
    await assertFails(
      setDoc(
        doc(authedDb("member-p819"), "projects", "proj-p819", "tasks", "t19"),
        p8Task("proj-p819", "t19", { assigneeUID: null })
      )
    );
  });

  it("P8-20 comments still valid on checklist task", async () => {
    await seedOwnedProject("owner-p820", "proj-p820", "checklist");
    await addRestrictedMember("owner-p820", "proj-p820", "member-p820");
    await setDoc(doc(authedDb("owner-p820"), "projects", "proj-p820", "tasks", "t20"), p8Task("proj-p820", "t20"));
    const now = new Date();
    await assertSucceeds(
      setDoc(doc(authedDb("member-p820"), "projects", "proj-p820", "tasks", "t20", "comments", "cm20"), {
        id: "cm20",
        authorUID: "member-p820",
        authorDisplayName: "M",
        body: "Note",
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      })
    );
  });

  it("P8-21 non-member denied on checklist", async () => {
    await seedOwnedProject("owner-p821", "proj-p821", "checklist");
    await setDoc(doc(authedDb("owner-p821"), "projects", "proj-p821", "tasks", "t21"), p8Task("proj-p821", "t21"));
    await assertFails(
      setDoc(doc(authedDb("stranger-p821"), "projects", "proj-p821", "tasks", "t21"), p8Task("proj-p821", "t21", { title: "X" }))
    );
  });

  // --- Tasks regression ---

  it("P8-22/23/24 Tasks project backlog/review/subtask still valid", async () => {
    await seedOwnedProject("owner-p822", "proj-p822", "tasks");
    await assertSucceeds(
      setDoc(doc(authedDb("owner-p822"), "projects", "proj-p822", "tasks", "tb"), p8Task("proj-p822", "tb", { statusRaw: "backlog" }))
    );
    await assertSucceeds(
      setDoc(doc(authedDb("owner-p822"), "projects", "proj-p822", "tasks", "tr"), p8Task("proj-p822", "tr", { statusRaw: "review" }))
    );
    await setDoc(doc(authedDb("owner-p822"), "projects", "proj-p822", "tasks", "root24"), p8Task("proj-p822", "root24"));
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p822"), "projects", "proj-p822", "tasks", "sub24"),
        p8Task("proj-p822", "sub24", { parentTaskId: "root24" })
      )
    );
  });

  it("P8-25 Tasks assignment/ACL unchanged", async () => {
    await seedOwnedProject("owner-p825", "proj-p825", "tasks");
    await addRestrictedMember("owner-p825", "proj-p825", "member-p825");
    await setDoc(
      doc(authedDb("owner-p825"), "projects", "proj-p825", "tasks", "t25"),
      p8Task("proj-p825", "t25", { assigneeUID: "member-p825", editorUIDs: ["member-p825"] })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p825"), "projects", "proj-p825", "tasks", "t25"),
        p8Task("proj-p825", "t25", {
          statusRaw: "review",
          assigneeUID: "member-p825",
          editorUIDs: ["member-p825"],
        })
      )
    );
  });
});

describe("Todoshi Firestore rules — Phase 8.1 checklist completion attribution", () => {
  async function seedOwnedProject(ownerId, projectId, projectType = "checklist") {
    await commitOwnerBootstrap(authedDb(ownerId), projectId, ownerId, { projectType });
  }

  async function addRestrictedMember(ownerId, projectId, memberId) {
    const token = makeInviteToken(`c81-${memberId}`);
    await seedInvite(token, inviteCreateData(projectId, ownerId));
    await commitInviteAcceptance(authedDb(memberId), token, projectId, memberId);
  }

  async function addFullMember(ownerId, projectId, memberId) {
    await addRestrictedMember(ownerId, projectId, memberId);
    await promoteMemberToFull(ownerId, projectId, memberId);
  }

  function p81Task(projectId, taskId, overrides = {}) {
    return {
      id: taskId,
      projectId,
      title: "Item",
      description: "",
      notes: "",
      statusRaw: "todo",
      priorityRaw: "none",
      position: 1000,
      parentTaskId: null,
      dueDate: null,
      reminderDate: null,
      completedAt: null,
      completedByUID: null,
      completedByDisplayName: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
      labelIds: [],
      recurrenceRuleRaw: null,
      recurrenceInterval: null,
      recurrenceSeriesID: null,
      recurrenceGeneration: 0,
      nextOccurrenceID: null,
      previousOccurrenceID: null,
      editorUIDs: [],
      assigneeUID: null,
      ...overrides,
    };
  }

  function doneAttrs(uid, name = "Member") {
    return {
      statusRaw: "done",
      completedAt: new Date(),
      completedByUID: uid,
      completedByDisplayName: name,
    };
  }

  it("P81-1 authorized full member completes with own UID", async () => {
    await seedOwnedProject("owner-p81a", "proj-p81a");
    await addFullMember("owner-p81a", "proj-p81a", "member-p81a");
    await setDoc(doc(authedDb("owner-p81a"), "projects", "proj-p81a", "tasks", "t1"), p81Task("proj-p81a", "t1"));
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p81a"), "projects", "proj-p81a", "tasks", "t1"),
        p81Task("proj-p81a", "t1", doneAttrs("member-p81a", "Self"))
      )
    );
  });

  it("P81-2 owner completes with own UID", async () => {
    await seedOwnedProject("owner-p81b", "proj-p81b");
    await setDoc(doc(authedDb("owner-p81b"), "projects", "proj-p81b", "tasks", "t2"), p81Task("proj-p81b", "t2"));
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p81b"), "projects", "proj-p81b", "tasks", "t2"),
        p81Task("proj-p81b", "t2", doneAttrs("owner-p81b", "Anas"))
      )
    );
  });

  it("P81-3 restricted authorized member completes item", async () => {
    await seedOwnedProject("owner-p81c", "proj-p81c");
    await addRestrictedMember("owner-p81c", "proj-p81c", "member-p81c");
    await setDoc(
      doc(authedDb("owner-p81c"), "projects", "proj-p81c", "tasks", "t3"),
      p81Task("proj-p81c", "t3", { editorUIDs: ["member-p81c"] })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p81c"), "projects", "proj-p81c", "tasks", "t3"),
        p81Task("proj-p81c", "t3", {
          ...doneAttrs("member-p81c", "Self"),
          editorUIDs: ["member-p81c"],
        })
      )
    );
  });

  it("P81-4 restricted unauthorized member still denied", async () => {
    await seedOwnedProject("owner-p81d", "proj-p81d");
    await addRestrictedMember("owner-p81d", "proj-p81d", "member-p81d");
    await setDoc(doc(authedDb("owner-p81d"), "projects", "proj-p81d", "tasks", "t4"), p81Task("proj-p81d", "t4"));
    await assertFails(
      setDoc(
        doc(authedDb("member-p81d"), "projects", "proj-p81d", "tasks", "t4"),
        p81Task("proj-p81d", "t4", doneAttrs("member-p81d", "Self"))
      )
    );
  });

  it("P81-5 member cannot complete while claiming another UID", async () => {
    await seedOwnedProject("owner-p81e", "proj-p81e");
    await addFullMember("owner-p81e", "proj-p81e", "member-p81e");
    await setDoc(doc(authedDb("owner-p81e"), "projects", "proj-p81e", "tasks", "t5"), p81Task("proj-p81e", "t5"));
    await assertFails(
      setDoc(
        doc(authedDb("member-p81e"), "projects", "proj-p81e", "tasks", "t5"),
        p81Task("proj-p81e", "t5", doneAttrs("owner-p81e", "Anas"))
      )
    );
  });

  it("P81-6 non-member cannot create completion attribution", async () => {
    await seedOwnedProject("owner-p81f", "proj-p81f");
    await setDoc(doc(authedDb("owner-p81f"), "projects", "proj-p81f", "tasks", "t6"), p81Task("proj-p81f", "t6"));
    await assertFails(
      setDoc(
        doc(authedDb("stranger-p81f"), "projects", "proj-p81f", "tasks", "t6"),
        p81Task("proj-p81f", "t6", doneAttrs("stranger-p81f", "X"))
      )
    );
  });

  it("P81-7 reopen clears attribution", async () => {
    await seedOwnedProject("owner-p81g", "proj-p81g");
    const completedAt = new Date();
    await setDoc(
      doc(authedDb("owner-p81g"), "projects", "proj-p81g", "tasks", "t7"),
      p81Task("proj-p81g", "t7", {
        statusRaw: "done",
        completedAt,
        completedByUID: "owner-p81g",
        completedByDisplayName: "Anas",
      })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p81g"), "projects", "proj-p81g", "tasks", "t7"),
        p81Task("proj-p81g", "t7", {
          statusRaw: "todo",
          completedAt: null,
          completedByUID: null,
          completedByDisplayName: null,
        })
      )
    );
  });

  it("P81-8 re-complete with new actor succeeds", async () => {
    await seedOwnedProject("owner-p81h", "proj-p81h");
    await addFullMember("owner-p81h", "proj-p81h", "member-p81h");
    await setDoc(
      doc(authedDb("owner-p81h"), "projects", "proj-p81h", "tasks", "t8"),
      p81Task("proj-p81h", "t8", doneAttrs("owner-p81h", "Anas"))
    );
    await setDoc(
      doc(authedDb("owner-p81h"), "projects", "proj-p81h", "tasks", "t8"),
      p81Task("proj-p81h", "t8", { statusRaw: "todo" })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p81h"), "projects", "proj-p81h", "tasks", "t8"),
        p81Task("proj-p81h", "t8", doneAttrs("member-p81h", "Self"))
      )
    );
  });

  it("P81-9 Done→Done cannot rewrite completer", async () => {
    await seedOwnedProject("owner-p81i", "proj-p81i");
    await addFullMember("owner-p81i", "proj-p81i", "member-p81i");
    const completedAt = new Date();
    await setDoc(
      doc(authedDb("owner-p81i"), "projects", "proj-p81i", "tasks", "t9"),
      p81Task("proj-p81i", "t9", {
        statusRaw: "done",
        completedAt,
        completedByUID: "owner-p81i",
        completedByDisplayName: "Anas",
      })
    );
    await assertFails(
      setDoc(
        doc(authedDb("member-p81i"), "projects", "proj-p81i", "tasks", "t9"),
        p81Task("proj-p81i", "t9", {
          statusRaw: "done",
          completedAt,
          completedByUID: "member-p81i",
          completedByDisplayName: "Self",
          title: "Renamed",
        })
      )
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p81i"), "projects", "proj-p81i", "tasks", "t9"),
        p81Task("proj-p81i", "t9", {
          statusRaw: "done",
          completedAt,
          completedByUID: "owner-p81i",
          completedByDisplayName: "Anas",
          title: "Renamed",
        })
      )
    );
  });

  it("P81-10 assignee and completer may differ", async () => {
    await seedOwnedProject("owner-p81j", "proj-p81j");
    await addFullMember("owner-p81j", "proj-p81j", "member-p81j");
    await setDoc(
      doc(authedDb("owner-p81j"), "projects", "proj-p81j", "tasks", "t10"),
      p81Task("proj-p81j", "t10", { assigneeUID: "member-p81j" })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p81j"), "projects", "proj-p81j", "tasks", "t10"),
        p81Task("proj-p81j", "t10", {
          ...doneAttrs("owner-p81j", "Anas"),
          assigneeUID: "member-p81j",
        })
      )
    );
  });

  it("P81-11 legacy completed item without attribution remains readable", async () => {
    await seedOwnedProject("owner-p81k", "proj-p81k");
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc("projects/proj-p81k/tasks/t11").set(
        p81Task("proj-p81k", "t11", {
          statusRaw: "done",
          completedAt: new Date(),
          completedByUID: null,
          completedByDisplayName: null,
        })
      );
    });
    await assertSucceeds(getDoc(doc(authedDb("owner-p81k"), "projects", "proj-p81k", "tasks", "t11")));
  });

  it("P81-12 direct Done creation cannot spoof completer", async () => {
    await seedOwnedProject("owner-p81l", "proj-p81l");
    await addFullMember("owner-p81l", "proj-p81l", "member-p81l");
    await assertFails(
      setDoc(
        doc(authedDb("member-p81l"), "projects", "proj-p81l", "tasks", "t12"),
        p81Task("proj-p81l", "t12", doneAttrs("owner-p81l", "Anas"))
      )
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("member-p81l"), "projects", "proj-p81l", "tasks", "t12"),
        p81Task("proj-p81l", "t12", doneAttrs("member-p81l", "Self"))
      )
    );
  });

  it("P81-13 Tasks-project behavior does not regress", async () => {
    await seedOwnedProject("owner-p81m", "proj-p81m", "tasks");
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p81m"), "projects", "proj-p81m", "tasks", "t13"),
        p81Task("proj-p81m", "t13", { statusRaw: "done", completedAt: new Date() })
      )
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("owner-p81m"), "projects", "proj-p81m", "tasks", "t13b"),
        p81Task("proj-p81m", "t13b", { statusRaw: "backlog" })
      )
    );
  });
});

describe("Todoshi Firestore rules — Phase 9A member lifecycle", () => {
  async function seedOwnedProject(ownerId, projectId, projectType = "tasks") {
    await commitOwnerBootstrap(authedDb(ownerId), projectId, ownerId, { projectType });
  }

  async function addRestrictedMember(ownerId, projectId, memberId) {
    const token = makeInviteToken(`p9a-${memberId}`);
    await seedInvite(token, inviteCreateData(projectId, ownerId));
    await commitInviteAcceptance(authedDb(memberId), token, projectId, memberId);
  }

  async function addFullMember(ownerId, projectId, memberId) {
    await addRestrictedMember(ownerId, projectId, memberId);
    await promoteMemberToFull(ownerId, projectId, memberId);
  }

  async function commitMemberRemoval(db, projectId, memberId) {
    const batch = writeBatch(db);
    batch.delete(doc(db, "projects", projectId, "members", memberId));
    batch.update(doc(db, "projects", projectId), { memberIds: arrayRemove(memberId) });
    return batch.commit();
  }

  function p9aTask(projectId, taskId, overrides = {}) {
    return {
      id: taskId,
      projectId,
      title: "Item",
      description: "",
      notes: "",
      statusRaw: "todo",
      priorityRaw: "none",
      position: 1000,
      parentTaskId: null,
      dueDate: null,
      reminderDate: null,
      completedAt: null,
      completedByUID: null,
      completedByDisplayName: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
      labelIds: [],
      recurrenceRuleRaw: null,
      recurrenceInterval: null,
      recurrenceSeriesID: null,
      recurrenceGeneration: 0,
      nextOccurrenceID: null,
      previousOccurrenceID: null,
      editorUIDs: [],
      assigneeUID: null,
      ...overrides,
    };
  }

  it("P9A-1 owner removes normal member", async () => {
    await seedOwnedProject("owner-p9a1", "proj-p9a1");
    await addFullMember("owner-p9a1", "proj-p9a1", "member-p9a1");
    await assertSucceeds(commitMemberRemoval(authedDb("owner-p9a1"), "proj-p9a1", "member-p9a1"));
    const memberSnap = await adminGet(["projects", "proj-p9a1", "members", "member-p9a1"]);
    if (memberSnap.exists) {
      throw new Error("expected membership to be deleted");
    }
  });

  it("P9A-2 owner cannot remove owner", async () => {
    await seedOwnedProject("owner-p9a2", "proj-p9a2");
    await assertFails(commitMemberRemoval(authedDb("owner-p9a2"), "proj-p9a2", "owner-p9a2"));
  });

  it("P9A-3 member cannot remove another member", async () => {
    await seedOwnedProject("owner-p9a3", "proj-p9a3");
    await addFullMember("owner-p9a3", "proj-p9a3", "member-a-p9a3");
    await addFullMember("owner-p9a3", "proj-p9a3", "member-b-p9a3");
    await assertFails(commitMemberRemoval(authedDb("member-a-p9a3"), "proj-p9a3", "member-b-p9a3"));
  });

  it("P9A-4 member can leave self", async () => {
    await seedOwnedProject("owner-p9a4", "proj-p9a4");
    await addFullMember("owner-p9a4", "proj-p9a4", "member-p9a4");
    await assertSucceeds(commitMemberRemoval(authedDb("member-p9a4"), "proj-p9a4", "member-p9a4"));
  });

  it("P9A-5 owner cannot leave through member flow", async () => {
    await seedOwnedProject("owner-p9a5", "proj-p9a5");
    await assertFails(commitMemberRemoval(authedDb("owner-p9a5"), "proj-p9a5", "owner-p9a5"));
  });

  it("P9A-6 non-member cannot alter membership", async () => {
    await seedOwnedProject("owner-p9a6", "proj-p9a6");
    await addFullMember("owner-p9a6", "proj-p9a6", "member-p9a6");
    await assertFails(commitMemberRemoval(authedDb("stranger-p9a6"), "proj-p9a6", "member-p9a6"));
  });

  it("P9A-7 exact memberIds removal succeeds", async () => {
    await seedOwnedProject("owner-p9a7", "proj-p9a7");
    await addFullMember("owner-p9a7", "proj-p9a7", "member-p9a7");
    await assertSucceeds(commitMemberRemoval(authedDb("owner-p9a7"), "proj-p9a7", "member-p9a7"));
    const projectSnap = await adminGet(["projects", "proj-p9a7"]);
    const memberIds = projectSnap.data().memberIds;
    if (memberIds.includes("member-p9a7") || !memberIds.includes("owner-p9a7")) {
      throw new Error(`unexpected memberIds: ${memberIds.join(",")}`);
    }
  });

  it("P9A-8 arbitrary memberIds replacement denied", async () => {
    await seedOwnedProject("owner-p9a8", "proj-p9a8");
    await addFullMember("owner-p9a8", "proj-p9a8", "member-p9a8");
    await assertFails(
      updateDoc(doc(authedDb("owner-p9a8"), "projects", "proj-p9a8"), {
        memberIds: ["owner-p9a8", "member-p9a8", "intruder-p9a8"],
      })
    );
  });

  it("P9A-9 memberIds-only user still has no access", async () => {
    await seedOwnedProject("owner-p9a9", "proj-p9a9");
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc("projects/proj-p9a9").update({
        memberIds: ["owner-p9a9", "fake-p9a9"],
      });
    });
    await assertFails(getDoc(doc(authedDb("fake-p9a9"), "projects", "proj-p9a9")));
  });

  it("P9A-10 removed member cannot read project", async () => {
    await seedOwnedProject("owner-p9a10", "proj-p9a10");
    await addFullMember("owner-p9a10", "proj-p9a10", "member-p9a10");
    await assertSucceeds(commitMemberRemoval(authedDb("owner-p9a10"), "proj-p9a10", "member-p9a10"));
    await assertFails(getDoc(doc(authedDb("member-p9a10"), "projects", "proj-p9a10")));
  });

  it("P9A-11 removed member cannot update task", async () => {
    await seedOwnedProject("owner-p9a11", "proj-p9a11");
    await addFullMember("owner-p9a11", "proj-p9a11", "member-p9a11");
    await setDoc(
      doc(authedDb("owner-p9a11"), "projects", "proj-p9a11", "tasks", "t11"),
      p9aTask("proj-p9a11", "t11")
    );
    await assertSucceeds(commitMemberRemoval(authedDb("owner-p9a11"), "proj-p9a11", "member-p9a11"));
    await assertFails(
      updateDoc(doc(authedDb("member-p9a11"), "projects", "proj-p9a11", "tasks", "t11"), {
        title: "Hacked",
        updatedAt: new Date(),
      })
    );
  });

  it("P9A-12 removed member cannot comment", async () => {
    await seedOwnedProject("owner-p9a12", "proj-p9a12");
    await addFullMember("owner-p9a12", "proj-p9a12", "member-p9a12");
    await setDoc(
      doc(authedDb("owner-p9a12"), "projects", "proj-p9a12", "tasks", "t12"),
      p9aTask("proj-p9a12", "t12")
    );
    await assertSucceeds(commitMemberRemoval(authedDb("owner-p9a12"), "proj-p9a12", "member-p9a12"));
    await assertFails(
      setDoc(doc(authedDb("member-p9a12"), "projects", "proj-p9a12", "tasks", "t12", "comments", "c12"), {
        id: "c12",
        authorUID: "member-p9a12",
        authorDisplayName: "Bob",
        body: "Hi",
        createdAt: new Date(),
        updatedAt: new Date(),
        deletedAt: null,
      })
    );
  });

  it("P9A-13 owner retains access", async () => {
    await seedOwnedProject("owner-p9a13", "proj-p9a13");
    await addFullMember("owner-p9a13", "proj-p9a13", "member-p9a13");
    await assertSucceeds(commitMemberRemoval(authedDb("owner-p9a13"), "proj-p9a13", "member-p9a13"));
    await assertSucceeds(getDoc(doc(authedDb("owner-p9a13"), "projects", "proj-p9a13")));
  });

  it("P9A-14 other members retain access", async () => {
    await seedOwnedProject("owner-p9a14", "proj-p9a14");
    await addFullMember("owner-p9a14", "proj-p9a14", "member-a-p9a14");
    await addFullMember("owner-p9a14", "proj-p9a14", "member-b-p9a14");
    await assertSucceeds(commitMemberRemoval(authedDb("owner-p9a14"), "proj-p9a14", "member-a-p9a14"));
    await assertSucceeds(getDoc(doc(authedDb("member-b-p9a14"), "projects", "proj-p9a14")));
  });

  it("P9A-15 self-leave can remove own editorUID", async () => {
    await seedOwnedProject("owner-p9a15", "proj-p9a15");
    await addFullMember("owner-p9a15", "proj-p9a15", "member-p9a15");
    await setDoc(
      doc(authedDb("owner-p9a15"), "projects", "proj-p9a15", "tasks", "t15"),
      p9aTask("proj-p9a15", "t15", { editorUIDs: ["member-p9a15"] })
    );
    await assertSucceeds(
      updateDoc(doc(authedDb("member-p9a15"), "projects", "proj-p9a15", "tasks", "t15"), {
        editorUIDs: [],
        updatedAt: new Date(),
      })
    );
  });

  it("P9A-16 self-leave cannot remove another editorUID", async () => {
    await seedOwnedProject("owner-p9a16", "proj-p9a16");
    await addFullMember("owner-p9a16", "proj-p9a16", "member-a-p9a16");
    await addFullMember("owner-p9a16", "proj-p9a16", "member-b-p9a16");
    await setDoc(
      doc(authedDb("owner-p9a16"), "projects", "proj-p9a16", "tasks", "t16"),
      p9aTask("proj-p9a16", "t16", { editorUIDs: ["member-a-p9a16", "member-b-p9a16"] })
    );
    await assertFails(
      updateDoc(doc(authedDb("member-a-p9a16"), "projects", "proj-p9a16", "tasks", "t16"), {
        editorUIDs: [],
        updatedAt: new Date(),
      })
    );
  });

  it("P9A-17 self-leave may clear own assigneeUID", async () => {
    await seedOwnedProject("owner-p9a17", "proj-p9a17");
    await addFullMember("owner-p9a17", "proj-p9a17", "member-p9a17");
    await setDoc(
      doc(authedDb("owner-p9a17"), "projects", "proj-p9a17", "tasks", "t17"),
      p9aTask("proj-p9a17", "t17", { assigneeUID: "member-p9a17" })
    );
    await assertSucceeds(
      updateDoc(doc(authedDb("member-p9a17"), "projects", "proj-p9a17", "tasks", "t17"), {
        assigneeUID: null,
        updatedAt: new Date(),
      })
    );
  });

  it("P9A-18 self-leave cannot clear someone else's assignee", async () => {
    await seedOwnedProject("owner-p9a18", "proj-p9a18");
    await addFullMember("owner-p9a18", "proj-p9a18", "member-a-p9a18");
    await addFullMember("owner-p9a18", "proj-p9a18", "member-b-p9a18");
    await setDoc(
      doc(authedDb("owner-p9a18"), "projects", "proj-p9a18", "tasks", "t18"),
      p9aTask("proj-p9a18", "t18", { assigneeUID: "member-b-p9a18" })
    );
    await assertFails(
      updateDoc(doc(authedDb("member-a-p9a18"), "projects", "proj-p9a18", "tasks", "t18"), {
        assigneeUID: null,
        updatedAt: new Date(),
      })
    );
  });

  it("P9A-19 historical completedByUID for removed member remains valid", async () => {
    await seedOwnedProject("owner-p9a19", "proj-p9a19", "checklist");
    await addFullMember("owner-p9a19", "proj-p9a19", "member-p9a19");
    const completedAt = new Date();
    await setDoc(
      doc(authedDb("member-p9a19"), "projects", "proj-p9a19", "tasks", "t19"),
      p9aTask("proj-p9a19", "t19", {
        statusRaw: "done",
        completedAt,
        completedByUID: "member-p9a19",
        completedByDisplayName: "Mohammed",
      })
    );
    await assertSucceeds(commitMemberRemoval(authedDb("owner-p9a19"), "proj-p9a19", "member-p9a19"));
    await assertSucceeds(
      updateDoc(doc(authedDb("owner-p9a19"), "projects", "proj-p9a19", "tasks", "t19"), {
        title: "Renamed",
        updatedAt: new Date(),
      })
    );
    const snap = await adminGet(["projects", "proj-p9a19", "tasks", "t19"]);
    if (snap.data().completedByUID !== "member-p9a19" || snap.data().completedByDisplayName !== "Mohammed") {
      throw new Error("historical completion attribution was not preserved");
    }
  });

  it("P9A-20 historical comment remains readable by remaining members", async () => {
    await seedOwnedProject("owner-p9a20", "proj-p9a20");
    await addFullMember("owner-p9a20", "proj-p9a20", "member-p9a20");
    await setDoc(
      doc(authedDb("owner-p9a20"), "projects", "proj-p9a20", "tasks", "t20"),
      p9aTask("proj-p9a20", "t20")
    );
    await setDoc(
      doc(authedDb("member-p9a20"), "projects", "proj-p9a20", "tasks", "t20", "comments", "c20"),
      {
        id: "c20",
        authorUID: "member-p9a20",
        authorDisplayName: "Bob",
        body: "Still here",
        createdAt: new Date(),
        updatedAt: new Date(),
        deletedAt: null,
      }
    );
    await assertSucceeds(commitMemberRemoval(authedDb("owner-p9a20"), "proj-p9a20", "member-p9a20"));
    const commentSnap = await getDoc(
      doc(authedDb("owner-p9a20"), "projects", "proj-p9a20", "tasks", "t20", "comments", "c20")
    );
    if (commentSnap.data().body !== "Still here") {
      throw new Error("historical comment was not preserved");
    }
  });

  it("P9A-21 removed member completion attribution cannot be rewritten", async () => {
    await seedOwnedProject("owner-p9a21", "proj-p9a21", "checklist");
    await addFullMember("owner-p9a21", "proj-p9a21", "member-p9a21");
    const completedAt = new Date();
    await setDoc(
      doc(authedDb("member-p9a21"), "projects", "proj-p9a21", "tasks", "t21"),
      p9aTask("proj-p9a21", "t21", {
        statusRaw: "done",
        completedAt,
        completedByUID: "member-p9a21",
        completedByDisplayName: "Bob",
      })
    );
    await assertSucceeds(commitMemberRemoval(authedDb("owner-p9a21"), "proj-p9a21", "member-p9a21"));
    await assertFails(
      updateDoc(doc(authedDb("member-p9a21"), "projects", "proj-p9a21", "tasks", "t21"), {
        completedByUID: "member-p9a21",
        completedByDisplayName: "Spoof",
        updatedAt: new Date(),
      })
    );
  });

  it("P9A-22 tasks project removal clears assignment", async () => {
    await seedOwnedProject("owner-p9a22", "proj-p9a22", "tasks");
    await addFullMember("owner-p9a22", "proj-p9a22", "member-p9a22");
    await setDoc(
      doc(authedDb("owner-p9a22"), "projects", "proj-p9a22", "tasks", "t22"),
      p9aTask("proj-p9a22", "t22", { assigneeUID: "member-p9a22", editorUIDs: ["member-p9a22"] })
    );
    await assertSucceeds(
      updateDoc(doc(authedDb("owner-p9a22"), "projects", "proj-p9a22", "tasks", "t22"), {
        assigneeUID: null,
        editorUIDs: [],
        updatedAt: new Date(),
      })
    );
    await assertSucceeds(commitMemberRemoval(authedDb("owner-p9a22"), "proj-p9a22", "member-p9a22"));
  });

  it("P9A-23 checklist project removal clears assignment", async () => {
    await seedOwnedProject("owner-p9a23", "proj-p9a23", "checklist");
    await addFullMember("owner-p9a23", "proj-p9a23", "member-p9a23");
    await setDoc(
      doc(authedDb("owner-p9a23"), "projects", "proj-p9a23", "tasks", "t23"),
      p9aTask("proj-p9a23", "t23", { assigneeUID: "member-p9a23", editorUIDs: ["member-p9a23"] })
    );
    await assertSucceeds(
      updateDoc(doc(authedDb("owner-p9a23"), "projects", "proj-p9a23", "tasks", "t23"), {
        assigneeUID: null,
        editorUIDs: [],
        updatedAt: new Date(),
      })
    );
    await assertSucceeds(commitMemberRemoval(authedDb("owner-p9a23"), "proj-p9a23", "member-p9a23"));
  });
});

describe("Todoshi Firestore rules — collaboration activity summary", () => {
  async function seedOwnedProject(ownerId, projectId) {
    await commitOwnerBootstrap(authedDb(ownerId), projectId, ownerId);
  }

  async function addRestrictedMember(ownerId, projectId, memberId) {
    const token = makeInviteToken(`ca-${memberId}`);
    await seedInvite(token, inviteCreateData(projectId, ownerId));
    await commitInviteAcceptance(authedDb(memberId), token, projectId, memberId);
  }

  async function addFullMember(ownerId, projectId, memberId) {
    await addRestrictedMember(ownerId, projectId, memberId);
    await promoteMemberToFull(ownerId, projectId, memberId);
  }

  function activityTask(projectId, taskId, overrides = {}) {
    return {
      id: taskId,
      projectId,
      title: "Task",
      description: "",
      notes: "",
      statusRaw: "todo",
      priorityRaw: "none",
      position: 1000,
      parentTaskId: null,
      dueDate: null,
      reminderDate: null,
      completedAt: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
      labelIds: [],
      recurrenceRuleRaw: null,
      recurrenceInterval: null,
      recurrenceSeriesID: null,
      recurrenceGeneration: 0,
      nextOccurrenceID: null,
      previousOccurrenceID: null,
      editorUIDs: [],
      ...overrides,
    };
  }

  function activityBump(uid, kind) {
    return {
      lastActivityAt: new Date(),
      lastActivityByUID: uid,
      lastActivityKind: kind,
      updatedAt: new Date(),
    };
  }

  it("CA-1 member task mutation can set own activity UID", async () => {
    await seedOwnedProject("owner-ca1", "proj-ca1");
    await addFullMember("owner-ca1", "proj-ca1", "member-ca1");
    await setDoc(
      doc(authedDb("owner-ca1"), "projects", "proj-ca1", "tasks", "t1"),
      activityTask("proj-ca1", "t1")
    );
    await assertSucceeds(
      updateDoc(doc(authedDb("member-ca1"), "projects", "proj-ca1", "tasks", "t1"), {
        ...activityTask("proj-ca1", "t1", { title: "Changed" }),
        ...activityBump("member-ca1", "taskUpdated"),
      })
    );
  });

  it("CA-2 cannot spoof another activity UID", async () => {
    await seedOwnedProject("owner-ca2", "proj-ca2");
    await addFullMember("owner-ca2", "proj-ca2", "member-ca2");
    await setDoc(
      doc(authedDb("owner-ca2"), "projects", "proj-ca2", "tasks", "t2"),
      activityTask("proj-ca2", "t2")
    );
    await assertFails(
      updateDoc(doc(authedDb("member-ca2"), "projects", "proj-ca2", "tasks", "t2"), activityBump("owner-ca2", "taskUpdated"))
    );
  });

  it("CA-3 non-member denied activity summary update", async () => {
    await seedOwnedProject("owner-ca3", "proj-ca3");
    await setDoc(
      doc(authedDb("owner-ca3"), "projects", "proj-ca3", "tasks", "t3"),
      activityTask("proj-ca3", "t3")
    );
    await assertFails(
      updateDoc(doc(authedDb("stranger-ca3"), "projects", "proj-ca3", "tasks", "t3"), activityBump("stranger-ca3", "commentAdded"))
    );
  });

  it("CA-4 valid comment can bump activity summary", async () => {
    await seedOwnedProject("owner-ca4", "proj-ca4");
    await addRestrictedMember("owner-ca4", "proj-ca4", "member-ca4");
    await setDoc(
      doc(authedDb("owner-ca4"), "projects", "proj-ca4", "tasks", "t4"),
      activityTask("proj-ca4", "t4")
    );
    await assertSucceeds(
      updateDoc(doc(authedDb("member-ca4"), "projects", "proj-ca4", "tasks", "t4"), activityBump("member-ca4", "commentAdded"))
    );
  });

  it("CA-5 comment activity cannot alter task title/status", async () => {
    await seedOwnedProject("owner-ca5", "proj-ca5");
    await addRestrictedMember("owner-ca5", "proj-ca5", "member-ca5");
    await setDoc(
      doc(authedDb("owner-ca5"), "projects", "proj-ca5", "tasks", "t5"),
      activityTask("proj-ca5", "t5")
    );
    await assertFails(
      updateDoc(doc(authedDb("member-ca5"), "projects", "proj-ca5", "tasks", "t5"), {
        title: "Hijacked",
        ...activityBump("member-ca5", "commentAdded"),
      })
    );
  });

  it("CA-6 restricted non-editor can bump comment activity only", async () => {
    await seedOwnedProject("owner-ca6", "proj-ca6");
    await addRestrictedMember("owner-ca6", "proj-ca6", "member-ca6");
    await setDoc(
      doc(authedDb("owner-ca6"), "projects", "proj-ca6", "tasks", "t6"),
      activityTask("proj-ca6", "t6")
    );
    await assertSucceeds(
      updateDoc(doc(authedDb("member-ca6"), "projects", "proj-ca6", "tasks", "t6"), activityBump("member-ca6", "commentEdited"))
    );
    await assertFails(
      updateDoc(doc(authedDb("member-ca6"), "projects", "proj-ca6", "tasks", "t6"), activityBump("member-ca6", "subtaskChanged"))
    );
  });

  it("CA-7 subtask-authorized member can bump root activity", async () => {
    await seedOwnedProject("owner-ca7", "proj-ca7");
    await addRestrictedMember("owner-ca7", "proj-ca7", "member-ca7");
    await setDoc(
      doc(authedDb("owner-ca7"), "projects", "proj-ca7", "tasks", "root7"),
      activityTask("proj-ca7", "root7", { editorUIDs: ["member-ca7"] })
    );
    await assertSucceeds(
      updateDoc(doc(authedDb("member-ca7"), "projects", "proj-ca7", "tasks", "root7"), activityBump("member-ca7", "subtaskChanged"))
    );
  });

  it("CA-8 assignment/status existing security unchanged", async () => {
    await seedOwnedProject("owner-ca8", "proj-ca8");
    await addRestrictedMember("owner-ca8", "proj-ca8", "member-ca8");
    await setDoc(
      doc(authedDb("owner-ca8"), "projects", "proj-ca8", "tasks", "t8"),
      activityTask("proj-ca8", "t8")
    );
    await assertFails(
      updateDoc(doc(authedDb("member-ca8"), "projects", "proj-ca8", "tasks", "t8"), {
        ...activityTask("proj-ca8", "t8", { statusRaw: "done" }),
        ...activityBump("member-ca8", "statusChanged"),
      })
    );
  });

  it("CA-9 historical removed-member activity metadata does not break later valid task update", async () => {
    await seedOwnedProject("owner-ca9", "proj-ca9");
    await addFullMember("owner-ca9", "proj-ca9", "member-ca9");
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), "projects", "proj-ca9", "tasks", "t9"),
        activityTask("proj-ca9", "t9", {
          lastActivityAt: new Date(),
          lastActivityByUID: "removed-member",
          lastActivityKind: "commentAdded",
        })
      );
    });
    await assertSucceeds(
      updateDoc(doc(authedDb("member-ca9"), "projects", "proj-ca9", "tasks", "t9"), {
        ...activityTask("proj-ca9", "t9", { title: "Still editable" }),
        ...activityBump("member-ca9", "taskUpdated"),
      })
    );
  });
});

describe("Todoshi Firestore rules — membership display name", () => {
  async function seedOwnedProject(ownerId, projectId) {
    await commitOwnerBootstrap(authedDb(ownerId), projectId, ownerId);
  }

  async function addFullMember(ownerId, projectId, memberId) {
    const token = makeInviteToken(`dn-${memberId}`);
    await seedInvite(token, inviteCreateData(projectId, ownerId));
    await commitInviteAcceptance(authedDb(memberId), token, projectId, memberId);
  }

  function memberData(uid, overrides = {}) {
    return {
      userId: uid,
      role: "member",
      displayName: "Old Name",
      joinedAt: new Date(),
      accessLevel: "full",
      ...overrides,
    };
  }

  it("DN-1 member can update own displayName only", async () => {
    await seedOwnedProject("owner-dn1", "proj-dn1");
    await addFullMember("owner-dn1", "proj-dn1", "member-dn1");
    await assertSucceeds(
      updateDoc(doc(authedDb("member-dn1"), "projects", "proj-dn1", "members", "member-dn1"), {
        displayName: "New Name",
      })
    );
  });

  it("DN-2 member cannot update another membership", async () => {
    await seedOwnedProject("owner-dn2", "proj-dn2");
    await addFullMember("owner-dn2", "proj-dn2", "member-dn2");
    await addFullMember("owner-dn2", "proj-dn2", "other-dn2");
    await assertFails(
      updateDoc(doc(authedDb("member-dn2"), "projects", "proj-dn2", "members", "other-dn2"), {
        displayName: "Hijacked",
      })
    );
  });

  it("DN-3 member cannot change own role", async () => {
    await seedOwnedProject("owner-dn3", "proj-dn3");
    await addFullMember("owner-dn3", "proj-dn3", "member-dn3");
    await assertFails(
      updateDoc(doc(authedDb("member-dn3"), "projects", "proj-dn3", "members", "member-dn3"), {
        displayName: "Still Member",
        role: "owner",
      })
    );
  });

  it("DN-4 member cannot change own accessLevel", async () => {
    await seedOwnedProject("owner-dn4", "proj-dn4");
    await addFullMember("owner-dn4", "proj-dn4", "member-dn4");
    await assertFails(
      updateDoc(doc(authedDb("member-dn4"), "projects", "proj-dn4", "members", "member-dn4"), {
        accessLevel: "restricted",
      })
    );
  });

  it("DN-5 member cannot change joinedAt", async () => {
    await seedOwnedProject("owner-dn5", "proj-dn5");
    await addFullMember("owner-dn5", "proj-dn5", "member-dn5");
    await assertFails(
      updateDoc(doc(authedDb("member-dn5"), "projects", "proj-dn5", "members", "member-dn5"), {
        displayName: "Still Member",
        joinedAt: new Date("2020-01-01"),
      })
    );
  });

  it("DN-6 owner access-level behavior unchanged", async () => {
    await seedOwnedProject("owner-dn6", "proj-dn6");
    await addFullMember("owner-dn6", "proj-dn6", "member-dn6");
    await assertSucceeds(
      updateDoc(doc(authedDb("owner-dn6"), "projects", "proj-dn6", "members", "member-dn6"), {
        accessLevel: "restricted",
      })
    );
  });

  it("DN-7 non-member cannot update another membership", async () => {
    await seedOwnedProject("owner-dn7", "proj-dn7");
    await addFullMember("owner-dn7", "proj-dn7", "member-dn7");
    await assertFails(
      updateDoc(doc(authedDb("stranger-dn7"), "projects", "proj-dn7", "members", "member-dn7"), {
        displayName: "Hijacked",
      })
    );
  });

  it("DN-8 profile rename does not change authorization", async () => {
    await seedOwnedProject("owner-dn8", "proj-dn8");
    await addFullMember("owner-dn8", "proj-dn8", "member-dn8");
    await assertSucceeds(
      updateDoc(doc(authedDb("member-dn8"), "projects", "proj-dn8", "members", "member-dn8"), {
        displayName: "ااااا",
      })
    );
    await assertSucceeds(getDoc(doc(authedDb("member-dn8"), "projects", "proj-dn8")));
  });
});

describe("Todoshi Firestore rules — stable Todoshi ID", () => {
  const sampleId = "TD-7K4P-9Q2M-X5R7Q";
  const otherId = "TD-AAAA-BBBB-CCCCC";

  async function seedUserProfile(uid, overrides = {}) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("users").doc(uid).set({
        displayName: "Member",
        email: "member@example.com",
        createdAt: new Date(),
        updatedAt: new Date(),
        ...overrides,
      });
    });
  }

  it("TI-1 user claims own new ID", async () => {
    await seedUserProfile("user-ti1");
    await assertSucceeds(
      setDoc(doc(authedDb("user-ti1"), "todoshiIds", sampleId), {
        uid: "user-ti1",
        createdAt: new Date(),
      })
    );
    await assertSucceeds(
      setDoc(doc(authedDb("user-ti1"), "publicIdentities", "user-ti1"), {
        userId: "user-ti1",
        todoshiId: sampleId,
        createdAt: new Date(),
      })
    );
    await assertSucceeds(
      setDoc(
        doc(authedDb("user-ti1"), "users", "user-ti1"),
        { todoshiId: sampleId, updatedAt: new Date() },
        { merge: true }
      )
    );
  });

  it("TI-2 user cannot claim ID for another UID", async () => {
    await assertFails(
      setDoc(doc(authedDb("user-ti2"), "todoshiIds", sampleId), {
        uid: "other-ti2",
        createdAt: new Date(),
      })
    );
  });

  it("TI-3 user cannot overwrite another user's claimed ID", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("todoshiIds").doc(sampleId).set({
        uid: "owner-ti3",
        createdAt: new Date(),
      });
    });
    await assertFails(
      setDoc(doc(authedDb("intruder-ti3"), "todoshiIds", sampleId), {
        uid: "intruder-ti3",
        createdAt: new Date(),
      })
    );
  });

  it("TI-4 existing claim cannot be reassigned", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("todoshiIds").doc(sampleId).set({
        uid: "owner-ti4",
        createdAt: new Date(),
      });
    });
    await assertFails(
      updateDoc(doc(authedDb("owner-ti4"), "todoshiIds", sampleId), {
        uid: "someone-else-ti4",
      })
    );
  });

  it("TI-5 todoshiIds collection listing denied", async () => {
    await assertFails(getDocs(collection(authedDb("user-ti5"), "todoshiIds")));
  });

  it("TI-6 exact collision-check get allowed for authenticated user", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("todoshiIds").doc(sampleId).set({
        uid: "owner-ti6",
        createdAt: new Date(),
      });
    });
    await assertSucceeds(getDoc(doc(authedDb("user-ti6"), "todoshiIds", sampleId)));
  });

  it("TI-7 public identity self-create valid", async () => {
    await assertSucceeds(
      setDoc(doc(authedDb("user-ti7"), "publicIdentities", "user-ti7"), {
        userId: "user-ti7",
        todoshiId: sampleId,
        createdAt: new Date(),
      })
    );
  });

  it("TI-8 user cannot create public identity for another UID", async () => {
    await assertFails(
      setDoc(doc(authedDb("user-ti8"), "publicIdentities", "other-ti8"), {
        userId: "other-ti8",
        todoshiId: sampleId,
        createdAt: new Date(),
      })
    );
  });

  it("TI-9 public identity ID immutable", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("publicIdentities").doc("user-ti9").set({
        userId: "user-ti9",
        todoshiId: sampleId,
        createdAt: new Date(),
      });
    });
    await assertFails(
      updateDoc(doc(authedDb("user-ti9"), "publicIdentities", "user-ti9"), {
        todoshiId: otherId,
      })
    );
  });

  it("TI-10 public identity collection list denied", async () => {
    await assertFails(getDocs(collection(authedDb("user-ti10"), "publicIdentities")));
  });

  it("TI-11 normal profile rename preserves todoshiId", async () => {
    await seedUserProfile("user-ti11", { todoshiId: sampleId });
    await assertSucceeds(
      setDoc(
        doc(authedDb("user-ti11"), "users", "user-ti11"),
        { displayName: "ااااا", updatedAt: new Date() },
        { merge: true }
      )
    );
    const snap = await getDoc(doc(authedDb("user-ti11"), "users", "user-ti11"));
    assert.equal(snap.data().todoshiId, sampleId);
  });

  it("TI-12 profile cannot change todoshiId", async () => {
    await seedUserProfile("user-ti12", { todoshiId: sampleId });
    await assertFails(
      setDoc(
        doc(authedDb("user-ti12"), "users", "user-ti12"),
        { todoshiId: otherId, updatedAt: new Date() },
        { merge: true }
      )
    );
  });

  it("TI-13 removed project member still retains global public identity", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await adminDb.collection("publicIdentities").doc("member-ti13").set({
        userId: "member-ti13",
        todoshiId: sampleId,
        createdAt: new Date(),
      });
      await adminDb.collection("projects").doc("proj-ti13").collection("members").doc("member-ti13").delete();
    });
    await assertSucceeds(getDoc(doc(authedDb("owner-ti13"), "publicIdentities", "member-ti13")));
  });

  it("TI-14 owner exact lookup by member UID succeeds", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("publicIdentities").doc("member-ti14").set({
        userId: "member-ti14",
        todoshiId: sampleId,
        createdAt: new Date(),
      });
    });
    const snap = await getDoc(doc(authedDb("owner-ti14"), "publicIdentities", "member-ti14"));
    assert.equal(snap.data().todoshiId, sampleId);
  });

  it("TI-15 non-auth user cannot read todoshiIds claim", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("todoshiIds").doc(sampleId).set({
        uid: "owner-ti15",
        createdAt: new Date(),
      });
    });
    await assertFails(getDoc(doc(anonDb(), "todoshiIds", sampleId)));
  });

  it("TI-15b non-auth user cannot read public identity", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("publicIdentities").doc("user-ti15").set({
        userId: "user-ti15",
        todoshiId: sampleId,
        createdAt: new Date(),
      });
    });
    await assertFails(getDoc(doc(anonDb(), "publicIdentities", "user-ti15")));
  });

  async function commitProvisioningTransaction(db, uid, todoshiId) {
    return runTransaction(db, async (transaction) => {
      const userRef = doc(db, "users", uid);
      const claimRef = doc(db, "todoshiIds", todoshiId);
      const publicRef = doc(db, "publicIdentities", uid);
      await transaction.get(userRef);
      await transaction.get(claimRef);
      await transaction.get(publicRef);
      transaction.set(
        userRef,
        { todoshiId, updatedAt: new Date() },
        { merge: true }
      );
      transaction.set(claimRef, {
        uid,
        createdAt: new Date(),
      });
      transaction.set(publicRef, {
        userId: uid,
        todoshiId,
        createdAt: new Date(),
      });
    });
  }

  it("TI-16 legacy user without todoshiId field can provision", async () => {
    await seedUserProfile("legacy-ti16");
    await assertSucceeds(
      commitProvisioningTransaction(authedDb("legacy-ti16"), "legacy-ti16", sampleId)
    );
    const snap = await getDoc(doc(authedDb("legacy-ti16"), "users", "legacy-ti16"));
    assert.equal(snap.data().todoshiId, sampleId);
  });

  it("TI-17 legacy user with null todoshiId can provision", async () => {
    await seedUserProfile("legacy-ti17", { todoshiId: null });
    await assertSucceeds(
      commitProvisioningTransaction(authedDb("legacy-ti17"), "legacy-ti17", sampleId)
    );
    const snap = await getDoc(doc(authedDb("legacy-ti17"), "users", "legacy-ti17"));
    assert.equal(snap.data().todoshiId, sampleId);
  });

  it("TI-18 new user without profile can provision", async () => {
    await assertSucceeds(
      commitProvisioningTransaction(authedDb("new-ti18"), "new-ti18", sampleId)
    );
    const snap = await getDoc(doc(authedDb("new-ti18"), "users", "new-ti18"));
    assert.equal(snap.data().todoshiId, sampleId);
  });

  it("TI-19 provisioned user cannot replace todoshiId", async () => {
    await seedUserProfile("legacy-ti19", { todoshiId: sampleId });
    await assertFails(
      setDoc(
        doc(authedDb("legacy-ti19"), "users", "legacy-ti19"),
        { todoshiId: otherId, updatedAt: new Date() },
        { merge: true }
      )
    );
  });

  it("TI-20 provisioned user cannot remove todoshiId", async () => {
    await seedUserProfile("legacy-ti20", { todoshiId: sampleId });
    await assertFails(
      setDoc(
        doc(authedDb("legacy-ti20"), "users", "legacy-ti20"),
        { todoshiId: null, updatedAt: new Date() },
        { merge: true }
      )
    );
  });

  it("TI-21 user cannot claim another user's todoshiId", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("todoshiIds").doc(sampleId).set({
        uid: "owner-ti21",
        createdAt: new Date(),
      });
    });
    await assertFails(
      setDoc(doc(authedDb("intruder-ti21"), "todoshiIds", sampleId), {
        uid: "intruder-ti21",
        createdAt: new Date(),
      })
    );
  });
});

describe("Todoshi account deletion security", () => {
  const alice = "alice-del";
  const bob = "bob-del";
  const sampleId = "TD-7K4P-9Q2M-X5R7Q";
  const otherId = "TD-AAAA-BBBB-CCCCC";

  beforeEach(async () => {
    await seedProject("adel-p1", alice, [alice, bob], {
      [alice]: { role: "owner" },
      [bob]: { role: "member" },
    });
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.collection("projects").doc("adel-p1").collection("tasks").doc("t1").set({
        id: "t1",
        title: "Task",
        status: "done",
        priority: "none",
        position: 1,
        parentTaskId: null,
        deletedAt: null,
        completedAt: new Date(),
        completedByUID: alice,
        completedByDisplayName: "Alice",
        lastActivityAt: new Date(),
        lastActivityByUID: alice,
        lastActivityKind: "statusChanged",
        assigneeUID: bob,
        editorUIDs: [bob],
        updatedAt: new Date(),
      });
      await db
        .collection("projects")
        .doc("adel-p1")
        .collection("tasks")
        .doc("t1")
        .collection("comments")
        .doc("c-alice")
        .set({
          id: "c-alice",
          authorUID: alice,
          authorDisplayName: "Alice",
          body: "mine",
          createdAt: new Date(),
          updatedAt: new Date(),
          deletedAt: null,
        });
      await db
        .collection("projects")
        .doc("adel-p1")
        .collection("tasks")
        .doc("t1")
        .collection("comments")
        .doc("c-bob")
        .set({
          id: "c-bob",
          authorUID: bob,
          authorDisplayName: "Bob",
          body: "bobs",
          createdAt: new Date(),
          updatedAt: new Date(),
          deletedAt: null,
        });
      await db.collection("users").doc(alice).set({
        displayName: "Alice",
        email: "a@example.com",
        todoshiId: sampleId,
        createdAt: new Date(),
        updatedAt: new Date(),
      });
      await db.collection("publicIdentities").doc(alice).set({
        userId: alice,
        todoshiId: sampleId,
        createdAt: new Date(),
      });
      await db.collection("todoshiIds").doc(sampleId).set({
        uid: alice,
        createdAt: new Date(),
      });
      await db.collection("todoshiIds").doc(otherId).set({
        uid: bob,
        createdAt: new Date(),
      });
      await db.collection("publicIdentities").doc(bob).set({
        userId: bob,
        todoshiId: otherId,
        createdAt: new Date(),
      });
    });
  });

  it("AD-1 own comment hard-delete allowed", async () => {
    await assertSucceeds(
      deleteDoc(
        doc(authedDb(alice), "projects", "adel-p1", "tasks", "t1", "comments", "c-alice")
      )
    );
  });

  it("AD-2 foreign comment delete denied for non-owner", async () => {
    await assertFails(
      deleteDoc(
        doc(authedDb(bob), "projects", "adel-p1", "tasks", "t1", "comments", "c-alice")
      )
    );
  });

  it("AD-3 own completion attribution scrub allowed", async () => {
    await assertSucceeds(
      updateDoc(doc(authedDb(alice), "projects", "adel-p1", "tasks", "t1"), {
        completedByUID: null,
        completedByDisplayName: null,
      })
    );
  });

  it("AD-4 foreign completion scrub denied", async () => {
    await assertFails(
      updateDoc(doc(authedDb(bob), "projects", "adel-p1", "tasks", "t1"), {
        completedByUID: null,
        completedByDisplayName: null,
      })
    );
  });

  it("AD-5 scrub cannot change title/status", async () => {
    await assertFails(
      updateDoc(doc(authedDb(alice), "projects", "adel-p1", "tasks", "t1"), {
        completedByUID: null,
        completedByDisplayName: null,
        title: "Hacked",
        status: "todo",
      })
    );
  });

  it("AD-6 own activity attribution scrub allowed", async () => {
    await assertSucceeds(
      updateDoc(doc(authedDb(alice), "projects", "adel-p1", "tasks", "t1"), {
        lastActivityByUID: null,
      })
    );
  });

  it("AD-7 public identity self-delete", async () => {
    await assertSucceeds(deleteDoc(doc(authedDb(alice), "publicIdentities", alice)));
  });

  it("AD-8 foreign identity delete denied", async () => {
    await assertFails(deleteDoc(doc(authedDb(alice), "publicIdentities", bob)));
  });

  it("AD-9 own Todoshi claim delete", async () => {
    await assertSucceeds(deleteDoc(doc(authedDb(alice), "todoshiIds", sampleId)));
  });

  it("AD-10 foreign claim delete denied", async () => {
    await assertFails(deleteDoc(doc(authedDb(alice), "todoshiIds", otherId)));
  });

  it("AD-11 owner can hard-delete task subcollection for project wipe", async () => {
    await assertSucceeds(
      deleteDoc(doc(authedDb(alice), "projects", "adel-p1", "tasks", "t1"))
    );
  });

  it("AD-12 member cannot hard-delete task", async () => {
    await assertFails(
      deleteDoc(doc(authedDb(bob), "projects", "adel-p1", "tasks", "t1"))
    );
  });

  it("AD-13 owner project delete allowed", async () => {
    await assertSucceeds(deleteDoc(doc(authedDb(alice), "projects", "adel-p1")));
  });

  it("AD-14 member project delete denied", async () => {
    await assertFails(deleteDoc(doc(authedDb(bob), "projects", "adel-p1")));
  });

  it("AD-15 user can delete own profile", async () => {
    await assertSucceeds(deleteDoc(doc(authedDb(alice), "users", alice)));
  });

  it("AD-16 user cannot delete other profile", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("users").doc(bob).set({
        displayName: "Bob",
        createdAt: new Date(),
        updatedAt: new Date(),
      });
    });
    await assertFails(deleteDoc(doc(authedDb(alice), "users", bob)));
  });

  it("AD-17 collection-group own comments list allowed", async () => {
    const q = query(
      collectionGroup(authedDb(alice), "comments"),
      where("authorUID", "==", alice)
    );
    await assertSucceeds(getDocs(q));
  });

  it("AD-18 memberIds-only fake access remains denied", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("projects").doc("adel-p1").update({
        memberIds: [alice, bob, "faker"],
      });
    });
    await assertFails(getDoc(doc(authedDb("faker"), "projects", "adel-p1")));
    await assertFails(
      getDoc(doc(authedDb("faker"), "projects", "adel-p1", "tasks", "t1"))
    );
  });

  it("AD-19 other members retain project access after owner profile delete path", async () => {
    await assertSucceeds(getDoc(doc(authedDb(bob), "projects", "adel-p1")));
  });
});

describe("Todoshi account deletion — owned project wipe + invites", () => {
  const owner = "wipe-owner";
  const member = "wipe-member";
  const otherOwner = "other-owner";
  const projectId = "wipe-proj";
  const otherProjectId = "other-proj";

  async function seedOwnedProjectTree() {
    await seedProject(projectId, owner, [owner, member], {
      [owner]: { role: "owner" },
      [member]: { role: "member" },
    });
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const taskRef = db.collection("projects").doc(projectId).collection("tasks").doc("t-wipe");
      await taskRef.set({
        id: "t-wipe",
        title: "Wipe me",
        status: "todo",
        priority: "none",
        position: 1,
        parentTaskId: null,
        deletedAt: null,
        editorUIDs: [],
        updatedAt: new Date(),
      });
      await taskRef.collection("comments").doc("c1").set({
        id: "c1",
        authorUID: owner,
        authorDisplayName: "Owner",
        body: "comment",
        createdAt: new Date(),
        updatedAt: new Date(),
        deletedAt: null,
      });
      await taskRef.collection("checklist").doc("cl1").set({
        id: "cl1",
        title: "item",
        isCompleted: false,
        position: 1,
      });
      await taskRef.collection("resources").doc("r1").set({
        id: "r1",
        kind: "link",
        title: "link",
        url: "https://example.com",
        body: "",
      });
      await db.collection("projects").doc(projectId).collection("labels").doc("l1").set({
        id: "l1",
        name: "Label",
        colorHex: "#5248D9",
      });
    });
  }

  /** Mirrors AccountDeletionService.deleteOwnedProjectTree order. */
  async function wipeOwnedProjectAsOwner(uid, pid) {
    const db = authedDb(uid);
    const projectRef = doc(db, "projects", pid);
    const tasksSnap = await getDocs(collection(db, "projects", pid, "tasks"));
    for (const taskDoc of tasksSnap.docs) {
      for (const sub of ["comments", "checklist", "resources"]) {
        const subSnap = await getDocs(collection(db, "projects", pid, "tasks", taskDoc.id, sub));
        const batch = writeBatch(db);
        for (const d of subSnap.docs) batch.delete(d.ref);
        if (!subSnap.empty) await assertSucceeds(batch.commit());
      }
    }
    {
      const snap = await getDocs(collection(db, "projects", pid, "tasks"));
      const batch = writeBatch(db);
      for (const d of snap.docs) batch.delete(d.ref);
      if (!snap.empty) await assertSucceeds(batch.commit());
    }
    {
      const snap = await getDocs(collection(db, "projects", pid, "labels"));
      const batch = writeBatch(db);
      for (const d of snap.docs) batch.delete(d.ref);
      if (!snap.empty) await assertSucceeds(batch.commit());
    }
    {
      const snap = await getDocs(collection(db, "projects", pid, "members"));
      const batch = writeBatch(db);
      for (const d of snap.docs) batch.delete(d.ref);
      if (!snap.empty) await assertSucceeds(batch.commit());
    }
    await assertSucceeds(deleteDoc(projectRef));
  }

  it("AD-20 owned wipe leaves no orphan comments/checklist/resources", async () => {
    await seedOwnedProjectTree();
    await wipeOwnedProjectAsOwner(owner, projectId);

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const comments = await db.collectionGroup("comments").get();
      const checklist = await db.collectionGroup("checklist").get();
      const resources = await db.collectionGroup("resources").get();
      const orphanComments = comments.docs.filter((d) => d.ref.path.includes(projectId));
      const orphanChecklist = checklist.docs.filter((d) => d.ref.path.includes(projectId));
      const orphanResources = resources.docs.filter((d) => d.ref.path.includes(projectId));
      assert.equal(orphanComments.length, 0);
      assert.equal(orphanChecklist.length, 0);
      assert.equal(orphanResources.length, 0);
      assert.equal((await db.collection("projects").doc(projectId).get()).exists, false);
      assert.equal(
        (await db.collection("projects").doc(projectId).collection("tasks").get()).size,
        0
      );
    });
  });

  it("AD-21 deleting task docs before nested wipe would orphan — order prevents it", async () => {
    await seedOwnedProjectTree();
    // Prove nested docs exist before wipe.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      assert.equal(
        (await db.collection("projects").doc(projectId).collection("tasks").doc("t-wipe").collection("comments").get())
          .size,
        1
      );
    });
    await wipeOwnedProjectAsOwner(owner, projectId);
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      // Path may not exist; collection get returns empty.
      const comments = await db
        .collection("projects")
        .doc(projectId)
        .collection("tasks")
        .doc("t-wipe")
        .collection("comments")
        .get();
      assert.equal(comments.size, 0);
    });
  });

  it("AD-22 owned-project invites are revoked; unrelated invites untouched", async () => {
    await seedProject(projectId, owner, [owner], { [owner]: { role: "owner" } });
    await seedProject(otherProjectId, otherOwner, [otherOwner], {
      [otherOwner]: { role: "owner" },
    });

    const ownedInvite = makeInviteToken("ad22own");
    const unrelatedInvite = makeInviteToken("ad22oth");
    await seedInvite(ownedInvite, inviteCreateData(projectId, owner));
    await seedInvite(unrelatedInvite, inviteCreateData(otherProjectId, otherOwner));

    // Owner lists invites for owned project and revokes.
    const ownedList = await assertSucceeds(
      getDocs(query(collection(authedDb(owner), "projectInvites"), where("projectId", "==", projectId)))
    );
    assert.ok(ownedList.docs.some((d) => d.id === ownedInvite));

    await assertSucceeds(
      updateDoc(doc(authedDb(owner), "projectInvites", ownedInvite), {
        revokedAt: serverTimestamp(),
      })
    );

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const owned = await db.collection("projectInvites").doc(ownedInvite).get();
      const other = await db.collection("projectInvites").doc(unrelatedInvite).get();
      assert.ok(owned.data().revokedAt != null);
      assert.equal(other.data().revokedAt, null);
      assert.equal(other.data().createdBy, otherOwner);
      assert.equal(other.data().projectId, otherProjectId);
    });
  });

  it("AD-23 creator-created invites are listable and revocable during deletion", async () => {
    await seedProject(projectId, owner, [owner], { [owner]: { role: "owner" } });
    const token = makeInviteToken("ad23crt");
    await seedInvite(token, inviteCreateData(projectId, owner));

    const listed = await assertSucceeds(
      getDocs(query(collection(authedDb(owner), "projectInvites"), where("createdBy", "==", owner)))
    );
    assert.ok(listed.docs.some((d) => d.id === token));

    await assertSucceeds(
      updateDoc(doc(authedDb(owner), "projectInvites", token), {
        revokedAt: serverTimestamp(),
      })
    );

    const snap = await adminGet(["projectInvites", token]);
    assert.ok(snap.data().revokedAt != null);
  });

  it("AD-24 non-owner cannot list another project's invites", async () => {
    await seedProject(projectId, owner, [owner, member], {
      [owner]: { role: "owner" },
      [member]: { role: "member" },
    });
    const token = makeInviteToken("ad24mem");
    await seedInvite(token, inviteCreateData(projectId, owner));

    await assertFails(
      getDocs(query(collection(authedDb(member), "projectInvites"), where("projectId", "==", projectId)))
    );
  });
});

// Custom board columns live in /projectBoards so /projects rules and old clients are untouched.
describe("Todoshi Firestore rules — project boards", () => {
  function boardData(uid, overrides = {}) {
    return {
      projectId: "p1",
      columns: [
        { id: "c1", name: "To do", colorHex: "#5248D9", kind: "todo" },
        { id: "c2", name: "Review", colorHex: "#8E5BD9", kind: "doing" },
        { id: "c3", name: "Done", colorHex: "#30A46C", kind: "done" },
      ],
      updatedAt: new Date(),
      updatedBy: uid,
      ...overrides,
    };
  }

  function placementData(uid, overrides = {}) {
    return { taskId: "t1", columnId: "c2", updatedAt: new Date(), updatedBy: uid, ...overrides };
  }

  it("B1 owner can create the board", async () => {
    await assertSucceeds(setDoc(doc(authedDb("frank"), "projectBoards", "p1"), boardData("frank")));
  });

  it("B2 member cannot write the board", async () => {
    await assertFails(setDoc(doc(authedDb("carol"), "projectBoards", "p1"), boardData("carol")));
  });

  it("B3 non-member cannot read the board", async () => {
    await assertSucceeds(setDoc(doc(authedDb("frank"), "projectBoards", "p1"), boardData("frank")));
    await assertFails(getDoc(doc(authedDb("mallory"), "projectBoards", "p1")));
  });

  it("B4 member can read the board", async () => {
    await assertSucceeds(setDoc(doc(authedDb("frank"), "projectBoards", "p1"), boardData("frank")));
    await assertSucceeds(getDoc(doc(authedDb("carol"), "projectBoards", "p1")));
  });

  it("B5 board with fewer than 3 or extra fields is denied", async () => {
    const db = authedDb("frank");
    await assertFails(setDoc(doc(db, "projectBoards", "p1"), boardData("frank", { columns: [] })));
    await assertFails(setDoc(doc(db, "projectBoards", "p1"), boardData("frank", { ownerId: "frank" })));
  });

  it("B6 full member can place an existing task", async () => {
    await assertSucceeds(
      setDoc(doc(authedDb("carol"), "projectBoards", "p1", "placements", "t1"), placementData("carol"))
    );
  });

  it("B7 placement for a missing task is denied", async () => {
    await assertFails(
      setDoc(
        doc(authedDb("frank"), "projectBoards", "p1", "placements", "nope"),
        placementData("frank", { taskId: "nope" })
      )
    );
  });

  it("B8 non-member cannot place tasks", async () => {
    await assertFails(
      setDoc(doc(authedDb("mallory"), "projectBoards", "p1", "placements", "t1"), placementData("mallory"))
    );
  });

  it("B9 board writes do not change the project document", async () => {
    await assertSucceeds(setDoc(doc(authedDb("frank"), "projectBoards", "p1"), boardData("frank")));
    const project = await adminGet(["projects", "p1"]);
    assert.equal(project.data().columns, undefined);
  });
});
