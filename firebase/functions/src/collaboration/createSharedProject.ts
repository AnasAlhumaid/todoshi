import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const auth = getAuth();

const TITLE_MAX = 100;
const DESCRIPTION_MAX = 2000;

const ALLOWED_COLORS = new Set([
  "#5B8DEF",
  "#7C5CFC",
  "#E85D75",
  "#F08C3A",
  "#E5B53A",
  "#3DBB7A",
  "#2BB8C2",
  "#8E8E93",
]);

const UUID_RE =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export type CreateSharedProjectRequest = {
  projectId?: unknown;
  title?: unknown;
  description?: unknown;
  color?: unknown;
  projectType?: unknown;
};

export type CreateSharedProjectResponse = {
  projectId: string;
  ownerId: string;
  created: boolean;
  repaired: boolean;
};

function trimString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function validateInput(data: CreateSharedProjectRequest): {
  projectId: string;
  title: string;
  description: string;
  color: string;
  projectType: "tasks" | "checklist";
} {
  const projectId = trimString(data.projectId);
  if (!UUID_RE.test(projectId)) {
    throw new HttpsError("invalid-argument", "Invalid projectId.");
  }

  const title = trimString(data.title);
  if (!title) {
    throw new HttpsError("invalid-argument", "Title is required.");
  }
  if (title.length > TITLE_MAX) {
    throw new HttpsError("invalid-argument", "Title is too long.");
  }

  const description = trimString(data.description ?? "");
  if (description.length > DESCRIPTION_MAX) {
    throw new HttpsError("invalid-argument", "Description is too long.");
  }

  let color = "#5B8DEF";
  if (data.color !== undefined && data.color !== null && data.color !== "") {
    const candidate = trimString(data.color).toUpperCase();
    const matched = [...ALLOWED_COLORS].find((c) => c.toUpperCase() === candidate);
    if (!matched) {
      throw new HttpsError("invalid-argument", "Invalid color.");
    }
    color = matched;
  }

  const typeRaw = trimString(data.projectType ?? "tasks");
  if (typeRaw !== "tasks" && typeRaw !== "checklist") {
    throw new HttpsError("invalid-argument", "Invalid projectType.");
  }

  return { projectId, title, description, color, projectType: typeRaw };
}

async function resolveDisplayName(uid: string): Promise<string | null> {
  const profileSnap = await db.collection("users").doc(uid).get();
  if (profileSnap.exists) {
    const name = trimString(profileSnap.data()?.displayName);
    if (name) return name;
  }

  try {
    const user = await auth.getUser(uid);
    const authName = trimString(user.displayName);
    if (authName) return authName;
  } catch {
    // Auth profile optional.
  }

  return null;
}

/**
 * Trusted shared-project bootstrap.
 * Owner UID is always derived from request.auth.uid — never from client payload.
 */
export async function createSharedProjectHandler(
  data: CreateSharedProjectRequest,
  authUid: string | undefined
): Promise<CreateSharedProjectResponse> {
  if (!authUid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  const { projectId, title, description, color, projectType } = validateInput(data);
  const ownerId = authUid;
  const displayName = await resolveDisplayName(ownerId);
  const projectRef = db.collection("projects").doc(projectId);
  const memberRef = projectRef.collection("members").doc(ownerId);

  return db.runTransaction(async (tx) => {
    const existing = await tx.get(projectRef);

    if (existing.exists) {
      const owner = existing.data()?.ownerId;
      if (owner !== ownerId) {
        throw new HttpsError(
          "permission-denied",
          "Project already owned by another user."
        );
      }

      const memberSnap = await tx.get(memberRef);
      let repaired = false;
      if (!memberSnap.exists) {
        tx.set(memberRef, {
          userId: ownerId,
          role: "owner",
          displayName: displayName,
          joinedAt: FieldValue.serverTimestamp(),
          accessLevel: "full",
        });
        repaired = true;
      } else {
        const memberData = memberSnap.data() ?? {};
        if (memberData.role !== "owner" || memberData.userId !== ownerId) {
          tx.set(
            memberRef,
            {
              userId: ownerId,
              role: "owner",
              displayName: displayName ?? memberData.displayName ?? null,
              joinedAt: memberData.joinedAt ?? FieldValue.serverTimestamp(),
              accessLevel: "full",
            },
            { merge: true }
          );
          repaired = true;
        }
      }

      const memberIds: string[] = Array.isArray(existing.data()?.memberIds)
        ? existing.data()!.memberIds
        : [];
      if (!memberIds.includes(ownerId)) {
        tx.update(projectRef, {
          memberIds: FieldValue.arrayUnion(ownerId),
          updatedAt: FieldValue.serverTimestamp(),
        });
        repaired = true;
      }

      return { projectId, ownerId, created: false, repaired };
    }

    tx.set(projectRef, {
      id: projectId,
      ownerId,
      title,
      description,
      color,
      memberIds: [ownerId],
      projectType,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      deletedAt: null,
    });

    tx.set(memberRef, {
      userId: ownerId,
      role: "owner",
      displayName: displayName,
      joinedAt: FieldValue.serverTimestamp(),
      accessLevel: "full",
    });

    return { projectId, ownerId, created: true, repaired: false };
  });
}

export const createSharedProject = onCall(
  { region: "us-central1" },
  async (request) => {
    return createSharedProjectHandler(
      (request.data ?? {}) as CreateSharedProjectRequest,
      request.auth?.uid
    );
  }
);
