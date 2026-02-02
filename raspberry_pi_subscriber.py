"""
Raspberry Pi / Django Server - Pub/Sub Subscriber
Listens for new session notifications from Firebase and processes embeddings.
"""

import json
import os
from concurrent.futures import TimeoutError
from google.cloud import pubsub_v1, firestore, storage

# Configuration
PROJECT_ID = "smartan-fitness"
SUBSCRIPTION_ID = "session-created-sub"  # You'll create this subscription
EMBEDDINGS_CACHE_DIR = "/home/pi/smartan_fitness/embeddings/"  # Adjust path

# Initialize Firebase Admin
db = firestore.Client()
storage_client = storage.Client()
bucket = storage_client.bucket(f"{PROJECT_ID}.appspot.com")


def load_embeddings_for_gym(gym_id):
    """
    Load embedding .bin files for a specific gym.
    Returns list of embedding data ready for face recognition.
    """
    cache_path = os.path.join(EMBEDDINGS_CACHE_DIR, gym_id)

    # Check if cached locally
    if os.path.exists(cache_path):
        print(f"Loading embeddings from cache: {cache_path}")
        embeddings = []
        for filename in sorted(os.listdir(cache_path)):
            if filename.endswith('.bin'):
                filepath = os.path.join(cache_path, filename)
                with open(filepath, 'rb') as f:
                    embeddings.append(f.read())
        print(f"Loaded {len(embeddings)} embeddings from cache")
        return embeddings

    # Download from Firebase Storage if not cached
    print(f"Downloading embeddings for gym {gym_id} from Firebase Storage")
    os.makedirs(cache_path, exist_ok=True)

    # Download all .bin files from storage
    blobs = bucket.list_blobs(prefix=f"gyms/{gym_id}/embeddings/")
    embeddings = []

    for blob in blobs:
        if blob.name.endswith('.bin'):
            local_filename = os.path.join(cache_path, os.path.basename(blob.name))
            blob.download_to_filename(local_filename)
            with open(local_filename, 'rb') as f:
                embeddings.append(f.read())
            print(f"Downloaded: {blob.name}")

    print(f"Downloaded {len(embeddings)} embeddings")
    return embeddings


def process_session(session_data):
    """
    Process a new session: load embeddings and update Firestore status.

    Args:
        session_data: Dictionary containing session information
    """
    session_id = session_data.get('sessionId')
    gym_id = session_data.get('gymId')
    user_id = session_data.get('userId')

    print(f"\n{'='*60}")
    print(f"Processing Session: {session_id}")
    print(f"Gym ID: {gym_id}")
    print(f"User ID: {user_id}")
    print(f"Status: {session_data.get('status')}")
    print(f"Exercises: {len(session_data.get('exercises', []))}")
    print(f"{'='*60}\n")

    try:
        # Load embeddings for this gym
        embeddings = load_embeddings_for_gym(gym_id)

        if not embeddings:
            print(f"WARNING: No embeddings found for gym {gym_id}")
            db.collection('sessions').document(session_id).update({
                'pi_status': 'error',
                'pi_error': 'No embeddings found for gym'
            })
            return

        # TODO: Integrate with your face recognition model here
        # Example: compare frames against embeddings
        # recognized_user = face_recognition_model.recognize(frame, embeddings)

        # Update Firestore: Pi is ready
        db.collection('sessions').document(session_id).update({
            'status': 'Active',
            'pi_ready': True,
            'embeddings_loaded': len(embeddings),
            'pi_updated_at': firestore.SERVER_TIMESTAMP
        })

        print(f"✅ Session {session_id} ready with {len(embeddings)} embeddings")

    except Exception as e:
        print(f"❌ Error processing session {session_id}: {e}")
        db.collection('sessions').document(session_id).update({
            'pi_status': 'error',
            'pi_error': str(e)
        })


def callback(message: pubsub_v1.subscriber.message.Message) -> None:
    """
    Callback function when a Pub/Sub message is received.
    """
    try:
        # Parse message data
        data = json.loads(message.data.decode('utf-8'))
        print(f"\n📨 Received message from Pub/Sub:")
        print(json.dumps(data, indent=2))

        # Process the session
        process_session(data)

        # Acknowledge the message
        message.ack()
        print(f"✅ Message acknowledged")

    except Exception as e:
        print(f"❌ Error processing message: {e}")
        message.nack()  # Negative acknowledgment - message will be redelivered


def main():
    """
    Main function to start the Pub/Sub subscriber.
    """
    subscriber = pubsub_v1.SubscriberClient()
    subscription_path = subscriber.subscription_path(PROJECT_ID, SUBSCRIPTION_ID)

    print(f"🚀 Starting Pub/Sub subscriber...")
    print(f"Project: {PROJECT_ID}")
    print(f"Subscription: {subscription_path}")
    print(f"Embeddings cache: {EMBEDDINGS_CACHE_DIR}")
    print(f"\nListening for session notifications...\n")

    # Create directory if it doesn't exist
    os.makedirs(EMBEDDINGS_CACHE_DIR, exist_ok=True)

    streaming_pull_future = subscriber.subscribe(
        subscription_path,
        callback=callback
    )

    print(f"Subscriber is running. Press Ctrl+C to stop.\n")

    # Keep the subscriber running
    with subscriber:
        try:
            streaming_pull_future.result()
        except TimeoutError:
            streaming_pull_future.cancel()
            streaming_pull_future.result()
        except KeyboardInterrupt:
            print("\n\n🛑 Stopping subscriber...")
            streaming_pull_future.cancel()


if __name__ == "__main__":
    main()
