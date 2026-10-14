import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, type Firestore } from "firebase-admin/firestore";
import { getAuth, type Auth } from "firebase-admin/auth";
import type {
  CollectionReference,
  Query,
  QueryDocumentSnapshot,
} from "firebase-admin/firestore";

if (getApps().length === 0) {
  initializeApp();
}

const BATCH_LIMIT = 400;
const MAX_PAGES = 10_000;

export type DeleteMyAccountResponse = {
  success: true;
  authUserDeleted: boolean;
};

export type DeleteMyAccountDeps = {
  db: Firestore;
  auth: Pick<Auth, "deleteUser" | "getUser">;
  log?: (message: string) => void;
};

function abbreviateUid(uid: string): string {
  return uid.length <= 8 ? uid : `${uid.slice(0, 8)}`;
}

function defaultLog(message: string): void {
  console.log(message);
}

/** Pure: classify memberIds projects into owned vs member-only. */
export function classifyProjectsForDeletion(
  uid: string,
  projects: Array<{ id: string; ownerId: string; memberIds: string[] }>
): { owned: string[]; member: string[] } {
  const owned: string[] = [];
  const member: string[] = [];
  const seenOwned = new Set<string>();
  const seenMember = new Set<string>();
  for (const project of projects) {
    const isMember =
      project.memberIds.includes(uid) || project.ownerId === uid;
    if (!isMember) continue;
    if (project.ownerId === uid) {
      if (!seenOwned.has(project.id)) {
        seenOwned.add(project.id);
        owned.push(project.id);
      }
    } else if (!seenMember.has(project.id)) {
      seenMember.add(project.id);
      member.push(project.id);
    }
  }
  owned.sort();
  member.sort();
  return { owned, member };
}

/** Pure: invite revocation selection (creator or owned-project invites). */
export function shouldRevokeInvite(args: {
  createdBy: string;
  projectId: string;
  acceptedBy: string | null | undefined;
  revokedAt: unknown;
  deletingUID: string;
  ownedProjectIDs: Set<string>;
}): boolean {
  if (args.acceptedBy != null || args.revokedAt != null) return false;
  if (args.createdBy === args.deletingUID) return true;
  if (args.ownedProjectIDs.has(args.projectId)) return true;
  return false;
}

/** Pure: nested wipe order for owned projects. */
export const OWNED_PROJECT_DELETE_STEPS = [
  "taskComments",
  "taskChecklist",
  "taskResources",
  "taskDocuments",
  "labels",
  "members",
  "projectDocument",
] as const;

export function assertsNoOrphansAfterOwnedWipe(args: {
  remainingComments: number;
  remainingChecklist: number;
  remainingResources: number;
  remainingTasks: number;
  remainingLabels: number;
  remainingMembers: number;
  projectExists: boolean;
}): boolean {
  return (
    args.remainingComments === 0 &&
    args.remainingChecklist === 0 &&
    args.remainingResources === 0 &&
    args.remainingTasks === 0 &&
    args.remainingLabels === 0 &&
    args.remainingMembers === 0 &&
    args.projectExists === false
  );
}

async function deleteQueryInBatches(
  db: Firestore,
  docs: QueryDocumentSnapshot[]
): Promise<void> {
  for (let i = 0; i < docs.length; i += BATCH_LIMIT) {
    const chunk = docs.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
}

async function deleteCollection(
  db: Firestore,
  collectionRef: CollectionReference
): Promise<void> {
  let page = 0;
  while (page < MAX_PAGES) {
    const snap = await collectionRef.limit(BATCH_LIMIT).get();
    if (snap.empty) return;
    await deleteQueryInBatches(db, snap.docs);
    page += 1;
    if (snap.size < BATCH_LIMIT) return;
  }
}

async function listAllDocs(
  collectionRef: CollectionReference
): Promise<QueryDocumentSnapshot[]> {
  const results: QueryDocumentSnapshot[] = [];
  let last: QueryDocumentSnapshot | undefined;
  let page = 0;
  while (page < MAX_PAGES) {
    let query: Query = collectionRef
      .orderBy("__name__")
      .limit(BATCH_LIMIT);
    if (last) {
      query = query.startAfter(last);
    }
    const snap = await query.get();
    if (snap.empty) break;
    results.push(...snap.docs);
    last = snap.docs[snap.docs.length - 1];
    page += 1;
    if (snap.size < BATCH_LIMIT) break;
  }
  return results;
}

async function deleteOwnedProjectTree(
  db: Firestore,
  projectID: string
): Promise<void> {
  const projectRef = db.collection("projects").doc(projectID);
  const tasks = await listAllDocs(projectRef.collection("tasks"));
  for (const task of tasks) {
    await deleteCollection(db, task.ref.collection("comments"));
    await deleteCollection(db, task.ref.collection("checklist"));
    await deleteCollection(db, task.ref.collection("resources"));
  }
  await deleteCollection(db, projectRef.collection("tasks"));
  await deleteCollection(db, projectRef.collection("labels"));
  await deleteCollection(db, projectRef.collection("members"));
  await projectRef.delete();
}

async function leaveMemberProject(
  db: Firestore,
  projectID: string,
  uid: string
): Promise<void> {
  const projectRef = db.collection("projects").doc(projectID);
  const memberRef = projectRef.collection("members").doc(uid);
  const batch = db.batch();
  batch.delete(memberRef);
  batch.update(projectRef, {
    memberIds: FieldValue.arrayRemove(uid),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
}

async function revokeInvites(
  db: Firestore,
  uid: string,
  ownedProjectIDs: Set<string>
): Promise<void> {
  const byID = new Map<string, QueryDocumentSnapshot>();
  const createdSnap = await db
    .collection("projectInvites")
    .where("createdBy", "==", uid)
    .get();
  for (const doc of createdSnap.docs) {
    byID.set(doc.id, doc);
  }
  for (const projectID of [...ownedProjectIDs].sort()) {
    const projectSnap = await db
      .collection("projectInvites")
      .where("projectId", "==", projectID)
      .get();
    for (const doc of projectSnap.docs) {
      byID.set(doc.id, doc);
    }
  }

  const toRevoke: QueryDocumentSnapshot[] = [];
  for (const doc of byID.values()) {
    const data = doc.data();
    if (
      shouldRevokeInvite({
        createdBy: String(data.createdBy ?? ""),
        projectId: String(data.projectId ?? ""),
        acceptedBy: data.acceptedBy ?? null,
        revokedAt: data.revokedAt ?? null,
        deletingUID: uid,
        ownedProjectIDs,
      })
    ) {
      toRevoke.push(doc);
    }
  }

  for (let i = 0; i < toRevoke.length; i += BATCH_LIMIT) {
    const chunk = toRevoke.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, { revokedAt: FieldValue.serverTimestamp() });
    }
    await batch.commit();
  }
}

async function scrubAttribution(
  db: Firestore,
  uid: string
): Promise<void> {
  const commentSnap = await db
    .collectionGroup("comments")
    .where("authorUID", "==", uid)
    .get();
  await deleteQueryInBatches(db, commentSnap.docs);

  const completionSnap = await db
    .collectionGroup("tasks")
    .where("completedByUID", "==", uid)
    .get();
  for (let i = 0; i < completionSnap.docs.length; i += BATCH_LIMIT) {
    const chunk = completionSnap.docs.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, {
        completedByUID: FieldValue.delete(),
        completedByDisplayName: FieldValue.delete(),
      });
    }
    await batch.commit();
  }

  const activitySnap = await db
    .collectionGroup("tasks")
    .where("lastActivityByUID", "==", uid)
    .get();
  for (let i = 0; i < activitySnap.docs.length; i += BATCH_LIMIT) {
    const chunk = activitySnap.docs.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, {
        lastActivityByUID: FieldValue.delete(),
      });
    }
    await batch.commit();
  }
}

