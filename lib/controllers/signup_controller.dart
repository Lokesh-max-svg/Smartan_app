import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class SignupController extends ChangeNotifier {
  final AuthService _authService = AuthService();

  bool isLoading = false;

  /// Sign up via Node.js backend middleware
  /// - Validates form input
  /// - Calls backend API at http://localhost:3000/api/auth/signup-email
  /// - Saves user data locally on success
  /// - Navigates to '/user-info' on success
  /// - Shows error SnackBar on failure
  Future<void> signUp({
    required BuildContext context,
    required GlobalKey<FormState> formKey,
    required String email,
    required String username,
    required String password,
  }) async {
    if (!formKey.currentState!.validate()) return;

    isLoading = true;
    notifyListeners();

    try {
      // Call backend signup endpoint
      await _authService.signUpViaBackend(
        email: email,
        password: password,
        username: username,
      );

      if (context.mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful! Please complete your profile.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );

        // Brief delay to show snackbar
        await Future.delayed(const Duration(seconds: 1));

        if (context.mounted) {
          // Navigate to user info page to complete profile
          Navigator.pushReplacementNamed(context, '/user-info');
        }
      }
    } catch (e) {
      // Display error message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_formatErrorMessage(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signUpWithGoogle(BuildContext context) async {
    isLoading = true;
    notifyListeners();

    try {
      final userCredential = await _authService.signInWithGoogle();

      if (userCredential != null) {
        final sessionData = await _authService.saveGoogleUser(userCredential.user!);
        final displayName =
            (sessionData['displayName'] ?? userCredential.user?.displayName ?? 'User')
                .toString();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Signed up as $displayName. Please complete your profile.'),
              backgroundColor: Colors.green,
            ),
          );

          // Navigate to User Info page after successful sign-up
          await Future.delayed(const Duration(seconds: 1));

          if (context.mounted) {
            Navigator.pushReplacementNamed(context, '/user-info');
          }
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Google Sign-Up cancelled"),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${_formatErrorMessage(e.toString())}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Format error messages for display
  /// Removes stack trace and improves readability
  String _formatErrorMessage(String error) {
    // Extract the meaningful part of the error
    if (error.contains(':')) {
      return error.split(':').last.trim();
    }
    return error;
  }
}
