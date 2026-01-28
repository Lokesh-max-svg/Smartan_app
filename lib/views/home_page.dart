import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String username = '';
  bool workout = true;
  Color progress1 = Colors.green;
  Color progress2 = Colors.green;
  Color progress3 = Colors.green;

  final List<String> muscleList = [
    "Select a Muscle",
    "Chest",
    "Back",
    "Shoulder",
    "Arms",
    "Legs",
    "Abs",
  ];

  // Map each muscle to a different image
  final Map<String, String> muscleImages = {
    "Select a Muscle": "asset/images/skeleton/skeleton.png",
    "Chest": "asset/images/skeleton/chest.png",
    "Back": "asset/images/skeleton/back.png",
    "Shoulder": "asset/images/skeleton/shoulder.png",
    "Arms": "asset/images/skeleton/arms.png",
    "Legs": "asset/images/skeleton/leg.png",
    "Abs": "asset/images/skeleton/abs.png",
  };

  String? selectedMuscle = "Select a Muscle";
  List<Map<String, dynamic>> allExercises = [];
  bool isLoading = true;
  DateTime selectedDate = DateTime.now();
  late String date;
  late String todayDate;

  @override
  void initState() {
    super.initState();
    _updateDateStrings();
    _loadUserData();
    _loadTodayWorkouts();
  }

  void _updateDateStrings() {
    date = "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}";
    todayDate = DateFormat('yyyy-MM-dd').format(selectedDate);
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0D4F48),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
        _updateDateStrings();
        isLoading = true;
      });
      _loadTodayWorkouts();
    }
  }

  Future<void> _loadUserData() async {
    final currentUser = _auth.currentUser;
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      username =
          currentUser?.displayName ?? prefs.getString('username') ?? 'User';
    });
  }

  Future<void> _loadTodayWorkouts() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      debugPrint('Loading workouts for user: ${currentUser.uid}, date: $todayDate');

      // Query workout plans for this user
      final snapshot = await _firestore
          .collection('workoutPlans')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      debugPrint('Found ${snapshot.docs.length} workout plans for user');

      List<Map<String, dynamic>> exercises = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();

        debugPrint('Workout plan document ID: ${doc.id}');
        debugPrint('Has workouts field: ${data['workouts'] != null}');

        // Check if workouts map exists and has today's date
        if (data['workouts'] != null && data['workouts'] is Map) {
          final workoutsMap = data['workouts'] as Map<String, dynamic>;

          debugPrint('Available workout dates: ${workoutsMap.keys.toList()}');
          debugPrint('Looking for date: $todayDate');
          debugPrint('Contains key check: ${workoutsMap.containsKey(todayDate)}');

          // Try all possible date formats
          var foundDate = false;
          for (var dateKey in workoutsMap.keys) {
            debugPrint('Checking date key: "$dateKey" (type: ${dateKey.runtimeType})');
            if (dateKey.toString() == todayDate) {
              foundDate = true;
              final todayWorkouts = workoutsMap[dateKey];

              debugPrint('Found matching date! Type: ${todayWorkouts.runtimeType}');

              if (todayWorkouts is List) {
                debugPrint('Found ${todayWorkouts.length} exercises for $dateKey');

                for (var exercise in todayWorkouts) {
                  if (exercise is Map<String, dynamic>) {
                    debugPrint('Adding exercise: ${exercise['name']}, muscle: ${exercise['muscle']}, muscle_name: ${exercise['muscle_name']}');
                    exercises.add({
                      'id': exercise['id']?.toString() ?? '',
                      'name': exercise['name'] ?? 'Unknown Exercise',
                      'muscle': exercise['muscle_name'] ?? exercise['muscle'] ?? 'Unknown',
                      'category': exercise['muscle_name'] ?? exercise['muscle'] ?? 'Unknown',
                      'difficulty': exercise['difficulty'] ?? 'Medium',
                      'sets': exercise['sets'] ?? 0,
                      'reps': exercise['reps'] ?? 0,
                      'duration': exercise['duration'] ?? '',
                      'image': exercise['image'] ?? '',
                      'muscleId': exercise['muscleId'] ?? 0,
                      'instanceId': exercise['instanceId'] ?? '',
                      'addedAt': exercise['addedAt'] ?? '',
                    });
                  }
                }
              }
              break;
            }
          }

          if (!foundDate) {
            debugPrint('❌ No matching date found for: $todayDate');
            debugPrint('Available dates were: ${workoutsMap.keys.toList()}');
          }
        } else {
          debugPrint('❌ No workouts map in document');
        }
      }

      debugPrint('Total exercises loaded: ${exercises.length}');

      // Debug: Show all unique muscle categories found
      final uniqueMuscles = exercises.map((e) => e['muscle']).toSet();
      debugPrint('Unique muscle categories found: $uniqueMuscles');

      setState(() {
        allExercises = exercises;
        isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Error loading workouts: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading workouts: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredExercises = selectedMuscle == "Select a Muscle"
        ? allExercises // Show all exercises when no muscle is selected
        : allExercises
              .where((exercise) {
                  final muscleName = exercise['muscle']?.toString().toLowerCase() ?? '';
                  final selectedMuscleLower = selectedMuscle?.toLowerCase() ?? '';
                  return muscleName == selectedMuscleLower;
                })
              .toList();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, $username!',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                            letterSpacing: 1
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          "Workout Plan • $date",
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: const Color(0xFF0D4F48),
                      child: Text(
                        username.isNotEmpty ? username[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Date Selector Card
                GestureDetector(
                  onTap: () => _selectDate(context),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D4F48),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.calendar_today,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Selected Date',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('EEEE, MMM d, yyyy').format(selectedDate),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),



                const SizedBox(height: 30),
                Column(
                  children: [
                    Row(
                      children: [
                        const Spacer(),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.5,
                          child: DropdownButton<String>(
                            dropdownColor: Colors.white,
                            value: selectedMuscle,
                            isExpanded: true,
                            items: muscleList.map((muscle) {
                              return DropdownMenuItem(
                                value: muscle,
                                child: Text(muscle),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() => selectedMuscle = value!);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Image.asset(
                      muscleImages[selectedMuscle]!,
                      width: MediaQuery.of(context).size.width * 0.8,
                    ),
                    const SizedBox(height: 20),

                    // Exercise count
                    if (allExercises.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          selectedMuscle == "Select a Muscle"
                              ? 'All Exercises (${allExercises.length})'
                              : '$selectedMuscle Exercises (${filteredExercises.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0D4F48),
                          ),
                        ),
                      ),

                    if (filteredExercises.isEmpty && allExercises.isNotEmpty)
                      Text(
                        "No exercises found for $selectedMuscle.",
                        style: const TextStyle(fontSize: 16),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredExercises.length,
                        itemBuilder: (context, index) {
                          final exercise = filteredExercises[index];
                          final difficulty = exercise['difficulty']?.toString().toLowerCase() ?? 'medium';

                          Color difficultyColor;
                          String difficultyText;
                          IconData difficultyIcon;

                          if (difficulty == "easy") {
                            difficultyColor = Colors.green;
                            difficultyText = 'Easy';
                            difficultyIcon = Icons.sentiment_satisfied;
                          } else if (difficulty == "medium") {
                            difficultyColor = Colors.orange;
                            difficultyText = 'Medium';
                            difficultyIcon = Icons.sentiment_neutral;
                          } else {
                            difficultyColor = Colors.red;
                            difficultyText = 'Hard';
                            difficultyIcon = Icons.sentiment_very_dissatisfied;
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  // Navigate to exercise detail
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      // Exercise Image
                                      Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          gradient: LinearGradient(
                                            colors: [
                                              const Color(0xFF0D4F48).withOpacity(0.1),
                                              const Color(0xFF0D4F48).withOpacity(0.05),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                        ),
                                        child: exercise['image'] != null && exercise['image'].toString().isNotEmpty
                                            ? ClipRRect(
                                                borderRadius: BorderRadius.circular(12),
                                                child: Image.network(
                                                  exercise['image'],
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return Icon(
                                                      Icons.fitness_center,
                                                      color: const Color(0xFF0D4F48).withOpacity(0.5),
                                                      size: 25,
                                                    );
                                                  },
                                                  loadingBuilder: (context, child, loadingProgress) {
                                                    if (loadingProgress == null) return child;
                                                    return Center(
                                                      child: CircularProgressIndicator(
                                                        value: loadingProgress.expectedTotalBytes != null
                                                            ? loadingProgress.cumulativeBytesLoaded /
                                                                loadingProgress.expectedTotalBytes!
                                                            : null,
                                                        strokeWidth: 2,
                                                        color: const Color(0xFF0D4F48),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              )
                                            : Icon(
                                                Icons.fitness_center,
                                                color: const Color(0xFF0D4F48).withOpacity(0.5),
                                                size: 36,
                                              ),
                                      ),
                                      const SizedBox(width: 14),

                                      // Exercise Details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              exercise['name'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 17,
                                                color: Colors.black87,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 8),

                                            // Muscle Category and Difficulty Badges Row
                                            Row(
                                              children: [
                                                // Muscle Category Tag
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF0D4F48).withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: const Color(0xFF0D4F48).withOpacity(0.3),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(
                                                        Icons.category,
                                                        size: 14,
                                                        color: Color(0xFF0D4F48),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        exercise['muscle'],
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Color(0xFF0D4F48),
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),

                                                // Difficulty Badge
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: difficultyColor.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: difficultyColor.withOpacity(0.3),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.signal_cellular_alt,
                                                        size: 12,
                                                        color: difficultyColor,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        difficultyText.toUpperCase(),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: difficultyColor,
                                                          fontWeight: FontWeight.bold,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Action Button
                                      PopupMenuButton<String>(
                                        icon: const Icon(
                                          Icons.more_vert,
                                          size: 20,
                                          color: Color(0xFF0D4F48),
                                        ),
                                        color: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        onSelected: (String value) {
                                          // Handle actions
                                          if (value == 'view') {
                                            // View exercise details
                                          } else if (value == 'tutorial') {
                                            // Navigate to tutorial
                                          }
                                        },
                                        itemBuilder: (BuildContext context) =>
                                            <PopupMenuEntry<String>>[
                                          const PopupMenuItem<String>(
                                            value: 'view',
                                            child: Row(
                                              children: [
                                                Icon(Icons.visibility, size: 18, color: Color(0xFF0D4F48)),
                                                SizedBox(width: 12),
                                                Text('View Details'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem<String>(
                                            value: 'tutorial',
                                            child: Row(
                                              children: [
                                                Icon(Icons.play_circle_outline, size: 18, color: Color(0xFF0D4F48)),
                                                SizedBox(width: 12),
                                                Text('Watch Tutorial'),
                                              ],
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
                        },
                      ),
                  ],
                ),
                if (allExercises.isEmpty)
                  Column(
                    children: [
                      const SizedBox(height: 40),
                      const Center(
                        child: Text(
                          "Please contact your coach for your exercise schedule.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF0D4F48),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Bottom action list (single row, two items)
                      Row(
                        children: [
                          Expanded(
                            child: Card(
                              color: Color(0xFF0D4F48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.play_circle_outline,
                                  color: Colors.white,
                                ),
                                title: const Text(
                                  "Explore Tutorials",
                                  style: TextStyle(fontSize: 11,color: Colors.white),
                                ),
                                onTap: () {
                                  // Navigate to tutorials
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Card(
                            color: Color(0xFF0D4F48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.trending_up,
                                  color: Colors.white,
                                ),
                                title: const Text(
                                  "View Trends",
                                  style: TextStyle(fontSize: 13, color: Colors.white),
                                ),
                                onTap: () {
                                  // Navigate to trends
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )

              ],
            ),
          ),
        ),
      ),
    );
  }

}
