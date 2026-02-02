# Pub/Sub Setup Guide for Raspberry Pi / Django Server

## Overview

This system uses Google Cloud Pub/Sub to notify your Raspberry Pi/Django server when a new workout session is created in the Flutter app.

**Flow:**
1. User creates session in Flutter app
2. Firestore document created in `sessions` collection
3. Cloud Function (`notifySessionCreated`) triggers automatically
4. Message published to Pub/Sub topic `session-created`
5. Raspberry Pi subscribes and receives notification
6. Pi loads embeddings and updates session status to "Active"

---

## Prerequisites

- Google Cloud Project: `smartan-fitness`
- Firebase Admin SDK credentials
- Raspberry Pi with Python 3.7+
- Embeddings stored in Firebase Storage or locally

---

## Step 1: Create Pub/Sub Topic (One-time setup)

```bash
# Enable Pub/Sub API (if not already enabled)
gcloud services enable pubsub.googleapis.com --project=smartan-fitness

# Create the topic
gcloud pubsub topics create session-created --project=smartan-fitness

# Verify topic created
gcloud pubsub topics list --project=smartan-fitness
```

---

## Step 2: Create Subscription for Raspberry Pi

```bash
# Create a subscription
gcloud pubsub subscriptions create session-created-sub \
  --topic=session-created \
  --project=smartan-fitness \
  --ack-deadline=60

# Verify subscription created
gcloud pubsub subscriptions list --project=smartan-fitness
```

---

## Step 3: Set Up Service Account

### Option A: Use Firebase Admin SDK (Recommended)

1. Go to Firebase Console → Project Settings → Service Accounts
2. Click "Generate New Private Key"
3. Download JSON file (e.g., `smartan-fitness-firebase-adminsdk.json`)
4. Copy to Raspberry Pi at `/home/pi/smartan_fitness/service-account.json`

### Option B: Create Dedicated Service Account

```bash
# Create service account
gcloud iam service-accounts create raspberry-pi-subscriber \
  --display-name="Raspberry Pi Pub/Sub Subscriber" \
  --project=smartan-fitness

# Grant necessary permissions
gcloud projects add-iam-policy-binding smartan-fitness \
  --member="serviceAccount:raspberry-pi-subscriber@smartan-fitness.iam.gserviceaccount.com" \
  --role="roles/pubsub.subscriber"

gcloud projects add-iam-policy-binding smartan-fitness \
  --member="serviceAccount:raspberry-pi-subscriber@smartan-fitness.iam.gserviceaccount.com" \
  --role="roles/datastore.user"

gcloud projects add-iam-policy-binding smartan-fitness \
  --member="serviceAccount:raspberry-pi-subscriber@smartan-fitness.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

# Download key
gcloud iam service-accounts keys create ~/raspberry-pi-key.json \
  --iam-account=raspberry-pi-subscriber@smartan-fitness.iam.gserviceaccount.com
```

---

## Step 4: Install Python Dependencies on Raspberry Pi

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Python packages
pip3 install google-cloud-pubsub google-cloud-firestore google-cloud-storage

# Or use requirements.txt
cat > requirements.txt << EOF
google-cloud-pubsub==2.21.1
google-cloud-firestore==2.16.0
google-cloud-storage==2.16.0
EOF

pip3 install -r requirements.txt
```

---

## Step 5: Configure Raspberry Pi

```bash
# Set environment variable for service account
export GOOGLE_APPLICATION_CREDENTIALS="/home/pi/smartan_fitness/service-account.json"

# Add to ~/.bashrc for persistence
echo 'export GOOGLE_APPLICATION_CREDENTIALS="/home/pi/smartan_fitness/service-account.json"' >> ~/.bashrc

# Create embeddings cache directory
mkdir -p /home/pi/smartan_fitness/embeddings
```

---

## Step 6: Copy Subscriber Script to Raspberry Pi

Copy `raspberry_pi_subscriber.py` to your Raspberry Pi:

```bash
# On your dev machine
scp raspberry_pi_subscriber.py pi@<raspberry-pi-ip>:/home/pi/smartan_fitness/

# SSH to Pi
ssh pi@<raspberry-pi-ip>
cd /home/pi/smartan_fitness
```

---

## Step 7: Run the Subscriber

```bash
# Test run
python3 raspberry_pi_subscriber.py

