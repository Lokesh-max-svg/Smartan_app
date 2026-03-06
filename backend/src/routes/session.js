const { Router } = require('express');
const { getFirestore, getStorage } = require('../config/firebase');

const router = Router();

const isObject = (value) => value && typeof value === 'object' && !Array.isArray(value);

const parseTimestampLike = (value) => {
  if (!value) return null;
  if (typeof value === 'string' || value instanceof Date) {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (typeof value === 'number') {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (isObject(value)) {
    if (typeof value._seconds === 'number') {
      return new Date(value._seconds * 1000);
    }
    if (typeof value.seconds === 'number') {
      return new Date(value.seconds * 1000);
    }
  }
  return null;
};

const normalizeSession = (doc) => {
  const data = doc.data();
  return {
    id: doc.id,
    ...data,
  };
};

const normalizeExerciseName = (name = '') =>
  name.toString().trim().toLowerCase().replaceAll('_', ' ');

const parseGcsFolderName = (folderName) => {
  const match = /_cam_(\d+)_(\d+)_(\d+)$/.exec(folderName);
  if (!match) return null;

  return {
    camera: Number(match[1]) || 0,
    batch: Number(match[2]) || 0,
    timestamp: Number(match[3]) || 0,
  };
};

const normalizeFolderEntry = (entry) => {
  if (typeof entry === 'string') {
    return { path: entry };
  }

  if (!isObject(entry)) return null;

  const path = (entry.path || entry.gcs_folder || '').toString();
  if (!path) return null;

  return {
    path,
    ...(entry.camera !== undefined ? { camera: Number(entry.camera) || 0 } : {}),
    ...(entry.batch !== undefined ? { batch: Number(entry.batch) || 0 } : {}),
    ...(entry.timestamp !== undefined ? { timestamp: Number(entry.timestamp) || 0 } : {}),
  };
};

const dedupeFolders = (folders) => {
  const seen = new Set();
  const unique = [];

  for (const folder of folders) {
    const normalized = normalizeFolderEntry(folder);
    if (!normalized || !normalized.path) continue;

    if (seen.has(normalized.path)) continue;
    seen.add(normalized.path);

    const folderName = normalized.path.split('/').pop() || '';
    const parsed = parseGcsFolderName(folderName);

    unique.push({
      ...normalized,
      ...(parsed ? {
        camera: normalized.camera ?? parsed.camera,
        batch: normalized.batch ?? parsed.batch,
        timestamp: normalized.timestamp ?? parsed.timestamp,
      } : {}),
    });
  }

  unique.sort((a, b) => {
    const batchA = Number(a.batch) || 0;
    const batchB = Number(b.batch) || 0;
    if (batchA !== batchB) return batchA - batchB;

    const tsA = Number(a.timestamp) || 0;
    const tsB = Number(b.timestamp) || 0;
    return tsA - tsB;
  });

  return unique;
};

const resolveSessionDoc = async (db, sessionIdOrDocId) => {
  const byDocId = await db.collection('sessions').doc(sessionIdOrDocId).get();
  if (byDocId.exists) return byDocId;

  const bySessionField = await db
    .collection('sessions')
    .where('sessionId', '==', sessionIdOrDocId)
    .limit(1)
    .get();

  if (!bySessionField.empty) {
    return bySessionField.docs[0];
  }

  return null;
};

const resolvePlaybackFolders = async ({ db, storage, sessionDoc, exerciseName }) => {
  const sessionData = sessionDoc.data() || {};
  const normalizedExerciseName = normalizeExerciseName(exerciseName);
  const normalizedExerciseForPath = exerciseName.toString().trim().toLowerCase().replaceAll(' ', '_');

  let folders = [];

  const sessionExercises = Array.isArray(sessionData.exercises) ? sessionData.exercises : [];
  for (const exercise of sessionExercises) {
    if (!isObject(exercise)) continue;
    const name = normalizeExerciseName(exercise.name);
    if (name === normalizedExerciseName) {
      if (Array.isArray(exercise.gcs_folders)) {
        folders = folders.concat(exercise.gcs_folders);
      }
      break;
    }
  }

  if (folders.length === 0 && Array.isArray(sessionData.gcs_folders)) {
    const filtered = sessionData.gcs_folders.filter((entry) => {
      const normalized = normalizeFolderEntry(entry);
      return normalized?.path?.includes(normalizedExerciseForPath);
    });
    folders = folders.concat(filtered);
  }

  const sessionIdField = (sessionData.sessionId || '').toString();
  if (folders.length === 0 && sessionIdField) {
    const workoutSnapshot = await db
      .collection('current_workout')
      .where('session_id', '==', sessionIdField)
      .get();

    for (const workoutDoc of workoutSnapshot.docs) {
      const workout = workoutDoc.data() || {};
      const workoutName = normalizeExerciseName(workout.exercise_name || '');
      const matched =
        workoutName === normalizedExerciseName ||
        workoutName.includes(normalizedExerciseName) ||
        normalizedExerciseName.includes(workoutName);

      if (!matched) continue;

      if (Array.isArray(workout.gcs_folders)) {
        folders = folders.concat(workout.gcs_folders);
      }

      if (isObject(workout.smpl_bin_files) && workout.smpl_bin_files.gcs_folder) {
        folders.push({ path: workout.smpl_bin_files.gcs_folder });
      }
    }
  }

  const userId = (sessionData.userId || '').toString();
  const sessionIdOrDocId = (sessionData.sessionId || sessionDoc.id).toString();

  if (folders.length === 0 && userId) {
    const basePath = `pose_data/${userId}/${sessionIdOrDocId}`;

    try {
      const [files] = await storage.bucket().getFiles({ prefix: `${basePath}/` });
      for (const file of files) {
        const filename = file.name.split('/').pop() || '';
        if (filename.endsWith('.zip')) {
          const folderName = file.name.split('/').slice(-2, -1)[0] || '';
          if (folderName.startsWith(normalizedExerciseForPath)) {
            folders.push({ path: file.name });
          }
        }
      }
    } catch (error) {
      // Do not fail the whole request if storage scan fails.
      console.warn('Storage scan warning:', error.message);
    }
  }

  return dedupeFolders(folders);
};

/**
 * GET /api/session/exercises
 * List tutorial exercises with optional filters
 */
router.get('/exercises', async (req, res) => {
  try {
    const { muscleName = '', search = '' } = req.query;
    const db = getFirestore();

    const snapshot = await db.collection('exercises').get();
    const normalizedMuscle = muscleName.toString().trim().toLowerCase();
    const normalizedSearch = search.toString().trim().toLowerCase();

    const exercises = snapshot.docs
      .map((doc) => ({ id: doc.id, ...doc.data() }))
      .filter((exercise) => {
        const muscle = (exercise.muscle_name || '').toString().toLowerCase();

        if (normalizedMuscle && normalizedMuscle !== 'all' && muscle !== normalizedMuscle) {
          return false;
        }

        if (!normalizedSearch) return true;

        const haystack = [
          exercise.exercise_name,
          exercise.muscle_name,
          exercise.muscleCategory,
          exercise.difficulty,
          exercise.description,
        ]
          .map((v) => (v || '').toString().toLowerCase())
          .join(' ');

        return haystack.includes(normalizedSearch);
      });

    res.status(200).json({
      success: true,
      exercises,
    });
  } catch (error) {
    console.error('Get exercises error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get exercises',
    });
  }
});

/**
 * GET /api/session/playback-data/:sessionId/:exerciseName
 * Resolve playback storage folders for an exercise in a session
 */
router.get('/playback-data/:sessionId/:exerciseName', async (req, res) => {
  try {
    const { sessionId, exerciseName } = req.params;
    const db = getFirestore();
    const storage = getStorage();

    const sessionDoc = await resolveSessionDoc(db, sessionId);

    if (!sessionDoc) {
      return res.status(404).json({
        success: false,
        message: 'Session not found',
      });
    }

    const folders = await resolvePlaybackFolders({
      db,
      storage,
      sessionDoc,
      exerciseName,
    });

    res.status(200).json({
      success: true,
      session: normalizeSession(sessionDoc),
      exerciseName,
      folders,
    });
  } catch (error) {
    console.error('Get playback data error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get playback data',
    });
  }
});

