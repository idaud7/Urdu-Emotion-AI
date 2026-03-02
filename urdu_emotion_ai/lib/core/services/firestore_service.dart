import 'package:cloud_firestore/cloud_firestore.dart';

/// Centralized wrapper around Cloud Firestore.
///
/// Collections:
/// - users/{uid}
/// - users/{uid}/sessions/{autoId}
/// - feedback/{autoId}
class FirestoreService {
  FirestoreService._();
  static final FirestoreService instance = FirestoreService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Session APIs ─────────────────────────────────────────────────────────────

  Future<void> saveSession({
    required String uid,
    required String emotion,
    required double confidence,
    required Map<String, double> allScores,
    required Duration duration,
    required String source,
  }) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .add({
      'uid': uid,
      'emotion': emotion,
      'confidence': confidence,
      'allScores': allScores,
      'durationSeconds': duration.inSeconds,
      'source': source,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<List<SessionRecord>> getRecentSessions(
    String uid, {
    int limit = 10,
  }) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(SessionRecord.fromDoc).toList();
  }

  Future<List<SessionRecord>> getAllSessions(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .orderBy('timestamp', descending: true)
        .get();
    return snap.docs.map(SessionRecord.fromDoc).toList();
  }

  Future<void> deleteAllSessions(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // ── User profile APIs ───────────────────────────────────────────────────────

  Future<UserProfile?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromDoc(doc);
  }

  /// Stream of a single user's profile for real-time updates (e.g. home screen).
  Stream<UserProfile?> watchUserProfile(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserProfile.fromDoc(doc);
    });
  }

  Future<void> createUserProfile({
    required String uid,
    required String email,
    String? displayName,
    String role = 'user',
    int? age,
    String? gender,
  }) async {
    final data = <String, dynamic>{
      'uid': uid,
      'email': email,
      'displayName': displayName ?? '',
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (age != null) data['age'] = age;
    if (gender != null) data['gender'] = gender;
    await _db.collection('users').doc(uid).set(data, SetOptions(merge: true));
  }

  Future<void> updateUserProfile({
    required String uid,
    String? email,
    String? displayName,
    int? age,
    String? gender,
  }) async {
    final data = <String, Object?>{};
    if (email != null) data['email'] = email;
    if (displayName != null) data['displayName'] = displayName;
    if (age != null) data['age'] = age;
    if (gender != null) data['gender'] = gender;
    if (data.isEmpty) return;
    await _db.collection('users').doc(uid).update(data);
  }

  Future<void> updateUserPreferences({
    required String uid,
    double? sensitivityThreshold,
    bool? pushNotificationsEnabled,
    bool? weeklyEmailEnabled,
  }) async {
    final data = <String, dynamic>{};
    if (sensitivityThreshold != null) data['sensitivityThreshold'] = sensitivityThreshold;
    if (pushNotificationsEnabled != null) data['pushNotificationsEnabled'] = pushNotificationsEnabled;
    if (weeklyEmailEnabled != null) data['weeklyEmailEnabled'] = weeklyEmailEnabled;
    if (data.isEmpty) return;
    await _db.collection('users').doc(uid).update(data);
  }

  Future<void> setWeeklyEmailLastSent(String uid, Timestamp when) async {
    await _db.collection('users').doc(uid).update({
      'weeklyEmailLastSent': when,
    });
  }

  Future<void> saveFcmToken(String uid, String token) async {
    await _db.collection('users').doc(uid).update({'fcmToken': token});
  }

  // ── Feedback API ─────────────────────────────────────────────────────────────

  Future<void> submitFeedback({
    required String uid,
    required String displayName,
    required String email,
    required String message,
  }) async {
    await _db.collection('feedback').add({
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'message': message,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Admin / aggregate APIs ──────────────────────────────────────────────────

  Future<AdminStats> getAdminStats() async {
    final sessionsSnap =
        await _db.collectionGroup('sessions').get();

    final sessions = sessionsSnap.docs.map(SessionRecord.fromDoc).toList();
    final totalSessions = sessions.length;
    final totalUsers = sessions.map((s) => s.uid).toSet().length;

    final now = DateTime.now();
    final todayStart =
        DateTime(now.year, now.month, now.day);
    final activeToday = sessions
        .where((s) =>
            s.timestamp != null &&
            s.timestamp!.toDate().isAfter(todayStart))
        .length;

    final totalMinutes =
        sessions.fold<int>(0, (acc, s) => acc + s.durationSeconds) ~/ 60;

    return AdminStats(
      totalUsers: totalUsers,
      totalSessions: totalSessions,
      totalMinutes: totalMinutes,
      activeToday: activeToday,
    );
  }

  Future<List<UserProfile>> getAllUsers() async {
    // No orderBy — ensures users without 'createdAt' are included too.
    final snap = await _db.collection('users').get();
    return snap.docs.map(UserProfile.fromDoc).toList();
  }

  Future<List<SessionRecord>> getAllSessionsAdmin() async {
    final snap = await _db.collectionGroup('sessions').get();
    return snap.docs.map(SessionRecord.fromDoc).toList();
  }

  // ── Real-time stream APIs (Admin) ──────────────────────────────────────────

  /// Stream of ALL sessions across every user (collection group).
  Stream<List<SessionRecord>> watchAllSessionsAdmin() {
    return _db.collectionGroup('sessions').snapshots().map(
          (snap) => snap.docs.map(SessionRecord.fromDoc).toList(),
        );
  }

  /// Stream of ALL user profiles.
  /// Note: no orderBy — documents without 'createdAt' are included too.
  Stream<List<UserProfile>> watchAllUsers() {
    return _db
        .collection('users')
        .snapshots()
        .map((snap) => snap.docs.map(UserProfile.fromDoc).toList());
  }

  /// Aggregate per-user metrics for the admin "Users" tab.
  Future<List<AdminUserView>> getAdminUserViews() async {
    final users = await getAllUsers();
    final sessions = await getAllSessionsAdmin();

    // Group sessions by user id.
    final Map<String, List<SessionRecord>> byUser = {};
    for (final s in sessions) {
      byUser.putIfAbsent(s.uid, () => []).add(s);
    }

    final List<AdminUserView> result = [];
    for (final user in users) {
      final userSessions = byUser[user.uid] ?? const <SessionRecord>[];
      final totalSessions = userSessions.length;

      // Top emotion by frequency.
      final Map<String, int> emotionCounts = {};
      for (final s in userSessions) {
        emotionCounts[s.emotion] =
            (emotionCounts[s.emotion] ?? 0) + 1;
      }
      String topEmotion = 'Neutral';
      if (emotionCounts.isNotEmpty) {
        topEmotion = (emotionCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
      }

      // Last active = latest session timestamp.
      DateTime? lastActive;
      for (final s in userSessions) {
        final dt = s.timestamp?.toDate();
        if (dt != null &&
            (lastActive == null || dt.isAfter(lastActive))) {
          lastActive = dt;
        }
      }

      result.add(
        AdminUserView(
          uid: user.uid,
          name: user.displayName.isNotEmpty
              ? user.displayName
              : user.email,
          email: user.email,
          sessions: totalSessions,
          topEmotion: topEmotion,
          lastActive: lastActive,
          isActive: true,
          isBlocked: user.isBlocked,
        ),
      );
    }

    return result;
  }

  // ── Admin user-management APIs ───────────────────────────────────────────────

  Future<void> setUserBlocked(String uid, {required bool blocked}) async {
    await _db.collection('users').doc(uid).update({'isBlocked': blocked});
  }

  /// Deletes all of the user's sessions then the user document itself.
  Future<void> deleteUserAccount(String uid) async {
    await deleteAllSessions(uid);
    await _db.collection('users').doc(uid).delete();
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

class SessionRecord {
  SessionRecord({
    required this.id,
    required this.uid,
    required this.emotion,
    required this.confidence,
    required this.allScores,
    required this.durationSeconds,
    required this.source,
    required this.timestamp,
  });

  final String id;
  final String uid;
  final String emotion;
  final double confidence;
  final Map<String, double> allScores;
  final int durationSeconds;
  final String source;
  final Timestamp? timestamp;

  factory SessionRecord.fromDoc(
          QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      SessionRecord(
        id: doc.id,
        uid: doc.data()['uid'] as String? ?? doc.reference.parent.parent?.id ?? '',
        emotion: doc.data()['emotion'] as String? ?? 'Neutral',
        confidence:
            (doc.data()['confidence'] as num?)?.toDouble() ?? 0.0,
        allScores: (doc.data()['allScores'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
            <String, double>{},
        durationSeconds:
            (doc.data()['durationSeconds'] as num?)?.toInt() ?? 0,
        source: doc.data()['source'] as String? ?? 'live',
        timestamp: doc.data()['timestamp'] as Timestamp?,
      );
}

class UserProfile {
  UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.createdAt,
    required this.isBlocked,
    this.age,
    this.gender,
    this.photoUrl,
    this.sensitivityThreshold,
    this.pushNotificationsEnabled,
    this.weeklyEmailEnabled,
    this.weeklyEmailLastSent,
  });

  final String uid;
  final String email;
  final String displayName;
  final String role;
  final Timestamp? createdAt;
  final bool isBlocked;
  final int? age;
  final String? gender;
  final String? photoUrl;
  final double? sensitivityThreshold;
  final bool? pushNotificationsEnabled;
  final bool? weeklyEmailEnabled;
  final Timestamp? weeklyEmailLastSent;

  factory UserProfile.fromDoc(
          DocumentSnapshot<Map<String, dynamic>> doc) =>
      UserProfile(
        uid: doc.id,
        email: doc.data()?['email'] as String? ?? '',
        displayName:
            doc.data()?['displayName'] as String? ?? '',
        role: doc.data()?['role'] as String? ?? 'user',
        createdAt: doc.data()?['createdAt'] as Timestamp?,
        isBlocked: doc.data()?['isBlocked'] as bool? ?? false,
        age: doc.data()?['age'] as int?,
        gender: doc.data()?['gender'] as String?,
        photoUrl: doc.data()?['photoUrl'] as String?,
        sensitivityThreshold:
            (doc.data()?['sensitivityThreshold'] as num?)?.toDouble(),
        pushNotificationsEnabled:
            doc.data()?['pushNotificationsEnabled'] as bool?,
        weeklyEmailEnabled:
            doc.data()?['weeklyEmailEnabled'] as bool?,
        weeklyEmailLastSent:
            doc.data()?['weeklyEmailLastSent'] as Timestamp?,
      );
}

class AdminStats {
  AdminStats({
    required this.totalUsers,
    required this.totalSessions,
    required this.totalMinutes,
    required this.activeToday,
  });

  final int totalUsers;
  final int totalSessions;
  final int totalMinutes;
  final int activeToday;
}

/// View model used by the admin "Users" tab.
class AdminUserView {
  AdminUserView({
    required this.uid,
    required this.name,
    required this.email,
    required this.sessions,
    required this.topEmotion,
    required this.lastActive,
    required this.isActive,
    required this.isBlocked,
  });

  final String uid;
  String name;
  final String email;
  final int sessions;
  final String topEmotion;
  final DateTime? lastActive;
  final bool isActive;
  final bool isBlocked;
}

