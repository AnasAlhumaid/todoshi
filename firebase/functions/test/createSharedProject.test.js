/**
 * Unit tests for createSharedProject validation + handler contract.
 * Emulator-backed Admin SDK integration tests can be added when Blaze/Functions
 * emulators are available in CI.
 *
 * Run: cd firebase/functions && npm install && npm test
 */
const { describe, it } = require("node:test");
const assert = require("node:assert/strict");

// Compiled JS after `npm run build`
const {
  createSharedProjectHandler,
} = require("../lib/collaboration/createSharedProject");

const VALID_UUID = "6A1D2B3C-4D5E-6F70-8192-A3B4C5D6E7F8";

describe("createSharedProject validation (unauthenticated)", () => {
  it("1 rejects unauthenticated calls", async () => {
    await assert.rejects(
      () =>
        createSharedProjectHandler(
          { projectId: VALID_UUID, title: "Demo" },
          undefined
        ),
      (err) => err?.code === "unauthenticated"
    );
  });
});

describe("createSharedProject validation (input)", () => {
  it("6 rejects invalid project UUID", async () => {
    await assert.rejects(
      () =>
        createSharedProjectHandler(
          { projectId: "not-a-uuid", title: "Demo" },
          "owner-1"
        ),
      (err) => err?.code === "invalid-argument"
    );
  });

  it("7 rejects blank title", async () => {
    await assert.rejects(
      () =>
        createSharedProjectHandler(
          { projectId: VALID_UUID, title: "   " },
          "owner-1"
        ),
      (err) => err?.code === "invalid-argument"
    );
  });
});

// Note: Firestore-backed cases (2–5, 8–10) require Admin emulator + Blaze-capable
// Functions environment. They are documented in PHASE2_SHARED_PROJECT.md and
// exercised manually once createSharedProject is deployed.
