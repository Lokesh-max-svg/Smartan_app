import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutTrackingPage extends StatefulWidget {
  final String sessionId;
  final String sessionDocId;

  const WorkoutTrackingPage({
    super.key,
    required this.sessionId,
    required this.sessionDocId,
  });

  @override
  State<WorkoutTrackingPage> createState() => _WorkoutTrackingPageState();
}

class _WorkoutTrackingPageState extends State<WorkoutTrackingPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? currentWorkout;
  List<Map<String, dynamic>> sessions = [];
  bool isLoading = true;
  Timer? _dataRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startDataRefresh();
  }

  @override
  void dispose() {
    _dataRefreshTimer?.cancel();
    super.dispose();
  }

  void _startDataRefresh() {
    _dataRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadCurrentWorkout(),
      _loadSessions(),
    ]);
    setState(() {
      isLoading = false;
    });
  }

  Future<void> _loadCurrentWorkout() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      debugPrint('Loading current workout for user: ${currentUser.uid}');

      // Query without orderBy to avoid composite index requirement
      final snapshot = await _firestore
          .collection('current_workout')
          .where('user_id', isEqualTo: currentUser.uid)
          .get();

      if (snapshot.docs.isNotEmpty) {
        // Sort by date in Dart to get the most recent
        final sortedDocs = snapshot.docs.toList();
        sortedDocs.sort((a, b) {
          final aDate = a.data()['date'] as Timestamp?;
          final bDate = b.data()['date'] as Timestamp?;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate); // Descending order (newest first)
        });

        final doc = sortedDocs.first;
        final workoutData = doc.data();
        final exerciseName = workoutData['exercise_name'];

        // Get the session document first to get session ID and exercises
        final sessionDoc = await _firestore
            .collection('sessions')
            .doc(widget.sessionDocId)
            .get();

        int targetReps = workoutData['reps'] ?? 0;
        int totalCurrentReps = 0;

        if (sessionDoc.exists) {
          final sessionData = sessionDoc.data();
          final exercises = sessionData?['exercises'] as List? ?? [];
          final sessionId = sessionData?['sessionId'] as String?;

          // Sum current_reps from current_workout entries ONLY for this session
          // Filter by session_id field in current_workout collection
          if (sessionId != null) {
            for (var workoutDoc in snapshot.docs) {
              final data = workoutDoc.data();
              final workoutSessionId = data['session_id'] as String?;

              // Only count reps from entries with matching session_id
              if (data['exercise_name'] == exerciseName &&
                  workoutSessionId == sessionId) {
                totalCurrentReps += (data['reps'] as int? ?? 0);
              }
            }
          }

          debugPrint('Total current reps for $exerciseName in session $sessionId: $totalCurrentReps');

          // Find matching exercise in session
          for (var exercise in exercises) {
            if (exercise['name'] == exerciseName) {
              targetReps = exercise['reps'] ?? 0;
              debugPrint('Found target reps from session: $targetReps');

              // Update the session exercise with the summed current_reps
              final updatedExercises = exercises.map((ex) {
                if (ex['name'] == exerciseName) {
                  final exReps = ex['reps'] ?? 0;
                  final isCompleted = totalCurrentReps >= exReps;
                  return {
                    ...ex,
                    'current_reps': totalCurrentReps,
                    'completed': isCompleted,
                  };
                }
                return ex;
              }).toList();

              // Update the session document
              await _firestore
                  .collection('sessions')
                  .doc(widget.sessionDocId)
                  .update({'exercises': updatedExercises});
              debugPrint('Updated session with current_reps: $totalCurrentReps');
              break;
            }
          }
        }

        // Fetch exercise image from exercises collection if not present
        String? imageUrl = workoutData['image'];
        debugPrint('Initial image from current_workout: $imageUrl');
        debugPrint('Exercise name to search: ${workoutData['exercise_name']}');

        if ((imageUrl == null || imageUrl.isEmpty) && workoutData['exercise_name'] != null) {
          try {
            final exerciseNameTrim = workoutData['exercise_name'].toString().trim();
            debugPrint('Trimmed exercise name: "$exerciseNameTrim"');

            // First try exact match
            var exerciseSnapshot = await _firestore
                .collection('exercises')
                .where('exercise_name', isEqualTo: exerciseNameTrim)
                .limit(1)
                .get();

            debugPrint('Exact match query returned ${exerciseSnapshot.docs.length} documents');

            // If no exact match, try case-insensitive search by fetching all and matching in Dart
            if (exerciseSnapshot.docs.isEmpty) {
              debugPrint('No exact match found, trying case-insensitive search...');
              final allExercises = await _firestore
                  .collection('exercises')
                  .get();

              debugPrint('Total exercises in collection: ${allExercises.docs.length}');

              // Log first few exercise names for debugging
              for (var i = 0; i < allExercises.docs.length && i < 5; i++) {
                final exData = allExercises.docs[i].data();
                debugPrint('Exercise $i: "${exData['exercise_name']}"');
              }

              if (allExercises.docs.isNotEmpty) {
                // Find matching exercise with case-insensitive and fuzzy comparison
                try {
                  // First try exact case-insensitive match
                  var matchingDoc = allExercises.docs.firstWhere(
                    (doc) {
                      final docExerciseName = doc.data()['exercise_name']?.toString().trim().toLowerCase() ?? '';
                      final searchName = exerciseNameTrim.toLowerCase();
                      final matches = docExerciseName == searchName;
                      if (matches) {
                        debugPrint('Found case-insensitive match: "$docExerciseName" == "$searchName"');
                      }
                      return matches;
                    },
                    orElse: () => throw StateError('No exact match'),
                  );

                  imageUrl = matchingDoc.data()['image'];
                  debugPrint('Fetched image from case-insensitive match: $imageUrl');
                } catch (e) {
                  debugPrint('No exact case-insensitive match: $e');

                  // Try fuzzy match (handles plural/singular differences)
                  try {
                    final searchName = exerciseNameTrim.toLowerCase();
                    final matchingDoc = allExercises.docs.firstWhere(
                      (doc) {
                        final docExerciseName = doc.data()['exercise_name']?.toString().trim().toLowerCase() ?? '';

                        // Check if one contains the other (handles plural variations)
                        final fuzzyMatch = docExerciseName.contains(searchName) ||
                                          searchName.contains(docExerciseName) ||
                                          _areSimilarNames(docExerciseName, searchName);

                        if (fuzzyMatch) {
                          debugPrint('Found fuzzy match: "$docExerciseName" ~ "$searchName"');
                        }
                        return fuzzyMatch;
                      },
                    );

                    imageUrl = matchingDoc.data()['image'];
                    debugPrint('Fetched image from fuzzy match: $imageUrl');
                  } catch (e) {
                    debugPrint('No fuzzy match found: $e');
                  }
                }
              }
            } else if (exerciseSnapshot.docs.isNotEmpty) {
              // Use the exact match result
              final exerciseData = exerciseSnapshot.docs.first.data();
              imageUrl = exerciseData['image'];
              debugPrint('Fetched image from exact match: $imageUrl');
            }

            if (imageUrl == null || imageUrl.isEmpty) {
              debugPrint('No matching exercise found in exercises collection');
            }
          } catch (e) {
            debugPrint('Error fetching exercise image: $e');
          }
        }

        setState(() {
          currentWorkout = {
            'id': doc.id,
            ...workoutData,
            'image': imageUrl, // Override with fetched image
            'current_reps': totalCurrentReps, // Summed current reps
            'reps': targetReps, // Target reps from session
          };
        });
        debugPrint('Current workout loaded: ${currentWorkout?['exercise_name']}');
        debugPrint('Current workout image URL: ${currentWorkout?['image']}');
        debugPrint('Current reps: $totalCurrentReps, Target reps: $targetReps');
      } else {
        setState(() {
          currentWorkout = null;
        });
        debugPrint('No current workout found');
      }
    } catch (e) {
      debugPrint('Error loading current workout: $e');
    }
  }

  bool _areSimilarNames(String name1, String name2) {
    // Remove common plural suffix 's' for comparison
    String normalize(String name) {
      name = name.toLowerCase().trim();
      if (name.endsWith('s') && name.length > 1) {
        return name.substring(0, name.length - 1);
      }
      return name;
    }

    final normalized1 = normalize(name1);
    final normalized2 = normalize(name2);

    return normalized1 == normalized2;
  }

  Future<void> _loadSessions() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      debugPrint('Loading sessions for user: ${currentUser.uid}');

      final snapshot = await _firestore
          .collection('sessions')
          .where('userId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'Active')
          .get();

      List<Map<String, dynamic>> loadedSessions = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        loadedSessions.add({
          'id': doc.id,
          'sessionId': data['sessionId'] ?? doc.id,
          'status': data['status'] ?? 'Active',
          'createdAt': data['createdAt'],
          'date': data['date'],
          'exercises': data['exercises'] ?? [],
        });
      }

      setState(() {
        sessions = loadedSessions;
      });

      debugPrint('Total sessions loaded: ${sessions.length}');
    } catch (e) {
      debugPrint('Error loading sessions: $e');
    }
  }

  Future<void> _endSession() async {
    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('End Session'),
          content: const Text(
            'Are you sure you want to end this workout session? This action cannot be undone.',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D4F48),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('End Session'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Get session document to calculate final stats before ending
      final sessionDoc = await _firestore
          .collection('sessions')
          .doc(widget.sessionDocId)
          .get();

      if (!sessionDoc.exists) {
        throw Exception('Session not found');
      }

      final sessionData = sessionDoc.data();
      final exercises = sessionData?['exercises'] as List? ?? [];
      final sessionId = sessionData?['sessionId'] as String?;

      if (sessionId != null && exercises.isNotEmpty) {
        // Get all current_workout entries for this user
        final currentUser = _auth.currentUser;
        if (currentUser != null) {
          final workoutSnapshot = await _firestore
              .collection('current_workout')
              .where('user_id', isEqualTo: currentUser.uid)
              .get();

          // Update each exercise with final summed current_reps
          final updatedExercises = exercises.map((exercise) {
            final exerciseName = exercise['name'];
            int totalCurrentReps = 0;

            // Sum reps from current_workout entries for this session and exercise
            for (var workoutDoc in workoutSnapshot.docs) {
              final data = workoutDoc.data();
              final workoutSessionId = data['session_id'] as String?;

              if (data['exercise_name'] == exerciseName &&
                  workoutSessionId == sessionId) {
                totalCurrentReps += (data['reps'] as int? ?? 0);
              }
            }

            final targetReps = exercise['reps'] ?? 0;
            final isCompleted = totalCurrentReps >= targetReps;

            return {
              ...exercise,
              'current_reps': totalCurrentReps,
              'completed': isCompleted,
            };
          }).toList();

          // Update session with final exercise data and mark as Completed
          await _firestore
              .collection('sessions')
              .doc(widget.sessionDocId)
              .update({
            'exercises': updatedExercises,
            'status': 'Closed',
            'endedAt': FieldValue.serverTimestamp(),
          });

          debugPrint('Session ${widget.sessionId} ended with final stats updated');
        } else {
          // No current user, just update status
          await _firestore
              .collection('sessions')
              .doc(widget.sessionDocId)
              .update({
            'status': 'Closed',
            'endedAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        // No exercises or sessionId, just update status
        await _firestore
            .collection('sessions')
            .doc(widget.sessionDocId)
            .update({
          'status': 'Closed',
          'endedAt': FieldValue.serverTimestamp(),
        });
      }

      debugPrint('Session ${widget.sessionId} ended successfully');

      if (mounted) {
        // Show closing dialog with spinner
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => PopScope(
            canPop: false,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF0D4F48)),
                  SizedBox(height: 20),
                  Text(
                    'Closing session...',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Please wait while we save your workout data',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );

        // Wait for Firestore to sync before navigating
        await Future.delayed(const Duration(seconds: 3));

        if (mounted) {
          // Close the loading dialog
          Navigator.of(context).pop();

          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session ended successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          // Navigate back
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      debugPrint('Error ending session: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error ending session: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D4F48),
        body: Center(
          child: Image.asset(
            'asset/images/loading1.gif',
            width: 200,
            height: 200,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Workout Tracking',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0D4F48),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton.icon(
              onPressed: _endSession,
              icon: const Icon(
                Icons.stop_circle_outlined,
                color: Colors.white,
                size: 20,
              ),
              label: const Text(
                'End Session',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current Workout Section
                const Text(
                  'Current Workout',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 15),

                if (currentWorkout != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D4F48),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.white.withOpacity(0.2),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: (currentWorkout!['image'] != null &&
                                        currentWorkout!['image'].toString().isNotEmpty)
                                    ? Image.network(
                                        currentWorkout!['image'].toString(),
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          debugPrint('Error loading image: $error');
                                          return const Icon(
                                            Icons.fitness_center,
                                            color: Colors.white,
                                            size: 30,
                                          );
                                        },
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Center(
                                            child: CircularProgressIndicator(
                                              value: loadingProgress.expectedTotalBytes != null
                                                  ? loadingProgress.cumulativeBytesLoaded /
                                                      loadingProgress.expectedTotalBytes!
                                                  : null,
                                              strokeWidth: 2,
                                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          );
                                        },
                                      )
                                    : const Icon(
                                        Icons.fitness_center,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentWorkout!['exercise_name'] ?? 'Unknown Exercise',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  if (currentWorkout!['muscle_name'] != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        currentWorkout!['muscle_name'],
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            if (currentWorkout!['sets'] != null)
                              _buildWorkoutStat(
                                'Sets',
                                currentWorkout!['sets']?.toString() ?? '0',
                                Icons.repeat,
                              ),
                            if (currentWorkout!['reps'] != null)
                              _buildWorkoutStat(
                                'Reps',
                                '${currentWorkout!['current_reps'] ?? 0}/${currentWorkout!['reps'] ?? 0}',
                                Icons.filter_list,
                              ),
                            if (currentWorkout!['weight'] != null &&
                                currentWorkout!['weight'].toString().isNotEmpty)
                              _buildWorkoutStat(
                                'Weight',
                                currentWorkout!['weight'].toString(),
                                Icons.fitness_center,
                              ),
                            if (currentWorkout!['duration'] != null &&
                                currentWorkout!['duration'].toString().isNotEmpty)
                              _buildWorkoutStat(
                                'Duration',
                                currentWorkout!['duration'].toString(),
                                Icons.timer,
                              ),
                          ],
                        ),
                        if (currentWorkout!['feedback'] != null)
                          Column(
                            children: [
                              const SizedBox(height: 12),
                              const Divider(color: Colors.white24),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.feedback_outlined,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Feedback: ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      currentWorkout!['feedback'].toString(),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        'No current workout',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 30),

                // Sessions Section
                const Text(
                  'Active Sessions',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 15),

                sessions.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(40),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text(
                            'No active sessions',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: sessions.length,
                        itemBuilder: (context, index) {
                          final session = sessions[index];
                          final exercises = session['exercises'] as List? ?? [];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF0D4F48).withOpacity(0.2),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Session Header
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0D4F48).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.timer,
                                          color: Color(0xFF0D4F48),
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Session: ${session['sessionId']}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Exercises: ${exercises.length}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                if (exercises.isNotEmpty) ...[
                                  const Divider(height: 1),

                                  // Exercises List
                                  Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: exercises.length,
                                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                                      itemBuilder: (context, exIndex) {
                                        final exercise = exercises[exIndex];
                                        return Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[50],
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: Colors.grey[200]!,
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              // Exercise Image
                                              Container(
                                                width: 60,
                                                height: 60,
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(10),
                                                  color: const Color(0xFF0D4F48).withOpacity(0.1),
                                                ),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(10),
                                                  child: exercise['image'] != null && exercise['image'].toString().isNotEmpty
                                                      ? Image.network(
                                                          exercise['image'],
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (context, error, stackTrace) {
                                                            return const Icon(
                                                              Icons.fitness_center,
                                                              color: Color(0xFF0D4F48),
                                                              size: 30,
                                                            );
                                                          },
                                                          loadingBuilder: (context, child, loadingProgress) {
                                                            if (loadingProgress == null) return child;
                                                            return const Center(
                                                              child: CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                              ),
                                                            );
                                                          },
                                                        )
                                                      : const Icon(
                                                          Icons.fitness_center,
                                                          color: Color(0xFF0D4F48),
                                                          size: 30,
                                                        ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              // Exercise Details
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      exercise['name'] ?? 'Exercise ${exIndex + 1}',
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w600,
                                                        color: Colors.black87,
                                                      ),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    if (exercise['muscle_name'] != null)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF0D4F48).withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          exercise['muscle_name'],
                                                          style: const TextStyle(
                                                            fontSize: 11,
                                                            color: Color(0xFF0D4F48),
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    const SizedBox(height: 6),
                                                    Row(
                                                      children: [
                                                        if (exercise['sets'] != null)
                                                          Text(
                                                            'Sets: ${exercise['sets']}',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Colors.grey[700],
                                                            ),
                                                          ),
                                                        if (exercise['sets'] != null && (exercise['reps'] != null || exercise['current_reps'] != null))
                                                          Text(
                                                            ' • ',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Colors.grey[700],
                                                            ),
                                                          ),
                                                        if (exercise['current_reps'] != null || exercise['reps'] != null)
                                                          Text(
                                                            'Reps: ${exercise['current_reps'] ?? 0}/${exercise['reps'] ?? 0}',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Colors.grey[700],
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // Completion Status
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: (exercise['completed'] == true ||
                                                         (exercise['current_reps'] != null &&
                                                          exercise['reps'] != null &&
                                                          exercise['current_reps'] >= exercise['reps']))
                                                      ? Colors.green.withOpacity(0.1)
                                                      : Colors.orange.withOpacity(0.1),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  (exercise['completed'] == true ||
                                                   (exercise['current_reps'] != null &&
                                                    exercise['reps'] != null &&
                                                    exercise['current_reps'] >= exercise['reps']))
                                                      ? Icons.check_circle
                                                      : Icons.pending,
                                                  color: (exercise['completed'] == true ||
                                                         (exercise['current_reps'] != null &&
                                                          exercise['reps'] != null &&
                                                          exercise['current_reps'] >= exercise['reps']))
                                                      ? Colors.green
                                                      : Colors.orange,
                                                  size: 20,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkoutStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}
