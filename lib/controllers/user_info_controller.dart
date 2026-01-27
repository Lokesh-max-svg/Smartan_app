import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_info.dart';

class UserInfoController extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
      final userInfo = UserInfo(
        userId: userId,
        heightInCm: height,
        weightInKg: weight,
        gymExpertise: selectedExpertise,
        hasHealthIssues: hasHealthIssues,
        healthIssuesDescription: hasHealthIssues ? healthIssuesDescription : null,
        createdAt: DateTime.now(),
      );

      // Save user info along with user_type and status
      final dataToSave = {
        ...userInfo.toJson(),
        'user_type': 'user',
        'status': 0, // 0 = enabled
      };

      await _firestore
          .collection('users')
          .doc(userId)
          .set(dataToSave, SetOptions(merge: true));

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
          Navigator.pushReplacementNamed(context, '/dashboard');
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
