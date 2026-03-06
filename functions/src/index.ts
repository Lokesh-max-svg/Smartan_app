import {onCall} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {getFunctions} from "firebase-admin/functions";
import * as admin from "firebase-admin";

admin.initializeApp();

/**
 * Helper function to normalize exercise name for folder matching
 * e.g., "Bicep Curls" -> "bicep_curls"
 * @param {string} name - The exercise name to normalize
 * @return {string} The normalized exercise name
 */
function normalizeExerciseName(name: string): string {
  return name.toLowerCase().replace(/\s+/g, "_");
}

/**
 * Helper function to parse GCS folder name
 * Format: {exercise_name}_cam_{camera}_{batch}_{timestamp}
 * @param {string} folderName - The folder name to parse
 * @return {object|null} Parsed folder info or null if invalid
 */
function parseGcsFolderName(folderName: string): {
  exerciseName: string;
  camera: number;
  batch: number;
  timestamp: number;
} | null {
  // Match pattern: anything_cam_X_X_timestamp
  const match = folderName.match(/^(.+)_cam_(\d+)_(\d+)_(\d+)$/);
  if (!match) return null;

  return {
    exerciseName: match[1],
    camera: parseInt(match[2], 10),
    batch: parseInt(match[3], 10),
    timestamp: parseInt(match[4], 10),
  };
}

// Interface for GCS folder info
interface GcsFolderInfo {
  path: string;
  camera: number;
  batch: number;
  timestamp: number;
  frames: number;
}

/**
 * Firestore trigger: when a new current_workout entry is created,
 * update the corresponding session with current_reps, completion
 * status, and GCS folder data. Also auto-closes sessions > 3 hours.
 *
 * Replaces the old updateExerciseCompletion scheduled function.
 * Only runs when actual workout data is written — zero cost when idle.
 */
export const onWorkoutCreated = onDocumentCreated(
  "current_workout/{docId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const sessionId = data.session_id;
    if (!sessionId) return;

    const db = admin.firestore();

    // Find the active session with this sessionId
    const sessionSnapshot = await db.collection("sessions")
      .where("sessionId", "==", sessionId)
      .where("status", "in", ["Active", "active"])
      .limit(1)
      .get();

    if (sessionSnapshot.empty) return;

    const sessionDoc = sessionSnapshot.docs[0];
    const sessionData = sessionDoc.data();
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const exercises = sessionData.exercises as Array<any> || [];

    if (exercises.length === 0) return;

    // Check if session should be auto-closed (3+ hours old)
    const createdAt = sessionData.createdAt?.toDate();
    if (createdAt) {
      const threeHoursAgo = new Date(Date.now() - 3 * 60 * 60 * 1000);
      if (createdAt <= threeHoursAgo) {
        await sessionDoc.ref.update({
          status: "Closed",
          endedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`Auto-closed session ${sessionDoc.id} (3+ hours old)`);
        return;
      }
    }

    // Get ALL current_workout entries for this session (single query)
    const workoutSnapshot = await db.collection("current_workout")
      .where("session_id", "==", sessionId)
      .get();

    // Sum reps and collect GCS folders in a single pass
    const repsByExercise = new Map<string, number>();
    const gcsFoldersByExercise = new Map<string, GcsFolderInfo[]>();

    workoutSnapshot.docs.forEach((doc) => {
      const d = doc.data();
      const exerciseName = d.exercise_name || "";
      const reps = d.reps || 0;

      // Sum reps
      repsByExercise.set(
        exerciseName,
        (repsByExercise.get(exerciseName) || 0) + reps
      );

      // Collect GCS folders
      const smplBinFiles = d.smpl_bin_files || {};
      const gcsFolder = smplBinFiles.gcs_folder || "";
      const fileCount = smplBinFiles.file_count || 0;

      if (exerciseName && gcsFolder) {
        const folderName = gcsFolder.split("/").pop() || "";
        const parsed = parseGcsFolderName(folderName);

        if (parsed) {
          const folderInfo: GcsFolderInfo = {
            path: gcsFolder,
            camera: parsed.camera,
            batch: parsed.batch,
            timestamp: parsed.timestamp,
            frames: fileCount || 192,
          };

          const existing = gcsFoldersByExercise.get(exerciseName) || [];
          existing.push(folderInfo);
          gcsFoldersByExercise.set(exerciseName, existing);
        }
      }
    });

    // Sort GCS folders by batch then timestamp
    gcsFoldersByExercise.forEach((folders, name) => {
      folders.sort((a, b) =>
        a.batch !== b.batch ? a.batch - b.batch : a.timestamp - b.timestamp
      );
      gcsFoldersByExercise.set(name, folders);
    });

    // Update exercises with current reps, completion, and GCS folders
    let hasUpdates = false;
    const updatedExercises = exercises.map((exercise) => {
      const exerciseName = exercise.name || "";
      const normalizedName = normalizeExerciseName(exerciseName);
      const currentReps = repsByExercise.get(exerciseName) ||
        repsByExercise.get(normalizedName) || 0;
      const prevCurrentReps = exercise.current_reps || 0;
      const targetReps = exercise.reps || 0;
      const isCompleted = exercise.completed || false;

      // GCS folder matching (try raw name then normalized)
      const folders = gcsFoldersByExercise.get(exerciseName) ||
        gcsFoldersByExercise.get(normalizedName) || [];
      const existingFolders = exercise.gcs_folders || [];

      const newFolderPaths = new Set(folders.map((f) => f.path));
      const existingPaths = new Set(
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        existingFolders.map((f: any) => f.path)
      );
      const hasNewFolders = folders.length > 0 && (
        folders.length !== existingFolders.length ||
        [...newFolderPaths].some((p) => !existingPaths.has(p))
      );

      const shouldComplete = !isCompleted &&
        currentReps >= targetReps &&
        targetReps > 0;
      const repsChanged = currentReps !== prevCurrentReps;

      if (shouldComplete || hasNewFolders || repsChanged) {
        hasUpdates = true;
        return {
          ...exercise,
          current_reps: currentReps,
          completed: shouldComplete ? true : isCompleted,
          gcs_folders: folders.length > 0 ? folders : existingFolders,
        };
      }

      return exercise;
    });

    if (hasUpdates) {
      await sessionDoc.ref.update({exercises: updatedExercises});
      console.log(`Updated session ${sessionDoc.id} via workout trigger`);
    }
  }
);

