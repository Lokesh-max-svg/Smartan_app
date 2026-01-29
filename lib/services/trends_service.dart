import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/exercise_frequency.dart';
import '../models/progress_metric.dart';
import '../models/activity_day.dart';
import '../models/session_summary.dart';

enum TimeFilter { today, last7Days, last15Days, last30Days, last90Days, custom }

class TrendsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache for performance
  Map<String, dynamic>? _cachedData;
  DateTime? _lastCacheTime;
  TimeFilter? _cachedFilter;
  static const cacheDuration = Duration(minutes: 5);

  /// Get all trends data for a user within the specified time filter
  Future<Map<String, dynamic>> getTrendsData(
    String userId,
    TimeFilter filter, {
    DateTime? customStartDate,
    DateTime? customEndDate,
  }) async {
    // Check cache first
    if (_cachedData != null &&
        _lastCacheTime != null &&
        _cachedFilter == filter) {
      if (DateTime.now().difference(_lastCacheTime!) < cacheDuration) {
        return _cachedData!;
      }
    }

    // Fetch fresh data in parallel
    final results = await Future.wait([
      getExerciseFrequency(userId, filter, customStartDate: customStartDate),
      getProgressMetrics(userId, filter, customStartDate: customStartDate),
      getActivityCalendar(userId, filter, customStartDate: customStartDate, customEndDate: customEndDate),
      getSessionHistory(userId, filter, customStartDate: customStartDate),
    ]);

    final data = {
      'exerciseFrequency': results[0] as List<ExerciseFrequency>,
      'progressMetrics': results[1] as Map<String, List<ProgressMetric>>,
      'activityCalendar': results[2] as List<ActivityDay>,
      'sessionHistory': results[3] as List<SessionSummary>,
    };

    // Update cache
    _cachedData = data;
    _lastCacheTime = DateTime.now();
    _cachedFilter = filter;

    return data;
  }

  /// Get exercise frequency data
  Future<List<ExerciseFrequency>> getExerciseFrequency(
    String userId,
    TimeFilter filter, {
    DateTime? customStartDate,
  }) async {
    final startDate = customStartDate ?? _getStartDateForFilter(filter);
    final snapshot = await _firestore
        .collection('sessions')
        .where('userId', isEqualTo: userId)
        .get();

    // Aggregate exercise counts
    final exerciseMap = <String, ExerciseFrequency>{};

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final sessionDate = _parseDate(data['date']);

      // Filter by date range
      if (sessionDate.isBefore(startDate)) continue;

      final exercises = data['exercises'] as List? ?? [];
      for (var exercise in exercises) {
        final name = exercise['name'] as String? ?? '';
        final muscleName = exercise['muscle_name'] as String? ?? '';
        final key = '$name|$muscleName';

        if (exerciseMap.containsKey(key)) {
          exerciseMap[key] = ExerciseFrequency(
            exerciseName: name,
            muscleName: muscleName,
            count: exerciseMap[key]!.count + 1,
            lastPerformed: sessionDate.isAfter(exerciseMap[key]!.lastPerformed)
                ? sessionDate
                : exerciseMap[key]!.lastPerformed,
          );
        } else {
          exerciseMap[key] = ExerciseFrequency(
            exerciseName: name,
            muscleName: muscleName,
            count: 1,
            lastPerformed: sessionDate,
          );
        }
      }
    }

    // Sort by count descending and return top 10
    final frequencies = exerciseMap.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return frequencies.take(10).toList();
  }

  /// Get progress metrics for all exercises
  Future<Map<String, List<ProgressMetric>>> getProgressMetrics(
    String userId,
    TimeFilter filter, {
    DateTime? customStartDate,
  }) async {
    final startDate = customStartDate ?? _getStartDateForFilter(filter);

    // Get data from both sessions and current_workout collections
    final sessionSnapshot = await _firestore
        .collection('sessions')
        .where('userId', isEqualTo: userId)
        .get();

    final workoutSnapshot = await _firestore
        .collection('current_workout')
        .where('user_id', isEqualTo: userId)
        .get();

    // Aggregate by exercise and date
    final exerciseDataMap = <String, Map<DateTime, ProgressDataPoint>>{};

    // Process sessions data
    for (var doc in sessionSnapshot.docs) {
      final data = doc.data();
      final sessionDate = _parseDate(data['date']);

      if (sessionDate.isBefore(startDate)) continue;

      final exercises = data['exercises'] as List? ?? [];
      for (var exercise in exercises) {
        final name = exercise['name'] as String? ?? '';
        final currentReps = exercise['current_reps'] as int? ?? 0;
        final targetReps = exercise['reps'] as int? ?? 1;
        final sets = exercise['sets'] as int? ?? 0;
        final completed = exercise['completed'] as bool? ?? false;

        if (name.isEmpty) continue;

        exerciseDataMap.putIfAbsent(name, () => {});

        final dateKey = DateTime(sessionDate.year, sessionDate.month, sessionDate.day);

        if (exerciseDataMap[name]!.containsKey(dateKey)) {
          final existing = exerciseDataMap[name]![dateKey]!;
          exerciseDataMap[name]![dateKey] = ProgressDataPoint(
            date: dateKey,
            totalReps: existing.totalReps + currentReps,
            totalSets: existing.totalSets + sets,
            completionRate: completed ? 1.0 : (currentReps / targetReps),
          );
        } else {
          exerciseDataMap[name]![dateKey] = ProgressDataPoint(
            date: dateKey,
            totalReps: currentReps,
            totalSets: sets,
            completionRate: completed ? 1.0 : (currentReps / targetReps),
          );
        }
      }
    }

    // Process current_workout data for additional rep tracking
    for (var doc in workoutSnapshot.docs) {
      final data = doc.data();
      final dateValue = data['date'];
      if (dateValue == null) continue;

      final workoutDate = _parseDate(dateValue);
      if (workoutDate.isBefore(startDate)) continue;

      final name = data['exercise_name'] as String? ?? '';
      final reps = data['reps'] as int? ?? 0;

      if (name.isEmpty) continue;

      exerciseDataMap.putIfAbsent(name, () => {});

      final dateKey = DateTime(workoutDate.year, workoutDate.month, workoutDate.day);

      if (exerciseDataMap[name]!.containsKey(dateKey)) {
        final existing = exerciseDataMap[name]![dateKey]!;
        exerciseDataMap[name]![dateKey] = ProgressDataPoint(
          date: dateKey,
          totalReps: existing.totalReps + reps,
          totalSets: existing.totalSets,
          completionRate: existing.completionRate,
        );
      }
    }

    // Convert to ProgressMetric objects
    final result = <String, List<ProgressMetric>>{};
    exerciseDataMap.forEach((exerciseName, dateMap) {
      final dataPoints = dateMap.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      result[exerciseName] = [
        ProgressMetric(
          exerciseName: exerciseName,
          dataPoints: dataPoints,
        )
      ];
    });

    return result;
  }

  /// Get activity calendar data
  Future<List<ActivityDay>> getActivityCalendar(
    String userId,
    TimeFilter filter, {
    DateTime? customStartDate,
    DateTime? customEndDate,
  }) async {
    final startDate = customStartDate ?? _getStartDateForFilter(filter);
    final endDate = customEndDate ?? DateTime.now();

    // Create a map for all days in range
    final dayMap = <DateTime, ActivityDay>{};
    var currentDate = startDate;
    while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
      final dateKey = DateTime(currentDate.year, currentDate.month, currentDate.day);
      dayMap[dateKey] = ActivityDay(
        date: dateKey,
        workoutCount: 0,
        exerciseCount: 0,
        completedExercises: 0,
        status: 'none',
      );
      currentDate = currentDate.add(const Duration(days: 1));
    }

    // Fetch sessions
    final snapshot = await _firestore
        .collection('sessions')
        .where('userId', isEqualTo: userId)
        .get();

    // Aggregate activity by date
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final sessionDate = _parseDate(data['date']);

      if (sessionDate.isBefore(startDate)) continue;

      final dateKey = DateTime(sessionDate.year, sessionDate.month, sessionDate.day);
      final exercises = data['exercises'] as List? ?? [];
      final completedCount = exercises.where((e) => e['completed'] == true).length;

      if (dayMap.containsKey(dateKey)) {
        final existing = dayMap[dateKey]!;
        final newExerciseCount = existing.exerciseCount + exercises.length;
        dayMap[dateKey] = ActivityDay(
          date: dateKey,
          workoutCount: existing.workoutCount + 1,
          exerciseCount: newExerciseCount,
          completedExercises: existing.completedExercises + completedCount,
          status: ActivityDay.getStatusFromExerciseCount(newExerciseCount),
        );
      }
    }

    // Return as sorted list
    final activityList = dayMap.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return activityList;
  }

  /// Get session history
  Future<List<SessionSummary>> getSessionHistory(
    String userId,
    TimeFilter filter, {
    DateTime? customStartDate,
  }) async {
    final startDate = customStartDate ?? _getStartDateForFilter(filter);
    final snapshot = await _firestore
        .collection('sessions')
        .where('userId', isEqualTo: userId)
        .get();

    final sessions = <SessionSummary>[];

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final sessionDate = _parseDate(data['date']);

      if (sessionDate.isBefore(startDate)) continue;

      final exercises = data['exercises'] as List? ?? [];
      final completedCount = exercises.where((e) => e['completed'] == true).length;

      // Calculate duration
      Duration? duration;
      if (data['createdAt'] != null && data['closedAt'] != null) {
        final createdAt = (data['createdAt'] as Timestamp).toDate();
        final closedAt = (data['closedAt'] as Timestamp).toDate();
        duration = closedAt.difference(createdAt);
      } else if (data['createdAt'] != null && data['endedAt'] != null) {
        final createdAt = (data['createdAt'] as Timestamp).toDate();
        final endedAt = (data['endedAt'] as Timestamp).toDate();
        duration = endedAt.difference(createdAt);
      }

      sessions.add(SessionSummary(
        sessionId: data['sessionId'] as String? ?? '',
        docId: doc.id,
        date: sessionDate,
        status: data['status'] as String? ?? 'Unknown',
        totalExercises: exercises.length,
        completedExercises: completedCount,
        duration: duration,
      ));
    }

    // Sort by date descending (most recent first)
    sessions.sort((a, b) => b.date.compareTo(a.date));
    return sessions;
  }

  /// Get start date based on time filter
  DateTime _getStartDateForFilter(TimeFilter filter) {
    final now = DateTime.now();
    switch (filter) {
      case TimeFilter.today:
        return DateTime(now.year, now.month, now.day); // Start of today
      case TimeFilter.last7Days:
        return now.subtract(const Duration(days: 7));
      case TimeFilter.last15Days:
        return now.subtract(const Duration(days: 15));
      case TimeFilter.last30Days:
        return now.subtract(const Duration(days: 30));
      case TimeFilter.last90Days:
        return now.subtract(const Duration(days: 90));
      case TimeFilter.custom:
        return DateTime(now.year, now.month, now.day); // Default to today for custom
    }
  }

  /// Clear cache (useful when data is updated)
  void clearCache() {
    _cachedData = null;
    _lastCacheTime = null;
    _cachedFilter = null;
  }

  /// Helper method to parse date from Firestore (handles both Timestamp and String)
  DateTime _parseDate(dynamic dateValue) {
    if (dateValue is Timestamp) {
      return dateValue.toDate();
    } else if (dateValue is String) {
      return DateTime.parse(dateValue);
    } else if (dateValue is DateTime) {
      return dateValue;
    } else {
      throw Exception('Unsupported date type: ${dateValue.runtimeType}');
    }
  }
}
