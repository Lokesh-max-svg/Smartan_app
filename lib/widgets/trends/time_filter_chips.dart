import 'package:flutter/material.dart';
import '../../services/trends_service.dart';

class TimeFilterChips extends StatelessWidget {
  final TimeFilter selectedFilter;
  final Function(TimeFilter) onFilterChanged;

  const TimeFilterChips({
    super.key,
    required this.selectedFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip(
            context,
            'Today',
            TimeFilter.today,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            context,
            '7 Days',
            TimeFilter.last7Days,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            context,
            '15 Days',
            TimeFilter.last15Days,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            context,
            '30 Days',
            TimeFilter.last30Days,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            context,
            '90 Days',
            TimeFilter.last90Days,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            context,
            'Custom',
            TimeFilter.custom,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context,
    String label,
    TimeFilter filter,
  ) {
    final isSelected = selectedFilter == filter;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onFilterChanged(filter),
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFF0D4F48),
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : const Color(0xFF0D4F48),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: const Color(0xFF0D4F48),
          width: isSelected ? 2 : 1,
        ),
      ),
    );
  }
}
