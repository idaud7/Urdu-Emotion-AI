import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import 'email_report_service.dart';
import 'notification_service.dart';

enum UserRole { user, admin }

/// Auth service backed by Firebase Authentication for both users and admin.
///
/// Admin still enters hardcoded username/password ("admin" / "admin"),
/// but behind the scenes we sign into a dedicated Firebase Auth account
/// so Firestore security rules work correctly.
class AuthService extends ChangeNotifier {
  // Global singleton — accessible without BuildContext (needed by GoRouter redirect).
  static final AuthService instance = AuthService._();
  AuthService._() {
    _init();
  }

  /// Runs once on startup. If the persisted Firebase user is the admin
  /// account, sign them out so the login screen appears.  Regular user
  /// sessions are kept alive.
  Future<void> _init() async {
    final user = _auth.currentUser;
    if (user != null && user.email == _adminFirebaseEmail) {
      // Admin sessions must not persist — force re-login.
      await _auth.signOut();
      _role = null;
      notifyListeners();
    }

    // Now listen to auth state for ongoing changes.
    _auth.authStateChanges().listen((user) async {
      if (user == null && !_isAdminSession) {
        _role = null;
        notifyListeners();
        return;
      }

      if (user != null && !_isAdminSession) {
        if (user.email == _adminFirebaseEmail) {
          await _auth.signOut();
          _role = null;
          notifyListeners();
          return;
        }
        // Validate Firestore profile before granting access (blocks deleted/blocked users)
        // Skip during signUp — profile is being created and listener would race with it
        if (_isSigningUp) return;

        final profile = await FirestoreService.instance.getUserProfile(user.uid);
        if (profile == null || profile.isBlocked) {
          await _auth.signOut();
          _role = null;
          notifyListeners();
          return;
        }
        // Best-effort weekly email report (non-blocking from caller perspective).
        try {
          await EmailReportService.instance.maybeSendWeeklyEmail(profile);
        } catch (_) {
          // Ignore failures; weekly email is non-critical.
        }
        // Save FCM token so admin can send push notifications.
        NotificationService.instance.initForUser().catchError((_) {});
        _role = UserRole.user;
        notifyListeners();
      }
    });
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;

  UserRole? _role;
  UserRole? get role => _role;

  /// True when admin logged in via hardcoded credentials.
  bool _isAdminSession = false;

  /// True during signUp — prevents authStateChanges from signing out before profile exists.
  bool _isSigningUp = false;

  bool get isLoggedIn =>
      (_auth.currentUser != null && _role != null) || _isAdminSession;
  bool get isAdmin => _role == UserRole.admin;

  User? get firebaseUser => _auth.currentUser;
  String? get currentEmail =>
      _isAdminSession ? 'admin' : _auth.currentUser?.email;
  String? get currentDisplayName =>
      _isAdminSession ? 'Admin' : _auth.currentUser?.displayName;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Admin credentials (what the user types) ─────────────────────────────────
  static const String adminUsername = 'admin';
  static const String adminPassword = 'admin';

  // ── Dedicated Firebase account for the admin ────────────────────────────────
  // This account is created automatically on first admin login.
  static const String _adminFirebaseEmail = 'admin@urdu-emotion-ai.app';
  static const String _adminFirebasePassword = 'AdminPanel@2026!';

  /// Email/password login.
  /// - For admin role: checks hardcoded username/password, then signs into
  ///   a dedicated Firebase Auth admin account so Firestore rules work.
  /// - For user role: logs into Firebase with the provided email/password.
  ///
  /// Returns null on success, or an error message string on failure.
  Future<String?> login(
      String email, String password, UserRole role) async {
    try {
      if (role == UserRole.admin) {
        // 1. Check hardcoded credentials
        if (email.trim() != adminUsername || password != adminPassword) {
          return 'Invalid admin credentials.';
        }

        // 2. Mark admin session BEFORE signing in so the authStateChanges
        //    listener doesn't immediately sign the admin back out.
        _isAdminSession = true;
        _role = UserRole.admin;

        // 3. Sign into Firebase with the dedicated admin account
        try {
          await _auth.signInWithEmailAndPassword(
            email: _adminFirebaseEmail,
            password: _adminFirebasePassword,
          );
        } on FirebaseAuthException catch (e) {
          if (e.code == 'user-not-found' ||
              e.code == 'invalid-credential') {
            // First-time admin login — create the Firebase account
            final cred = await _auth.createUserWithEmailAndPassword(
              email: _adminFirebaseEmail,
              password: _adminFirebasePassword,
            );

            // Create Firestore profile with role: 'admin'
            if (cred.user != null) {
              await cred.user!.updateDisplayName('Admin');
              await FirestoreService.instance.createUserProfile(
                uid: cred.user!.uid,
                email: _adminFirebaseEmail,
                displayName: 'Admin',
                role: 'admin',
              );
            }
          } else {
            // Sign-in failed — revert admin flags
            _isAdminSession = false;
            _role = null;
            rethrow;
          }
        }

        // 4. Ensure the Firestore profile has role: 'admin'
        final uid = _auth.currentUser?.uid;
        if (uid != null) {
          final profile =
              await FirestoreService.instance.getUserProfile(uid);
          if (profile == null || profile.role != 'admin') {
            await FirestoreService.instance.createUserProfile(
              uid: uid,
              email: _adminFirebaseEmail,
              displayName: 'Admin',
              role: 'admin',
            );
          }
        }

        notifyListeners();
        return null;
      } else {
        final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );

        final user = cred.user;
        if (user == null) {
          return 'Authentication failed. Please try again.';
        }

        final profile =
            await FirestoreService.instance.getUserProfile(user.uid);

        // Deleted by admin: Firestore doc was removed
        if (profile == null) {
          await _auth.signOut();
          return 'Your account has been deleted.';
        }

        // Blocked by admin
        if (profile.isBlocked) {
          await _auth.signOut();
          return 'Your account has been blocked. Please contact support.';
        }

        _isAdminSession = false;
        _role = UserRole.user;
        notifyListeners();
        return null;
      }
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-email':
          return 'The email address is invalid.';
        case 'user-disabled':
          return 'This user has been disabled.';
        case 'user-not-found':
          return 'No user found for this email.';
        case 'wrong-password':
          return 'Incorrect password. Please try again.';
        default:
          return e.message ?? 'Authentication failed. Please try again.';
      }
    } catch (_) {
      return 'An unexpected error occurred. Please try again.';
    }
  }

  /// Sign up a new user with email & password.
  /// Creates a corresponding user profile document in Firestore.
  Future<String?> signUp(
    String email,
    String password, {
    String? displayName,
    int? age,
    String? gender,
  }) async {
    _isSigningUp = true;
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = cred.user;
      if (user != null) {
        final name = (displayName != null && displayName.isNotEmpty)
            ? displayName
            : email.split('@').first;
        await user.updateDisplayName(name);

        await FirestoreService.instance.createUserProfile(
          uid: user.uid,
          email: user.email ?? email.trim(),
          displayName: name,
          role: 'user',
          age: age,
          gender: gender,
        );
      }

      _isAdminSession = false;
      _role = UserRole.user;
      // Save FCM token for newly registered users (authStateChanges skips
      // this during sign-up to avoid a race with profile creation).
      NotificationService.instance.initForUser().catchError((_) {});
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'An account already exists for this email.';
        case 'invalid-email':
          return 'The email address is invalid.';
        case 'weak-password':
          return 'Password is too weak. Please choose a stronger one.';
        default:
          return e.message ?? 'Sign up failed. Please try again.';
      }
    } catch (_) {
      return 'An unexpected error occurred. Please try again.';
    } finally {
      _isSigningUp = false;
    }
  }

  Future<void> logout() async {
    // Always sign out of Firebase (admin now uses Firebase Auth too)
    await _auth.signOut();
    _isAdminSession = false;
    _role = null;
    notifyListeners();
  }
}
