import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'exercise_playback_page.dart';

class SessionAnalyticsPage extends StatefulWidget {
  final String sessionId;
  final String sessionDocId;

  const SessionAnalyticsPage({
    super.key,
    required this.sessionId,
    required this.sessionDocId,
  });

  @override
  State<SessionAnalyticsPage> createState() => _SessionAnalyticsPageState();
}

class _SessionAnalyticsPageState extends State<SessionAnalyticsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? sessionData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessionData();
  }

  Future<void> _loadSessionData() async {
    try {
      final doc = await _firestore
          .collection('sessions')
          .doc(widget.sessionDocId)
          .get();

      if (doc.exists) {
        setState(() {
          sessionData = {
            'id': doc.id,
            ...doc.data()!,
          };
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading session data: $e');
      setState(() {
        isLoading = false;
      });
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

    if (sessionData == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'Session Analytics',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF0D4F48),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Text('Session not found'),
        ),
      );
    }

    final exercises = sessionData!['exercises'] as List? ?? [];
    final completedExercises = exercises.where((e) => e['completed'] == true).length;
    final totalExercises = exercises.length;
    final completionRate = totalExercises > 0 ? (completedExercises / totalExercises * 100) : 0;

    final createdAt = sessionData!['createdAt'] as Timestamp?;
    final endedAt = sessionData!['endedAt'] as Timestamp?;
    final closedAt = sessionData!['closedAt'] as Timestamp?;

    String? duration;
    if (createdAt != null && (endedAt != null || closedAt != null)) {
      final end = endedAt ?? closedAt;
      final diff = end!.toDate().difference(createdAt.toDate());
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      duration = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Session Analytics',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0D4F48),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Session Header Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0D4F48), Color(0xFF1A6B5F)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
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
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.analytics,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Session Completed',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'ID: ${widget.sessionId}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(color: Colors.white24, height: 1),
                      const SizedBox(height: 20),

                      // Stats Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStat(
                            Icons.fitness_center,
                            '$completedExercises/$totalExercises',
                            'Completed',
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: Colors.white24,
                          ),
                          _buildStat(
                            Icons.percent,
                            '${completionRate.toStringAsFixed(0)}%',
                            'Success Rate',
                          ),
                          if (duration != null) ...[
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.white24,
                            ),
                            _buildStat(
                              Icons.timer,
                              duration,
                              'Duration',
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // Session Details
                const Text(
                  'Session Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 15),

                _buildDetailCard(
                  'Date',
                  sessionData!['date'] ?? 'N/A',
                  Icons.calendar_today,
                ),
                const SizedBox(height: 12),

                if (createdAt != null)
                  _buildDetailCard(
                    'Started At',
                    DateFormat('MMM dd, yyyy - hh:mm a').format(createdAt.toDate()),
                    Icons.play_circle,
                  ),
                const SizedBox(height: 12),

                if (endedAt != null || closedAt != null)
                  _buildDetailCard(
                    'Ended At',
                    DateFormat('MMM dd, yyyy - hh:mm a').format((endedAt ?? closedAt)!.toDate()),
                    Icons.stop_circle,
                  ),
                const SizedBox(height: 12),

                _buildDetailCard(
                  'Status',
                  sessionData!['status'] ?? 'N/A',
                  Icons.info_outline,
                  valueColor: _getStatusColor(sessionData!['status']),
                ),

                const SizedBox(height: 30),

                // Exercises List
                const Text(
                  'Exercises',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 15),

                if (exercises.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        'No exercises in this session',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: exercises.length,
                    itemBuilder: (context, index) {
                      final exercise = exercises[index];
                      final isCompleted = exercise['completed'] == true;
                      final hasGcsFolders = exercise['gcs_folders'] != null &&
                          (exercise['gcs_folders'] as List).isNotEmpty;

                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ExercisePlaybackPage(
                                exercise: Map<String, dynamic>.from(exercise),
                                sessionId: widget.sessionId,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? Colors.green.withOpacity(0.05)
                                : Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isCompleted
                                  ? Colors.green.withOpacity(0.3)
                                  : Colors.grey[200]!,
                              width: 1.5,
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
                                child: exercise['image'] != null &&
                                       exercise['image'].toString().isNotEmpty
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
                                      )
                                    : const Icon(
                                        Icons.fitness_center,
                                        color: Color(0xFF0D4F48),
                                        size: 30,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Exercise Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    exercise['name'] ?? 'Exercise ${index + 1}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
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
                                      if (hasGcsFolders) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.play_circle_outline,
                                                size: 12,
                                                color: Colors.blue,
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'View',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
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
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isCompleted
                                    ? Colors.green.withOpacity(0.1)
                                    : Colors.orange.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isCompleted ? Icons.check_circle : Icons.cancel,
                                color: isCompleted ? Colors.green : Colors.orange,
                                size: 24,
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildStat(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 8),
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
            fontSize: 11,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailCard(String label, String value, IconData icon, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D4F48).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF0D4F48),
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'closed':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
