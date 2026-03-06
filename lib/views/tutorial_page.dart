import 'package:flutter/material.dart';
import '../services/api_client.dart';

// Exercise Model
class Exercise {
  final String id;
  final String name;
  final String? description;
  final String? muscleCategory;
  final String? muscleName;
  final String? difficulty;
  final String? imageUrl;
  final int? exerciseId;
  final int? muscleId;

  Exercise({
    required this.id,
    required this.name,
    this.description,
    this.muscleCategory,
    this.muscleName,
    this.difficulty,
    this.imageUrl,
    this.exerciseId,
    this.muscleId,
  });

  factory Exercise.fromMap(Map<String, dynamic> data) {
    final imageUrl = data['image'] as String?;
    return Exercise(
      id: (data['id'] ?? '').toString(),
      name: data['exercise_name'] ?? 'Unnamed Exercise',
      description: data['description'],
      muscleCategory: data['muscleCategory'],
      muscleName: data['muscle_name'],
      difficulty: data['difficulty'],
      imageUrl: (imageUrl != null && imageUrl.isNotEmpty) ? imageUrl : null,
      exerciseId: data['exercise_id'],
      muscleId: data['muscle_id'],
    );
  }
}

class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key});

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedMuscleType = 'All';
  List<String> _muscleTypes = ['All'];
  List<Exercise> _allExercises = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // App colors
  static const Color primaryColor = Color(0xFF0D4F48);
  static const Color selectedChipColor = Color(0xFF90EE90);
  static const Color unselectedChipColor = Colors.transparent;

  @override
  void initState() {
    super.initState();
    _loadMuscleTypes();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMuscleTypes() async {
    try {
      final response = await ApiClient.getExercises();
      final raw = (response['exercises'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final exercises = raw.map(Exercise.fromMap).toList();

      final Set<String> muscleTypes = {'All'};

      for (final exercise in exercises) {
        if (exercise.muscleName != null && exercise.muscleName!.isNotEmpty) {
          muscleTypes.add(exercise.muscleName!);
        }
      }

      // Sort muscle types with "All" first, then alphabetically
      final muscleTypesList = muscleTypes.toList();
      muscleTypesList.remove('All');
      muscleTypesList.sort();
      muscleTypesList.insert(0, 'All');

      setState(() {
        _allExercises = exercises;
        _muscleTypes = muscleTypesList;
        _selectedMuscleType = 'All';
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Error loading muscle types: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading exercises: $e'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                setState(() {
                  _isLoading = true;
                });
                _loadMuscleTypes();
              },
            ),
          ),
        );
      }
    }
  }

  List<Exercise> _getExercises() {
    var exercises = _allExercises;

    if (_selectedMuscleType != 'All') {
      exercises = exercises
          .where((exercise) => exercise.muscleName == _selectedMuscleType)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      exercises = exercises.where((exercise) {
        final name = exercise.name.toLowerCase();
        final muscleName = exercise.muscleName?.toLowerCase() ?? '';
        final category = exercise.muscleCategory?.toLowerCase() ?? '';
        final difficulty = exercise.difficulty?.toLowerCase() ?? '';
        return name.contains(_searchQuery) ||
               muscleName.contains(_searchQuery) ||
               category.contains(_searchQuery) ||
               difficulty.contains(_searchQuery);
      }).toList();
    }

    return exercises;
  }

  Color _getDifficultyColor(String? difficulty) {
    if (difficulty == null) return Colors.grey;
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'hard':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section with Chip Filters
            Container(
              decoration: const BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tutorials',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Filter based on Categories',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Search Bar
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search exercises...',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 15,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: primaryColor.withOpacity(0.7),
                            size: 22,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear,
                                    color: Colors.grey.shade600,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Horizontal Chip Filters
                    SizedBox(
                      height: 45,
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _muscleTypes.length,
                              itemBuilder: (context, index) {
                                final muscleType = _muscleTypes[index];
                                final isSelected = _selectedMuscleType == muscleType;

                                return Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: FilterChip(
                                    label: Text(
                                      muscleType,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.black87
                                            : Colors.black,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: 12,
                                      ),
                                    ),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setState(() {
                                        _selectedMuscleType = muscleType;
                                      });
                                    },
                                    backgroundColor: unselectedChipColor,
                                    selectedColor: selectedChipColor,
                                    side: BorderSide(
                                      color: isSelected
                                          ? selectedChipColor
                                          : Colors.white.withOpacity(0.5),
                                      width: 1.5,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),

            // Exercise Count
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Builder(
                builder: (context) {
                  final count = _getExercises().length;
                  return Text(
                    '$count ${count == 1 ? 'Exercise' : 'Exercises'}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
            ),

            // Exercise List
            Expanded(
              child: Builder(
                builder: (context) {
                  final exercises = _getExercises();

                  if (exercises.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.fitness_center,
                            size: 80,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No exercises available',
                            style: TextStyle(
                              fontSize: 20,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _selectedMuscleType != 'All'
                                ? 'Try selecting a different category'
                                : 'Add exercises to get started',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: exercises.length,
                    itemBuilder: (context, index) {
                      final exercise = exercises[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
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
                              // Handle exercise tap - navigate to detail page
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  // Exercise Image
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: LinearGradient(
                                        colors: [
                                          primaryColor.withOpacity(0.1),
                                          primaryColor.withOpacity(0.05),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: exercise.imageUrl != null
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: Image.network(
                                              exercise.imageUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                return Icon(
                                                  Icons.fitness_center,
                                                  color: primaryColor.withOpacity(0.5),
                                                  size: 36,
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
                                                    color: primaryColor,
                                                  ),
                                                );
                                              },
                                            ),
                                          )
                                        : Icon(
                                            Icons.fitness_center,
                                            color: primaryColor.withOpacity(0.5),
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
                                          exercise.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 10),

                                        // Tags Row
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: [
                                            if (exercise.muscleName != null)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: primaryColor.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: primaryColor.withOpacity(0.3),
                                                    width: 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.category,
                                                      size: 12,
                                                      color: primaryColor,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      exercise.muscleName!,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: primaryColor,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (exercise.difficulty != null)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _getDifficultyColor(exercise.difficulty)
                                                      .withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: _getDifficultyColor(exercise.difficulty)
                                                        .withOpacity(0.3),
                                                    width: 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.signal_cellular_alt,
                                                      size: 12,
                                                      color: _getDifficultyColor(exercise.difficulty),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      exercise.difficulty!.toUpperCase(),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: _getDifficultyColor(exercise.difficulty),
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

                                  // Arrow Icon
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: primaryColor.withOpacity(0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.arrow_forward_ios,
                                      size: 14,
                                      color: primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
