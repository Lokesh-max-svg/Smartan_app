import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gym.dart';
import 'api_client.dart';

/// Gym Service - Uses backend API instead of direct Firestore
class GymService {
  /// Validate gym ID by checking if it exists via backend API
  Future<Gym?> validateGymId(String gymId) async {
    try {
      print('Validating gym ID: $gymId');

      final response = await ApiClient.validateGymId(gymId);
      
      if (response['success'] == true && response['gym'] != null) {
        final gymData = response['gym'] as Map<String, dynamic>;
        return Gym.fromJson(gymData);
      }

      print('Gym not found');
      return null;
    } catch (e) {
      print('Error validating gym ID: $e');
      return null;
    }
  }

  /// Save gym info locally (gym data already exists in Firestore)
  Future<void> saveGymDataLocally(Gym gym) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gym_id', gym.gymId);
      await prefs.setString('organization_id', gym.organizationId);
      await prefs.setString('gym_name', gym.name);
    } catch (e) {
      throw 'Error saving gym data locally: $e';
    }
  }

  /// Upload proof image via backend API
  Future<String> uploadProofImage(String userId, String gymId, File imageFile) async {
    try {
      print('Uploading proof image for user $userId, gym $gymId');

      final imageBytes = await imageFile.readAsBytes();
      final response = await ApiClient.uploadProofImage(
        userId: userId,
        gymId: gymId,
        imageBytes: imageBytes,
        filename: 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final downloadUrl = response['downloadUrl'] as String;
      print('Image uploaded successfully: $downloadUrl');

      return downloadUrl;
    } catch (e) {
      print('Error uploading proof image: $e');
      throw 'Error uploading image: $e';
    }
  }

  /// Associate user with gym via backend API
  Future<void> associateUserWithGym(String userId, String gymId, {String? proofImageUrl}) async {
    try {
      print('Associating user $userId with gym $gymId');

      await ApiClient.associateUserWithGym(
        userId: userId,
        gymId: gymId,
        proofImageUrl: proofImageUrl,
      );

      print('User associated with gym successfully');

      // Update local cache
      await _updateLocalGymCache(userId);
    } catch (e) {
      print('Error associating user with gym: $e');
      throw 'Error associating user with gym: $e';
    }
  }

  /// Get all active gym IDs for user
  Future<List<String>> getUserGymIds(String userId, {bool forceRefresh = false}) async {
    try {
      print('Getting gym IDs for user: $userId (forceRefresh: $forceRefresh)');

      if (!forceRefresh) {
        // Check local cache first
        final prefs = await SharedPreferences.getInstance();
        final localGymIds = prefs.getString('user_gym_ids');
        if (localGymIds != null && localGymIds.isNotEmpty) {
          final ids = localGymIds.split(',').where((id) => id.isNotEmpty).toList();
          print('Found local gym IDs: $ids');
          return ids;
        }
      }

      // Fetch from backend
      print('Fetching gym IDs from backend...');
      final response = await ApiClient.getUserGyms(userId, activeOnly: true);
      
      final gymIds = (response['gymIds'] as List<dynamic>?)
          ?.map((id) => id.toString())
          .toList() ?? [];

      print('Backend active/pending gym IDs: $gymIds');

      // Update local cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_gym_ids', gymIds.join(','));

      return gymIds;
    } catch (e) {
      print('Error getting gym IDs: $e');
      return [];
    }
  }

  /// Update local gym cache from backend
  Future<void> _updateLocalGymCache(String userId) async {
    try {
      final response = await ApiClient.getUserGyms(userId, activeOnly: true);
      final gymIds = (response['gymIds'] as List<dynamic>?)
          ?.map((id) => id.toString())
          .toList() ?? [];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_gym_ids', gymIds.join(','));
    } catch (e) {
      print('Error updating local gym cache: $e');
    }
  }
      if (!forceRefresh) {
        // Check locally first
        final prefs = await SharedPreferences.getInstance();
        final localGymIds = prefs.getString('user_gym_ids');
        if (localGymIds != null && localGymIds.isNotEmpty) {
          final ids = localGymIds.split(',').where((id) => id.isNotEmpty).toList();
          print('Found local gym IDs: $ids');
          return ids;
        }
      }

      // Check Firestore
      print('Checking Firestore for gym IDs...');
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (userDoc.exists) {
        final data = userDoc.data();
        final gyms = data?['gyms'] as List<dynamic>?;

        if (gyms != null && gyms.isNotEmpty) {
          // Get active and pending gyms (status = 0 or 2)
          final activeGymIds = gyms
              .where((g) => g['status'] == 0 || g['status'] == 2)
              .map((g) => g['gymId'].toString())
              .toList();

          print('Firestore active/pending gym IDs: $activeGymIds');

          // Update local cache
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_gym_ids', activeGymIds.join(','));

          return activeGymIds;
        } else {
          // Clear local cache if no gyms in Firestore
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('user_gym_ids');
          return [];
        }
      }

      print('User document does not exist in Firestore');
      // Clear local cache if user doc doesn't exist
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_gym_ids');

      return [];
    } catch (e) {
      print('Error getting gym IDs: $e');
      return [];
    }
  }

  /// Check if user is already associated with a gym (legacy method for backward compatibility)
  @Deprecated('Use getUserGymIds instead')
  Future<String?> getUserGymId(String userId, {bool forceRefresh = false}) async {
    final gymIds = await getUserGymIds(userId, forceRefresh: forceRefresh);
    return gymIds.isNotEmpty ? gymIds.first : null;
  }

  /// Clear all gym-related cached data
  Future<void> clearGymCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_gym_ids');
      await prefs.remove('user_gym_id'); // Legacy
      await prefs.remove('gym_id');
      await prefs.remove('organization_id');
      await prefs.remove('gym_name');
      print('Gym cache cleared');
    } catch (e) {
      print('Error clearing gym cache: $e');
    }
  }

  /// Remove user from specific gym (update status to -1 = left)
  Future<void> removeUserFromGym(String userId, String gymId) async {
    try {
      print('Removing user $userId from gym $gymId');

      // Get current user document
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final data = userDoc.data() ?? {};

      // Get existing gyms array
      List<Map<String, dynamic>> gyms = [];
      if (data['gyms'] != null) {
        gyms = List<Map<String, dynamic>>.from(data['gyms']);
      }

      // Find and update the specific gym's status
      final gymIndex = gyms.indexWhere((g) => g['gymId'] == gymId);
      if (gymIndex != -1) {
        gyms[gymIndex]['status'] = -1; // -1 = left
        gyms[gymIndex]['leftAt'] = DateTime.now().toIso8601String();
      }

      // Update user document (keeps height, weight, and all other data)
      await _firestore.collection('users').doc(userId).update({
        'gyms': gyms,
      });

      print('User removed from gym in Firestore');

      // Update local cache (include both active and pending)
      final prefs = await SharedPreferences.getInstance();
      final activeGymIds = gyms.where((g) => g['status'] == 0 || g['status'] == 2).map((g) => g['gymId'].toString()).toList();
      await prefs.setString('user_gym_ids', activeGymIds.join(','));

      print('User successfully removed from gym');
    } catch (e) {
      print('Error removing user from gym: $e');
      throw 'Error leaving gym: $e';
    }
  }

  /// Get all gym details for the user (active and inactive)
  Future<List<Map<String, dynamic>>> getUserGymsWithDetails(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final data = userDoc.data() ?? {};

      final gyms = data['gyms'] as List<dynamic>?;
      if (gyms == null || gyms.isEmpty) {
        return [];
      }

      List<Map<String, dynamic>> gymsWithDetails = [];

      for (var gymEntry in gyms) {
        final gymId = gymEntry['gymId'];
        final status = gymEntry['status'];

        // Fetch gym details
        final gym = await validateGymId(gymId);
        if (gym != null) {
          gymsWithDetails.add({
            'gym': gym,
            'status': status,
            'joinedAt': gymEntry['joinedAt'],
            'leftAt': gymEntry['leftAt'],
            'rejoinedAt': gymEntry['rejoinedAt'],
          });
        }
      }

      return gymsWithDetails;
    } catch (e) {
      print('Error getting user gyms with details: $e');
      return [];
    }
  }

  /// Get current gym details for the user (legacy - returns first active gym)
  @Deprecated('Use getUserGymsWithDetails instead')
  Future<Gym?> getCurrentGymDetails(String userId) async {
    try {
      final gymsWithDetails = await getUserGymsWithDetails(userId);
      final activeGym = gymsWithDetails.firstWhere(
        (g) => g['status'] == 0,
        orElse: () => {},
      );

      return activeGym.isNotEmpty ? activeGym['gym'] : null;
    } catch (e) {
      print('Error getting current gym details: $e');
      return null;
    }
  }
}
