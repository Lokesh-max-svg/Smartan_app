# Prompt for Second Claude Code Instance

Copy and paste this to the second Claude Code session:

---

## Task: Integrate Django Server with Firebase Pub/Sub for Workout Session Notifications

### Context

I have a Flutter fitness app with Firebase backend. When users create workout sessions, a Cloud Function publishes notifications to Google Cloud Pub/Sub. I need to set up a Django server (running on Raspberry Pi or separate PC) to:

1. **Subscribe to Pub/Sub topic** `session-created`
2. **Receive session notifications** with JSON data (sessionId, gymId, userId, exercises)
3. **Load 40 face recognition embedding files** (.bin format) for the gym
4. **Process embeddings** and prepare for face recognition
5. **Update Firestore** to mark session as "Active" when ready

### What's Already Done

✅ Firebase Cloud Function `notifySessionCreated` deployed and working
✅ Publishing messages to Pub/Sub topic `session-created` when sessions created
✅ Python subscriber script template created (`raspberry_pi_subscriber.py`)
✅ Complete documentation written

### Message Format Received from Pub/Sub

```json
{
  "sessionId": "abc123xyz",
  "gymId": "gym_001",
  "userId": "user_456",
  "status": "pending",
  "exercises": [...],
  "createdAt": "2026-01-29T12:00:00.000Z",
  "embeddingsPath": "gyms/gym_001/embeddings/"
}
```

### What Needs to Be Done

**Task 1:** Set up Google Cloud Pub/Sub
- Create topic: `session-created`
- Create subscription: `session-created-sub`
- Project ID: `smartan-fitness`

**Task 2:** Configure Django Server
- Install: `google-cloud-pubsub`, `google-cloud-firestore`, `google-cloud-storage`
- Set up Firebase service account authentication
- Create Pub/Sub subscriber (Django management command or standalone script)

**Task 3:** Implement Processing Logic
- Receive Pub/Sub messages
- Load 40 .bin embedding files from local cache or Firebase Storage
- Structure: `/embeddings/gym_001/member_001.bin` ... `member_040.bin`
- Integrate with existing face recognition model

**Task 4:** Update Firestore After Processing
```python
db.collection('sessions').document(session_id).update({
    'status': 'Active',
    'pi_ready': True,
    'embeddings_loaded': 40,
    'pi_updated_at': firestore.SERVER_TIMESTAMP
})
```

**Task 5:** Run as System Service
- Create systemd service or run as Django management command
- Ensure auto-restart on failure
- Add logging and error handling

### Files Available

I have these files ready with complete implementation:
1. `raspberry_pi_subscriber.py` - Working Python Pub/Sub subscriber
2. `PUBSUB_SETUP.md` - Complete setup guide with all commands
3. `DJANGO_INTEGRATION_HANDOFF.md` - Detailed integration specs

### Environment Details

- **Firebase Project:** smartan-fitness
- **Pub/Sub Topic:** session-created
- **Subscription:** session-created-sub (to be created)
- **Firestore Collection:** sessions
- **Embeddings:** 40 .bin files per gym
- **Server:** Raspberry Pi or Ubuntu PC with Django

### Expected Workflow

```
Flutter App creates session
    ↓
Firestore document created
    ↓
Cloud Function triggers (already working ✅)
    ↓
Pub/Sub message published (already working ✅)
    ↓
Django server receives notification (NEED TO BUILD)
    ↓
Load 40 embedding .bin files (NEED TO BUILD)
    ↓
Update Firestore status to "Active" (NEED TO BUILD)
```

### Success Criteria

- Django receives real-time notifications when sessions are created
- Loads embeddings in < 2 seconds
- Updates Firestore successfully
- Runs reliably as background service
- Handles errors gracefully

### Questions for You

1. Should we integrate this as a Django management command or standalone Python script?
2. Where will the 40 .bin files be stored? (Local cache vs Firebase Storage)
3. Do you have existing face recognition code to integrate with?
4. What's the server environment? (Raspberry Pi, Ubuntu server, etc.)

Please help me:
1. Set up the Pub/Sub subscription
2. Create the Django subscriber implementation
3. Integrate with embedding loading
4. Configure as a system service

Let me know if you need any of the reference files I mentioned above!

---

**Start by helping me create the Pub/Sub topic and subscription, then we'll build the Django subscriber.**