async function deleteIdentity(db: Firestore, uid: string): Promise<void> {
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const todoshiId =
    typeof userSnap.data()?.todoshiId === "string"
      ? String(userSnap.data()?.todoshiId).trim()
      : "";
  if (todoshiId) {
    try {
      await db.collection("todoshiIds").doc(todoshiId).delete();
    } catch {
      // Idempotent — claim may already be gone.
    }
  }
  try {
    await db.collection("publicIdentities").doc(uid).delete();
  } catch {
    // Idempotent.
  }
  try {
    await userRef.delete();
  } catch {
    // Idempotent.
  }
}

/**
 * Trusted account deletion.
 * UID is ALWAYS from verified Firebase Auth context — never from client payload.
 */
export async function deleteMyAccountHandler(
  authUid: string | undefined,
  deps: DeleteMyAccountDeps,
  // Intentionally unused — reject trusting client-supplied identity.
  _clientData?: Record<string, unknown>
): Promise<DeleteMyAccountResponse> {
  const log = deps.log ?? defaultLog;

  if (!authUid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  // Security: ignore any client-supplied uid field.
  if (_clientData && typeof _clientData.uid === "string" && _clientData.uid !== authUid) {
    throw new HttpsError(
      "permission-denied",
      "Cannot delete another user's account."
    );
  }

  const uid = authUid;
  log(`[AccountDeletionServer] START uid=${abbreviateUid(uid)}`);

  const projectSnap = await deps.db
    .collection("projects")
    .where("memberIds", "array-contains", uid)
    .get();

  const projects = projectSnap.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      ownerId: String(data.ownerId ?? ""),
      memberIds: Array.isArray(data.memberIds)
        ? data.memberIds.map(String)
        : [],
    };
  });

  const { owned, member } = classifyProjectsForDeletion(uid, projects);
  const ownedSet = new Set(owned);

  await scrubAttribution(deps.db, uid);

  for (const projectID of member) {
    try {
      await leaveMemberProject(deps.db, projectID, uid);
    } catch {
      // Retry-safe: membership may already be gone.
    }
  }

  await revokeInvites(deps.db, uid, ownedSet);

  for (const projectID of owned) {
    await deleteOwnedProjectTree(deps.db, projectID);
  }

  await deleteIdentity(deps.db, uid);
  log("[AccountDeletionServer] cloud cleanup complete");

  let authUserDeleted = false;
  try {
    await deps.auth.deleteUser(uid);
    authUserDeleted = true;
  } catch (error: unknown) {
    const code =
      typeof error === "object" && error && "code" in error
        ? String((error as { code: unknown }).code)
        : "";
    // Idempotent retry: user already absent is success.
    if (code === "auth/user-not-found") {
      authUserDeleted = true;
    } else {
      throw new HttpsError("internal", "Firebase Auth user deletion failed.");
    }
  }

  log("[AccountDeletionServer] Firebase Auth delete complete");
  log("[AccountDeletionServer] SUCCESS");

  return { success: true, authUserDeleted };
}

export const deleteMyAccount = onCall(
  { region: "us-central1" },
  async (request) => {
    return deleteMyAccountHandler(
      request.auth?.uid,
      {
        db: getFirestore(),
        auth: getAuth(),
      },
      (request.data ?? {}) as Record<string, unknown>
    );
  }
);
