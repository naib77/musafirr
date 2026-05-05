enum UserRole { admin, owner, tenant }

extension UserRoleLabel on UserRole {
  String get title => switch (this) {
        UserRole.admin => 'Admin',
        UserRole.owner => 'House Owner',
        UserRole.tenant => 'Tenant',
      };
}
