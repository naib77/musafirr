import 'package:flutter/material.dart';

import '../../state/auth_state.dart';

class BecomeHostScreen extends StatelessWidget {
  const BecomeHostScreen({
    super.key,
    required this.authState,
    required this.onBecomeHost,
  });

  final AuthStateNotifier authState;
  final VoidCallback onBecomeHost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with close button
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Hero section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Become a Host',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Share your space and earn extra income by hosting travelers from around the world.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Benefits
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Why host on Musafir?',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _BenefitItem(
                      icon: Icons.attach_money,
                      title: 'Earn extra income',
                      description:
                          'Turn your extra space into extra income. Set your own prices and availability.',
                      theme: theme,
                    ),
                    const SizedBox(height: 16),
                    _BenefitItem(
                      icon: Icons.calendar_today,
                      title: 'Host on your schedule',
                      description:
                          'You decide when to host. Block dates, set minimum stays, and manage bookings easily.',
                      theme: theme,
                    ),
                    const SizedBox(height: 16),
                    _BenefitItem(
                      icon: Icons.security,
                      title: 'Host with confidence',
                      description:
                          'Our platform provides support and protection for every booking.',
                      theme: theme,
                    ),
                    const SizedBox(height: 16),
                    _BenefitItem(
                      icon: Icons.people,
                      title: 'Meet travelers',
                      description:
                          'Connect with guests from different backgrounds and share local experiences.',
                      theme: theme,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // How it works
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How it works',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _StepItem(
                      number: '1',
                      title: 'Create your listing',
                      description:
                          'Tell us about your space, add photos, and set your price.',
                      theme: theme,
                    ),
                    const SizedBox(height: 12),
                    _StepItem(
                      number: '2',
                      title: 'Welcome guests',
                      description:
                          'Accept bookings and communicate with travelers.',
                      theme: theme,
                    ),
                    const SizedBox(height: 12),
                    _StepItem(
                      number: '3',
                      title: 'Get paid',
                      description:
                          'Receive payments securely through our platform.',
                      theme: theme,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // CTA Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ListenableBuilder(
                  listenable: authState,
                  builder: (context, _) {
                    return FilledButton(
                      onPressed: authState.isLoading
                          ? null
                          : () async {
                              final success = await authState.becomeHost();
                              if (success && context.mounted) {
                                onBecomeHost();
                              }
                            },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: authState.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Get Started'),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Terms
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'By becoming a host, you agree to our Host Terms of Service and acknowledge our Host Privacy Policy.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _BenefitItem extends StatelessWidget {
  const _BenefitItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.theme,
  });

  final IconData icon;
  final String title;
  final String description;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.number,
    required this.title,
    required this.description,
    required this.theme,
  });

  final String number;
  final String title;
  final String description;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
