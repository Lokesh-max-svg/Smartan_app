import {onSchedule} from "firebase-functions/v2/scheduler";
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
 * Function to get GCS folders for a session from current_workout collection
 * @param {string} sessionId - The session ID
 * @return {Promise<Map>} Map of exercise name to GcsFolderInfo array
 */
async function getGcsFoldersForSession(
  sessionId: string
): Promise<Map<string, GcsFolderInfo[]>> {
  const db = admin.firestore();

  try {
    // Query current_workout collection for this session's data
    const snapshot = await db.collection("current_workout")
      .where("session_id", "==", sessionId)
      .get();

    console.log(
      `  Found ${snapshot.size} current_workout docs for session ${sessionId}`
    );

    // Group folders by exercise name
    const exerciseFolders = new Map<string, GcsFolderInfo[]>();

    snapshot.docs.forEach((doc) => {
      const data = doc.data();
      const exerciseName = data.exercise_name || "";
      const smplBinFiles = data.smpl_bin_files || {};
      const gcsFolder = smplBinFiles.gcs_folder || "";
      const fileCount = smplBinFiles.file_count || 0;

      if (exerciseName && gcsFolder) {
        // Parse folder name to extract camera, batch, timestamp
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

          const existing = exerciseFolders.get(exerciseName) || [];
          existing.push(folderInfo);
          exerciseFolders.set(exerciseName, existing);

          console.log(
            `    Found folder for ${exerciseName}: batch ${parsed.batch}`
          );
        }
      }
    });

    // Sort each exercise's folders by batch number first, then timestamp
    exerciseFolders.forEach((folders, exerciseName) => {
      folders.sort((a, b) => {
        // Primary sort by batch number
        if (a.batch !== b.batch) {
          return a.batch - b.batch;
        }
        // Secondary sort by timestamp
        return a.timestamp - b.timestamp;
      });
      exerciseFolders.set(exerciseName, folders);
    });

    return exerciseFolders;
  } catch (error) {
    console.error(`Error getting GCS folders for session ${sessionId}:`, error);
    return new Map();
  }
}

// Runs every 10 minutes - auto-closes Active sessions after 3 hours
export const updateCompletedStatus = onSchedule({
  schedule: "*/10 * * * *", // Cron syntax: every 10 minutes
  timeZone: "America/New_York", // Set your timezone
}, async () => {
  const db = admin.firestore();
  const threeHoursAgo = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - 3 * 60 * 60 * 1000)
  );

  try {
    // Query sessions where createdAt < 3 hours ago
    // Note: Filtering status in code to avoid composite index requirement
    const snapshot = await db.collection("sessions")
      .where("createdAt", "<=", threeHoursAgo)
      .get();

    if (snapshot.empty) {
      console.log("No documents to update");
      return;
    }

    // Filter in code and batch update
    const batch = db.batch();
    let updateCount = 0;

    snapshot.docs.forEach((doc) => {
      const data = doc.data();
      const status = data.status;

      // Only update Active sessions to Closed (leave Closed sessions as is)
      if (status === "Active") {
        batch.update(doc.ref, {
          status: "Closed",
          endedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        updateCount++;
      }
    });

    if (updateCount === 0) {
      console.log("No documents need updating");
      return;
    }

    await batch.commit();
    console.log(`Updated ${updateCount} sessions to Closed`);

    return;
  } catch (error) {
    console.error("Error updating documents:", error);
    throw error;
  }
});

