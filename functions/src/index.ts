import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";

admin.initializeApp();

// Runs every 30 minutes
export const updateCompletedStatus = onSchedule({
  schedule: "*/10 * * * *", // Cron syntax: every 30 minutes
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

      // Only update if status is Active or Closed (not already Completed)
      if (status === "Active" || status === "Closed") {
        batch.update(doc.ref, {
          status: "Completed",
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
    console.log(`Updated ${updateCount} sessions to Completed`);

    return;
  } catch (error) {
    console.error("Error updating documents:", error);
    throw error;
  }
});

// Runs every 1 minute (minimum for Cloud Scheduler)
// Checks and updates exercise completion status based on current_reps vs reps
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
      .where("status", "in", ["Active", "Closed", "Completed",
        "active", "closed", "completed"])
      .get();

    console.log(`Found ${snapshot.size} sessions to check`);

    if (snapshot.empty) {
      console.log("No sessions to check");
      return;
    }

    const batch = db.batch();
    let sessionUpdateCount = 0;
    let exerciseUpdateCount = 0;

    snapshot.docs.forEach((doc) => {
      const data = doc.data();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const exercises = data.exercises as Array<any> || [];

      console.log(
        `Session ${doc.id}: ${exercises.length} exercises, ` +
        `status: ${data.status}`
      );

      let hasUpdates = false;
      const updatedExercises = exercises.map((exercise, idx) => {
        const currentReps = exercise.current_reps || 0;
        const targetReps = exercise.reps || 0;
        const isCompleted = exercise.completed || false;

        if (idx === 0) {
          console.log(
            `  First exercise: ${exercise.name}, ` +
            `current_reps=${currentReps}, reps=${targetReps}, ` +
            `completed=${isCompleted}`
          );
        }

        // Check if exercise should be marked as completed
        if (!isCompleted && currentReps >= targetReps && targetReps > 0) {
          console.log(
            `  Marking exercise ${exercise.name} as completed ` +
            `(${currentReps}/${targetReps})`
          );
          exerciseUpdateCount++;
          hasUpdates = true;
          return {...exercise, completed: true};
        }

        return exercise;
      });

      // Update session if any exercises were marked as completed
      if (hasUpdates) {
        batch.update(doc.ref, {exercises: updatedExercises});
        sessionUpdateCount++;
      }
    });

    if (sessionUpdateCount === 0) {
      console.log("No exercises need completion update");
      return;
    }

    await batch.commit();
    console.log(
      `Updated ${exerciseUpdateCount} exercises ` +
      `in ${sessionUpdateCount} sessions`
    );

    return;
  } catch (error) {
    console.error("Error updating exercise completion:", error);
    throw error;
  }
});
