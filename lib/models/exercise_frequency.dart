class ExerciseFrequency {
  final String exerciseName;
  final String muscleName;
  final int count;
  final DateTime lastPerformed;

  ExerciseFrequency({
    required this.exerciseName,
    required this.muscleName,
    required this.count,
    required this.lastPerformed,
  });

  factory ExerciseFrequency.fromJson(Map<String, dynamic> json) {
    return ExerciseFrequency(
      exerciseName: json['exerciseName'] as String,
      muscleName: json['muscleName'] as String,
      count: json['count'] as int,
      lastPerformed: DateTime.parse(json['lastPerformed'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'exerciseName': exerciseName,
      'muscleName': muscleName,
      'count': count,
      'lastPerformed': lastPerformed.toIso8601String(),
    };
  }
}
