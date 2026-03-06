import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/user_profile_service.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final UserProfileService _profileService = UserProfileService();

  Future<void> _navigateBasedOnAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final authToken = prefs.getString('auth_token');

    if ((userId ?? '').isNotEmpty && (authToken ?? '').isNotEmpty) {
      final isCompleted = await _profileService.isProfileCompleted(userId!);

      if (mounted) {
        if (isCompleted) {
          Navigator.pushReplacementNamed(context, '/dashboard');
        } else {
          Navigator.pushReplacementNamed(context, '/user-info');
        }
      }
    } else {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // Show splash for 1 second then check auth
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _navigateBasedOnAuth();
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: MediaQuery.of(context).size.width*1.0,
        color: Color(0xFF0D4F48),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset('asset/images/smartan.jpg',width: MediaQuery.of(context).size.width*0.7,),
            ],
          ),
        ),
      ),
    );
  }
}
