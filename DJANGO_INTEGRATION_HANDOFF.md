# Django/Raspberry Pi Integration - Setup Summary

## 🎯 Project Overview

**Goal:** Integrate Django server (on Raspberry Pi or separate PC) to receive real-time notifications when users create workout sessions in the Flutter app, process face recognition embeddings, and update session status.

---

## ✅ What's Already Done (Firebase/Flutter Side)

### 1. **Firebase Cloud Function - `notifySessionCreated`**
- **Location:** Deployed to Firebase Cloud Functions (us-central1)
- **Trigger:** Automatically runs when a new document is created in Firestore `sessions` collection
- **Action:** Publishes session details to Google Cloud Pub/Sub topic `session-created`
- **Status:** ✅ **DEPLOYED AND LIVE**

### 2. **Message Format Being Sent**
When a user creates a session in the Flutter app, this JSON message is published to Pub/Sub:

```json
{
  "sessionId": "abc123xyz",
  "gymId": "gym_001",
  "userId": "user_456",
  "status": "pending",
  "exercises": [
    {
      "name": "Bench Press",
      "reps": 12,
      "sets": 3,
      "current_reps": 0,
      "completed": false
    }
  ],
  "createdAt": "2026-01-29T12:00:00.000Z",
  "embeddingsPath": "gyms/gym_001/embeddings/"
}
```

### 3. **Firebase Project Details**
- **Project ID:** `smartan-fitness`
- **Firestore Collection:** `sessions`
- **Pub/Sub Topic:** `session-created` (needs to be created)
- **Subscription:** `session-created-sub` (needs to be created)

---

## 🚀 What Needs to Be Done (Django/Pi Side)

### Architecture Flow

```
Flutter App → Firestore → Cloud Function → Pub/Sub → Django Server
                                                          ↓
                                                    Load 40 .bin files
                                                          ↓
                                                    Process embeddings
                                                          ↓
                                                    Update Firestore
                                                          ↓
                                              Session status: "Active"
```

### Tasks for Django/Raspberry Pi Setup

#### **Task 1: Create Pub/Sub Topic & Subscription**
```bash
# Run from your Google Cloud Shell or local machine with gcloud CLI
gcloud pubsub topics create session-created --project=smartan-fitness

gcloud pubsub subscriptions create session-created-sub \
  --topic=session-created \
  --project=smartan-fitness \
  --ack-deadline=60
```

