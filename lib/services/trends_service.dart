import 'api_client.dart';
import '../models/exercise_frequency.dart';
import '../models/progress_metric.dart';
import '../models/activity_day.dart';
import '../models/session_summary.dart';

enum TimeFilter { today, last7Days, last15Days, last30Days, last90Days, custom }

/// Trends Service - Uses backend API instead of direct Firestore
class TrendsService {
  // Cache for performance
  Map<String, dynamic>? _cachedData;
  DateTime? _lastCacheTime;
  TimeFilter? _cachedFilter;
  DateTime? _cachedStartDate;
  DateTime? _cachedEndDate;
  static const cacheDuration = Duration(minutes: 5);

  void clearCache() {
    _cachedData = null;
    _lastCacheTime = null;
    _cachedFilter = null;
    _cachedStartDate = null;
    _cachedEndDate = null;
  }

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
        _cachedFilter == filter &&
        _cachedStartDate == customStartDate &&
        _cachedEndDate == customEndDate) {
      if (DateTime.now().difference(_lastCacheTime!) < cacheDuration) {
        return _cachedData!;
      }
    }

    // Fetch fresh data from backend
    final filterString = _filterToString(filter);
    final response = await ApiClient.getAllTrends(
      userId,
      filter: filterString,
      customStart: customStartDate?.toIso8601String(),
      customEnd: customEndDate?.toIso8601String(),
    );

    final sessions = (response['data']['sessions'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final workouts = (response['data']['workouts'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();

    // Process data locally
    final data = {
      'exerciseFrequency': _processExerciseFrequency(sessions),
      'progressMetrics': _processProgressMetrics(sessions, workouts),
      'activityCalendar': _processActivityCalendar(sessions),
      'sessionHistory': _processSessionHistory(sessions),
    };

    // Update cache
    _cachedData = data;
    _lastCacheTime = DateTime.now();
    _cachedFilter = filter;
    _cachedStartDate = customStartDate;
    _cachedEndDate = customEndDate;

    return data;
  }

  /// Get exercise frequency data
  Future<List<ExerciseFrequency>> getExerciseFrequency(
    String userId,
    TimeFilter filter, {
    DateTime? customStartDate,
    DateTime? customEndDate,
  }) async {
    final data = await getTrendsData(userId, filter,
        customStartDate: customStartDate, customEndDate: customEndDate);
    return data['exerciseFrequency'] as List<ExerciseFrequency>;
  }

  /// Get progress metrics
  Future<Map<String, List<ProgressMetric>>> getProgressMetrics(
    String userId,
    TimeFilter filter, {
    DateTime? customStartDate,
    DateTime? customEndDate,
  }) async {
    final data = await getTrendsData(userId, filter,
        customStartDate: customStartDate, customEndDate: customEndDate);
    return data['progressMetrics'] as Map<String, List<ProgressMetric>>;
  }

  /// Get activity calendar
  Future<List<ActivityDay>> getActivityCalendar(
    String userId,
    TimeFilter filter, {
    DateTime? customStartDate,
    DateTime? customEndDate,
  }) async {
    final data = await getTrendsData(userId, filter,
        customStartDate: customStartDate, customEndDate: customEndDate);
    return data['activityCalendar'] as List<ActivityDay>;
  }

  /// Get session history
  Future<List<SessionSummary>> getSessionHistory(
    String userId,
    TimeFilter filter, {
    DateTime? customStartDate,
    DateTime? customEndDate,
  }) async {
    final data = await getTrendsData(userId, filter,
        customStartDate: customStartDate, customEndDate: customEndDate);
    return data['sessionHistory'] as List<SessionSummary>;
  }

  String _filterToString(TimeFilter filter) {
    switch (filter) {
      case TimeFilter.today:
        return 'today';
      case TimeFilter.last7Days:
        return 'last7Days';
      case TimeFilter.last15Days:
        return 'last15Days';
      case TimeFilter.last30Days:
        return 'last30Days';
      case TimeFilter.last90Days:
        return 'last90Days';
      case TimeFilter.custom:
        return 'custom';
    }
  }

  List<ExerciseFrequency> _processExerciseFrequency(List<Map<String, dynamic>> sessions) {
    final exerciseMap = <String, ExerciseFrequency>{};

    for (var session in sessions) {
      final exercises = session['exercises'] as List? ?? [];
      for (var exercise in exercises) {
        final name = exercise['name'] as String? ?? '';
        final muscleName = exercise['muscle_name'] as String? ?? '';
        final key = '$name|$muscleName';

        final sessionDate = _parseDate(session['date']);
        
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

    final frequencies = exerciseMap.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return frequencies.take(10).toList();
  }

  Map<String, List<ProgressMetric>> _processProgressMetrics(
    List<Map<String, dynamic>> sessions,
    List<Map<String, dynamic>> workouts,
  ) {
    // Implementation similar to original but processing data from backend
    // This is a simplified version - you may need to adapt based on your models
    return {};
  }

  List<ActivityDay> _processActivityCalendar(List<Map<String, dynamic>> sessions) {
    final activityMap = <String, Map<String, int>>{};

    for (var session in sessions) {
      final date = _parseDate(session['date']);
      final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      final exercises = (session['exercises'] as List?) ?? [];
      final completedExercises = exercises
          .where((e) => (e as Map<String, dynamic>)['completed'] == true)
          .length;

      final current = activityMap[dateKey] ??
          {
            'workoutCount': 0,
            'exerciseCount': 0,
            'completedExercises': 0,
          };

      activityMap[dateKey] = {
        'workoutCount': (current['workoutCount'] ?? 0) + 1,
        'exerciseCount': (current['exerciseCount'] ?? 0) + exercises.length,
        'completedExercises':
            (current['completedExercises'] ?? 0) + completedExercises,
      };
    }

    return activityMap.entries.map((entry) {
      final parts = entry.key.split('-');
      final exerciseCount = entry.value['exerciseCount'] ?? 0;
      return ActivityDay(
        date: DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])),
        workoutCount: entry.value['workoutCount'] ?? 0,
        exerciseCount: exerciseCount,
        completedExercises: entry.value['completedExercises'] ?? 0,
        status: ActivityDay.getStatusFromExerciseCount(exerciseCount),
      );
    }).toList();
  }

  List<SessionSummary> _processSessionHistory(List<Map<String, dynamic>> sessions) {
    return sessions.map((session) {
      final exercises = (session['exercises'] as List?) ?? [];
      final completedExercises = exercises
          .where((e) => (e as Map<String, dynamic>)['completed'] == true)
          .length;

      final durationSeconds = _durationFromSession(session);
      return SessionSummary(
        sessionId: (session['sessionId'] ?? '').toString(),
        docId: (session['id'] ?? '').toString(),
        date: _parseDate(session['date']),
        status: (session['status'] ?? 'Unknown').toString(),
        totalExercises: exercises.length,
        completedExercises: completedExercises,
        duration: durationSeconds != null ? Duration(seconds: durationSeconds) : null,
      );
    }).toList();
  }

  int? _durationFromSession(Map<String, dynamic> session) {
    final explicit = session['duration'];
    if (explicit is int) return explicit;
    if (explicit is num) return explicit.toInt();

    final created = _parseDate(session['createdAt']);
    final ended = _parseDate(session['endedAt']);
    if (ended.isAfter(created)) {
      return ended.difference(created).inSeconds;
    }
    return null;
  }

  DateTime _parseDate(dynamic date) {
    if (date == null) return DateTime.now();
    if (date is DateTime) return date;
    if (date is String) {
      return DateTime.tryParse(date) ?? DateTime.now();
    }
    if (date is Map<String, dynamic>) {
      final seconds = date['_seconds'];
      if (seconds is int) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }
    return DateTime.now();
  }
}
