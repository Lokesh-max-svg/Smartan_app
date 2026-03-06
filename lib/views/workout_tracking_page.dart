import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/reid_monitor_service.dart';
import '../services/api_client.dart';

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

class _WorkoutTrackingPageState extends State<WorkoutTrackingPage>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? currentWorkout;
  List<Map<String, dynamic>> sessions = [];
  bool isLoading = true;

  final ReidMonitorService _reidMonitorService = ReidMonitorService();

  Timer? _pollingTimer;

  // Cache for exercise images to avoid repeated lookups
  final Map<String, String> _imageCache = {};

  // Store latest polled responses for processing
  List<Map<String, dynamic>> _workoutDocs = [];
  Map<String, dynamic>? _sessionDoc;
  List<Map<String, dynamic>> _activeSessions = [];

  // Pulsing animation for reid status banner
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _reidMonitorService.startMonitoring(widget.sessionDocId);
    _startPolling();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _startPolling() async {
    await _pollData();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _pollData();
    });
  }

  Future<void> _pollData() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if ((userId ?? '').isEmpty) {
      if (mounted) setState(() => isLoading = false);
      return;
    }

    try {
      final responses = await Future.wait([
        ApiClient.getSession(widget.sessionDocId),
        ApiClient.getSessionWorkoutsBySessionId(widget.sessionId),
        ApiClient.getActiveSessions(userId!),
      ]);

      _sessionDoc = responses[0]['session'] as Map<String, dynamic>?;
      _workoutDocs = (responses[1]['workouts'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      _activeSessions = (responses[2]['sessions'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();

      _processCurrentWorkout();
      _processActiveSessions();
    } catch (e) {
      debugPrint('Error polling workout data: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _processCurrentWorkout() async {
    if (_sessionDoc == null) return;

    try {
      if (_workoutDocs.isEmpty) {
        setState(() {
          currentWorkout = null;
          isLoading = false;
        });
        debugPrint('No current workout found');
        return;
      }

      // Sort by date in Dart to get the most recent
      final sortedDocs = _workoutDocs.toList();
      sortedDocs.sort((a, b) {
        final aDate = DateTime.tryParse((a['date'] ?? '').toString());
        final bDate = DateTime.tryParse((b['date'] ?? '').toString());
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      final doc = sortedDocs.first;
      final workoutData = doc;
      final exerciseName = workoutData['exercise_name'];

      int targetReps = workoutData['reps'] ?? 0;
      int totalCurrentReps = 0;

      final exercises = (_sessionDoc?['exercises'] as List? ?? []);

        // Sum current_reps from current_workout entries for this session
        for (var workoutDoc in _workoutDocs) {
          final data = workoutDoc;
          if (data['exercise_name'] == exerciseName) {
            totalCurrentReps += (data['reps'] as int? ?? 0);
          }
        }

        debugPrint('Total current reps for $exerciseName: $totalCurrentReps');

        // Find matching exercise in session for target reps
        for (var exercise in exercises) {
          if (exercise['name'] == exerciseName) {
            targetReps = exercise['reps'] ?? 0;
            debugPrint('Found target reps from session: $targetReps');
            break;
          }
        }
      // Fetch exercise image (with caching to avoid repeated lookups)
      String? imageUrl = workoutData['image'];

      if ((imageUrl == null || imageUrl.isEmpty) && exerciseName != null) {
        final cached = _imageCache[exerciseName.toString()];
        if (cached != null) {
          imageUrl = cached;
        } else {
          imageUrl = await _fetchExerciseImage(exerciseName.toString());
          if (imageUrl != null && imageUrl.isNotEmpty) {
            _imageCache[exerciseName.toString()] = imageUrl;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        currentWorkout = {
          'id': doc['id'],
          ...workoutData,
          'image': imageUrl,
          'current_reps': totalCurrentReps,
          'reps': targetReps,
        };
        isLoading = false;
      });
      debugPrint('Current workout loaded: ${currentWorkout?['exercise_name']}');
      debugPrint('Current reps: $totalCurrentReps, Target reps: $targetReps');
    } catch (e) {
      debugPrint('Error processing current workout: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<String?> _fetchExerciseImage(String exerciseName) async {
    try {
      final response = await ApiClient.getExerciseImage(exerciseName);
      return response['image'] as String?;
    } catch (e) {
      debugPrint('Error fetching exercise image: $e');
      return null;
    }
  }

  void _processActiveSessions() {
    if (_activeSessions.isEmpty) {
      if (mounted) {
        setState(() {
          sessions = [];
        });
      }
      return;
    }

    List<Map<String, dynamic>> loadedSessions = [];

    for (var data in _activeSessions) {
      final sessionId = data['sessionId'] as String?;
      List<dynamic> exercises = data['exercises'] as List? ?? [];

      // For the current session, compute current_reps from workout listener data
      if (sessionId == widget.sessionId) {
        exercises = exercises.map((exercise) {
          final exerciseName = exercise['name'];
          int totalCurrentReps = 0;

          for (var wData in _workoutDocs) {
            if (wData['exercise_name'] == exerciseName) {
              totalCurrentReps += (wData['reps'] as int? ?? 0);
            }
          }

          final targetReps = exercise['reps'] ?? 0;
          return {
            ...Map<String, dynamic>.from(exercise),
            'current_reps': totalCurrentReps,
            'completed': totalCurrentReps >= targetReps,
          };
        }).toList();
      }

      loadedSessions.add({
        'id': data['id'],
        'sessionId': sessionId ?? data['id'],
        'status': data['status'] ?? 'Active',
        'createdAt': data['createdAt'],
        'date': data['date'],
        'exercises': exercises,
      });
    }

    setState(() {
      sessions = loadedSessions;
    });

    debugPrint('Total sessions loaded: ${sessions.length}');
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

      if (!mounted) return;

      // Show loading immediately after confirmation
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

      // Use cached session data from listener instead of re-fetching
      final sessionData = _sessionDoc;
      final exercises = sessionData?['exercises'] as List? ?? [];

      if (exercises.isNotEmpty) {
        // Use cached workout docs from listener, filtered by session_id
        final workoutDocs = _workoutDocs;

        // Update each exercise with final summed current_reps
        final updatedExercises = exercises.map((exercise) {
          final exerciseName = exercise['name'];
          int totalCurrentReps = 0;

          for (var workoutDoc in workoutDocs) {
            final data = workoutDoc;
            if (data['exercise_name'] == exerciseName) {
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

        // Update session with final exercise data and mark as Closed
        await ApiClient.closeSession(
          sessionId: widget.sessionDocId,
          exercises: updatedExercises
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );

        debugPrint('Session ${widget.sessionId} ended with final stats updated');
      } else {
        // No exercises, just update status
        await ApiClient.closeSession(sessionId: widget.sessionDocId);
      }

      debugPrint('Session ${widget.sessionId} ended successfully');

      // Stop reid monitoring since session is closed
      await _reidMonitorService.stopMonitoring();

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
                // ReID Status Banner
                ValueListenableBuilder<int>(
                  valueListenable: _reidMonitorService.reidStatus,
                  builder: (context, reidStatus, _) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: _reidMonitorService.alertDismissed,
                      builder: (context, alertDismissed, _) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: reidStatus == 1
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: reidStatus == 1 ? Colors.green : Colors.orange,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    reidStatus == 1
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: reidStatus == 1 ? Colors.green : Colors.orange,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          reidStatus == 1
                                              ? 'You are being tracked'
                                              : 'Not yet identified',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: reidStatus == 1
                                                ? Colors.green.shade800
                                                : Colors.orange.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          reidStatus == 1
                                              ? 'Camera system has identified you'
                                              : 'Move into the camera view to be recognised',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: reidStatus == 1
                                                ? Colors.green.shade700
                                                : Colors.orange.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Pulsing dot when waiting, solid when tracked
                                  reidStatus == 1
                                      ? Container(
                                          width: 10,
                                          height: 10,
                                          decoration: const BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle,
                                          ),
                                        )
                                      : AnimatedBuilder(
                                          animation: _pulseAnimation,
                                          builder: (context, child) {
                                            return Container(
                                              width: 10,
                                              height: 10,
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withValues(alpha: _pulseAnimation.value),
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.orange.withValues(alpha: _pulseAnimation.value * 0.5),
                                                    blurRadius: 6,
                                                    spreadRadius: 2,
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                ],
                              ),
                              // Dismiss alert button
                              if (reidStatus == 0 && !alertDismissed)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: GestureDetector(
                                    onTap: _reidMonitorService.dismissAlert,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Icon(
                                          Icons.volume_off,
                                          size: 16,
                                          color: Colors.orange.shade700,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Dismiss alert',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.orange.shade700,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 20),

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
