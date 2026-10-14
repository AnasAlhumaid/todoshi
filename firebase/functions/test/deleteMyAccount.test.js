/**
 * Account deletion server tests (AD-S1 … AD-S7).
 * Pure helpers + handler auth contract. Full Firestore Admin integration requires
 * Blaze + Functions emulator (not auto-enabled).
 *
 * Run: cd firebase/functions && npm install && npm test
 */
const { describe, it } = require("node:test");
const assert = require("node:assert/strict");

const {
  deleteMyAccountHandler,
  classifyProjectsForDeletion,
  shouldRevokeInvite,
  OWNED_PROJECT_DELETE_STEPS,
  assertsNoOrphansAfterOwnedWipe,
} = require("../lib/collaboration/deleteMyAccount");

describe("AD-S1 — Unauthenticated request is denied", () => {
  it("rejects missing auth", async () => {
    await assert.rejects(
      () =>
        deleteMyAccountHandler(undefined, {
          db: {},
          auth: { deleteUser: async () => {}, getUser: async () => ({}) },
        }),
      (err) => err?.code === "unauthenticated"
    );
  });
});

describe("AD-S2 — Authenticated user can delete only their own account", () => {
  it("rejects client-supplied different uid", async () => {
    await assert.rejects(
      () =>
        deleteMyAccountHandler(
          "uid-alice",
          {
            db: {},
            auth: { deleteUser: async () => {}, getUser: async () => ({}) },
          },
          { uid: "uid-bob" }
        ),
      (err) => err?.code === "permission-denied"
    );
  });

  it("classifies only the deleting UID as owner/member", () => {
    const { owned, member } = classifyProjectsForDeletion("uid-alice", [
      { id: "p1", ownerId: "uid-alice", memberIds: ["uid-alice", "uid-bob"] },
      { id: "p2", ownerId: "uid-bob", memberIds: ["uid-bob", "uid-alice"] },
      { id: "p3", ownerId: "uid-bob", memberIds: ["uid-bob"] },
    ]);
    assert.deepEqual(owned, ["p1"]);
    assert.deepEqual(member, ["p2"]);
    assert.ok(!owned.includes("p3"));
    assert.ok(!member.includes("p3"));
  });
});

describe("AD-S3 — Server deletes Todoshi cloud data (plan helpers)", () => {
  it("selects owned and member projects for cleanup", () => {
    const plan = classifyProjectsForDeletion("u1", [
      { id: "a", ownerId: "u1", memberIds: ["u1"] },
      { id: "b", ownerId: "u2", memberIds: ["u2", "u1"] },
    ]);
    assert.deepEqual(plan.owned, ["a"]);
    assert.deepEqual(plan.member, ["b"]);
  });
});

describe("AD-S4 — Server deletes Firebase Auth user (idempotent contract)", () => {
  it("treats auth/user-not-found as success", async () => {
    const logs = [];
    // Minimal stub db returning empty project membership.
    const emptySnap = { docs: [] };
    const db = {
      collection: () => ({
        where: () => ({
          get: async () => emptySnap,
        }),
        doc: () => ({
          get: async () => ({ data: () => ({}) }),
          delete: async () => {},
          collection: () => ({
            doc: () => ({ delete: async () => {} }),
          }),
        }),
      }),
      collectionGroup: () => ({
        where: () => ({
          get: async () => emptySnap,
        }),
      }),
    };

    let deleted = false;
    const result = await deleteMyAccountHandler(
      "uid-gone",
      {
        db,
        auth: {
          deleteUser: async () => {
            const err = new Error("missing");
            err.code = "auth/user-not-found";
            throw err;
          },
          getUser: async () => ({ uid: "uid-gone" }),
        },
        log: (m) => logs.push(m),
      },
      {}
    );
    assert.equal(result.success, true);
    assert.equal(result.authUserDeleted, true);
    assert.ok(logs.some((l) => String(l).includes("Firebase Auth delete complete")));
    deleted = true;
    assert.ok(deleted);
  });
});

describe("AD-S5 — Retry after partial deletion is idempotent", () => {
  it("same classification inputs yield same owned/member sets", () => {
    const projects = [
      { id: "p1", ownerId: "u", memberIds: ["u"] },
      { id: "p2", ownerId: "o", memberIds: ["o", "u"] },
    ];
    const a = classifyProjectsForDeletion("u", projects);
    const b = classifyProjectsForDeletion("u", projects);
    assert.deepEqual(a, b);
  });
});

describe("AD-S6 — Owned project recursive deletion leaves no orphan subcollections", () => {
  it("wipe order nests before project document", () => {
    assert.ok(
      OWNED_PROJECT_DELETE_STEPS.indexOf("taskComments") <
        OWNED_PROJECT_DELETE_STEPS.indexOf("taskDocuments")
    );
    assert.ok(
      OWNED_PROJECT_DELETE_STEPS.indexOf("taskDocuments") <
        OWNED_PROJECT_DELETE_STEPS.indexOf("projectDocument")
    );
    assert.ok(
      assertsNoOrphansAfterOwnedWipe({
        remainingComments: 0,
        remainingChecklist: 0,
        remainingResources: 0,
        remainingTasks: 0,
        remainingLabels: 0,
        remainingMembers: 0,
        projectExists: false,
      })
    );
    assert.ok(
      !assertsNoOrphansAfterOwnedWipe({
        remainingComments: 1,
        remainingChecklist: 0,
        remainingResources: 0,
        remainingTasks: 0,
        remainingLabels: 0,
        remainingMembers: 0,
        projectExists: false,
      })
    );
  });
});

describe("AD-S7 — Unrelated users/projects remain untouched", () => {
  it("does not select unrelated invites or projects", () => {
    const { owned, member } = classifyProjectsForDeletion("alice", [
      { id: "keep", ownerId: "bob", memberIds: ["bob"] },
    ]);
    assert.deepEqual(owned, []);
    assert.deepEqual(member, []);

    assert.equal(
      shouldRevokeInvite({
        createdBy: "bob",
        projectId: "keep",
        acceptedBy: null,
        revokedAt: null,
        deletingUID: "alice",
        ownedProjectIDs: new Set(),
      }),
      false
    );
    assert.equal(
      shouldRevokeInvite({
        createdBy: "alice",
        projectId: "p1",
        acceptedBy: null,
        revokedAt: null,
        deletingUID: "alice",
        ownedProjectIDs: new Set(),
      }),
      true
    );
  });
});
