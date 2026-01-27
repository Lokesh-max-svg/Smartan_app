import 'package:flutter/material.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D4F48),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Progress',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Track your fitness journey',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 25),

                // Weekly Summary
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFA4FEB7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This Week',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0D4F48),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _summaryItem('Workouts', '0', Icons.fitness_center),
                          _summaryItem('Calories', '0', Icons.local_fire_department),
                          _summaryItem('Hours', '0', Icons.access_time),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),

                // Body Measurements
                const Text(
                  'Body Measurements',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 15),
                _measurementCard('Weight', '0 kg', Icons.monitor_weight, '0%'),
                const SizedBox(height: 10),
                _measurementCard('Body Fat', '0%', Icons.percent, '0%'),
                const SizedBox(height: 10),
                _measurementCard('Muscle Mass', '0 kg', Icons.fitness_center, '0%'),
                const SizedBox(height: 25),

                // Achievements
                const Text(
                  'Achievements',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: _achievementCard(
                        'First Workout',
                        Icons.stars,
                        Colors.yellow.shade700,
                        false,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _achievementCard(
                        '7 Day Streak',
                        Icons.local_fire_department,
                        Colors.orange.shade700,
                        false,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _achievementCard(
                        '30 Workouts',
                        Icons.emoji_events,
                        Colors.purple.shade700,
                        false,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _achievementCard(
                        'Goal Crusher',
                        Icons.rocket_launch,
                        Colors.blue.shade700,
                        false,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF0D4F48), size: 28),
        const SizedBox(height: 10),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0D4F48),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF0D4F48),
          ),
        ),
      ],
    );
  }

  Widget _measurementCard(String title, String value, IconData icon, String change) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFA4FEB7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF0D4F48),
              size: 24,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Text(
            change,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFFA4FEB7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _achievementCard(String title, IconData icon, Color color, bool unlocked) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: unlocked ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unlocked ? color.withOpacity(0.5) : Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: unlocked ? color : Colors.white.withOpacity(0.3),
            size: 32,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: unlocked ? Colors.white : Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}