/**
 * Task queue function: auto-closes a session if still Active.
 * Dispatched by onSessionCreated with a 3-hour delay.
 */
export const autoCloseSession = onTaskDispatched({
  retryConfig: {
    maxAttempts: 3,
    minBackoffSeconds: 30,
  },
  rateLimits: {
    maxConcurrentDispatches: 10,
  },
}, async (req) => {
  const {sessionDocId} = req.data as {sessionDocId: string};
  if (!sessionDocId) return;

  const db = admin.firestore();
  const sessionRef = db.collection("sessions").doc(sessionDocId);
  const sessionDoc = await sessionRef.get();

  if (!sessionDoc.exists) return;

  const data = sessionDoc.data();
  if (data?.status !== "Active") {
    console.log(`Session ${sessionDocId} already ${data?.status}, skipping`);
    return;
  }

  await sessionRef.update({
    status: "Closed",
    endedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(`Auto-closed session ${sessionDocId} via scheduled task`);
});

/**
 * Firestore trigger: when a new session is created, enqueue a task
 * to auto-close it 3 hours later.
 */
export const onSessionCreated = onDocumentCreated(
  "sessions/{docId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    // Only schedule auto-close for Active sessions
    if (data.status !== "Active") return;

    const projectId = process.env.GCLOUD_PROJECT ||
      process.env.GCP_PROJECT || "";
    const location = "us-central1";
    const queue = getFunctions().taskQueue(
      `locations/${location}/functions/autoCloseSession`
    );

    await queue.enqueue(
      {sessionDocId: event.params.docId},
      {
        scheduleDelaySeconds: 3 * 60 * 60, // 3 hours
        uri: `https://${location}-${projectId}.cloudfunctions.net/autoCloseSession`,
      }
    );

    console.log(
      `Scheduled auto-close for session ${event.params.docId} in 3 hours`
    );
  }
);

/**
 * Callable function to resolve user display names from Firebase Auth.
 * Accepts a list of userIds, returns a map of
 * userId -> {name, email, photoUrl}.
 * Also syncs resolved names back to Firestore users collection.
 */
export const getUserNames = onCall({
  timeoutSeconds: 30,
}, async (request) => {
  const userIds = request.data.userIds as string[] | undefined;
  if (!userIds || !Array.isArray(userIds) || userIds.length === 0) {
    return {users: {}};
  }

  // Limit to 50 users per call
  const ids = userIds.slice(0, 50);
  const auth = admin.auth();
  const db = admin.firestore();
  const results: Record<string, {
    name: string; email: string; photoUrl: string
  }> = {};

  for (const uid of ids) {
    try {
      const authUser = await auth.getUser(uid);
      const name = authUser.displayName ||
        (authUser.email ? authUser.email.split("@")[0] : "");
      const email = authUser.email || "";
      const photoUrl = authUser.photoURL || "";

      if (name) {
        results[uid] = {name, email, photoUrl};

        // Sync back to Firestore so future lookups don't need this call
        await db.collection("users").doc(uid).set({
          displayName: name,
          email: email || undefined,
          photoURL: photoUrl || undefined,
          lastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }
    } catch (e) {
      console.log(`Could not resolve user ${uid}: ${e}`);
    }
  }

  return {users: results};
});
