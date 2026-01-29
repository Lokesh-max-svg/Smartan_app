import 'package:flutter/material.dart';

class TrendsSummaryCards extends StatelessWidget {
  final int totalWorkouts;
  final int totalExercises;
  final double avgCompletionRate;

  const TrendsSummaryCards({
    super.key,
    required this.totalWorkouts,
    required this.totalExercises,
    required this.avgCompletionRate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            context,
            'Workouts',
            totalWorkouts.toString(),
            Icons.fitness_center,
            const Color(0xFF0D4F48),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            context,
            'Completion',
            '${avgCompletionRate.toStringAsFixed(0)}%',
            Icons.check_circle_outline,
            avgCompletionRate >= 75
                ? Colors.green
                : avgCompletionRate >= 50
                    ? Colors.orange
                    : Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: color,
                size: 14,
              ),
              SizedBox(width: 5,),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