#### **Task 2: Set Up Service Account Authentication**
1. Go to [Firebase Console](https://console.firebase.google.com/project/smartan-fitness/settings/serviceaccounts/adminsdk)
2. Click "Generate New Private Key"
3. Download JSON file (e.g., `smartan-fitness-firebase-adminsdk.json`)
4. Copy to Django server at: `/path/to/service-account.json`
5. Set environment variable:
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
   ```

#### **Task 3: Install Python Dependencies**
```bash
pip3 install google-cloud-pubsub google-cloud-firestore google-cloud-storage
```

#### **Task 4: Implement Pub/Sub Subscriber**

**Option A: Use Provided Python Script**
- File: `raspberry_pi_subscriber.py` (already created in Flutter project)
- Copy to Django server and run: `python3 raspberry_pi_subscriber.py`

**Option B: Integrate into Django**
- Create a Django management command
- Run as background service
- Integrate with existing face recognition pipeline

---

## 📂 Files Available for Django Server

### 1. **`raspberry_pi_subscriber.py`** (Python Pub/Sub Listener)
**Location:** `/home/karthi/StudioProjects/smartan_fitness/raspberry_pi_subscriber.py`

**What it does:**
- Subscribes to Pub/Sub topic `session-created`
- Receives session notifications in real-time
- Loads 40 .bin embedding files (cached locally or from Firebase Storage)
- Updates Firestore when embeddings are ready

**Key Functions:**
- `load_embeddings_for_gym(gym_id)` - Loads/downloads 40 .bin files
- `process_session(session_data)` - Main processing logic
- `callback(message)` - Pub/Sub message handler

### 2. **`PUBSUB_SETUP.md`** (Complete Setup Guide)
**Location:** `/home/karthi/StudioProjects/smartan_fitness/PUBSUB_SETUP.md`

Contains:
- Step-by-step setup instructions
- gcloud commands
- Troubleshooting tips
- Monitoring and testing procedures

### 3. **`QUICK_START_PUBSUB.md`** (Quick Reference)
**Location:** `/home/karthi/StudioProjects/smartan_fitness/QUICK_START_PUBSUB.md`

Contains:
- Quick start overview
- Testing procedures
- FAQ

---

## 🔧 Integration Points for Django

### Where to Integrate with Django

#### **Option 1: Django Management Command (Recommended)**

Create: `yourapp/management/commands/listen_sessions.py`

```python
from django.core.management.base import BaseCommand
from google.cloud import pubsub_v1
import json

class Command(BaseCommand):
    help = 'Listen for session notifications from Pub/Sub'

    def handle(self, *args, **options):
        subscriber = pubsub_v1.SubscriberClient()
        subscription_path = subscriber.subscription_path(
            'smartan-fitness',
            'session-created-sub'
        )

        def callback(message):
            data = json.loads(message.data.decode('utf-8'))
            session_id = data['sessionId']
            gym_id = data['gymId']

            # Call your existing face recognition logic
            process_workout_session(session_id, gym_id, data)

            message.ack()

        subscriber.subscribe(subscription_path, callback=callback)
        self.stdout.write('Listening for sessions...')

        # Keep running
        import time
        while True:
            time.sleep(60)
```

Run with:
```bash
python manage.py listen_sessions
```

#### **Option 2: Celery Task (For Existing Celery Setup)**

```python
from celery import shared_task
from google.cloud import firestore

@shared_task
def process_session_embeddings(session_id, gym_id):
    # Load embeddings
    embeddings = load_gym_embeddings(gym_id)

    # Your face recognition logic here
    # ...

    # Update Firestore
    db = firestore.Client()
    db.collection('sessions').document(session_id).update({
        'status': 'Active',
        'pi_ready': True,
        'embeddings_loaded': len(embeddings)
    })
```

---

## 📊 Firestore Update Requirements

### When Django Finishes Processing

Update the session document in Firestore with:

```python
from google.cloud import firestore

db = firestore.Client()
session_ref = db.collection('sessions').document(session_id)

session_ref.update({
    'status': 'Active',              # Change from "pending" to "Active"
    'pi_ready': True,                # Indicate Pi is ready
    'embeddings_loaded': 40,         # Number of embeddings loaded
    'pi_updated_at': firestore.SERVER_TIMESTAMP
})
```

**Fields to Update:**
- `status`: `"Active"` (was `"pending"`)
- `pi_ready`: `true`
- `embeddings_loaded`: Number (e.g., 40)
- `pi_updated_at`: Server timestamp

---

## 🗄️ Embedding Files Structure

### Expected Structure (40 .bin files per gym)

**Option A: Firebase Storage**
```
gs://smartan-fitness.appspot.com/
  └── gyms/
      ├── gym_001/
      │   └── embeddings/
      │       ├── member_001.bin
      │       ├── member_002.bin
      │       └── ... (40 files)
      └── gym_002/
          └── embeddings/
              └── ...
```

**Option B: Local Cache**
```
/home/pi/smartan_fitness/embeddings/
  ├── gym_001/
  │   ├── member_001.bin
  │   ├── member_002.bin
  │   └── ... (40 files)
  └── gym_002/
      └── ...
```

### Loading Logic

```python
import os

def load_gym_embeddings(gym_id):
    """Load all .bin files for a gym"""
    cache_dir = f"/home/pi/smartan_fitness/embeddings/{gym_id}"

    embeddings = []
    for filename in sorted(os.listdir(cache_dir)):
        if filename.endswith('.bin'):
            with open(os.path.join(cache_dir, filename), 'rb') as f:
                embeddings.append(f.read())

    return embeddings
```

---

## 🧪 Testing the Integration

### Test 1: Verify Pub/Sub Setup

```bash
# Publish a test message
gcloud pubsub topics publish session-created \
  --message='{"sessionId":"test123","gymId":"gym_001","userId":"user_test"}' \
  --project=smartan-fitness

# Check if subscriber receives it
```

### Test 2: Create Session in Flutter App

1. Open Flutter app
2. Create a new workout session
3. Check Django logs - should receive Pub/Sub message
4. Verify Firestore updated with `status: "Active"`

### Test 3: Monitor Cloud Function

```bash
firebase functions:log | grep notifySessionCreated
```

Should see:
```
Publishing session abc123 to Pub/Sub topic session-created
Successfully published session abc123 for gym gym_001
```

---

## 🔒 Security & Permissions

### Required IAM Roles for Service Account

The service account needs these permissions:

1. **Pub/Sub Subscriber**: `roles/pubsub.subscriber`
2. **Firestore User**: `roles/datastore.user`
3. **Storage Viewer**: `roles/storage.objectViewer` (if using Firebase Storage)

Grant permissions:
```bash
gcloud projects add-iam-policy-binding smartan-fitness \
  --member="serviceAccount:YOUR_SERVICE_ACCOUNT@smartan-fitness.iam.gserviceaccount.com" \
  --role="roles/pubsub.subscriber"

gcloud projects add-iam-policy-binding smartan-fitness \
  --member="serviceAccount:YOUR_SERVICE_ACCOUNT@smartan-fitness.iam.gserviceaccount.com" \
  --role="roles/datastore.user"
```

---

## 💡 Key Integration Points

### What Django Needs to Implement

1. ✅ **Pub/Sub Subscriber** - Listen for session notifications
2. ✅ **Load Embeddings** - Fetch 40 .bin files (cached or from storage)
3. ✅ **Face Recognition** - Process embeddings (your existing logic)
4. ✅ **Update Firestore** - Mark session as "Active" when ready
5. ⚠️ **Error Handling** - Handle missing embeddings, network errors
6. ⚠️ **Logging** - Track processing times, errors

### Django Response Flow

```python
def handle_session_notification(session_data):
    """
    Called when Pub/Sub message received

    Args:
        session_data: Dict with sessionId, gymId, userId, etc.
    """

    # 1. Extract data
    session_id = session_data['sessionId']
    gym_id = session_data['gymId']

    # 2. Load embeddings (40 .bin files)
    embeddings = load_gym_embeddings(gym_id)

    # 3. Initialize face recognition model
    # (Your existing code)

    # 4. Update Firestore
    update_session_status(session_id, 'Active', len(embeddings))

    # 5. Log success
    print(f"Session {session_id} ready with {len(embeddings)} embeddings")
```

---

## 📝 Environment Variables Needed

```bash
# Required on Django server
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
export GOOGLE_CLOUD_PROJECT="smartan-fitness"
export PUBSUB_SUBSCRIPTION="session-created-sub"
export EMBEDDINGS_CACHE_DIR="/home/pi/smartan_fitness/embeddings"
```

---

## 🆘 Common Issues & Solutions

### Issue: "Permission denied"
**Solution:** Check service account has correct IAM roles

### Issue: "Topic not found"
**Solution:** Run `gcloud pubsub topics create session-created`

### Issue: "No messages received"
**Solution:** Check Cloud Function logs, verify topic name matches

### Issue: "Embeddings not found"
**Solution:** Verify Firebase Storage structure or local cache path

---

## 📚 Documentation Files to Reference

1. **`raspberry_pi_subscriber.py`** - Complete working Python subscriber
2. **`PUBSUB_SETUP.md`** - Detailed setup guide
3. **`QUICK_START_PUBSUB.md`** - Quick reference
4. **This file** - Integration summary

---

## 🎯 Success Criteria

Your Django integration is successful when:

1. ✅ Receives Pub/Sub messages when sessions are created
2. ✅ Loads 40 .bin embedding files (< 2 seconds)
3. ✅ Updates Firestore session status to "Active"
4. ✅ Handles errors gracefully (missing files, network issues)
5. ✅ Runs as system service (restarts on failure)

---

## 🚀 Quick Start Commands

```bash
# 1. Create Pub/Sub resources
gcloud pubsub topics create session-created --project=smartan-fitness
gcloud pubsub subscriptions create session-created-sub \
  --topic=session-created --project=smartan-fitness

# 2. Install dependencies
pip3 install google-cloud-pubsub google-cloud-firestore google-cloud-storage

# 3. Set credentials
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"

# 4. Run subscriber
python3 raspberry_pi_subscriber.py

# Or integrate into Django
python manage.py listen_sessions
```

---

## 📞 Contact & Support

**Firebase Project:** https://console.firebase.google.com/project/smartan-fitness

**Cloud Function Status:**
```bash
firebase functions:log | grep notifySessionCreated
```

**Pub/Sub Monitoring:**
Google Cloud Console → Pub/Sub → Topics → session-created

---

## 📦 Files to Copy to Second PC

1. `raspberry_pi_subscriber.py` - Main subscriber script
2. `PUBSUB_SETUP.md` - Setup guide
3. `service-account.json` - Firebase credentials (download from console)
4. This handoff document

---

**Ready to integrate? Start with Step 1: Create Pub/Sub Topic!** 🚀
