import 'package:flutter/material.dart';

import 'models/user_role.dart';
import 'repositories/in_memory_musafir_repository.dart';
import 'screens/admin_dashboard.dart';
import 'screens/owner_dashboard.dart';
import 'screens/tenant_dashboard.dart';

class MusafirApp extends StatefulWidget {
  const MusafirApp({super.key});

  @override
  State<MusafirApp> createState() => _MusafirAppState();
}

class _MusafirAppState extends State<MusafirApp> {
  final InMemoryMusafirRepository repository = InMemoryMusafirRepository();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) {
        return MaterialApp(
          title: 'Musafir',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0B7285),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF6F8F7),
            useMaterial3: true,
          ),
          home: HomeShell(repository: repository),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.repository});

  final InMemoryMusafirRepository repository;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  UserRole selectedRole = UserRole.tenant;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Musafir'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<UserRole>(
                value: selectedRole,
                borderRadius: BorderRadius.circular(16),
                items: UserRole.values
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(role.title),
                      ),
                    )
                    .toList(),
                onChanged: (role) {
                  if (role != null) {
                    setState(() => selectedRole = role);
                  }
                },
              ),
            ),
          ),
        ],
      ),
      body: switch (selectedRole) {
        UserRole.admin => AdminDashboard(repository: widget.repository),
        UserRole.owner => OwnerDashboard(repository: widget.repository),
        UserRole.tenant => TenantDashboard(repository: widget.repository),
      },
    );
  }
}
