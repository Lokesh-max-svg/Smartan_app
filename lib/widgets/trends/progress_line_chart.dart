import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../models/progress_metric.dart';

class ProgressLineChart extends StatefulWidget {
  final Map<String, List<ProgressMetric>> progressMetrics;

  const ProgressLineChart({
    super.key,
    required this.progressMetrics,
  });

  @override
  State<ProgressLineChart> createState() => _ProgressLineChartState();
}

class _ProgressLineChartState extends State<ProgressLineChart> {
  String? selectedExercise;
  bool showReps = true; // true for reps, false for sets

  @override
  void initState() {
    super.initState();
    if (widget.progressMetrics.isNotEmpty) {
      selectedExercise = widget.progressMetrics.keys.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.progressMetrics.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'No progress data available',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final exerciseList = widget.progressMetrics.keys.toList()..sort();

    return Column(
      children: [
        // Exercise selector and toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: selectedExercise,
                  isExpanded: true,
                  items: exerciseList.map((exercise) {
                    return DropdownMenuItem(
                      value: exercise,
                      child: Text(
                        exercise,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedExercise = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Reps')),
                  ButtonSegment(value: false, label: Text('Sets')),
                ],
                selected: {showReps},
                onSelectionChanged: (Set<bool> newSelection) {
                  setState(() {
                    showReps = newSelection.first;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Chart
        if (selectedExercise != null)
          _buildChart()
        else
          const Center(
            child: Text('Select an exercise to view progress'),
          ),
      ],
    );
  }

  Widget _buildChart() {
    final metrics = widget.progressMetrics[selectedExercise]!;
    if (metrics.isEmpty || metrics.first.dataPoints.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'No data points available for this exercise',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final dataPoints = metrics.first.dataPoints;
    final spots = dataPoints.asMap().entries.map((entry) {
      final index = entry.key;
      final point = entry.value;
      final value = showReps ? point.totalReps : point.totalSets;
      return FlSpot(index.toDouble(), value.toDouble());
    }).toList();

    final maxY = dataPoints
        .map((p) => showReps ? p.totalReps : p.totalSets)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();

    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY + (maxY * 0.2),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFF0D4F48),
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF0D4F48).withOpacity(0.1),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: dataPoints.length > 7 ? 2 : 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < dataPoints.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        DateFormat('MM/dd').format(dataPoints[index].date),
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY / 5).ceilToDouble(),
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey[300]!,
                strokeWidth: 1,
              );
            },
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: Colors.grey[300]!, width: 1),
              left: BorderSide(color: Colors.grey[300]!, width: 1),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final index = spot.x.toInt();
                  final point = dataPoints[index];
                  return LineTooltipItem(
                    '${DateFormat('MM/dd').format(point.date)}\n${showReps ? "Reps" : "Sets"}: ${spot.y.toInt()}',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
}
