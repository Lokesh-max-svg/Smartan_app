import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // Sign in with Email and Password using Firebase
  Future<UserCredential> login(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      // Save user data locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userCredential.user!.uid);
      await prefs.setString('user_email', email.trim());
      await prefs.setString('username', userCredential.user?.displayName ?? '');

      return userCredential;
    } on FirebaseAuthException catch (e) {
      // Handle specific Firebase errors
      switch (e.code) {
        case 'user-not-found':
          throw 'No user found with this email';
        case 'wrong-password':
          throw 'Incorrect password';
        case 'invalid-email':
          throw 'Invalid email address';
        case 'user-disabled':
          throw 'This account has been disabled';
        case 'too-many-requests':
          throw 'Too many login attempts. Please try again later';
        default:
          throw e.message ?? 'Login failed';
      }
    } catch (e) {
      throw 'Login failed: $e';
    }
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } catch (e) {
      print("Error signing in with Google: $e");
      return null;
    }
  }

  // ✅ Save Google user safely
  Future<void> saveGoogleUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', user.uid);
    await prefs.setString('user_email', user.email ?? '');
    await prefs.setString('username', user.displayName ?? '');
  }

  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }

  // Sign up with Email and Password
  Future<UserCredential> signUpWithEmailPassword({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      // Create user in Firebase Auth
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      // Update display name
      await userCredential.user?.updateDisplayName(username.trim());
      await userCredential.user?.reload();

      // Save user data locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userCredential.user!.uid);
      await prefs.setString('user_email', email.trim());
      await prefs.setString('username', username.trim());

      return userCredential;
    } on FirebaseAuthException catch (e) {
      // Handle specific Firebase errors
      switch (e.code) {
        case 'weak-password':
          throw 'Password is too weak';
        case 'email-already-in-use':
          throw 'An account already exists with this email';
        case 'invalid-email':
          throw 'Invalid email address';
        case 'operation-not-allowed':
          throw 'Email/password accounts are not enabled';
        default:
          throw e.message ?? 'Registration failed';
      }
    } catch (e) {
      throw 'Registration failed: $e';
    }
  }
}
