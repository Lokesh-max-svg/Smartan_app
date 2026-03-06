import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized API client for all backend communication
/// Replaces direct Firestore connections with HTTP API calls
class ApiClient {
  // Backend API URL
  // Use 10.0.2.2 for Android emulator (maps to host machine's localhost)
  static const String baseUrl = 'http://10.0.2.2:3000/api';
  static const String _baseUrl = baseUrl;

  /// Get authorization headers with JWT token
  static Future<Map<String, String>> _getHeaders({bool includeAuth = true}) async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (includeAuth) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  /// Handle API response and errors
  static Future<Map<String, dynamic>> _handleResponse(http.Response response) async {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return body;
      } else {
        throw ApiException(
          statusCode: response.statusCode,
          message: body['message'] ?? 'Request failed',
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to parse response: ${response.body}',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // AUTHENTICATION ENDPOINTS
  // ═══════════════════════════════════════════════════════════

  /// Sign up with email and password
  static Future<Map<String, dynamic>> signUpEmail({
    required String email,
    required String password,
    required String username,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/signup-email'),
      headers: await _getHeaders(includeAuth: false),
      body: jsonEncode({
        'email': email,
        'password': password,
        'username': username,
      }),
    );

    return _handleResponse(response);
  }

  /// Login with email and password
  static Future<Map<String, dynamic>> loginEmail({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/login-email'),
      headers: await _getHeaders(includeAuth: false),
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    return _handleResponse(response);
  }

  /// Authenticate with Google
  static Future<Map<String, dynamic>> googleAuth({
    required String idToken,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/google'),
      headers: await _getHeaders(includeAuth: false),
      body: jsonEncode({
        'idToken': idToken,
      }),
    );

    return _handleResponse(response);
  }

  // ═══════════════════════════════════════════════════════════
  // USER PROFILE ENDPOINTS
  // ═══════════════════════════════════════════════════════════

  /// Save or update user profile
  static Future<Map<String, dynamic>> saveUserProfile({
    String? userId,
    double? heightInCm,
    double? weightInKg,
    String? gymExpertise,
    bool? hasHealthIssues,
    String? displayName,
    String? healthIssuesDescription,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/user/profile'),
      headers: await _getHeaders(),
      body: jsonEncode({
        if (userId != null) 'userId': userId,
        if (heightInCm != null) 'heightInCm': heightInCm,
        if (weightInKg != null) 'weightInKg': weightInKg,
        if (gymExpertise != null) 'gymExpertise': gymExpertise,
        if (hasHealthIssues != null) 'hasHealthIssues': hasHealthIssues,
        if (displayName != null) 'displayName': displayName,
        if (healthIssuesDescription != null)
          'healthIssuesDescription': healthIssuesDescription,
      }),
    );

    return _handleResponse(response);
  }

  /// Get user profile
  static Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/user/profile/$userId'),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Check if user profile is completed
  static Future<Map<String, dynamic>> checkProfileStatus(String userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/user/profile-status/$userId'),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Get user status
  static Future<Map<String, dynamic>> getUserStatus(String userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/user/status/$userId'),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Get workout plan for a specific date (YYYY-MM-DD)
  static Future<Map<String, dynamic>> getWorkoutPlanForDate({
    required String userId,
    required String date,
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/user/workout-plan/$userId/$date'),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Initialize user with default fields
  static Future<Map<String, dynamic>> initializeUser(String userId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/user/initialize'),
      headers: await _getHeaders(),
      body: jsonEncode({'userId': userId}),
    );

    return _handleResponse(response);
  }

  // ═══════════════════════════════════════════════════════════
  // GYM MANAGEMENT ENDPOINTS
  // ═══════════════════════════════════════════════════════════

  /// Validate gym ID
  static Future<Map<String, dynamic>> validateGymId(String gymId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/gym/validate/$gymId'),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Upload proof image
  static Future<Map<String, dynamic>> uploadProofImage({
    required String userId,
    required String gymId,
    required List<int> imageBytes,
    String filename = 'proof.jpg',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/gym/upload-proof'),
    );

    final headers = await _getHeaders();
    request.headers.addAll(headers);

    request.fields['userId'] = userId;
    request.fields['gymId'] = gymId;
    
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: filename,
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    return _handleResponse(response);
  }

  /// Associate user with gym
  static Future<Map<String, dynamic>> associateUserWithGym({
    required String userId,
    required String gymId,
    String? proofImageUrl,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/gym/associate'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'userId': userId,
        'gymId': gymId,
        if (proofImageUrl != null) 'proofImageUrl': proofImageUrl,
      }),
    );

    return _handleResponse(response);
  }

  /// Leave gym association
  static Future<Map<String, dynamic>> leaveGym({
    required String userId,
    required String gymId,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/gym/leave'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'userId': userId,
        'gymId': gymId,
      }),
    );

    return _handleResponse(response);
  }

  /// Get user gyms
  static Future<Map<String, dynamic>> getUserGyms(
    String userId, {
    bool activeOnly = false,
    bool includeDetails = false,
  }) async {
    final queryParams = {
      'activeOnly': activeOnly.toString(),
      'includeDetails': includeDetails.toString(),
    };

    final response = await http.get(
      Uri.parse('$_baseUrl/gym/user-gyms/$userId')
          .replace(queryParameters: queryParams),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Get gym details
  static Future<Map<String, dynamic>> getGymDetails({
    required String organizationId,
    required String gymId,
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/gym/details/$organizationId/$gymId'),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  // ═══════════════════════════════════════════════════════════
  // TRENDS & ANALYTICS ENDPOINTS
  // ═══════════════════════════════════════════════════════════

  /// Get all trends data
  static Future<Map<String, dynamic>> getAllTrends(
    String userId, {
    String filter = 'last30Days',
    String? customStart,
    String? customEnd,
  }) async {
    final queryParams = {
      'filter': filter,
      if (customStart != null) 'customStart': customStart,
      if (customEnd != null) 'customEnd': customEnd,
    };

    final uri = Uri.parse('$_baseUrl/trends/all/$userId')
        .replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Get session history
  static Future<Map<String, dynamic>> getSessionHistory(
    String userId, {
    String filter = 'last30Days',
    String? customStart,
    String? customEnd,
    int? limit,
  }) async {
    final queryParams = {
      'filter': filter,
      if (customStart != null) 'customStart': customStart,
      if (customEnd != null) 'customEnd': customEnd,
      if (limit != null) 'limit': limit.toString(),
    };

    final uri = Uri.parse('$_baseUrl/trends/sessions/$userId')
        .replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Get workout data
  static Future<Map<String, dynamic>> getWorkoutData(
    String userId, {
    String? sessionId,
  }) async {
    final queryParams = {
      if (sessionId != null) 'sessionId': sessionId,
    };

    final uri = Uri.parse('$_baseUrl/trends/workouts/$userId')
        .replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  // ═══════════════════════════════════════════════════════════
  // SESSION MANAGEMENT ENDPOINTS
  // ═══════════════════════════════════════════════════════════

  /// Create a new session
  static Future<Map<String, dynamic>> createSession({
    required String userId,
    required String date,
    required List<Map<String, dynamic>> exercises,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/session/create'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'userId': userId,
        'date': date,
        'exercises': exercises,
      }),
    );

    return _handleResponse(response);
  }

  /// Get sessions for a user by date
  static Future<Map<String, dynamic>> getSessionsByDate({
    required String userId,
    required String date,
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/session/user/$userId/date/$date'),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Get session by document ID
  static Future<Map<String, dynamic>> getSession(String sessionId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/session/$sessionId'),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Get session by sessionId field
  static Future<Map<String, dynamic>> getSessionBySessionId(
    String sessionId,
  ) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/session/by-session-id/$sessionId'),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Get active session for user
  static Future<Map<String, dynamic>> getActiveSession(String userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/session/user/$userId/active'),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Get all active sessions for user
  static Future<Map<String, dynamic>> getActiveSessions(String userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/session/user/$userId/active-all'),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Get workouts by sessionId field
  static Future<Map<String, dynamic>> getSessionWorkoutsBySessionId(
    String sessionId,
  ) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/session/workouts/by-session-id/$sessionId'),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Get exercise image by exercise name
  static Future<Map<String, dynamic>> getExerciseImage(
    String exerciseName,
  ) async {
    final encoded = Uri.encodeComponent(exerciseName);
    final response = await http.get(
      Uri.parse('$_baseUrl/session/exercise-image/$encoded'),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Update session reid status
  static Future<Map<String, dynamic>> updateSessionReidStatus({
    required String sessionId,
    required int reidStatus,
  }) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/session/$sessionId/reid-status'),
      headers: await _getHeaders(),
      body: jsonEncode({'reidStatus': reidStatus}),
    );

    return _handleResponse(response);
  }

  /// Update session status
  static Future<Map<String, dynamic>> updateSessionStatus({
    required String sessionId,
    required String status,
  }) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/session/$sessionId/status'),
      headers: await _getHeaders(),
      body: jsonEncode({'status': status}),
    );

    return _handleResponse(response);
  }

  /// Close session and optionally update exercises
  static Future<Map<String, dynamic>> closeSession({
    required String sessionId,
    List<Map<String, dynamic>>? exercises,
  }) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/session/$sessionId/close'),
      headers: await _getHeaders(),
      body: jsonEncode({
        if (exercises != null) 'exercises': exercises,
      }),
    );

    return _handleResponse(response);
  }

  /// Update current user profile fields
  static Future<Map<String, dynamic>> updateCurrentUserProfile({
    String? displayName,
    String? photoURL,
  }) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/user/profile'),
      headers: await _getHeaders(),
      body: jsonEncode({
        if (displayName != null) 'displayName': displayName,
        if (photoURL != null) 'photoURL': photoURL,
      }),
    );

    return _handleResponse(response);
  }

  // ═══════════════════════════════════════════════════════════
  // TUTORIAL & PLAYBACK ENDPOINTS
  // ═══════════════════════════════════════════════════════════

  /// Get tutorial exercises with optional filters
  static Future<Map<String, dynamic>> getExercises({
    String? muscleName,
    String? search,
  }) async {
    final queryParams = {
      if (muscleName != null && muscleName.isNotEmpty) 'muscleName': muscleName,
      if (search != null && search.isNotEmpty) 'search': search,
    };

    final response = await http.get(
      Uri.parse('$_baseUrl/session/exercises').replace(queryParameters: queryParams),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Resolve playback folders for exercise in session
  static Future<Map<String, dynamic>> getPlaybackData({
    required String sessionId,
    required String exerciseName,
  }) async {
    final encodedName = Uri.encodeComponent(exerciseName);
    final response = await http.get(
      Uri.parse('$_baseUrl/session/playback-data/$sessionId/$encodedName'),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// List storage files under a path via backend proxy
  static Future<Map<String, dynamic>> listStorageFiles({
    required String path,
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/session/storage/list')
          .replace(queryParameters: {'path': path}),
      headers: await _getHeaders(),
    );

    return _handleResponse(response);
  }

  /// Download storage file bytes via backend proxy
  static Future<Uint8List> downloadStorageFile({
    required String path,
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/session/storage/file')
          .replace(queryParameters: {'path': path}),
      headers: await _getHeaders(),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }

    throw ApiException(
      statusCode: response.statusCode,
      message: 'Failed to download storage file',
    );
  }
}

/// Custom exception for API errors
class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() => message;
}