/**
 * GET /api/session/storage/list
 * List files under a Firebase Storage path
 */
router.get('/storage/list', async (req, res) => {
  try {
    const rawPath = (req.query.path || '').toString().trim();

    if (!rawPath) {
      return res.status(400).json({
        success: false,
        message: 'path query parameter is required',
      });
    }

    if (!rawPath.startsWith('pose_data/')) {
      return res.status(400).json({
        success: false,
        message: 'Only pose_data paths are allowed',
      });
    }

    const storage = getStorage();
    const prefix = rawPath.endsWith('/') ? rawPath : `${rawPath}/`;
    const [files] = await storage.bucket().getFiles({ prefix });

    const items = files
      .map((file) => ({
        name: file.name.split('/').pop() || file.name,
        path: file.name,
      }))
      .filter((file) => file.path !== prefix);

    res.status(200).json({
      success: true,
      items,
    });
  } catch (error) {
    console.error('List storage files error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to list storage files',
    });
  }
});

/**
 * GET /api/session/storage/file
 * Download a file from Firebase Storage through backend
 */
router.get('/storage/file', async (req, res) => {
  try {
    const path = (req.query.path || '').toString().trim();

    if (!path) {
      return res.status(400).json({
        success: false,
        message: 'path query parameter is required',
      });
    }

    if (!path.startsWith('pose_data/')) {
      return res.status(400).json({
        success: false,
        message: 'Only pose_data paths are allowed',
      });
    }

    const storage = getStorage();
    const file = storage.bucket().file(path);
    const [exists] = await file.exists();

    if (!exists) {
      return res.status(404).json({
        success: false,
        message: 'File not found',
      });
    }

    const [buffer] = await file.download();
    const lower = path.toLowerCase();

    let contentType = 'application/octet-stream';
    if (lower.endsWith('.zip')) contentType = 'application/zip';
    if (lower.endsWith('.bin')) contentType = 'application/octet-stream';

    res.setHeader('Content-Type', contentType);
    res.setHeader('Content-Length', buffer.length.toString());
    res.send(buffer);
  } catch (error) {
    console.error('Download storage file error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to download storage file',
    });
  }
});

