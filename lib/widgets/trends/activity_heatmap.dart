import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/activity_day.dart';

class ActivityHeatmap extends StatelessWidget {
  final List<ActivityDay> activityDays;

  const ActivityHeatmap({
    super.key,
    required this.activityDays,
  });

  @override
  Widget build(BuildContext context) {
    if (activityDays.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'No activity data available',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    // Group days by week
    final weeks = _groupByWeeks(activityDays);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Week day labels
        Padding(
          padding: const EdgeInsets.only(left: 40, bottom: 8),
          child: Row(
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Heatmap grid
        Container(
          height: weeks.length * 36.0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: weeks.length,
            itemBuilder: (context, weekIndex) {
              final week = weeks[weekIndex];
              return _buildWeekRow(context, week, weekIndex);
            },
          ),
        ),
        const SizedBox(height: 16),
        // Legend
        _buildLegend(),
      ],
    );
  }

  Widget _buildWeekRow(BuildContext context, List<ActivityDay?> week, int weekIndex) {
    // Get the month for this week (from the first non-null day)
    final firstDay = week.firstWhere((d) => d != null, orElse: () => null);
    final monthLabel = firstDay != null
        ? DateFormat('MMM').format(firstDay.date)
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          // Month label (only show for first week of month)
          SizedBox(
            width: 32,
            child: Text(
              weekIndex == 0 || _isFirstWeekOfMonth(week) ? monthLabel : '',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
              ),
            ),
          ),
          // Day cells
          Expanded(
            child: Row(
              children: week.map((day) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: day != null
                        ? _buildDayCell(context, day)
                        : Container(), // Empty cell for days outside range
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(BuildContext context, ActivityDay day) {
    final color = _getColorForStatus(day.status);

    return Tooltip(
      message: '${DateFormat('MMM dd').format(day.date)}\n'
          '${day.exerciseCount} exercises\n'
          '${day.completedExercises} completed',
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.grey[300]!,
            width: 0.5,
          ),
        ),
        child: day.exerciseCount > 0
            ? Center(
                child: Text(
                  day.exerciseCount.toString(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: day.status == 'none' || day.status == 'light'
                        ? const Color(0xFF0D4F48)
                        : Colors.white,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Less',
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          ),
          const SizedBox(width: 8),
          _buildLegendCell(_getColorForStatus('none')),
          _buildLegendCell(_getColorForStatus('light')),
          _buildLegendCell(_getColorForStatus('medium')),
          _buildLegendCell(_getColorForStatus('heavy')),
          const SizedBox(width: 8),
          Text(
            'More',
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendCell(Color color) {
    return Container(
      width: 20,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey[300]!, width: 0.5),
      ),
    );
  }

  Color _getColorForStatus(String status) {
    switch (status) {
      case 'none':
        return Colors.grey[100]!;
      case 'light':
        return const Color(0xFF0D4F48).withOpacity(0.3);
      case 'medium':
        return const Color(0xFF0D4F48).withOpacity(0.6);
      case 'heavy':
        return const Color(0xFF0D4F48);
      default:
        return Colors.grey[100]!;
    }
  }

  List<List<ActivityDay?>> _groupByWeeks(List<ActivityDay> days) {
    if (days.isEmpty) return [];

    final weeks = <List<ActivityDay?>>[];
    var currentWeek = <ActivityDay?>[];

    // Sort days by date
    final sortedDays = List<ActivityDay>.from(days)
      ..sort((a, b) => a.date.compareTo(b.date));

    // Find the first Monday before or on the first day
    var currentDate = sortedDays.first.date;
    while (currentDate.weekday != DateTime.monday) {
      currentDate = currentDate.subtract(const Duration(days: 1));
    }

    var dayIndex = 0;
    while (dayIndex < sortedDays.length || currentWeek.isNotEmpty) {
      // Start a new week
      if (currentWeek.isEmpty) {
        for (var i = 0; i < 7; i++) {
          final targetDate = currentDate.add(Duration(days: i));

          // Find if we have data for this date
          final dayData = sortedDays.firstWhere(
            (d) => d.date.year == targetDate.year &&
                   d.date.month == targetDate.month &&
                   d.date.day == targetDate.day,
            orElse: () => ActivityDay(
              date: targetDate,
              workoutCount: 0,
              exerciseCount: 0,
              completedExercises: 0,
              status: 'none',
            ),
          );

          currentWeek.add(dayData);
        }
        weeks.add(List.from(currentWeek));
        currentWeek.clear();
        currentDate = currentDate.add(const Duration(days: 7));
        dayIndex += 7;
      }
    }

    return weeks;
  }

  bool _isFirstWeekOfMonth(List<ActivityDay?> week) {
    final firstDay = week.firstWhere((d) => d != null, orElse: () => null);
    if (firstDay == null) return false;
    return firstDay.date.day <= 7;
  }
}
