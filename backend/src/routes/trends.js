const { Router } = require('express');
const { getFirestore } = require('../config/firebase');

const router = Router();

const getTimeFilter = (filter, customStart, customEnd) => {
  const now = new Date();
  const endDate = customEnd ? new Date(customEnd) : now;
  let startDate;

  switch (filter) {
    case 'today':
      startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      break;
    case 'last7Days':
      startDate = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
      break;
    case 'last15Days':
      startDate = new Date(now.getTime() - 15 * 24 * 60 * 60 * 1000);
      break;
    case 'last30Days':
      startDate = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
      break;
    case 'last90Days':
      startDate = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000);
      break;
    case 'custom':
      startDate = customStart ? new Date(customStart) : new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
      break;
    default:
      startDate = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  }

  return { startDate, endDate };
};

/**
 * GET /api/trends/all/:userId
 * Get all trends data (exercise frequency, progress metrics, activity calendar, session history)
 */
router.get('/all/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const { filter = 'last30Days', customStart, customEnd } = req.query;

    const db = getFirestore();
    const { startDate, endDate } = getTimeFilter(filter, customStart, customEnd);

    // Get sessions data
    const sessionsSnapshot = await db
      .collection('sessions')
      .where('userId', '==', userId)
      .get();

    // Get current workout data
    const workoutSnapshot = await db
      .collection('current_workout')
      .where('user_id', '==', userId)
      .get();

    // Process sessions
    const sessions = sessionsSnapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data(),
    }));

    // Process workout data
    const workouts = workoutSnapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data(),
    }));

    res.status(200).json({
      success: true,
      data: {
        sessions,
        workouts,
        filter: {
          type: filter,
          startDate: startDate.toISOString(),
          endDate: endDate.toISOString(),
        },
      },
    });
  } catch (error) {
    console.error('Get trends error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get trends data',
    });
  }
});

/**
 * GET /api/trends/sessions/:userId
 * Get session history for a user
 */
router.get('/sessions/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const { filter = 'last30Days', customStart, customEnd, limit } = req.query;

    const db = getFirestore();
    const { startDate, endDate } = getTimeFilter(filter, customStart, customEnd);

    let query = db
      .collection('sessions')
      .where('userId', '==', userId);

    if (limit) {
      query = query.limit(Number(limit));
    }

    const snapshot = await query.get();
    const sessions = snapshot.docs
      .map(doc => ({
        id: doc.id,
        ...doc.data(),
      }))
      .filter((session) => {
        const sessionDate = session.date ? new Date(session.date) : null;
        return sessionDate && sessionDate >= startDate && sessionDate <= endDate;
      });

    res.status(200).json({
      success: true,
      sessions,
    });
  } catch (error) {
    console.error('Get sessions error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get sessions',
    });
  }
});

/**
 * GET /api/trends/workouts/:userId
 * Get workout data for a user
 */
router.get('/workouts/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const { sessionId } = req.query;

    const db = getFirestore();

    let query = db
      .collection('current_workout')
      .where('user_id', '==', userId);

    if (sessionId) {
      query = query.where('session_id', '==', sessionId);
    }

    const snapshot = await query.get();
    const workouts = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data(),
    }));

    res.status(200).json({
      success: true,
      workouts,
    });
  } catch (error) {
    console.error('Get workouts error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get workouts',
    });
  }
});

module.exports = router;
