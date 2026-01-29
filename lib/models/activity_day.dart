class ActivityDay {
  final DateTime date;
  final int workoutCount;
  final int exerciseCount;
  final int completedExercises;
  final String status; // 'none', 'light', 'medium', 'heavy'

  ActivityDay({
    required this.date,
    required this.workoutCount,
    required this.exerciseCount,
    required this.completedExercises,
    required this.status,
  });

  factory ActivityDay.fromJson(Map<String, dynamic> json) {
    return ActivityDay(
      date: DateTime.parse(json['date'] as String),
      workoutCount: json['workoutCount'] as int,
      exerciseCount: json['exerciseCount'] as int,
      completedExercises: json['completedExercises'] as int,
      status: json['status'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'workoutCount': workoutCount,
      'exerciseCount': exerciseCount,
      'completedExercises': completedExercises,
      'status': status,
    };
  }

  // Helper method to get status based on exercise count
  static String getStatusFromExerciseCount(int count) {
    if (count == 0) return 'none';
    if (count <= 3) return 'light';
    if (count <= 7) return 'medium';
    return 'heavy';
  }
}
