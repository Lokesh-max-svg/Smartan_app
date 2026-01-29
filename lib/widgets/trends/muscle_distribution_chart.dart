import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class MuscleDistributionChart extends StatelessWidget {
  final Map<String, int> muscleGroups;

  const MuscleDistributionChart({
    super.key,
    required this.muscleGroups,
  });

  @override
  Widget build(BuildContext context) {
    if (muscleGroups.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'No muscle group data available',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final total = muscleGroups.values.fold(0, (sum, count) => sum + count);
    final colors = _getMuscleColors();

    return Column(
      children: [
        Container(
          height: 250,
          padding: const EdgeInsets.all(16),
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 50,
              sections: muscleGroups.entries.map((entry) {
                final index = muscleGroups.keys.toList().indexOf(entry.key);
                final percentage = (entry.value / total * 100);
                return PieChartSectionData(
                  value: entry.value.toDouble(),
                  title: '${percentage.toStringAsFixed(0)}%',
                  radius: 80,
                  titleStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  color: colors[index % colors.length],
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildLegend(colors),
      ],
    );
  }

  Widget _buildLegend(List<Color> colors) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: muscleGroups.entries.map((entry) {
        final index = muscleGroups.keys.toList().indexOf(entry.key);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: colors[index % colors.length],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${entry.key} (${entry.value})',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      }).toList(),
    );
  }

  List<Color> _getMuscleColors() {
    return [
      const Color(0xFF0D4F48), // Teal (primary)
      const Color(0xFFA4FEB7), // Light green (secondary)
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.cyan,
      Colors.amber,
      Colors.indigo,
      Colors.pink,
    ];
  }
}
