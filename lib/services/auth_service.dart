import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  static const String _apiBaseUrl = ApiClient.baseUrl;
  static const String _authBaseUrl = '$_apiBaseUrl/auth';

  Map<String, dynamic> _decodeBody(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw 'Invalid server response';
    }
  }

  Map<String, dynamic> _payloadFromBody(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return body;
  }

  Future<void> _persistSession({
    required Map<String, dynamic> payload,
    String? fallbackEmail,
    String? fallbackUsername,
    String? fallbackUid,
  }) async {
    final token = (payload['token'] ?? '').toString();
    final uid = (payload['uid'] ?? fallbackUid ?? '').toString();
    final email = (payload['email'] ?? fallbackEmail ?? '').toString();
    final username =
        (payload['username'] ?? payload['displayName'] ?? fallbackUsername ?? 'User')
            .toString();

    if (token.isEmpty) {
      throw 'Token missing from server response';
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);

    if (uid.isNotEmpty) {
      await prefs.setString('user_id', uid);
    }
    if (email.isNotEmpty) {
      await prefs.setString('user_email', email);
    }
    await prefs.setString('username', username);

    final firebaseToken = (payload['firebaseToken'] ?? '').toString();
    if (firebaseToken.isNotEmpty) {
      await prefs.setString('firebase_token', firebaseToken);
    }
  }

  Future<Map<String, dynamic>> loginViaBackend({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_authBaseUrl/login-email'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim(),
              'password': password.trim(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      final responseBody = _decodeBody(response);
      if (response.statusCode != 200) {
        throw (responseBody['message'] ?? 'Login failed').toString();
      }

      final payload = _payloadFromBody(responseBody);
      await _persistSession(payload: payload, fallbackEmail: email.trim());
      return payload;
    } on TimeoutException {
      throw 'Server timeout';
    } on http.ClientException catch (e) {
      throw 'Network error: ${e.message}';
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return null;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> saveGoogleUser(User user) async {
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw 'Unable to get Google token';
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_authBaseUrl/google'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'idToken': idToken}),
          )
          .timeout(const Duration(seconds: 30));

      final responseBody = _decodeBody(response);
      if (response.statusCode != 200) {
        throw (responseBody['message'] ?? 'Google sign-in failed').toString();
      }

      final payload = _payloadFromBody(responseBody);
      await _persistSession(
        payload: payload,
        fallbackEmail: user.email,
        fallbackUsername: user.displayName,
        fallbackUid: user.uid,
      );
      return payload;
    } on TimeoutException {
      throw 'Server timeout';
    } on http.ClientException catch (e) {
      throw 'Network error: ${e.message}';
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('firebase_token');
    await prefs.remove('user_id');
    await prefs.remove('user_email');
    await prefs.remove('username');
  }

  Future<Map<String, dynamic>> signUpViaBackend({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_authBaseUrl/signup-email'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim(),
              'password': password.trim(),
              'username': username.trim(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      final responseBody = _decodeBody(response);
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw (responseBody['message'] ?? 'Registration failed').toString();
      }

      final payload = _payloadFromBody(responseBody);
      await _persistSession(
        payload: payload,
        fallbackEmail: email.trim(),
        fallbackUsername: username.trim(),
      );
      return payload;
    } on TimeoutException {
      throw 'Server timeout';
    } on http.ClientException catch (e) {
      throw 'Network error: ${e.message}';
    }
  }

  Future<Map<String, dynamic>> saveUserProfileViaBackend({
    required String userId,
    required double heightInCm,
    required double weightInKg,
    required String gymExpertise,
    required bool hasHealthIssues,
    String? healthIssuesDescription,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';

      if (token.isEmpty) {
        throw 'Please log in again';
      }

      final profileResponse = await http
          .post(
            Uri.parse('$_apiBaseUrl/user/profile'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'heightInCm': heightInCm,
              'weightInKg': weightInKg,
              'gymExpertise': gymExpertise,
              'hasHealthIssues': hasHealthIssues,
              if (healthIssuesDescription != null &&
                  healthIssuesDescription.isNotEmpty)
                'healthIssuesDescription': healthIssuesDescription,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final profileBody = _decodeBody(profileResponse);
      if (profileResponse.statusCode != 200 && profileResponse.statusCode != 201) {
        throw (profileBody['message'] ?? 'Failed to save profile').toString();
      }

      final statusResponse = await http
          .get(
            Uri.parse('$_apiBaseUrl/user/status/$userId'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      final statusBody = _decodeBody(statusResponse);
      final status = (statusBody['status'] ?? 0) as int;

      return {
        ...profileBody,
        'status': status,
      };
    } on TimeoutException {
      throw 'Server timeout';
    } on http.ClientException catch (e) {
      throw 'Network error: ${e.message}';
    }
  }

  @Deprecated('Use signUpViaBackend instead')
  Future<UserCredential> signUpWithEmailPassword({
    required String email,
    required String password,
    required String username,
  }) async {
    throw UnsupportedError(
      'signUpWithEmailPassword is deprecated. Use signUpViaBackend instead.',
    );
  }
}
