import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';

class LoginController extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final UserProfileService _profileService = UserProfileService();

  bool isLoading = false;

  Future<void> login({
    required BuildContext context,
    required GlobalKey<FormState> formKey,
    required String email,
    required String password,
  }) async {
    if (!formKey.currentState!.validate()) return;

    isLoading = true;
    notifyListeners();

    try {
      final userCredential = await _authService.login(email, password);
      final userId = userCredential.user!.uid;

      // Check user status
      final status = await _profileService.getUserStatus(userId);

      if (context.mounted) {
        // Validate user status
        if (status == -1) {
          // User is blocked
          await _authService.signOut();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your account has been blocked. Please contact support.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        } else if (status == 1) {
          // User is deleted
          await _authService.signOut();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This account has been deleted.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome back, ${userCredential.user?.displayName ?? userCredential.user?.email}!'),
            backgroundColor: Colors.green,
          ),
        );

        await Future.delayed(const Duration(seconds: 1));

        if (context.mounted) {
          // Check if profile is completed
          final isCompleted = await _profileService.isProfileCompleted(userId);
          if (isCompleted) {
            Navigator.pushReplacementNamed(context, '/dashboard');
          } else {
            Navigator.pushReplacementNamed(context, '/user-info');
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle(BuildContext context) async {
    isLoading = true;
    notifyListeners();

    try {
      final userCredential = await _authService.signInWithGoogle();

      if (userCredential != null) {
        await _authService.saveGoogleUser(userCredential.user!);
        final userId = userCredential.user!.uid;

        // Check user status
        final status = await _profileService.getUserStatus(userId);

        if (context.mounted) {
          // Validate user status
          if (status == -1) {
            // User is blocked
            await _authService.signOut();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Your account has been blocked. Please contact support.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
            return;
          } else if (status == 1) {
            // User is deleted
            await _authService.signOut();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This account has been deleted.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
            return;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Signed in as ${userCredential.user?.displayName}"),
              backgroundColor: Colors.green,
            ),
          );

          // Navigate based on profile completion
          await Future.delayed(const Duration(seconds: 1));

          if (context.mounted) {
            // Check if profile is completed
            final isCompleted = await _profileService.isProfileCompleted(userId);
            if (isCompleted) {
              Navigator.pushReplacementNamed(context, '/dashboard');
            } else {
              Navigator.pushReplacementNamed(context, '/user-info');
            }
          }
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Google Sign-In cancelled"),
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
