import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'session_embedding_page.dart';
import 'session_analytics_page.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime selectedDate = DateTime.now();
  late String todayDate;

  List<Map<String, dynamic>> workouts = [];
  List<Map<String, dynamic>> sessions = [];
  bool isLoading = true;

  int totalWorkouts = 0;
  int totalCalories = 0;
  double totalHours = 0.0;

  @override
  void initState() {
    super.initState();
    _updateDateStrings();
    _loadData();
  }

  void _updateDateStrings() {
    todayDate = DateFormat('yyyy-MM-dd').format(selectedDate);
  }


  Future<void> _loadData() async {
    await Future.wait([
      _loadWorkouts(),
      _loadSessions(),
    ]);
  }

  Future<void> _loadWorkouts() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      debugPrint('Loading workouts for user: ${currentUser.uid}, date: $todayDate');

      // Query workout plans for this user
      final snapshot = await _firestore
          .collection('workoutPlans')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      List<Map<String, dynamic>> loadedWorkouts = [];
      int workoutsCount = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();

        if (data['workouts'] != null && data['workouts'] is Map) {
          final workoutsMap = data['workouts'] as Map<String, dynamic>;

          for (var dateKey in workoutsMap.keys) {
            if (dateKey.toString() == todayDate) {
              final todayWorkouts = workoutsMap[dateKey];

              if (todayWorkouts is List) {
                workoutsCount = todayWorkouts.length;
                for (var exercise in todayWorkouts) {
                  if (exercise is Map<String, dynamic>) {
                    loadedWorkouts.add(exercise);
                  }
                }
              }
              break;
            }
          }
        }
      }

      setState(() {
        workouts = loadedWorkouts;
        totalWorkouts = workoutsCount;
        totalCalories = workoutsCount * 50; // Estimate 50 calories per exercise
        totalHours = (workoutsCount * 5) / 60; // Estimate 5 minutes per exercise
        isLoading = false;
      });

      debugPrint('Total workouts loaded: $totalWorkouts');
    } catch (e, stackTrace) {
      debugPrint('Error loading workouts: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadSessions() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      debugPrint('Loading sessions for user: ${currentUser.uid}, date: $todayDate');

      // Query sessions for this user and date (without orderBy to avoid index requirement)
      final snapshot = await _firestore
          .collection('sessions')
          .where('userId', isEqualTo: currentUser.uid)
          .where('date', isEqualTo: todayDate)
          .get();

      List<Map<String, dynamic>> loadedSessions = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        loadedSessions.add({
          'id': doc.id,
          'sessionId': data['sessionId'] ?? doc.id,
          'status': data['status'] ?? 'Active',
          'createdAt': data['createdAt'],
          'closedAt': data['closedAt'],
          'exercises': data['exercises'] ?? [],
        });
      }

      // Sort by createdAt in Dart instead of Firestore
      loadedSessions.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime); // Descending order (newest first)
      });

      setState(() {
        sessions = loadedSessions;
      });

      debugPrint('Total sessions loaded: ${sessions.length}');
    } catch (e, stackTrace) {
      debugPrint('Error loading sessions: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> _createNewSession() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      // Check if there's already an active session for today
      final activeSession = sessions.firstWhere(
        (s) => s['status'] == 'Active',
        orElse: () => {},
      );

      if (activeSession.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You already have an active session for today'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Generate unique short session ID combining user ID prefix and timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Take first 6 chars of user ID + last 10 digits of timestamp for shorter ID
      final userPrefix = currentUser.uid.length > 6
          ? currentUser.uid.substring(0, 6)
          : currentUser.uid;
      final timestampSuffix = timestamp.toString().substring(timestamp.toString().length - 10);
      final sessionId = '$userPrefix$timestampSuffix';

      // Copy today's workout plan and add reps/current_reps fields to each exercise
      final exercisesForSession = workouts.map((exercise) {
        return {
          ...exercise,
          'reps': exercise['reps'] ?? 0, // Target reps from workout plan
          'current_reps': 0, // Initialize current_reps to 0 for tracking during session
          'completed': false, // Track completion status
        };
      }).toList();

      debugPrint('Creating session with ${exercisesForSession.length} exercises');

      // Create new session document
      await _firestore.collection('sessions').add({
        'userId': currentUser.uid,
        'sessionId': sessionId,
        'date': todayDate,
        'status': 'Active',
        'embedding_status': 0,
        'global_session': null,
        'createdAt': FieldValue.serverTimestamp(),
        'exercises': exercisesForSession,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New session created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Reload sessions
      _loadSessions();
    } catch (e) {
      debugPrint('Error creating session: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating session: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _closeSession(String sessionId) async {
    try {
      // Get the session document
      final sessionDoc = await _firestore.collection('sessions').doc(sessionId).get();

      if (!sessionDoc.exists) {
        throw Exception('Session not found');
      }

      final sessionData = sessionDoc.data();
      final exercises = sessionData?['exercises'] as List? ?? [];
      final sessionIdValue = sessionData?['sessionId'] as String?;

      // Calculate final statistics before closing
      if (sessionIdValue != null && exercises.isNotEmpty) {
        final currentUser = _auth.currentUser;
        if (currentUser != null) {
          // Fetch all current_workout entries for this user
          final workoutSnapshot = await _firestore
              .collection('current_workout')
              .where('user_id', isEqualTo: currentUser.uid)
              .get();

          // Calculate current_reps for each exercise by summing from current_workout
          final updatedExercises = exercises.map((exercise) {
            final exerciseName = exercise['name'];
            int totalCurrentReps = 0;

            // Sum all current_reps for this exercise in this session
            for (var workoutDoc in workoutSnapshot.docs) {
              final data = workoutDoc.data();
              final workoutSessionId = data['session_id'] as String?;

              if (data['exercise_name'] == exerciseName &&
                  workoutSessionId == sessionIdValue) {
                totalCurrentReps += (data['reps'] as int? ?? 0);
              }
            }

            // Check if exercise is completed (current_reps >= target_reps)
            final targetReps = exercise['reps'] ?? 0;
            final isCompleted = totalCurrentReps >= targetReps;

            return {
              ...exercise,
              'current_reps': totalCurrentReps,
              'completed': isCompleted,
            };
          }).toList();

          // Update session with final statistics
          await _firestore.collection('sessions').doc(sessionId).update({
            'exercises': updatedExercises,
            'status': 'Closed',
            'closedAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        // If no exercises or sessionId, just update status
        await _firestore.collection('sessions').doc(sessionId).update({
          'status': 'Closed',
          'closedAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session closed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Reload sessions
      _loadSessions();
    } catch (e) {
      debugPrint('Error closing session: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error closing session: $e'),
            backgroundColor: Colors.red,
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
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                const Text(
                  'Current Progress',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Track your fitness journey',
                  style: TextStyle(fontSize: 14, color: Colors.black),
                ),
                const SizedBox(height: 20),

                Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D4F48),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.calendar_today,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Selected Date',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('EEEE, MMM d, yyyy').format(selectedDate),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // const Icon(
                        //   Icons.arrow_forward_ios,
                        //   color: Colors.white,
                        //   size: 16,
                        // ),
                      ],
                    ),
                  ),


                const SizedBox(height: 25),

                // Weekly Summary
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D4F48),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Today\'s Plan',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _summaryItem('Workouts', totalWorkouts.toString(), Icons.fitness_center),
                          _summaryItem(
                            'Calories',
                            totalCalories.toString(),
                            Icons.local_fire_department,
                          ),
                          _summaryItem('Hours', totalHours.toStringAsFixed(1), Icons.access_time),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 25),

                // Session Details header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Today's Session",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _createNewSession,
                      icon: const Icon(
                        Icons.add,
                        size: 18,
                        color: Color(0xFF0D4F48),
                      ),
                      label: const Text(
                        "New Session",
                        style: TextStyle(
                          color: Color(0xFF0D4F48),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 15),

                // Check if sessions exist
                sessions.isEmpty
                    ? Center(
                  child: Container(
                    padding: const EdgeInsets.all(50),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      "No sessions found.\nPlease create a new session.",
                      textAlign: TextAlign.center,
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
                    final bool isActive = session['status'] == "Active";
                    final Color statusColor = _getStatusColor(session['status']);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Left icon
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D4F48)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.timer,
                              color: Color(0xFF0D4F48),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Title & Status
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Session Id: ${session['sessionId']}",
                                  style: const TextStyle(
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Text(
                                      "Status: ",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      session['status'],
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: statusColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Actions: View + Close
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // View button - route based on status
                              TextButton(
                                onPressed: () {
                                  // Navigate to analytics page if completed/closed, else to embedding page
                                  if (session['status'] == 'Completed' || session['status'] == 'Closed') {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => SessionAnalyticsPage(
                                          sessionId: session['sessionId'],
                                          sessionDocId: session['id'],
                                        ),
                                      ),
                                    );
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => SessionEmbeddingPage(
                                          sessionId: session['sessionId'],
                                          sessionDocId: session['id'],
                                        ),
                                      ),
                                    );
                                  }
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  minimumSize: const Size(0, 32),
                                  backgroundColor:
                                  Colors.blue.withOpacity(0.1),
                                  foregroundColor: Colors.blue,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(20),
                                  ),
                                ),
                                child: const Text(
                                  "View",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),

                              const SizedBox(width: 8),

                              // Close button only for Active
                              if (isActive)
                                TextButton(
                                  onPressed: () {
                                    _closeSession(session['id']);
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    backgroundColor:
                                    Colors.red.withOpacity(0.1),
                                    foregroundColor: Colors.red,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                      BorderRadius.circular(20),
                                    ),
                                  ),
                                  child: const Text(
                                    "Close",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
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

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'completed':
        return Colors.blue;
      case 'closed':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  // Summary Item widget
  Widget _summaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 10),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)),
      ],
    );
  }
}
