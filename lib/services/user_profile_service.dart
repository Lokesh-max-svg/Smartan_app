import 'api_client.dart';

/// User Profile Service - Uses backend API instead of direct Firestore
class UserProfileService {
  /// Check if user profile is completed via backend API
  /// Returns true if profile exists with required fields, false otherwise
  Future<bool> isProfileCompleted(String userId) async {
    try {
      final response = await ApiClient.checkProfileStatus(userId);
      return response['isCompleted'] as bool? ?? false;
    } catch (e) {
      print('Error checking profile completion: $e');
      return false;
    }
  }

  /// Get user status from backend API
  /// Returns: 0 = enabled, -1 = blocked, 1 = deleted, null = not found
  Future<int?> getUserStatus(String userId) async {
    try {
      final response = await ApiClient.getUserStatus(userId);
      return response['status'] as int?;
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
      await ApiClient.initializeUser(userId);
    } catch (e) {
      print('Error initializing user: $e');
      throw 'Error initializing user: $e';
    }
  }

  /// Get full user profile
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await ApiClient.getUserProfile(userId);
      return response['data'] as Map<String, dynamic>?;
    } catch (e) {
      print('Error getting user profile: $e');
      return null;
    }
  }
}
