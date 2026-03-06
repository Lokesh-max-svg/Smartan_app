const { Router } = require('express');
const { body, validationResult } = require('express-validator');
const jwt = require('jsonwebtoken');
const { getFirestore, getAuth } = require('../config/firebase');
const { verifyJWT } = require('../middleware/auth');

const router = Router();
const db = () => getFirestore();
const auth = () => getAuth();
const getFirebaseApiKey = () =>
  process.env.FIREBASE_API_KEY || process.env.NEXT_PUBLIC_FIREBASE_API_KEY || '';

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Generate JWT token
 */
function generateJWT(uid, email, role = 'user') {
  const jwtSecret = process.env.JWT_SECRET || 'your-secret-key';
  const options = {
    expiresIn: process.env.JWT_EXPIRES_IN || '7d',
  };
  return jwt.sign({ uid, email, role }, jwtSecret, options);
}

/**
 * Create or get user document in Firestore
 */
async function createOrGetUserDoc(uid, userData) {
  const userRef = db().collection('users').doc(uid);
  const userDoc = await userRef.get();

  if (!userDoc.exists) {
    const newUserData = {
      uid,
      email: userData.email,
      username: userData.username || userData.displayName || 'User',
      displayName: userData.displayName || userData.username || '',
      photoURL: userData.photoURL || '',
      user_type: userData.user_type || 'user',
      status: 0, // 0 = enabled, -1 = blocked, 1 = deleted
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      profile: {
        age: null,
        gender: null,
        height: null,
        weight: null,
        fitnessGoal: null,
      },
    };
    await userRef.set(newUserData);
    return newUserData;
  }

  return userDoc.data();
}

// ============================================================================
// Authentication Routes
// ============================================================================

/**
 * POST /api/auth/signup-email
 * Create new user with email and password
 */
router.post(
  '/signup-email',
  [
    body('email').isEmail().normalizeEmail().toLowerCase(),
    body('password').isLength({ min: 6 }).withMessage('Password must be at least 6 characters'),
    body('username').trim().notEmpty().withMessage('Username is required'),
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

      const { email, password, username, displayName } = req.body;
      const normalizedEmail = email.trim().toLowerCase();

      // Create user in Firebase Auth
      const userRecord = await auth().createUser({
        email: normalizedEmail,
        password,
        displayName: displayName || username,
      });

      // Create user document in Firestore
      const userData = await createOrGetUserDoc(userRecord.uid, {
        email: normalizedEmail,
        username,
        displayName: displayName || username,
      });

      // Generate JWT token
      const token = generateJWT(userRecord.uid, normalizedEmail);

      // Create custom token for Firebase client SDK
      const customToken = await auth().createCustomToken(userRecord.uid);

      res.status(201).json({
        success: true,
        message: 'User created successfully',
        data: {
          uid: userRecord.uid,
          email: userRecord.email,
          username: userData.username,
          displayName: userData.displayName,
          token,
          customToken,
        },
      });
    } catch (error) {
      console.error('Signup error:', error);

      if (error.code === 'auth/email-already-exists') {
        return res.status(400).json({
          success: false,
          message: 'Email already in use',
        });
      }

      if (error.code === 'auth/weak-password') {
        return res.status(400).json({
          success: false,
          message: 'Password is too weak',
        });
      }

      res.status(500).json({
        success: false,
        message: error.message || 'Failed to create user',
      });
    }
  }
);

/**
 * POST /api/auth/login-email
 * Login with email and password
 */
