# Smartan Fitness Backend API

This is the backend middleware for the Smartan Fitness application. It provides a RESTful API that sits between the Flutter mobile app and Firebase Firestore, handling authentication, data validation, and business logic.

## Architecture

```
Flutter App --> Backend API (Express/Node.js) --> Firebase Firestore
```

### Benefits of this architecture:
- **Security**: Client doesn't have direct database access
- **Validation**: All data is validated before reaching Firestore
- **Business Logic**: Centralized logic makes maintenance easier
- **API Control**: Easy to rate limit, monitor, and version
- **Testing**: Easier to test backend logic independently

## Prerequisites

- Node.js >= 18.0.0
- Firebase project with Admin SDK credentials
- npm or yarn

## Setup

1. **Install dependencies:**
   ```bash
   cd backend
   npm install
   ```

2. **Configure environment variables:**
   ```bash
   cp .env.example .env
   ```
   
   Edit `.env` and set:
   - `JWT_SECRET`: A secure random string for JWT token generation
   - `FIREBASE_SERVICE_ACCOUNT_PATH`: Path to your Firebase service account JSON file

3. **Get Firebase Service Account Key:**
   - Go to Firebase Console > Project Settings > Service Accounts
   - Click "Generate New Private Key"
   - Save the JSON file as `serviceAccountKey.json` in the backend directory

4. **Build the TypeScript code:**
   ```bash
   npm run build
   ```

## Development

Run the server in development mode with auto-reload:

```bash
npm run dev
```

## Production

Build and run in production:

```bash
npm run build
npm start
```

## API Endpoints

### Authentication
- `POST /api/auth/signup-email` - Create new user with email/password
- `POST /api/auth/login-email` - Login with email/password
- `POST /api/auth/google` - Authenticate with Google

### User Profile
- `POST /api/user/profile` - Save/update user profile
- `GET /api/user/profile/:userId` - Get user profile
- `GET /api/user/profile-status/:userId` - Check if profile is completed
- `GET /api/user/status/:userId` - Get user status
- `POST /api/user/initialize` - Initialize user with defaults

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

## Testing

Test the API with curl:

```bash
# Health check
curl http://localhost:3000/health

# Signup
curl -X POST http://localhost:3000/api/auth/signup-email \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123","username":"testuser"}'
```

## Docker Support (Optional)

You can also run the backend in Docker:

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY dist ./dist
COPY serviceAccountKey.json ./
ENV NODE_ENV=production
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

## Security Notes

- Always use HTTPS in production
- Keep `JWT_SECRET` and `serviceAccountKey.json` secure
- Never commit sensitive credentials to version control
- Implement rate limiting for production
- Use environment-specific configurations

## License

ISC
