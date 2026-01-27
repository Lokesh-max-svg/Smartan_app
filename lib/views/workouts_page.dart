import 'package:flutter/material.dart';

class WorkoutsPage extends StatelessWidget {
  const WorkoutsPage({super.key});

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
                  'Workouts',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Choose your workout plan',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 25),

                // Categories
                const Text(
                  'Categories',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _categoryChip('All', true),
                      _categoryChip('Strength', false),
                      _categoryChip('Cardio', false),
                      _categoryChip('Flexibility', false),
                      _categoryChip('HIIT', false),
                    ],
                  ),
                ),
                const SizedBox(height: 25),

                // Workout Plans
                const Text(
                  'Popular Workouts',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 15),
                _workoutPlanCard(
                  'Full Body Workout',
                  '45 min',
                  'Intermediate',
                  Icons.fitness_center,
                  const Color(0xFFA4FEB7),
                ),
                const SizedBox(height: 15),
                _workoutPlanCard(
                  'Chest & Triceps',
                  '40 min',
                  'Advanced',
                  Icons.accessibility_new,
                  Colors.orange.shade300,
                ),
                const SizedBox(height: 15),
                _workoutPlanCard(
                  'Cardio Blast',
                  '30 min',
                  'Beginner',
                  Icons.directions_run,
                  Colors.blue.shade300,
                ),
                const SizedBox(height: 15),
                _workoutPlanCard(
                  'Back & Biceps',
                  '45 min',
                  'Intermediate',
                  Icons.fitness_center,
                  Colors.purple.shade300,
                ),
                const SizedBox(height: 15),
                _workoutPlanCard(
                  'Leg Day Power',
                  '50 min',
                  'Advanced',
                  Icons.accessibility,
                  Colors.red.shade300,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(String label, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFA4FEB7) : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: isSelected ? const Color(0xFFA4FEB7) : Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: isSelected ? const Color(0xFF0D4F48) : Colors.white,
        ),
      ),
    );
  }

  Widget _workoutPlanCard(
    String title,
    String duration,
    String level,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
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
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: Colors.white.withOpacity(0.7),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      duration,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Icon(
                      Icons.signal_cellular_alt,
                      size: 14,
                      color: Colors.white.withOpacity(0.7),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      level,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios,
            color: Colors.white70,
            size: 16,
          ),
        ],
      ),
    );
  }
}
