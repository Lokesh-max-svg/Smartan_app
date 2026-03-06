const { Router } = require('express');
const { body, validationResult } = require('express-validator');
const { verifyJWT } = require('../middleware/auth');
const { getFirestore } = require('../config/firebase');

const router = Router();
const db = () => getFirestore();

/**
 * POST /api/user/profile
 * Save or update user profile
 */
router.post(
  '/profile',
  verifyJWT,
  [
    body('heightInCm').optional().isNumeric(),
    body('weightInKg').optional().isNumeric(),
    body('gymExpertise').optional().notEmpty(),
    body('hasHealthIssues').optional().isBoolean(),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: 'Validation failed',
          errors: errors.array(),
        });
      }

      const userId = req.user?.uid;
      if (!userId) {
        return res.status(401).json({
          success: false,
          message: 'Unauthorized',
        });
      }

      const {
        heightInCm,
        weightInKg,
        gymExpertise,
        hasHealthIssues,
        healthIssuesDescription,
        displayName,
        age,
        gender,
        fitnessGoal,
      } = req.body;

      const userRef = db().collection('users').doc(userId);

      // Check if user exists
      const userDoc = await userRef.get();
      if (!userDoc.exists) {
        return res.status(404).json({
          success: false,
          message: 'User not found',
        });
      }

      // Update profile
      const updateData = {
        updatedAt: new Date().toISOString(),
      };

      if (heightInCm !== undefined) updateData.heightInCm = Number(heightInCm);
      if (weightInKg !== undefined) updateData.weightInKg = Number(weightInKg);
      if (gymExpertise !== undefined) updateData.gymExpertise = gymExpertise;
      if (hasHealthIssues !== undefined) updateData.hasHealthIssues = hasHealthIssues;
      if (healthIssuesDescription) updateData.healthIssuesDescription = healthIssuesDescription;
      if (displayName !== undefined) {
        updateData.displayName = displayName;
        updateData.username = displayName;
      }
      if (age !== undefined) updateData.profile = { ...userDoc.data()?.profile, age };
      if (gender !== undefined)
        updateData.profile = { ...userDoc.data()?.profile, gender };
      if (fitnessGoal !== undefined)
        updateData.profile = { ...userDoc.data()?.profile, fitnessGoal };

      // Mark profile as completed if all required fields are set
      if (heightInCm && weightInKg && gymExpertise && hasHealthIssues !== undefined) {
        updateData.profileCompleted = true;
      }

      await userRef.update(updateData);

      res.status(200).json({
        success: true,
        message: 'Profile updated successfully',
      });
    } catch (error) {
      console.error('Profile update error:', error);
      res.status(500).json({
        success: false,
        message: error.message || 'Failed to update profile',
      });
    }
  }
);

/**
 * GET /api/user/profile
 * Get current user profile (requires authentication)
 */
router.get('/profile', verifyJWT, async (req, res) => {
  try {
    const userId = req.user?.uid;
    if (!userId) {
      return res.status(401).json({
        success: false,
        message: 'Unauthorized',
      });
    }

    const userDoc = await db().collection('users').doc(userId).get();

    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
      });
    }

    const userData = userDoc.data();

    res.status(200).json({
      success: true,
      data: userData,
    });
  } catch (error) {
    console.error('Get profile error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get profile',
    });
  }
});

/**
 * GET /api/user/workout-plan/:userId/:date
 * Get workout plan exercises for a specific day (YYYY-MM-DD)
 */
