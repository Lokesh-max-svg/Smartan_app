const jwt = require('jsonwebtoken');
const { admin } = require('../config/firebase');

/**
 * Middleware to verify Firebase ID token
 * Verifies Firebase ID tokens issued by Firebase Auth
 */
const verifyFirebaseToken = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        message: 'Unauthorized - No token provided',
      });
    }

    const token = authHeader.split(' ')[1];

    // Verify Firebase ID token
    const decodedToken = await admin.auth().verifyIdToken(token);

    req.user = {
      uid: decodedToken.uid,
      email: decodedToken.email,
    };
    req.userId = decodedToken.uid;

    next();
  } catch (error) {
    console.error('Firebase token verification error:', error.message);
    res.status(401).json({
      success: false,
      message: 'Invalid or expired Firebase token',
    });
  }
};

/**
 * Middleware to verify JWT token
 * Adds user info to request object
 */
const verifyJWT = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        message: 'Unauthorized - No token provided',
      });
    }

    const token = authHeader.split(' ')[1];
    const jwtSecret = process.env.JWT_SECRET || 'your-secret-key';

    // Verify JWT token
    const decoded = jwt.verify(token, jwtSecret);

    req.user = decoded;
    req.userId = decoded.uid;

    next();
  } catch (error) {
    console.error('JWT verification error:', error.message);
    res.status(401).json({
      success: false,
      message: 'Invalid or expired token',
    });
  }
};

/**
 * Optional authentication - proceeds even if no token
 * But validates token if present
 */
const optionalAuth = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      // No token provided, but that's okay
      next();
      return;
    }

    const token = authHeader.split(' ')[1];
    const jwtSecret = process.env.JWT_SECRET;

    if (!jwtSecret) {
      next();
      return;
    }

    try {
      const decoded = jwt.verify(token, jwtSecret);

      req.user = decoded;
      req.userId = decoded.uid;
    } catch (error) {
      // Invalid token, but proceed anyway
      console.warn('Invalid token in optional auth:', error);
    }

    next();
  } catch (error) {
    next();
  }
};

module.exports = {
  verifyFirebaseToken,
  verifyJWT,
  optionalAuth,
};
