class ProgressMetric {
  final String exerciseName;
  final List<ProgressDataPoint> dataPoints;

  ProgressMetric({
    required this.exerciseName,
    required this.dataPoints,
  });

  factory ProgressMetric.fromJson(Map<String, dynamic> json) {
    return ProgressMetric(
      exerciseName: json['exerciseName'] as String,
      dataPoints: (json['dataPoints'] as List)
          .map((e) => ProgressDataPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'exerciseName': exerciseName,
      'dataPoints': dataPoints.map((e) => e.toJson()).toList(),
    };
  }
}

class ProgressDataPoint {
  final DateTime date;
  final int totalReps;
  final int totalSets;
  final double completionRate;

  ProgressDataPoint({
    required this.date,
    required this.totalReps,
    required this.totalSets,
    required this.completionRate,
  });

  factory ProgressDataPoint.fromJson(Map<String, dynamic> json) {
    return ProgressDataPoint(
      date: DateTime.parse(json['date'] as String),
      totalReps: json['totalReps'] as int,
      totalSets: json['totalSets'] as int,
      completionRate: (json['completionRate'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'totalReps': totalReps,
      'totalSets': totalSets,
      'completionRate': completionRate,
    };
  }
}
