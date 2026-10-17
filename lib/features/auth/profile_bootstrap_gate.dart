import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';

class ProfileBootstrapGate extends ConsumerWidget {
  const ProfileBootstrapGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(authProfileBootstrapProvider);

    // Once the app has been shown, a re-run keeps it on screen: replacing
    // it with a spinner would tear down every page and window above it.
    return bootstrap.when(
      skipLoadingOnReload: true,
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
                tr('Profile setup failed'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                error is StateError
                    ? tr('Bad state: {message}', {
                        'message': (error as StateError).message,
                      })
                    : error.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  ref.invalidate(authProfileBootstrapProvider);
                },
                child: Text(tr('Try again')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
