# Backend Architecture Migration Guide

## Overview

This project has been refactored from a direct Firebase Firestore connection model to a **backend API middleware architecture**. The Flutter app no longer connects directly to Firestore; instead, all database operations go through a Node.js/Express backend API.

## New Architecture

```
┌─────────────────┐      HTTP/REST      ┌──────────────────┐      Firebase     ┌──────────────┐
│                 │ ──────────────────> │                  │ ──────────────> │              │
│  Flutter App    │                     │  Backend API     │                  │  Firestore   │
│  (Mobile)       │ <────────────────── │  (Node.js/       │ <────────────── │  Database    │
│                 │      JSON           │   Express)       │      Data        │              │
└─────────────────┘                     └──────────────────┘                  └──────────────┘
```

### Benefits of This Architecture

1. **Security**: Client doesn't have direct database access
2. **Validation**: All data is validated before reaching Firestore
3. **Business Logic**: Centralized logic makes maintenance easier
4. **API Control**: Easy to rate limit, monitor, and version
5. **Testing**: Easier to test backend logic independently
6. **Flexibility**: Can swap out Firebase for another database without changing the app

## Directory Structure

```
smartan_fitness/
├── backend/                           # NEW - Backend API server
│   ├── src/
│   │   ├── config/
│   │   │   └── firebase.ts            # Firebase Admin SDK initialization
│   │   ├── middleware/
│   │   │   ├── auth.ts                # JWT authentication middleware
│   │   │   └── errorHandler.ts       # Global error handling
│   │   ├── routes/
│   │   │   ├── auth.ts                # Authentication endpoints
│   │   │   ├── user.ts                # User profile endpoints
│   │   │   ├── gym.ts                 # Gym management endpoints
│   │   │   ├── trends.ts              # Analytics endpoints
│   │   │   └── session.ts             # Session management endpoints
│   │   └── server.ts                  # Main Express server
│   ├── package.json
│   ├── tsconfig.json
│   ├── .env.example
│   └── README.md
│
├── lib/
│   ├── services/
│   │   ├── api_client.dart            # NEW - Centralized API client
│   │   ├── auth_service.dart          # UPDATED - Uses backend API
│   │   ├── user_profile_service.dart  # UPDATED - Uses backend API
│   │   ├── gym_service.dart           # UPDATED - Uses backend API
│   │   ├── trends_service.dart        # UPDATED - Uses backend API
│   │   └── reid_monitor_service.dart  # UPDATED - Polling instead of listeners
│   └── ...
└── ...
```

## Setup Instructions

### Backend Setup

1. **Navigate to backend directory:**
   ```bash
   cd backend
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Get Firebase Service Account Key:**
   - Go to [Firebase Console](https://console.firebase.google.com/)
   - Select your project
   - Go to Project Settings > Service Accounts
   - Click "Generate New Private Key"
   - Save the JSON file as `serviceAccountKey.json` in the `backend` directory

4. **Configure environment variables:**
   ```bash
   cp .env.example .env
   ```
   
   Edit `.env` and set:
   ```env
   PORT=3000
   NODE_ENV=development
   JWT_SECRET=your-super-secret-jwt-key-change-this-in-production
   JWT_EXPIRES_IN=7d
   FIREBASE_SERVICE_ACCOUNT_PATH=./serviceAccountKey.json
   ALLOWED_ORIGINS=http://localhost:3000,http://10.0.2.2:3000
   ```

5. **Build TypeScript:**
   ```bash
   npm run build
   ```

6. **Run in development mode:**
   ```bash
   npm run dev
   ```

   Or for production:
   ```bash
   npm start
   ```

The backend will start on `http://localhost:3000`

### Flutter App Setup

1. **Update dependencies:**
   ```bash
   flutter pub get
   ```

2. **Configure API base URL:**
   
   Open `lib/services/api_client.dart` and verify the base URL:
   
   - For Android Emulator: `http://10.0.2.2:3000/api`
   - For iOS Simulator: `http://localhost:3000/api`
   - For Real Device: `http://YOUR_COMPUTER_IP:3000/api`
   - For Production: `https://your-api-domain.com/api`

3. **Update Android network security (if needed):**
   
   Create/update `android/app/src/main/res/xml/network_security_config.xml`:
   ```xml
   <?xml version="1.0" encoding="utf-8"?>
   <network-security-config>
       <domain-config cleartextTrafficPermitted="true">
           <domain includeSubdomains="true">10.0.2.2</domain>
           <domain includeSubdomains="true">localhost</domain>
       </domain-config>
   </network-security-config>
   ```

   Update `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <application
       android:networkSecurityConfig="@xml/network_security_config"
       ...>
   ```

4. **Run the app:**
   ```bash
   flutter run
   ```

## API Endpoints

### Authentication
- `POST /api/auth/signup-email` - Create new user
- `POST /api/auth/login-email` - Login with email/password
- `POST /api/auth/google` - Google authentication

