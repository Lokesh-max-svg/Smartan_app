import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class UserInfoController extends ChangeNotifier {
  final AuthService _authService = AuthService();

  bool isLoading = false;
  String selectedExpertise = 'Novice';
  bool hasHealthIssues = false;

  final List<String> expertiseLevels = ['Novice', 'Intermediate', 'Strong'];

  void setExpertise(String expertise) {
    selectedExpertise = expertise;
    notifyListeners();
  }

  void setHealthIssues(bool value) {
    hasHealthIssues = value;
    notifyListeners();
  }

  Future<void> saveUserInfo({
    required BuildContext context,
    required GlobalKey<FormState> formKey,
    required String userId,
    required double height,
    required double weight,
    String? healthIssuesDescription,
  }) async {
    if (!formKey.currentState!.validate()) return;

    if (hasHealthIssues && (healthIssuesDescription == null || healthIssuesDescription.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe your health issues'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    isLoading = true;
    notifyListeners();

    try {
      // Save user info to backend and get response with user status
      final response = await _authService.saveUserProfileViaBackend(
        userId: userId,
        heightInCm: height,
        weightInKg: weight,
        gymExpertise: selectedExpertise,
        hasHealthIssues: hasHealthIssues,
        healthIssuesDescription: hasHealthIssues ? healthIssuesDescription : null,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile setup completed!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );

        await Future.delayed(const Duration(seconds: 1));

        if (context.mounted) {
          // Get user status from backend response
          final userStatus = response['status'] ?? response['user']?['status'] ?? 0;
          
          if (userStatus == 2) {
            // Navigate to gym verification page if status is 2
            Navigator.pushReplacementNamed(context, '/gym-verification');
          } else if (userStatus == 0) {
            // Push directly to dashboard if status is 0 (enabled/active)
            Navigator.pushReplacementNamed(context, '/dashboard');
          } else {
            // Default to dashboard for other statuses
            Navigator.pushReplacementNamed(context, '/dashboard');
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving information: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