/**
 * POST /api/session/create
 * Create a new session document
 */
router.post('/create', async (req, res) => {
  try {
    const { userId, date, exercises = [] } = req.body;

    if (!userId || !date) {
      return res.status(400).json({
        success: false,
        message: 'userId and date are required',
      });
    }

    const db = getFirestore();

    const existingActive = await db
      .collection('sessions')
      .where('userId', '==', userId)
      .where('date', '==', date)
      .where('status', 'in', ['Active', 'active'])
      .limit(1)
      .get();

    if (!existingActive.empty) {
      return res.status(409).json({
        success: false,
        message: 'An active session already exists for this date',
      });
    }

    const now = Date.now();
    const userPrefix = userId.length > 6 ? userId.substring(0, 6) : userId;
    const timestampSuffix = now.toString().slice(-10);
    const sessionIdValue = `${userPrefix}${timestampSuffix}`;

    const normalizedExercises = Array.isArray(exercises)
      ? exercises.map((exercise) => ({
          ...exercise,
          reps: Number(exercise.reps) || 0,
          current_reps: 0,
          completed: false,
        }))
      : [];

    const sessionPayload = {
      userId,
      sessionId: sessionIdValue,
      date,
      status: 'Active',
      embedding_status: 0,
      reid_status: 0,
      global_session: null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      exercises: normalizedExercises,
    };

    const docRef = await db.collection('sessions').add(sessionPayload);

    res.status(201).json({
      success: true,
      message: 'Session created successfully',
      session: {
        id: docRef.id,
        ...sessionPayload,
      },
    });
  } catch (error) {
    console.error('Create session error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to create session',
    });
  }
});

/**
 * GET /api/session/user/:userId/date/:date
 * Get all sessions for a user and date
 */
