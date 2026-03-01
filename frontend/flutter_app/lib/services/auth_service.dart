import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Riverpod provider for the current Firebase user stream.
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Riverpod provider for the AuthService singleton.
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Firebase Authentication service.
///
/// Supports Google Sign-In and email/password.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  /// Current user (synchronous check).
  User? get currentUser => _auth.currentUser;

  /// Whether a user is signed in.
  bool get isSignedIn => currentUser != null;

  /// Get Firebase ID token for WebSocket authentication.
  Future<String?> getIdToken() async {
    return await currentUser?.getIdToken();
  }

  /// Sign in with Google (google_sign_in 7.x API).
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Authenticate with Google using the 7.x API.
      final googleUser = await _googleSignIn.authenticate();

      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } catch (e) {
      debugPrint('[Auth] Google Sign-In failed: $e');
      rethrow;
    }
  }

  /// Sign in with email and password.
  Future<UserCredential> signInWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      debugPrint('[Auth] Email Sign-In failed: $e');
      rethrow;
    }
  }

  /// Create account with email and password.
  Future<UserCredential> createAccount(String email, String password) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      debugPrint('[Auth] Account creation failed: $e');
      rethrow;
    }
  }

  /// Sign out.
  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.disconnect(),
    ]);
  }
}
