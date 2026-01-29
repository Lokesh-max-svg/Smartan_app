import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/trends_service.dart';
import '../models/exercise_frequency.dart';
import '../models/progress_metric.dart';
import '../models/activity_day.dart';
import '../models/session_summary.dart';
import '../widgets/trends/time_filter_chips.dart';
import '../widgets/trends/trends_summary_cards.dart';
import '../widgets/trends/muscle_distribution_chart.dart';
import '../widgets/trends/progress_line_chart.dart';
import '../widgets/trends/activity_heatmap.dart';
import '../widgets/trends/session_history_list.dart';
import 'session_analytics_page.dart';

class TrendsPage extends StatefulWidget {
  const TrendsPage({super.key});

  @override
  State<TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<TrendsPage> {
  final TrendsService _trendsService = TrendsService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  TimeFilter _selectedFilter = TimeFilter.today;
  bool _isLoading = true;
  String? _error;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  // Data
  List<ExerciseFrequency> _exerciseFrequencies = [];
  Map<String, List<ProgressMetric>> _progressMetrics = {};
  List<ActivityDay> _activityDays = [];
  List<SessionSummary> _sessionHistory = [];

  // Summary metrics
  int _totalWorkouts = 0;
  int _totalExercises = 0;
  double _avgCompletionRate = 0.0;

  @override
  void initState() {
    super.initState();
    _loadTrendsData();
  }

  Future<void> _loadTrendsData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final data = await _trendsService.getTrendsData(
        currentUser.uid,
        _selectedFilter,
        customStartDate: _customStartDate,
        customEndDate: _customEndDate,
      );

      setState(() {
        _exerciseFrequencies = data['exerciseFrequency'] as List<ExerciseFrequency>;
        _progressMetrics = data['progressMetrics'] as Map<String, List<ProgressMetric>>;
        _activityDays = data['activityCalendar'] as List<ActivityDay>;
        _sessionHistory = data['sessionHistory'] as List<SessionSummary>;

        // Calculate summary metrics
        _totalWorkouts = _sessionHistory.length;
        _totalExercises = _sessionHistory.fold(
          0,
          (sum, session) => sum + session.totalExercises,
        );
        _avgCompletionRate = _sessionHistory.isEmpty
            ? 0.0
            : _sessionHistory.fold(
                  0.0,
                  (sum, session) => sum + session.completionPercentage,
                ) /
                _sessionHistory.length;

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load trends data: $e';
        _isLoading = false;
      });
    }
  }

  void _onFilterChanged(TimeFilter filter) async {
    if (filter == TimeFilter.custom) {
      await _showCustomDatePicker();
    } else {
      setState(() {
        _selectedFilter = filter;
        _customStartDate = null;
        _customEndDate = null;
      });
      _loadTrendsData();
    }
  }

  Future<void> _showCustomDatePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 7)),
              end: DateTime.now(),
            ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0D4F48),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedFilter = TimeFilter.custom;
        _customStartDate = picked.start;
        _customEndDate = picked.end;
      });
      _loadTrendsData();
    }
  }

  void _onSessionTap(String sessionId, String docId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SessionAnalyticsPage(
          sessionId: sessionId,
          sessionDocId: docId,
        ),
      ),
    );
  }

  Map<String, int> _getMuscleGroupDistribution() {
    final muscleMap = <String, int>{};
    for (var frequency in _exerciseFrequencies) {
      muscleMap[frequency.muscleName] =
          (muscleMap[frequency.muscleName] ?? 0) + frequency.count;
    }
    return muscleMap;
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Workout Trends',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0D4F48),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              _trendsService.clearCache();
              _loadTrendsData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadTrendsData,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : SafeArea(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      _trendsService.clearCache();
                      await _loadTrendsData();
                    },
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Time filter chips
                            TimeFilterChips(
                              selectedFilter: _selectedFilter,
                              onFilterChanged: _onFilterChanged,
                            ),
                            if (_selectedFilter == TimeFilter.custom &&
                                _customStartDate != null &&
                                _customEndDate != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      size: 16,
                                      color: Color(0xFF0D4F48),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${_formatDate(_customStartDate!)} - ${_formatDate(_customEndDate!)}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF0D4F48),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 20),

                            // Summary cards
                            TrendsSummaryCards(
                              totalWorkouts: _totalWorkouts,
                              totalExercises: _totalExercises,
                              avgCompletionRate: _avgCompletionRate,
                            ),
                            const SizedBox(height: 24),

                            // Muscle Group Distribution
                            _buildSection(
                              title: 'Muscle Group Distribution',
                              icon: Icons.pie_chart,
                              child: MuscleDistributionChart(
                                muscleGroups: _getMuscleGroupDistribution(),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Progress Over Time
                            _buildSection(
                              title: 'Progress Over Time',
                              icon: Icons.show_chart,
                              child: ProgressLineChart(
                                progressMetrics: _progressMetrics,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Activity Heatmap
                            _buildSection(
                              title: 'Activity Calendar',
                              icon: Icons.calendar_month,
                              child: ActivityHeatmap(
                                activityDays: _activityDays,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Session History
                            _buildSection(
                              title: 'Recent Sessions',
                              icon: Icons.history,
                              child: SessionHistoryList(
                                sessions: _sessionHistory.take(10).toList(),
                                onSessionTap: _onSessionTap,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
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
          // Section header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: const Color(0xFF0D4F48),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D4F48),
                  ),
                ),
              ],
            ),
          ),
          // Section content
          child,
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