router.get('/user/:userId/date/:date', async (req, res) => {
  try {
    const { userId, date } = req.params;
    const db = getFirestore();

    const snapshot = await db
      .collection('sessions')
      .where('userId', '==', userId)
      .where('date', '==', date)
      .get();

    const sessions = snapshot.docs.map(normalizeSession);

    sessions.sort((a, b) => {
      const aDate = parseTimestampLike(a.createdAt);
      const bDate = parseTimestampLike(b.createdAt);
      if (!aDate && !bDate) return 0;
      if (!aDate) return 1;
      if (!bDate) return -1;
      return bDate.getTime() - aDate.getTime();
    });

    res.status(200).json({
      success: true,
      sessions,
    });
  } catch (error) {
    console.error('Get sessions by date error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get sessions by date',
    });
  }
});

/**
 * GET /api/session/by-session-id/:sessionId
 * Get session by sessionId field (not document ID)
 */
router.get('/by-session-id/:sessionId', async (req, res) => {
  try {
    const { sessionId } = req.params;
    const db = getFirestore();

    const snapshot = await db
      .collection('sessions')
      .where('sessionId', '==', sessionId)
      .limit(1)
      .get();

    if (snapshot.empty) {
      return res.status(404).json({
        success: false,
        message: 'Session not found',
      });
    }

    const sessionDoc = snapshot.docs[0];
    res.status(200).json({
      success: true,
      session: normalizeSession(sessionDoc),
    });
  } catch (error) {
    console.error('Get session error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get session',
    });
  }
});

/**
 * GET /api/session/user/:userId/active
 * Get active session for a user
 */
router.get('/user/:userId/active', async (req, res) => {
  try {
    const { userId } = req.params;
    const db = getFirestore();

    const snapshot = await db
      .collection('sessions')
      .where('userId', '==', userId)
      .where('status', 'in', ['Active', 'active'])
      .limit(1)
      .get();

    if (snapshot.empty) {
      return res.status(404).json({
        success: false,
        message: 'No active session found',
        hasActiveSession: false,
      });
    }

    const sessionDoc = snapshot.docs[0];
    res.status(200).json({
      success: true,
      hasActiveSession: true,
      session: normalizeSession(sessionDoc),
    });
  } catch (error) {
    console.error('Get active session error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get active session',
    });
  }
});

/**
 * GET /api/session/user/:userId/active-all
 * Get all active sessions for a user
 */
router.get('/user/:userId/active-all', async (req, res) => {
  try {
    const { userId } = req.params;
    const db = getFirestore();

    const snapshot = await db
      .collection('sessions')
      .where('userId', '==', userId)
      .where('status', 'in', ['Active', 'active'])
      .get();

    const sessions = snapshot.docs.map(normalizeSession);

    res.status(200).json({
      success: true,
      sessions,
    });
  } catch (error) {
    console.error('Get active sessions error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get active sessions',
    });
  }
});

/**
 * GET /api/session/workouts/by-session-id/:sessionId
 * Get current_workout rows by session_id field
 */
router.get('/workouts/by-session-id/:sessionId', async (req, res) => {
  try {
    const { sessionId } = req.params;
    const db = getFirestore();

    const snapshot = await db
      .collection('current_workout')
      .where('session_id', '==', sessionId)
      .get();

    const workouts = snapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));

    res.status(200).json({
      success: true,
      workouts,
    });
  } catch (error) {
    console.error('Get session workouts error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get session workouts',
    });
  }
});

/**
 * GET /api/session/exercise-image/:exerciseName
 * Get exercise image from exercises collection by name
 */
router.get('/exercise-image/:exerciseName', async (req, res) => {
  try {
    const { exerciseName } = req.params;
    const db = getFirestore();
    const normalized = exerciseName.trim().toLowerCase();

    const exact = await db
      .collection('exercises')
      .where('exercise_name', '==', exerciseName.trim())
      .limit(1)
      .get();

    if (!exact.empty) {
      return res.status(200).json({
        success: true,
        image: exact.docs[0].data()?.image || '',
      });
    }

    const all = await db.collection('exercises').get();
    const match = all.docs.find((doc) => {
      const name = (doc.data()?.exercise_name || '').toString().trim().toLowerCase();
      return name === normalized || name.includes(normalized) || normalized.includes(name);
    });

    res.status(200).json({
      success: true,
      image: match?.data()?.image || '',
    });
  } catch (error) {
    console.error('Get exercise image error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get exercise image',
    });
  }
});

