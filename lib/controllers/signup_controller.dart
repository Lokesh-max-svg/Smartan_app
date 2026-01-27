import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class SignupController extends ChangeNotifier {
  final AuthService _authService = AuthService();

  bool isLoading = false;

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
      await _authService.signUpWithEmailPassword(
        email: email,
        password: password,
        username: username,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful! Please complete your profile.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );

        await Future.delayed(const Duration(seconds: 1));

        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/user-info');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
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
        await _authService.saveGoogleUser(userCredential.user!);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Signed up as ${userCredential.user?.displayName}. Please complete your profile."),
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
            content: Text("Error: $e"),
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
