#!/bin/bash

# Test the Firebase Cloud Function
echo "Triggering updateCompletedStatus function..."

# Use Firebase Functions emulator or call via HTTP
firebase functions:shell <<EOF
updateCompletedStatus()
EOF

echo "Check logs with: firebase functions:log --limit 20"