router.post(
  '/login-email',
  [
    body('email').isEmail().normalizeEmail().toLowerCase(),
    body('password').notEmpty().withMessage('Password is required'),
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

      const { email, password } = req.body;
      const normalizedEmail = email.trim().toLowerCase();

      const firebaseApiKey = getFirebaseApiKey();

      if (!firebaseApiKey) {
        return res.status(500).json({
          success: false,
          message:
            'Server login is not configured. Missing FIREBASE_API_KEY or NEXT_PUBLIC_FIREBASE_API_KEY.',
        });
      }

      // Use Firebase REST API to verify password and get ID token
      const firebaseUrl = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${firebaseApiKey}`;
      
      const response = await fetch(firebaseUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: normalizedEmail,
          password,
          returnSecureToken: true,
        }),
      });

      if (!response.ok) {
        return res.status(401).json({
          success: false,
          message: 'Invalid email or password',
        });
      }

      const loginData = await response.json();
      const uid = loginData.localId;
      const firebaseEmail = (loginData.email || normalizedEmail).toLowerCase();
      const idToken = loginData.idToken;

      if (!uid || !idToken) {
        return res.status(500).json({
          success: false,
          message: 'Firebase login response is missing required fields.',
        });
      }

      // Load/create user profile in Firestore by Firebase Auth UID
      let userDoc = await db().collection('users').doc(uid).get();
      let userData = userDoc.data();
      if (!userDoc.exists) {
        userData = await createOrGetUserDoc(uid, {
          email: firebaseEmail,
          username: firebaseEmail.split('@')[0],
          displayName: '',
        });
        userDoc = await db().collection('users').doc(uid).get();
      }

      if (userData && userData.status !== 0) {
        return res.status(403).json({
          success: false,
          message:
            userData.status === -1 ? 'Account is blocked' : 'Account is deleted',
        });
      }

      // Generate JWT token for backend
      const token = generateJWT(uid, firebaseEmail);

      res.status(200).json({
        success: true,
        message: 'Login successful',
        data: {
          uid,
          email: firebaseEmail,
          username: userData?.username || userData?.displayName || 'User',
          displayName: userData?.displayName || '',
          photoURL: userData?.photoURL || '',
          token,
          firebaseToken: idToken,
        },
      });
    } catch (error) {
      console.error('Login error:', error);

      if (error.code === 'auth/user-not-found') {
        return res.status(401).json({
          success: false,
          message: 'No account found for this email. Please sign up first.',
        });
      }

      if (error.code === 'auth/invalid-email') {
        return res.status(400).json({
          success: false,
          message: 'Invalid email format.',
        });
      }

      res.status(500).json({
        success: false,
        message: error.message || 'Login failed',
      });
    }
  }
);

/**
 * POST /api/auth/google
 * Authenticate with Google (expects Firebase ID token)
 */
router.post('/google', async (req, res) => {
  try {
    const { idToken } = req.body;

    if (!idToken) {
      return res.status(400).json({
        success: false,
        message: 'ID token is required',
      });
    }

    // Verify Firebase ID token
    const decodedToken = await auth().verifyIdToken(idToken);
    const { uid, email, name, picture } = decodedToken;

    if (!email) {
      return res.status(400).json({
        success: false,
        message: 'Email not available from Google account',
      });
    }

    // Create or update user
    const userData = await createOrGetUserDoc(uid, {
      email,
      displayName: name || '',
      photoURL: picture || '',
      user_type: 'user',
    });

    // Generate JWT token
    const token = generateJWT(uid, email);

    res.status(200).json({
      success: true,
      message: 'Google login successful',
      data: {
        uid,
        email,
        username: userData.username,
        displayName: userData.displayName,
        photoURL: userData.photoURL,
        token,
      },
    });
  } catch (error) {
    console.error('Google auth error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Google authentication failed',
    });
  }
});

/**
 * POST /api/auth/logout
 * Logout user (revoke refresh tokens)
 */
router.post('/logout', verifyJWT, async (req, res) => {
  try {
    if (!req.user?.uid) {
      return res.status(400).json({
        success: false,
        message: 'User ID is required',
      });
    }

    // Revoke all refresh tokens for the user
    await auth().revokeRefreshTokens(req.user.uid);

    res.status(200).json({
      success: true,
      message: 'Logout successful',
    });
  } catch (error) {
    console.error('Logout error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Logout failed',
    });
  }
});

/**
 * POST /api/auth/refresh-token
 * Refresh JWT token
 */
router.post('/refresh-token', async (req, res) => {
  try {
    const { refreshToken } = req.body;
    const firebaseApiKey = getFirebaseApiKey();

    if (!refreshToken) {
      return res.status(400).json({
        success: false,
        message: 'Refresh token is required',
      });
    }
    if (!firebaseApiKey) {
      return res.status(500).json({
        success: false,
        message:
          'Server token refresh is not configured. Missing FIREBASE_API_KEY or NEXT_PUBLIC_FIREBASE_API_KEY.',
      });
    }

    // Exchange refresh token for new ID token via Firebase REST API
    const response = await fetch(
      'https://securetoken.googleapis.com/v1/token?key=' + firebaseApiKey,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: `grant_type=refresh_token&refresh_token=${refreshToken}`,
      }
    );

    if (!response.ok) {
      return res.status(401).json({
        success: false,
        message: 'Failed to refresh token',
      });
    }

    const { id_token, user_id } = await response.json();

    // Verify and decode the new ID token
    const decodedToken = await auth().verifyIdToken(id_token);

    // Generate new JWT token
    const token = generateJWT(user_id, decodedToken.email || '');

    res.status(200).json({
      success: true,
      message: 'Token refreshed successfully',
      data: {
        token,
        firebaseToken: id_token,
      },
    });
  } catch (error) {
    console.error('Refresh token error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to refresh token',
    });
  }
});

/**
 * POST /api/auth/reset-password
 * Send password reset email
 */
router.post(
  '/reset-password',
  [body('email').isEmail().normalizeEmail()],
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

      const { email } = req.body;

      try {
        // Generate password reset link
        const resetLink = await auth().generatePasswordResetLink(email);

        // In production, you would send this via email
        // For development, we'll return it (don't do this in production!)
        if (process.env.NODE_ENV === 'development') {
          return res.status(200).json({
            success: true,
            message: 'Password reset link generated (dev only)',
            resetLink,
          });
        }

        // TODO: Send reset link via email service
        res.status(200).json({
          success: true,
          message: 'Password reset email sent',
        });
      } catch (error) {
        if (error.code === 'auth/user-not-found') {
          return res.status(404).json({
            success: false,
            message: 'User not found',
          });
        }
        throw error;
      }
    } catch (error) {
      console.error('Reset password error:', error);
      res.status(500).json({
        success: false,
        message: error.message || 'Failed to reset password',
      });
    }
  }
);

/**
 * POST /api/auth/verify-reset-token
 * Verify password reset token
 */
router.post(
  '/verify-reset-token',
  [body('oobCode').notEmpty()],
  async (req, res) => {
    try {
      const { oobCode } = req.body;

      try {
        const email = await auth().verifyPasswordResetCode(oobCode);

        res.status(200).json({
          success: true,
          message: 'Token is valid',
          email,
        });
      } catch (error) {
        return res.status(400).json({
          success: false,
          message: 'Invalid or expired reset token',
        });
      }
    } catch (error) {
      console.error('Verify reset token error:', error);
      res.status(500).json({
        success: false,
        message: error.message || 'Failed to verify token',
      });
    }
  }
);

/**
 * POST /api/auth/confirm-password-reset
 * Confirm password reset with new password
 */
router.post(
  '/confirm-password-reset',
  [
    body('oobCode').notEmpty(),
    body('newPassword')
      .isLength({ min: 6 })
      .withMessage('Password must be at least 6 characters'),
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

      const { oobCode, newPassword } = req.body;

      try {
        const email = await auth().confirmPasswordReset(oobCode, newPassword);

        res.status(200).json({
          success: true,
          message: 'Password reset successfully',
          email,
        });
      } catch (error) {
        if (error.code === 'auth/expired-oob-code') {
          return res.status(400).json({
            success: false,
            message: 'Reset token has expired',
          });
        }
        throw error;
      }
    } catch (error) {
      console.error('Confirm password reset error:', error);
      res.status(500).json({
        success: false,
        message: error.message || 'Failed to reset password',
      });
    }
  }
);

/**
 * GET /api/auth/verify-token
 * Verify if token is valid
 */
router.get('/verify-token', verifyJWT, async (req, res) => {
  res.status(200).json({
    success: true,
    message: 'Token is valid',
    user: req.user,
  });
});

module.exports = router;
