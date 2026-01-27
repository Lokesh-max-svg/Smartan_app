import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_profile_service.dart';
import '../services/gym_service.dart';
import 'home_page.dart';
import 'workouts_page.dart';
import 'progress_page.dart';
import 'nutrition_page.dart';
import 'profile_page.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserProfileService _profileService = UserProfileService();
  final GymService _gymService = GymService();
  int _currentIndex = 0;
  bool _isCheckingProfile = true;

  final List<Widget> _pages = [
    const HomePage(),
    const WorkoutsPage(),
    const ProgressPage(),
    const NutritionPage(),
    const ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkRequirements();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App resumed, revalidate gym membership
      _checkRequirements();
    }
  }

  Future<void> _checkRequirements() async {
    setState(() {
      _isCheckingProfile = true;
    });

    final currentUser = _auth.currentUser;

    if (currentUser != null) {
      // Check if profile is completed
      final isCompleted = await _profileService.isProfileCompleted(currentUser.uid);

      if (!isCompleted) {
        // Profile not completed, redirect to user info page
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/user-info');
          return;
        }
      }

      // Check if user has any approved (active) gyms
      final userDoc = await _gymService.getUserGymsWithDetails(currentUser.uid);
      final hasActiveGym = userDoc.any((gym) => gym['status'] == 0);

      if (!hasActiveGym) {
        // No active gym (either no gyms or only pending), redirect to gym verification
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/gym-verification');
          return;
        }
      }
    }

    if (mounted) {
      setState(() {
        _isCheckingProfile = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingProfile) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D4F48),
        body: Center(
          child: Image.asset(
            'asset/images/loading1.gif',
            width: 200,
            height: 200,
          ),
        ),
      );
    }

    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
              child: SafeArea(
                child: Container(
                  height: 70,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem(0, Icons.home_outlined, Icons.home, 'Home'),
                      _buildNavItem(1, Icons.calendar_today_outlined, Icons.calendar_today, 'Trends'),
                      const SizedBox(width: 60), // Space for center button
                      _buildNavItem(3, Icons.video_collection, Icons.video_collection, 'Tutorials'),
                      _buildNavItem(4, Icons.person_outline, Icons.person, 'Profile'),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Large center button
          Positioned(
            top: -25,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _currentIndex = 2;
                });
              },
              child: Container(
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D4F48),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0D4F48).withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  _currentIndex == 2 ? Icons.fitness_center_outlined : Icons.fitness_center_outlined,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _currentIndex = index;
          });
        },
        child: Container(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? const Color(0xFF0D4F48) : Colors.grey,
                size: 26,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? const Color(0xFF0D4F48) : Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              // Underline indicator
              Container(
                height: 3,
                width: 40,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0D4F48) : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
