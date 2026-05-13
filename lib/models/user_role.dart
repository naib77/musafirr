enum UserRole { admin, owner, tenant, guest }

extension UserRoleLabel on UserRole {
  String get title => switch (this) {
        UserRole.admin => 'Admin',
        UserRole.owner => 'House Owner',
        UserRole.tenant => 'Tenant',
        UserRole.guest => 'Guest',
      };
}
