class SessionSummary {
  final String sessionId;
  final String docId;
  final DateTime date;
  final String status;
  final int totalExercises;
  final int completedExercises;
  final Duration? duration;

  SessionSummary({
    required this.sessionId,
    required this.docId,
    required this.date,
    required this.status,
    required this.totalExercises,
    required this.completedExercises,
    this.duration,
  });

  double get completionPercentage {
    if (totalExercises == 0) return 0.0;
    return (completedExercises / totalExercises) * 100;
  }

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      sessionId: json['sessionId'] as String,
      docId: json['docId'] as String,
      date: DateTime.parse(json['date'] as String),
      status: json['status'] as String,
      totalExercises: json['totalExercises'] as int,
      completedExercises: json['completedExercises'] as int,
      duration: json['duration'] != null
          ? Duration(seconds: json['duration'] as int)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'docId': docId,
      'date': date.toIso8601String(),
      'status': status,
      'totalExercises': totalExercises,
      'completedExercises': completedExercises,
      'duration': duration?.inSeconds,
    };
  }
}
