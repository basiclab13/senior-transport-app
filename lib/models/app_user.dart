enum UserRole { admin, staff }

enum UserProfileFailure {
  missingDocument,
  missingActive,
  invalidActive,
  inactive,
  invalidRole,
  invalidStaffMapping,
}

class UserProfileException extends FormatException {
  const UserProfileException(this.reason) : super('Invalid user profile');

  final UserProfileFailure reason;
}

class AppUser {
  const AppUser({required this.uid, required this.role, this.staffId});

  final String uid;
  final UserRole role;
  final String? staffId;

  factory AppUser.fromDocument(String uid, Map<String, dynamic>? data) {
    if (data == null) {
      throw const UserProfileException(UserProfileFailure.missingDocument);
    }
    if (!data.containsKey('active')) {
      throw const UserProfileException(UserProfileFailure.missingActive);
    }
    if (data['active'] is! bool) {
      throw const UserProfileException(UserProfileFailure.invalidActive);
    }
    if (data['active'] != true) {
      throw const UserProfileException(UserProfileFailure.inactive);
    }
    final role = switch (data['role']) {
      'admin' => UserRole.admin,
      'staff' => UserRole.staff,
      _ => throw const UserProfileException(UserProfileFailure.invalidRole),
    };
    final staffId = data['staffId'];
    if (role == UserRole.staff &&
        (staffId is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(staffId))) {
      throw const UserProfileException(UserProfileFailure.invalidStaffMapping);
    }
    return AppUser(
      uid: uid,
      role: role,
      staffId: role == UserRole.staff ? staffId as String : null,
    );
  }
}
