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
