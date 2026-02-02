# Pub/Sub Integration - Quick Start

## ✅ What's Been Implemented

### Cloud Function: `notifySessionCreated`
- **Trigger:** Automatically runs when a new document is created in `sessions` collection
- **Action:** Publishes session details to Pub/Sub topic `session-created`
- **Status:** ✅ Deployed and ready
- **Location:** `us-central1`

### Message Format
When a session is created, this JSON message is published:
```json
{
  "sessionId": "abc123",
  "gymId": "gym_001",
  "userId": "user_456",
  "status": "pending",
  "exercises": [...],
  "createdAt": "2026-01-29T12:00:00Z",
  "embeddingsPath": "gyms/gym_001/embeddings/"
}
```

---

## 🚀 Next Steps to Complete Setup

### 1. Create Pub/Sub Topic & Subscription

Run these commands on your local machine or Cloud Shell:

```bash
# Create topic
gcloud pubsub topics create session-created --project=smartan-fitness

# Create subscription for your Raspberry Pi
gcloud pubsub subscriptions create session-created-sub \
  --topic=session-created \
  --project=smartan-fitness \
  --ack-deadline=60
```

### 2. Set Up Raspberry Pi

**Install dependencies:**
```bash
pip3 install google-cloud-pubsub google-cloud-firestore google-cloud-storage
```

**Get service account key:**
1. Go to Firebase Console → Project Settings → Service Accounts
2. Click "Generate New Private Key"
3. Download and copy to Pi: `/home/pi/smartan_fitness/service-account.json`

**Set environment variable:**
```bash
export GOOGLE_APPLICATION_CREDENTIALS="/home/pi/smartan_fitness/service-account.json"
```

### 3. Run the Subscriber

Copy `raspberry_pi_subscriber.py` to your Pi and run:

```bash
python3 raspberry_pi_subscriber.py
```

You'll see:
```
🚀 Starting Pub/Sub subscriber...
Listening for session notifications...
```

---

## 🧪 Testing

### Test the Cloud Function

Create a session in your Flutter app and check logs:

```bash
firebase functions:log | grep notifySessionCreated
```

You should see:
```
Publishing session abc123 to Pub/Sub topic session-created
Successfully published session abc123 for gym gym_001
```

### Test the Full Flow

1. **Create session in Flutter app**
2. **Cloud Function publishes to Pub/Sub** (check logs above)
3. **Raspberry Pi receives message** (check Pi console)
4. **Pi loads embeddings and updates Firestore**
5. **Session status changes to "Active"**

---

## 📊 Current Architecture

```
Flutter App (User creates session)
    ↓
Firestore (sessions collection)
    ↓
Cloud Function (notifySessionCreated) [✅ DEPLOYED]
    ↓
Pub/Sub Topic (session-created) [⏳ TO BE CREATED]
    ↓
Pub/Sub Subscription (session-created-sub) [⏳ TO BE CREATED]
    ↓
Raspberry Pi Subscriber [⏳ TO BE SET UP]
    ↓
Loads Embeddings (40 .bin files)
    ↓
Updates Firestore (status: "Active", pi_ready: true)
```

---

## 🔧 Customization

### Modify what data is sent

Edit `/functions/src/index.ts` at line ~185:

```typescript
const message = {
  sessionId: sessionId,
  gymId: sessionData.gymId || "",
  userId: sessionData.userId || "",
  // Add your custom fields here
  custom_field: sessionData.your_field,
};
```

Then redeploy:
```bash
firebase deploy --only functions:notifySessionCreated
```

### Change topic name

Edit line 165 in `functions/src/index.ts`:
```typescript
const SESSION_TOPIC = "your-custom-topic-name";
```

---

## 📝 Files Created

1. **`/functions/src/index.ts`** - Added `notifySessionCreated` function
2. **`raspberry_pi_subscriber.py`** - Python subscriber for Raspberry Pi
3. **`PUBSUB_SETUP.md`** - Complete setup documentation
4. **`QUICK_START_PUBSUB.md`** - This file

---

## ❓ FAQ

**Q: Do I need to modify my Flutter app?**
A: No changes needed! The Cloud Function triggers automatically when you create a session.

**Q: What if I have multiple gyms?**
A: The `gymId` is included in the message. Your Pi subscriber can filter or cache embeddings per gym.

**Q: What if Raspberry Pi is offline when session is created?**
A: Pub/Sub will retain messages for up to 7 days. When Pi comes online, it will process queued messages.

**Q: How do I handle 40 .bin files?**
A: The Python subscriber has caching logic. First time: downloads from Firebase Storage. After: loads from local cache.

**Q: Can I test without Raspberry Pi?**
A: Yes! Run the Python subscriber on your local machine with the same setup.

---

## 💰 Cost

- **Pub/Sub:** FREE (within free tier for typical usage)
- **Cloud Functions:** ~$0.40/month (includes 2 million invocations free)
- **Firestore:** Existing usage
- **Total new cost:** < $1/month

---

## 🆘 Need Help?

See detailed documentation in `PUBSUB_SETUP.md` or:

1. Check Cloud Function logs: `firebase functions:log`
2. Check Pub/Sub metrics: Google Cloud Console → Pub/Sub
3. Test with manual message: `gcloud pubsub topics publish session-created --message='{"test":"data"}'`