# You should see:
# 🚀 Starting Pub/Sub subscriber...
# Listening for session notifications...
```

### Expected Output When Session Created:

```
📨 Received message from Pub/Sub:
{
  "sessionId": "abc123xyz",
  "gymId": "gym_001",
  "userId": "user_456",
  "status": "pending",
  "exercises": [...],
  "embeddingsPath": "gyms/gym_001/embeddings/"
}

============================================================
Processing Session: abc123xyz
Gym ID: gym_001
User ID: user_456
Status: pending
Exercises: 3
============================================================

Loading embeddings from cache: /home/pi/smartan_fitness/embeddings/gym_001
Loaded 40 embeddings from cache
✅ Session abc123xyz ready with 40 embeddings
✅ Message acknowledged
```

---

## Step 8: Run as System Service (Production)

Create a systemd service file:

```bash
sudo nano /etc/systemd/system/session-subscriber.service
```

Paste this content:

```ini
[Unit]
Description=Smartan Fitness Session Subscriber
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/smartan_fitness
Environment="GOOGLE_APPLICATION_CREDENTIALS=/home/pi/smartan_fitness/service-account.json"
ExecStart=/usr/bin/python3 /home/pi/smartan_fitness/raspberry_pi_subscriber.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable session-subscriber

# Start service
sudo systemctl start session-subscriber

# Check status
sudo systemctl status session-subscriber

# View logs
sudo journalctl -u session-subscriber -f
```

---

## Testing the Integration

### Test 1: Verify Pub/Sub Setup

```bash
# Publish a test message
gcloud pubsub topics publish session-created \
  --message='{"sessionId":"test123","gymId":"gym_001","userId":"user_test"}' \
  --project=smartan-fitness
```

Check Raspberry Pi logs - you should see the message received.

### Test 2: Create Session in Flutter App

1. Open Flutter app
2. Create a new workout session
3. Check Cloud Function logs:
   ```bash
   firebase functions:log | grep notifySessionCreated
   ```
4. Check Raspberry Pi logs - should receive notification

---

## Troubleshooting

### Issue: No messages received

**Check subscription:**
```bash
gcloud pubsub subscriptions describe session-created-sub --project=smartan-fitness
```

**Pull messages manually:**
```bash
gcloud pubsub subscriptions pull session-created-sub --auto-ack --project=smartan-fitness
```

### Issue: Permission denied

**Check service account has correct roles:**
- `roles/pubsub.subscriber`
- `roles/datastore.user`
- `roles/storage.objectViewer`

### Issue: Embeddings not found

**Verify Firebase Storage structure:**
```
gs://smartan-fitness.appspot.com/
  └── gyms/
      └── gym_001/
          └── embeddings/
              ├── member_001.bin
              ├── member_002.bin
              └── ...
```

---

## Monitoring

### View Pub/Sub Metrics

Firebase Console → Cloud Functions → notifySessionCreated → Logs

Google Cloud Console → Pub/Sub → Topics → session-created → Metrics

### Check Subscription Backlog

```bash
gcloud pubsub subscriptions describe session-created-sub \
  --project=smartan-fitness \
  --format="value(messageRetentionDuration, numUndeliveredMessages)"
```

---

## Cost Estimates

**Pub/Sub Pricing (as of 2026):**
- First 10 GB/month: Free
- Each message < 1 KB
- ~1,000 sessions/day = ~1 MB/day = ~30 MB/month
- **Cost: FREE** (well within free tier)

**Firestore Reads:**
- Subscriber updates 1 document per session
- ~1,000 updates/day = ~30,000 reads/month
- **Cost: ~$0.18/month**

**Total estimated cost: ~$0.20/month**

---

## Next Steps

1. ✅ Deploy Cloud Function
2. ✅ Create Pub/Sub topic
3. ✅ Create subscription
4. ✅ Set up Raspberry Pi
5. ✅ Run subscriber
6. 🔄 Integrate face recognition model
7. 🔄 Handle multiple gyms (if needed)
8. 🔄 Add error handling and retries
9. 🔄 Monitor and optimize

---

## Questions?

- Check Firebase Functions logs: `firebase functions:log`
- Check Pub/Sub metrics: Google Cloud Console
- Test with manual message publishing
