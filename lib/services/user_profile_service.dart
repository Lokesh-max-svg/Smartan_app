import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Check if user profile is completed in Firestore
  /// Returns true if profile exists with required fields, false otherwise
  Future<bool> isProfileCompleted(String userId) async {
    try {
      final docSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .get();

      if (!docSnapshot.exists) {
        return false;
      }

      final data = docSnapshot.data();
      if (data == null) {
        return false;
      }

      // Check if all required fields are present
      final hasHeight = data.containsKey('heightInCm') && data['heightInCm'] != null;
      final hasWeight = data.containsKey('weightInKg') && data['weightInKg'] != null;
      final hasExpertise = data.containsKey('gymExpertise') && data['gymExpertise'] != null;
      final hasHealthIssues = data.containsKey('hasHealthIssues') && data['hasHealthIssues'] != null;

      return hasHeight && hasWeight && hasExpertise && hasHealthIssues;
    } catch (e) {
      print('Error checking profile completion: $e');
      return false;
    }
  }

  /// Get user status from Firestore
  /// Returns: 0 = enabled, -1 = blocked, 1 = deleted, null = not found
  Future<int?> getUserStatus(String userId) async {
    try {
      final docSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .get();

      if (!docSnapshot.exists) {
        return null;
      }

      final data = docSnapshot.data();
      if (data == null) {
        return null;
      }

      return data['status'] as int? ?? 0; // Default to 0 (enabled) if not set
    } catch (e) {
      print('Error getting user status: $e');
      return null;
    }
  }

  /// Check if user is active (status = 0)
  Future<bool> isUserActive(String userId) async {
    final status = await getUserStatus(userId);
    return status == 0;
  }

  /// Initialize user with default fields (user_type and status)
  Future<void> initializeUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'user_type': 'user',
        'status': 0, // 0 = enabled
        'createdAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error initializing user: $e');
      throw 'Error initializing user: $e';
    }
  }
}
