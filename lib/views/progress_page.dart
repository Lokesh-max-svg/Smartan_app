import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/reid_monitor_service.dart';
import '../services/api_client.dart';
import 'session_embedding_page.dart';
import 'session_analytics_page.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  DateTime selectedDate = DateTime.now();
  late String todayDate;
  String? _userId;

  List<Map<String, dynamic>> workouts = [];
  List<Map<String, dynamic>> sessions = [];
  bool isLoading = true;
  String? _closingSessionId;

  int totalWorkouts = 0;
  int totalCalories = 0;
  double totalHours = 0.0;

  Timer? _sessionsPollingTimer;

  @override
  void initState() {
    super.initState();
    _updateDateStrings();
    _loadData();
  }

  @override
  void dispose() {
    _sessionsPollingTimer?.cancel();
    super.dispose();
  }

  void _updateDateStrings() {
    todayDate = DateFormat('yyyy-MM-dd').format(selectedDate);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id');

    await _loadWorkouts();
    await _fetchSessions();
    _startSessionsPolling();
  }

  Future<void> _loadWorkouts() async {
    try {
      if ((_userId ?? '').isEmpty) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      final response = await ApiClient.getWorkoutPlanForDate(
        userId: _userId!,
        date: todayDate,
      );
      final loadedWorkouts = (response['exercises'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final workoutsCount = loadedWorkouts.length;

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

  void _startSessionsPolling() {
    _sessionsPollingTimer?.cancel();
    if ((_userId ?? '').isEmpty) return;

    _sessionsPollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _fetchSessions();
    });
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      return parsed;
    }
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is Map<String, dynamic>) {
      final seconds = value['_seconds'] ?? value['seconds'];
      if (seconds is int) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).toInt());
      }
    }
    return null;
  }

  Future<void> _fetchSessions() async {
    if ((_userId ?? '').isEmpty) return;

    try {
      final response = await ApiClient.getSessionsByDate(
        userId: _userId!,
        date: todayDate,
      );

      final loadedSessions = (response['sessions'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((data) => {
                'id': data['id'],
                'sessionId': data['sessionId'] ?? data['id'],
                'status': data['status'] ?? 'Active',
                'createdAt': data['createdAt'],
                'closedAt': data['closedAt'],
                'exercises': data['exercises'] ?? [],
              })
          .toList();

      loadedSessions.sort((a, b) {
        final aTime = _parseDateTime(a['createdAt']);
        final bTime = _parseDateTime(b['createdAt']);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      if (!mounted) return;

      setState(() {
        sessions = loadedSessions;
        _closingSessionId = null;
      });
    } catch (e) {
      debugPrint('Error fetching sessions: $e');
    }
  }

  Future<void> _createNewSession() async {
    try {
      if ((_userId ?? '').isEmpty) return;

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

      await ApiClient.createSession(
        userId: _userId!,
        date: todayDate,
        exercises: exercisesForSession,
      );

      await _fetchSessions();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New session created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

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

  Future<void> _closeSession(String docId) async {
    if (_closingSessionId != null) return; // Prevent double-tap

    setState(() => _closingSessionId = docId);

    try {
      await ApiClient.closeSession(sessionId: docId);
      await _fetchSessions();

      // Stop reid monitoring if this was the active monitored session
      final reidService = ReidMonitorService();
      if (reidService.activeSessionDocId == docId) {
        await reidService.stopMonitoring();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session closed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error closing session: $e');
      if (mounted) {
        setState(() => _closingSessionId = null);
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
                                  // Navigate to analytics page if closed, else to embedding page
                                  if (session['status'] == 'Closed') {
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
                                _closingSessionId == session['id']
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.red,
                                        ),
                                      )
                                    : TextButton(
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
