import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';

class ProfileBootstrapGate extends ConsumerWidget {
  const ProfileBootstrapGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(authProfileBootstrapProvider);

    return bootstrap.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => _ProfileBootstrapError(error: error),
      data: (_) => child,
    );
  }
}

class _ProfileBootstrapError extends ConsumerWidget {
  const _ProfileBootstrapError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Profile setup failed',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  ref.invalidate(authProfileBootstrapProvider);
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
