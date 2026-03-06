const { Router } = require('express');
const { body, validationResult } = require('express-validator');
const { getFirestore, getStorage } = require('../config/firebase');
const multer = require('multer');

const router = Router();
const upload = multer({ storage: multer.memoryStorage() });

/**
 * GET /api/gym/validate/:gymId
 * Validate gym ID by checking if it exists
 */
router.get('/validate/:gymId', async (req, res) => {
  try {
    const { gymId } = req.params;
    const db = getFirestore();

    // Query all organizations to find the gym
    const orgsSnapshot = await db.collection('organizations').get();

    for (const orgDoc of orgsSnapshot.docs) {
      const gymDoc = await db
        .collection('organizations')
        .doc(orgDoc.id)
        .collection('gyms')
        .doc(gymId)
        .get();

      if (gymDoc.exists) {
        const gymData = gymDoc.data();
        return res.status(200).json({
          success: true,
          gym: {
            gymId,
            organizationId: orgDoc.id,
            ...gymData,
          },
        });
      }
    }

    res.status(404).json({
      success: false,
      message: 'Gym not found',
    });
  } catch (error) {
    console.error('Gym validation error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to validate gym',
    });
  }
});

/**
 * POST /api/gym/upload-proof
 * Upload proof image to Firebase Storage
 */
router.post(
  '/upload-proof',
  upload.single('image'),
  async (req, res) => {
    try {
      const { userId, gymId } = req.body;

      if (!req.file) {
        return res.status(400).json({
          success: false,
          message: 'No image file provided',
        });
      }

      if (!userId || !gymId) {
        return res.status(400).json({
          success: false,
          message: 'userId and gymId are required',
        });
      }

      const storage = getStorage();
      const bucket = storage.bucket();

      // Create unique filename
      const timestamp = Date.now();
      const fileName = `gym_proofs/${userId}/${userId}_${gymId}_${timestamp}.jpg`;

      const file = bucket.file(fileName);
      await file.save(req.file.buffer, {
        metadata: {
          contentType: req.file.mimetype,
        },
      });

      // Make file publicly accessible
      await file.makePublic();

      // Get download URL
      const downloadUrl = `https://storage.googleapis.com/${bucket.name}/${fileName}`;

      res.status(200).json({
        success: true,
        downloadUrl,
      });
    } catch (error) {
      console.error('Image upload error:', error);
      res.status(500).json({
        success: false,
        message: error.message || 'Failed to upload image',
      });
    }
  }
);

/**
 * POST /api/gym/associate
 * Associate user with gym
 */
router.post(
  '/associate',
  [
    body('userId').notEmpty(),
    body('gymId').notEmpty(),
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

      const { userId, gymId, proofImageUrl } = req.body;
      const db = getFirestore();

      // Get user document
      const userRef = db.collection('users').doc(userId);
      const userDoc = await userRef.get();

      if (!userDoc.exists) {
        return res.status(404).json({
          success: false,
          message: 'User not found',
        });
      }

      const userData = userDoc.data();
      let gyms = userData?.gyms || [];

      // Check if gym already exists
      const existingGymIndex = gyms.findIndex((g) => g.gymId === gymId);

      if (existingGymIndex !== -1) {
        // Update existing gym entry
        gyms[existingGymIndex] = {
          gymId,
          status: 2, // pending approval
          joinedAt: gyms[existingGymIndex].joinedAt || new Date().toISOString(),
          rejoinedAt: new Date().toISOString(),
          proofImageUrl: proofImageUrl || gyms[existingGymIndex].proofImageUrl,
        };
      } else {
        // Add new gym
        gyms.push({
          gymId,
          status: 2, // pending approval
          joinedAt: new Date().toISOString(),
          proofImageUrl,
        });
      }

      await userRef.update({ gyms });

      res.status(200).json({
        success: true,
        message: 'User associated with gym successfully',
      });
    } catch (error) {
      console.error('Gym association error:', error);
      res.status(500).json({
        success: false,
        message: error.message || 'Failed to associate with gym',
      });
    }
  }
);

/**
 * POST /api/gym/leave
 * Mark a user as left from a gym
 */
router.post(
  '/leave',
  [body('userId').notEmpty(), body('gymId').notEmpty()],
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

      const { userId, gymId } = req.body;
      const db = getFirestore();

      const userRef = db.collection('users').doc(userId);
      const userDoc = await userRef.get();

      if (!userDoc.exists) {
        return res.status(404).json({
          success: false,
          message: 'User not found',
        });
      }

      const userData = userDoc.data();
      const gyms = userData?.gyms || [];
      const existingGymIndex = gyms.findIndex((g) => g.gymId === gymId);

      if (existingGymIndex === -1) {
        return res.status(404).json({
          success: false,
          message: 'Gym association not found',
        });
      }

      gyms[existingGymIndex] = {
        ...gyms[existingGymIndex],
        status: 1, // left
        leftAt: new Date().toISOString(),
      };

      await userRef.update({ gyms });

      res.status(200).json({
        success: true,
        message: 'User left gym successfully',
      });
    } catch (error) {
      console.error('Leave gym error:', error);
      res.status(500).json({
        success: false,
        message: error.message || 'Failed to leave gym',
      });
    }
  }
);

/**
 * GET /api/gym/user-gyms/:userId
 * Get all gym IDs for a user
 */
router.get('/user-gyms/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const { activeOnly, includeDetails } = req.query;
    const db = getFirestore();

    const userDoc = await db.collection('users').doc(userId).get();

    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
        gymIds: [],
      });
    }

    const userData = userDoc.data();
    const gyms = userData?.gyms || [];

    let gymIds;

    if (activeOnly === 'true') {
      // Return only active and pending gyms (status 0 or 2)
      gymIds = gyms
        .filter((g) => g.status === 0 || g.status === 2)
        .map((g) => g.gymId);
    } else {
      // Return all gyms
      gymIds = gyms.map((g) => g.gymId);
    }

    let gymsDetailed = undefined;
    if (includeDetails === 'true') {
      gymsDetailed = [];
      for (const gymEntry of gyms) {
        const gymId = gymEntry.gymId;
        let gymDetails = null;

        const orgsSnapshot = await db.collection('organizations').get();
        for (const orgDoc of orgsSnapshot.docs) {
          const gymDoc = await db
            .collection('organizations')
            .doc(orgDoc.id)
            .collection('gyms')
            .doc(gymId)
            .get();

          if (gymDoc.exists) {
            gymDetails = {
              gymId,
              organizationId: orgDoc.id,
              ...gymDoc.data(),
            };
            break;
          }
        }

        gymsDetailed.push({
          ...gymEntry,
          gym: gymDetails,
        });
      }
    }

    res.status(200).json({
      success: true,
      gymIds,
      gyms, // Return full gym objects with status
      ...(gymsDetailed !== undefined ? { gymsDetailed } : {}),
    });
  } catch (error) {
    console.error('Get user gyms error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get user gyms',
    });
  }
});

/**
 * GET /api/gym/details/:organizationId/:gymId
 * Get gym details
 */
router.get('/details/:organizationId/:gymId', async (req, res) => {
  try {
    const { organizationId, gymId } = req.params;
    const db = getFirestore();

    const gymDoc = await db
      .collection('organizations')
      .doc(organizationId)
      .collection('gyms')
      .doc(gymId)
      .get();

    if (!gymDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Gym not found',
      });
    }

    res.status(200).json({
      success: true,
      gym: {
        gymId,
        organizationId,
        ...gymDoc.data(),
      },
    });
  } catch (error) {
    console.error('Get gym details error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get gym details',
    });
  }
});

module.exports = router;