// Runs every 1 minute (minimum for Cloud Scheduler)
// Checks and updates exercise completion status based on current_reps vs reps
// Also aggregates GCS folder data for each exercise
export const updateExerciseCompletion = onSchedule({
  schedule: "* * * * *", // Every 1 minute
  timeZone: "America/New_York",
}, async () => {
  const db = admin.firestore();

  try {
    // Get ALL sessions first to see what statuses exist
    const allSnapshot = await db.collection("sessions").limit(10).get();

    console.log(`Total sessions (first 10): ${allSnapshot.size}`);

    if (!allSnapshot.empty) {
      const statuses = new Set<string>();
      allSnapshot.docs.forEach((doc) => {
        const status = doc.data().status;
        if (status) statuses.add(status);
      });
      console.log(`Unique statuses found: ${Array.from(statuses).join(", ")}`);
    }

    // Query all sessions that might have incomplete exercises
    const snapshot = await db.collection("sessions")
      .where("status", "in", ["Active", "Closed", "active", "closed"])
      .get();

    console.log(`Found ${snapshot.size} sessions to check`);

    if (snapshot.empty) {
      console.log("No sessions to check");
      return;
    }

    // Process each session (need to use for...of for async operations)
    let sessionUpdateCount = 0;
    let exerciseUpdateCount = 0;
    let gcsFolderUpdateCount = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const exercises = data.exercises as Array<any> || [];
      const userId = data.userId || "";
      const sessionId = data.sessionId || "";

      console.log(
        `Session ${doc.id}: ${exercises.length} exercises, ` +
        `status: ${data.status}, userId: ${userId}, sessionId: ${sessionId}`
      );

      // Get GCS folders for this session
      let gcsFolders = new Map<string, GcsFolderInfo[]>();
      if (userId && sessionId) {
        gcsFolders = await getGcsFoldersForSession(sessionId);
        console.log(
          `  Found GCS folders for ${gcsFolders.size} exercises`
        );
      }

      let hasUpdates = false;
      const updatedExercises = exercises.map((exercise, idx) => {
        const currentReps = exercise.current_reps || 0;
        const targetReps = exercise.reps || 0;
        const isCompleted = exercise.completed || false;
        const exerciseName = exercise.name || "";

        // Normalize exercise name for matching with GCS folder names
        const normalizedName = normalizeExerciseName(exerciseName);

        if (idx === 0) {
          console.log(
            `  First exercise: ${exerciseName} (${normalizedName}), ` +
            `current_reps=${currentReps}, reps=${targetReps}, ` +
            `completed=${isCompleted}`
          );
        }

        // Check if there are new GCS folders for this exercise
        const folders = gcsFolders.get(normalizedName) || [];
        const existingFolders = exercise.gcs_folders || [];

        // Only update if we have new folders
        const newFolderPaths = new Set(folders.map((f) => f.path));
        const existingPaths = new Set(
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          existingFolders.map((f: any) => f.path)
        );
        const hasNewFolders = folders.length > 0 && (
          folders.length !== existingFolders.length ||
          [...newFolderPaths].some((p) => !existingPaths.has(p))
        );

        // Check if exercise should be marked as completed
        const shouldComplete = !isCompleted &&
          currentReps >= targetReps &&
          targetReps > 0;

        if (shouldComplete || hasNewFolders) {
          if (shouldComplete) {
            console.log(
              `  Marking exercise ${exerciseName} as completed ` +
              `(${currentReps}/${targetReps})`
            );
            exerciseUpdateCount++;
          }

          if (hasNewFolders) {
            console.log(
              `  Updating GCS folders for ${exerciseName}: ` +
              `${folders.length} folders`
            );
            gcsFolderUpdateCount++;
          }

          hasUpdates = true;
          return {
            ...exercise,
            completed: shouldComplete ? true : isCompleted,
            gcs_folders: folders.length > 0 ? folders : existingFolders,
          };
        }

        return exercise;
      });

      // Update session if any exercises were updated
      if (hasUpdates) {
        await db.collection("sessions").doc(doc.id).update({
          exercises: updatedExercises,
        });
        sessionUpdateCount++;
      }
    }

    if (sessionUpdateCount === 0) {
      console.log("No exercises need updates");
      return;
    }

    console.log(
      `Updated ${exerciseUpdateCount} exercise completions, ` +
      `${gcsFolderUpdateCount} GCS folder updates ` +
      `in ${sessionUpdateCount} sessions`
    );

    return;
  } catch (error) {
    console.error("Error updating exercise completion:", error);
    throw error;
  }
});