### User Profile
- `POST /api/user/profile` - Save/update profile
- `GET /api/user/profile/:userId` - Get profile
- `GET /api/user/profile-status/:userId` - Check if profile is completed
- `GET /api/user/status/:userId` - Get user status
- `POST /api/user/initialize` - Initialize user

### Gym Management
- `GET /api/gym/validate/:gymId` - Validate gym ID
- `POST /api/gym/upload-proof` - Upload proof image
- `POST /api/gym/associate` - Associate user with gym
- `GET /api/gym/user-gyms/:userId` - Get user's gyms
- `GET /api/gym/details/:organizationId/:gymId` - Get gym details

### Trends & Analytics
- `GET /api/trends/all/:userId` - Get all trends data
- `GET /api/trends/sessions/:userId` - Get session history
- `GET /api/trends/workouts/:userId` - Get workout data

### Session Management
- `GET /api/session/:sessionId` - Get session by ID
- `GET /api/session/by-session-id/:sessionId` - Get session by sessionId field
- `GET /api/session/user/:userId/active` - Get active session
- `PATCH /api/session/:sessionId/reid-status` - Update reid status
- `PATCH /api/session/:sessionId/status` - Update session status

## Testing the Backend

```bash
# Health check
curl http://localhost:3000/health

# Signup
curl -X POST http://localhost:3000/api/auth/signup-email \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123","username":"testuser"}'

# Login
curl -X POST http://localhost:3000/api/auth/login-email \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'
```

## Migration Checklist

### Completed ✅

- [x] Backend API server structure
- [x] Firebase Admin SDK integration
- [x] JWT authentication middleware
- [x] Authentication endpoints (signup, login, Google)
- [x] User profile endpoints
- [x] Gym management endpoints
- [x] Trends/analytics endpoints
- [x] Session management endpoints
- [x] Flutter API client service
- [x] Updated auth_service.dart
- [x] Updated user_profile_service.dart
- [x] Updated gym_service.dart
- [x] Updated trends_service.dart
- [x] Updated reid_monitor_service.dart (polling-based)

### Remaining TODO ⏳

- [ ] Update profile_page.dart to use API client instead of direct Firestore
- [ ] Update any other views with direct Firestore calls
- [ ] Remove `cloud_firestore` dependency from Flutter pubspec.yaml (optional)
- [ ] Remove Firebase configuration from Flutter app security rules
- [ ] Add error handling and retry logic in API client
- [ ] Add request/response logging for debugging
- [ ] Implement rate limiting on backend
- [ ] Add API versioning
- [ ] Set up backend deployment (Cloud Run, App Engine, etc.)
- [ ] Configure production environment variables
- [ ] Set up SSL/HTTPS for production
- [ ] Implement WebSocket for real-time reid monitoring (optional improvement)

## Important Notes

### Real-time Monitoring

The `reid_monitor_service.dart` now uses **polling** (checks every 3 seconds) instead of Firestore real-time listeners. For production, consider:

1. **WebSocket implementation** for true real-time updates
2. **Server-Sent Events (SSE)** as an alternative
3. **Adjusting polling interval** based on requirements

### Firebase Storage

File uploads (gym proof images) still go through the backend but use Firebase Storage. The backend:
1. Receives the file from Flutter
2. Uploads to Firebase Storage
3. Returns the download URL

### Authentication

The app now uses **dual authentication**:
1. **Firebase Auth** - For Google Sign-In and user management
2. **JWT tokens** - For backend API authentication

Both tokens are stored and used appropriately.

## Troubleshooting

### "Connection refused" error
- Ensure backend is running on port 3000
- Check firewall settings
- Verify the correct IP address for your device

### "Unauthorized" errors
- Check if JWT token is being sent in headers
- Verify JWT_SECRET is the same in backend .env
- Token might be expired (default 7 days)

### Backend crashes on startup
- Ensure `serviceAccountKey.json` exists
- Verify Firebase project credentials
- Check Node.js version (requires >= 18.0.0)

### CORS errors
- Add your origin to ALLOWED_ORIGINS in .env
- Check CORS middleware configuration in server.ts

## Production Deployment

### Backend Deployment Options

1. **Google Cloud Run** (Recommended)
2. **Google App Engine**
3. **Heroku**
4. **AWS Elastic Beanstalk**
5. **DigitalOcean App Platform**

### Pre-deployment Checklist

- [ ] Change JWT_SECRET to a strong random string
- [ ] Set NODE_ENV=production
- [ ] Configure production ALLOWED_ORIGINS
- [ ] Set up SSL certificate
- [ ] Enable request rate limiting
- [ ] Set up monitoring and logging
- [ ] Configure automatic backups
- [ ] Test all endpoints in staging environment

## Support

For issues or questions:
1. Check the backend logs in `backend/` directory
2. Review Flutter debug console output
3. Test API endpoints with curl or Postman
4. Verify Firebase service account permissions

---

**Migration completed on**: 2026-03-06
**Architecture version**: 2.0