router.get('/workout-plan/:userId/:date', async (req, res) => {
  try {
    const { userId, date } = req.params;

    const workoutPlansSnapshot = await db()
      .collection('workoutPlans')
      .where('userId', '==', userId)
      .get();

    const exercises = [];

    for (const doc of workoutPlansSnapshot.docs) {
      const data = doc.data();
      const workouts = data?.workouts || {};
      const dateWorkouts = workouts[date];

      if (Array.isArray(dateWorkouts)) {
        for (const exercise of dateWorkouts) {
          exercises.push({
            id: exercise.id?.toString() || '',
            name: exercise.name || 'Unknown Exercise',
            muscle: exercise.muscle_name || exercise.muscle || 'Unknown',
            category: exercise.muscle_name || exercise.muscle || 'Unknown',
            difficulty: exercise.difficulty || 'Medium',
            sets: exercise.sets || 0,
            reps: exercise.reps || 0,
            duration: exercise.duration || '',
            image: exercise.image || '',
            muscleId: exercise.muscleId || 0,
            instanceId: exercise.instanceId || '',
            addedAt: exercise.addedAt || '',
          });
        }
      }
    }

    res.status(200).json({
      success: true,
      exercises,
    });
  } catch (error) {
    console.error('Workout plan fetch error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get workout plan',
    });
  }
});

/**
 * GET /api/user/profile/:userId
 * Get user profile by user ID
 */
router.get('/profile/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const userDoc = await db().collection('users').doc(userId).get();

    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
      });
    }

    const userData = userDoc.data();

    res.status(200).json({
      success: true,
      data: userData,
    });
  } catch (error) {
    console.error('Get profile error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get profile',
    });
  }
});

/**
 * GET /api/user/profile-status/:userId
 * Check if user profile is completed
 */
router.get('/profile-status/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const userDoc = await db().collection('users').doc(userId).get();

    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
        isCompleted: false,
      });
    }

    const data = userDoc.data();
    const isCompleted = !!(
      data &&
      data.heightInCm &&
      data.weightInKg &&
      data.gymExpertise &&
      data.hasHealthIssues !== undefined
    );

    res.status(200).json({
      success: true,
      isCompleted,
      status: data?.status ?? 0,
    });
  } catch (error) {
    console.error('Profile status error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to check profile status',
      isCompleted: false,
    });
  }
});

/**
 * GET /api/user/status/:userId
 * Get user status (0 = enabled, -1 = blocked, 1 = deleted)
 */
router.get('/status/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const userDoc = await db().collection('users').doc(userId).get();

    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
        status: null,
      });
    }

    const data = userDoc.data();
    const status = data?.status ?? 0;

    res.status(200).json({
      success: true,
      status,
      isActive: status === 0,
    });
  } catch (error) {
    console.error('User status error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get user status',
    });
  }
});

/**
 * POST /api/user/initialize
 * Initialize user with default fields
 */
router.post('/initialize', async (req, res) => {
  try {
    const { userId } = req.body;

    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'userId is required',
      });
    }

    const userRef = db().collection('users').doc(userId);

    await userRef.set(
      {
        user_type: 'user',
        status: 0,
        createdAt: new Date().toISOString(),
      },
      { merge: true }
    );

    res.status(200).json({
      success: true,
      message: 'User initialized successfully',
    });
  } catch (error) {
    console.error('User initialization error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to initialize user',
    });
  }
});

/**
 * PUT /api/user/profile
 * Update current user profile
 */
router.put(
  '/profile',
  verifyJWT,
  [
    body('displayName').optional().trim(),
    body('photoURL').optional().isURL(),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: 'Validation failed',
          errors: errors.array(),
        });
      }

      const userId = req.user?.uid;
      if (!userId) {
        return res.status(401).json({
          success: false,
          message: 'Unauthorized',
        });
      }

      const { displayName, photoURL } = req.body;

      const userRef = db().collection('users').doc(userId);
      const updateData = { updatedAt: new Date().toISOString() };

      if (displayName) updateData.displayName = displayName;
      if (photoURL) updateData.photoURL = photoURL;

      await userRef.update(updateData);

      res.status(200).json({
        success: true,
        message: 'Profile updated successfully',
      });
    } catch (error) {
      console.error('Profile update error:', error);
      res.status(500).json({
        success: false,
        message: error.message || 'Failed to update profile',
      });
    }
  }
);

module.exports = router;