/**
 * PATCH /api/session/:sessionId/reid-status
 * Update reid_status for a session
 */
router.patch('/:sessionId/reid-status', async (req, res) => {
  try {
    const { sessionId } = req.params;
    const { reidStatus } = req.body;

    if (reidStatus === undefined) {
      return res.status(400).json({
        success: false,
        message: 'reidStatus is required',
      });
    }

    const db = getFirestore();
    const sessionRef = db.collection('sessions').doc(sessionId);

    await sessionRef.update({
      reid_status: reidStatus,
      updatedAt: new Date().toISOString(),
    });

    res.status(200).json({
      success: true,
      message: 'Reid status updated successfully',
    });
  } catch (error) {
    console.error('Update reid status error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to update reid status',
    });
  }
});

/**
 * PATCH /api/session/:sessionId/status
 * Update session status (Active/Closed)
 */
router.patch('/:sessionId/status', async (req, res) => {
  try {
    const { sessionId } = req.params;
    const { status } = req.body;

    if (!status) {
      return res.status(400).json({
        success: false,
        message: 'status is required',
      });
    }

    const db = getFirestore();
    const sessionRef = db.collection('sessions').doc(sessionId);

    const updateData = {
      status,
      updatedAt: new Date().toISOString(),
    };

    if (status === 'Closed') {
      updateData.endedAt = new Date().toISOString();
      updateData.closedAt = new Date().toISOString();
    }

    await sessionRef.update(updateData);

    res.status(200).json({
      success: true,
      message: 'Session status updated successfully',
    });
  } catch (error) {
    console.error('Update session status error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to update session status',
    });
  }
});

/**
 * PATCH /api/session/:sessionId/close
 * Close a session and compute latest exercise completion from current_workout
 */
router.patch('/:sessionId/close', async (req, res) => {
  try {
    const { sessionId } = req.params;
    const { exercises } = req.body;

    const db = getFirestore();
    const sessionRef = db.collection('sessions').doc(sessionId);
    const sessionDoc = await sessionRef.get();

    if (!sessionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Session not found',
      });
    }

    const sessionData = sessionDoc.data() || {};
    const sourceExercises = Array.isArray(exercises)
      ? exercises
      : Array.isArray(sessionData.exercises)
      ? sessionData.exercises
      : [];

    let computedExercises = sourceExercises;
    const sessionIdField = (sessionData.sessionId || '').toString();

    if (sourceExercises.length > 0 && sessionIdField) {
      const workoutSnapshot = await db
        .collection('current_workout')
        .where('session_id', '==', sessionIdField)
        .get();

      computedExercises = sourceExercises.map((exercise) => {
        const name = (exercise.name || '').toString();
        let totalCurrentReps = 0;

        for (const workoutDoc of workoutSnapshot.docs) {
          const workout = workoutDoc.data() || {};
          if ((workout.exercise_name || '') === name) {
            totalCurrentReps += Number(workout.reps) || 0;
          }
        }

        const targetReps = Number(exercise.reps) || 0;
        return {
          ...exercise,
          current_reps: totalCurrentReps,
          completed: targetReps > 0 ? totalCurrentReps >= targetReps : false,
        };
      });
    }

    await sessionRef.update({
      status: 'Closed',
      updatedAt: new Date().toISOString(),
      endedAt: new Date().toISOString(),
      closedAt: new Date().toISOString(),
      ...(computedExercises.length > 0 ? { exercises: computedExercises } : {}),
    });

    res.status(200).json({
      success: true,
      message: 'Session closed successfully',
    });
  } catch (error) {
    console.error('Close session error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to close session',
    });
  }
});

/**
 * GET /api/session/:sessionId
 * Get session details by document ID
 */
router.get('/:sessionId', async (req, res) => {
  try {
    const { sessionId } = req.params;
    const db = getFirestore();

    const sessionDoc = await db.collection('sessions').doc(sessionId).get();

    if (!sessionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Session not found',
      });
    }

    res.status(200).json({
      success: true,
      session: normalizeSession(sessionDoc),
    });
  } catch (error) {
    console.error('Get session error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get session',
    });
  }
});

module.exports = router;
