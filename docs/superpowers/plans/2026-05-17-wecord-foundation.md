# WeCord Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the WeCord foundation: a Flutter app scaffold for iOS, macOS, and Web with Supabase configuration, typed environment loading, base navigation, theme, and stub feature screens ready for the private-chat milestone.

**Architecture:** This plan creates a Flutter application at the repository root, then organizes app code by feature and shared services. Supabase initialization is isolated behind a small bootstrap layer so later auth, realtime, storage, and database repositories can depend on one configured client. The UI starts with a WeChat-first shell: Chats is the default tab, with Contacts, Circles, and Me available as secondary tabs.

**Tech Stack:** Flutter, Dart, Supabase Flutter, flutter_dotenv, go_router, Riverpod, flutter_test.

---

## Scope Split

The approved WeCord spec covers the full MVP, which is too large for one safe implementation pass. Split execution into separate plans:

1. Foundation: scaffold Flutter, Supabase config, theme, navigation, stub screens.
2. Private Chat: auth, profiles, friends, direct conversations, text messages.
3. Group Chat: group creation, invitations, member roles, announcements, mentions.
4. Circles and Channels: private circles, channel-backed conversations, membership policies.
5. Media and Polish: avatars, image/file uploads, reply/edit/recall, search, presence, typing.
6. Notifications and Release Readiness: push pipeline, web notifications, hardening, QA docs.

This document implements only the Foundation plan.

## File Structure

- Create: `.gitignore` to ignore macOS metadata and local secrets.
- Create: `.env.example` to document required Supabase environment variables.
- Create: `lib/main.dart` as the app entrypoint.
- Create: `lib/bootstrap/app_bootstrap.dart` for app startup and Supabase initialization.
- Create: `lib/shared/config/app_config.dart` for typed environment access.
- Create: `lib/shared/theme/wecord_theme.dart` for the app theme.
- Create: `lib/shared/navigation/app_router.dart` for routing.
- Create: `lib/features/shell/wecord_shell.dart` for the responsive app shell.
- Create: `lib/features/chats/chats_screen.dart` as the default home screen.
- Create: `lib/features/contacts/contacts_screen.dart` for contacts.
- Create: `lib/features/circles/circles_screen.dart` for private circles.
- Create: `lib/features/settings/settings_screen.dart` for profile/settings.
- Create: `test/shared/config/app_config_test.dart` for config validation.
- Create: `test/shared/navigation/app_router_test.dart` for default route behavior.
- Create: `test/features/shell/wecord_shell_test.dart` for tab navigation behavior.
- Modify: `pubspec.yaml` to set app metadata and dependencies.

## Task 1: Verify Flutter Tooling

**Files:**
- No repository files changed.

- [ ] **Step 1: Check whether Flutter is installed**

Run:

```bash
rtk flutter --version
```

Expected if Flutter is missing:

```text
[rtk: No such file or directory (os error 2)]
```

Expected if Flutter is installed:

```text
Flutter 3.x.x ...
```

- [ ] **Step 2: Install Flutter if missing**

Run on macOS with Homebrew:

```bash
rtk brew install --cask flutter
```

Expected:

```text
flutter was successfully installed
```

If Homebrew says Flutter is already installed, continue to the next step.

- [ ] **Step 3: Verify target platform support**

Run:

```bash
rtk flutter doctor -v
```

Expected:

```text
[✓] Flutter
```

The doctor output may show warnings for Android tooling. Android is not a WeCord target, so Android warnings do not block this plan. iOS, macOS, and Chrome/Web warnings do block this plan.

- [ ] **Step 4: Commit**

No commit is needed because this task only verifies local tooling.

## Task 2: Scaffold Flutter App

**Files:**
- Create: generated Flutter project files at repository root.
- Modify: `pubspec.yaml`
- Modify: `.gitignore`

- [ ] **Step 1: Create Flutter project in the current repository**

Run:

```bash
rtk flutter create --platforms=ios,macos,web --project-name wecord .
```

Expected:

```text
All done!
```

- [ ] **Step 2: Replace `.gitignore` with WeCord ignore rules**

Use this exact `.gitignore` content:

```gitignore
.DS_Store
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
.pub-cache/
.pub/
build/
coverage/

# Local environment files
.env
.env.local

# IDE state
.idea/
.vscode/
*.iml

# macOS/iOS generated state
ios/Pods/
ios/.symlinks/
ios/Flutter/Flutter.framework
ios/Flutter/Flutter.podspec
macos/Pods/
macos/Flutter/ephemeral/
```

- [ ] **Step 3: Update `pubspec.yaml` metadata and dependencies**

Use this dependencies block in `pubspec.yaml`:

```yaml
name: wecord
description: "A familiar-social real-time chat app for iOS, macOS, and Web."
publish_to: "none"
version: 0.1.0+1

environment:
  sdk: ">=3.4.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_dotenv: ^5.2.1
  flutter_riverpod: ^2.6.1
  go_router: ^14.6.2
  supabase_flutter: ^2.8.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
```

- [ ] **Step 4: Fetch dependencies**

Run:

```bash
rtk flutter pub get
```

Expected:

```text
Got dependencies!
```

- [ ] **Step 5: Run generated tests**

Run:

```bash
rtk flutter test
```

Expected before replacing generated app code:

```text
All tests passed!
```

- [ ] **Step 6: Commit**

Run:

```bash
rtk git add .gitignore pubspec.yaml pubspec.lock ios macos web lib test
rtk git commit -m "chore: scaffold Flutter app"
```

Expected:

```text
[main ...] chore: scaffold Flutter app
```

## Task 3: Add Environment Configuration

**Files:**
- Create: `.env.example`
- Create: `lib/shared/config/app_config.dart`
- Create: `test/shared/config/app_config_test.dart`

- [ ] **Step 1: Write failing config tests**

Create `test/shared/config/app_config_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('creates config when Supabase values are present', () {
      final config = AppConfig.fromMap({
        'SUPABASE_URL': 'https://example.supabase.co',
        'SUPABASE_ANON_KEY': 'anon-key',
      });

      expect(config.supabaseUrl, Uri.parse('https://example.supabase.co'));
      expect(config.supabaseAnonKey, 'anon-key');
    });

    test('throws when Supabase URL is missing', () {
      expect(
        () => AppConfig.fromMap({'SUPABASE_ANON_KEY': 'anon-key'}),
        throwsA(isA<ConfigException>()),
      );
    });

    test('throws when Supabase URL is invalid', () {
      expect(
        () => AppConfig.fromMap({
          'SUPABASE_URL': 'not-a-url',
          'SUPABASE_ANON_KEY': 'anon-key',
        }),
        throwsA(isA<ConfigException>()),
      );
    });

    test('throws when Supabase anon key is missing', () {
      expect(
        () => AppConfig.fromMap({'SUPABASE_URL': 'https://example.supabase.co'}),
        throwsA(isA<ConfigException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
rtk flutter test test/shared/config/app_config_test.dart
```

Expected:

```text
Error: Not found: 'package:wecord/shared/config/app_config.dart'
```

- [ ] **Step 3: Implement typed config**

Create `lib/shared/config/app_config.dart`:

```dart
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  final Uri supabaseUrl;
  final String supabaseAnonKey;

  factory AppConfig.fromMap(Map<String, String> values) {
    final rawUrl = values['SUPABASE_URL']?.trim();
    final anonKey = values['SUPABASE_ANON_KEY']?.trim();

    if (rawUrl == null || rawUrl.isEmpty) {
      throw const ConfigException('SUPABASE_URL is required');
    }

    final parsedUrl = Uri.tryParse(rawUrl);
    if (parsedUrl == null || !parsedUrl.hasScheme || parsedUrl.host.isEmpty) {
      throw ConfigException('SUPABASE_URL must be a valid absolute URL: $rawUrl');
    }

    if (anonKey == null || anonKey.isEmpty) {
      throw const ConfigException('SUPABASE_ANON_KEY is required');
    }

    return AppConfig(
      supabaseUrl: parsedUrl,
      supabaseAnonKey: anonKey,
    );
  }
}

class ConfigException implements Exception {
  const ConfigException(this.message);

  final String message;

  @override
  String toString() => 'ConfigException: $message';
}
```

- [ ] **Step 4: Add environment example**

Create `.env.example`:

```dotenv
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

- [ ] **Step 5: Run config tests**

Run:

```bash
rtk flutter test test/shared/config/app_config_test.dart
```

Expected:

```text
All tests passed!
```

- [ ] **Step 6: Commit**

Run:

```bash
rtk git add .env.example lib/shared/config/app_config.dart test/shared/config/app_config_test.dart
rtk git commit -m "feat: add app environment config"
```

Expected:

```text
[main ...] feat: add app environment config
```

## Task 4: Add App Bootstrap and Supabase Initialization

**Files:**
- Create: `lib/bootstrap/app_bootstrap.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Replace `lib/main.dart` with a small bootstrap entrypoint**

Use this exact `lib/main.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runWeCordApp();
}
```

- [ ] **Step 2: Implement app bootstrap**

Create `lib/bootstrap/app_bootstrap.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/config/app_config.dart';
import 'package:wecord/shared/navigation/app_router.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

Future<void> runWeCordApp() async {
  await dotenv.load(
    fileName: '.env',
    isOptional: true,
    mergeWith: const {
      'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL'),
      'SUPABASE_ANON_KEY': String.fromEnvironment('SUPABASE_ANON_KEY'),
    },
  );
  final config = AppConfig.fromMap(dotenv.env);

  await Supabase.initialize(
    url: config.supabaseUrl.toString(),
    anonKey: config.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: WeCordApp()));
}

class WeCordApp extends ConsumerWidget {
  const WeCordApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'WeCord',
      debugShowCheckedModeBanner: false,
      theme: WeCordTheme.light(),
      routerConfig: router,
    );
  }
}
```

- [ ] **Step 3: Run analyzer to see missing imports fail**

Run:

```bash
rtk flutter analyze
```

Expected:

```text
Target of URI doesn't exist: 'package:wecord/shared/navigation/app_router.dart'
Target of URI doesn't exist: 'package:wecord/shared/theme/wecord_theme.dart'
```

These failures are expected until Tasks 5 and 6 create theme and routing.

- [ ] **Step 4: Commit**

Do not commit this task yet. Commit it together with Tasks 5 and 6 so the repository does not land in a non-analyzing state.

## Task 5: Add Theme

**Files:**
- Create: `lib/shared/theme/wecord_theme.dart`

- [ ] **Step 1: Implement WeCord theme**

Create `lib/shared/theme/wecord_theme.dart`:

```dart
import 'package:flutter/material.dart';

class WeCordTheme {
  const WeCordTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2F7CF6),
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: colorScheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyzer to see only routing files remain missing**

Run:

```bash
rtk flutter analyze
```

Expected:

```text
Target of URI doesn't exist: 'package:wecord/shared/navigation/app_router.dart'
```

- [ ] **Step 3: Commit**

Do not commit this task yet. Commit it together with Tasks 4 and 6.

## Task 6: Add Routing and Placeholder Screens

**Files:**
- Create: `lib/shared/navigation/app_router.dart`
- Create: `lib/features/shell/wecord_shell.dart`
- Create: `lib/features/chats/chats_screen.dart`
- Create: `lib/features/contacts/contacts_screen.dart`
- Create: `lib/features/circles/circles_screen.dart`
- Create: `lib/features/settings/settings_screen.dart`
- Create: `test/shared/navigation/app_router_test.dart`
- Create: `test/features/shell/wecord_shell_test.dart`

- [ ] **Step 1: Write routing and shell tests**

Create `test/shared/navigation/app_router_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';

void main() {
  testWidgets('opens Chats as the default screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: WeCordApp()));
    await tester.pumpAndSettle();

    expect(find.text('Chats'), findsWidgets);
    expect(find.text('No conversations yet'), findsOneWidget);
  });
}
```

Create `test/features/shell/wecord_shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/shell/wecord_shell.dart';

void main() {
  testWidgets('switches between primary tabs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeCordShell(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          child: const Text('Current screen'),
        ),
      ),
    );

    expect(find.text('Chats'), findsWidgets);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Circles'), findsOneWidget);
    expect(find.text('Me'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
rtk flutter test test/shared/navigation/app_router_test.dart test/features/shell/wecord_shell_test.dart
```

Expected:

```text
Error: Not found: 'package:wecord/shared/navigation/app_router.dart'
Error: Not found: 'package:wecord/features/shell/wecord_shell.dart'
```

- [ ] **Step 3: Implement router**

Create `lib/shared/navigation/app_router.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circles_screen.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/features/shell/wecord_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: ChatsScreen.path,
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return WeCordShell(
            selectedIndex: _selectedIndexForLocation(state.uri.path),
            onDestinationSelected: (index) {
              switch (index) {
                case 0:
                  context.go(ChatsScreen.path);
                case 1:
                  context.go(ContactsScreen.path);
                case 2:
                  context.go(CirclesScreen.path);
                case 3:
                  context.go(SettingsScreen.path);
              }
            },
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: ChatsScreen.path,
            builder: (context, state) => const ChatsScreen(),
          ),
          GoRoute(
            path: ContactsScreen.path,
            builder: (context, state) => const ContactsScreen(),
          ),
          GoRoute(
            path: CirclesScreen.path,
            builder: (context, state) => const CirclesScreen(),
          ),
          GoRoute(
            path: SettingsScreen.path,
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

int _selectedIndexForLocation(String location) {
  if (location.startsWith(ContactsScreen.path)) {
    return 1;
  }
  if (location.startsWith(CirclesScreen.path)) {
    return 2;
  }
  if (location.startsWith(SettingsScreen.path)) {
    return 3;
  }
  return 0;
}
```

- [ ] **Step 4: Implement responsive shell**

Create `lib/features/shell/wecord_shell.dart`:

```dart
import 'package:flutter/material.dart';

class WeCordShell extends StatelessWidget {
  const WeCordShell({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final useRail = MediaQuery.sizeOf(context).width >= 720;

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  selectedIcon: Icon(Icons.chat_bubble),
                  label: Text('Chats'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.contacts_outlined),
                  selectedIcon: Icon(Icons.contacts),
                  label: Text('Contacts'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.groups_outlined),
                  selectedIcon: Icon(Icons.groups),
                  label: Text('Circles'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: Text('Me'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.contacts_outlined),
            selectedIcon: Icon(Icons.contacts),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Circles',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Me',
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Implement stub screens**

Create `lib/features/chats/chats_screen.dart`:

```dart
import 'package:flutter/material.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  static const path = '/chats';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: const Center(
        child: Text('No conversations yet'),
      ),
    );
  }
}
```

Create `lib/features/contacts/contacts_screen.dart`:

```dart
import 'package:flutter/material.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  static const path = '/contacts';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: const Center(
        child: Text('No contacts yet'),
      ),
    );
  }
}
```

Create `lib/features/circles/circles_screen.dart`:

```dart
import 'package:flutter/material.dart';

class CirclesScreen extends StatelessWidget {
  const CirclesScreen({super.key});

  static const path = '/circles';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Circles')),
      body: const Center(
        child: Text('No circles yet'),
      ),
    );
  }
}
```

Create `lib/features/settings/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const path = '/me';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: const Center(
        child: Text('Profile and settings'),
      ),
    );
  }
}
```

- [ ] **Step 6: Run routing and shell tests**

Run:

```bash
rtk flutter test test/shared/navigation/app_router_test.dart test/features/shell/wecord_shell_test.dart
```

Expected:

```text
All tests passed!
```

- [ ] **Step 7: Run analyzer**

Run:

```bash
rtk flutter analyze
```

Expected:

```text
No issues found!
```

- [ ] **Step 8: Commit Tasks 4-6**

Run:

```bash
rtk git add lib/main.dart lib/bootstrap/app_bootstrap.dart lib/shared/theme/wecord_theme.dart lib/shared/navigation/app_router.dart lib/features test
rtk git commit -m "feat: add WeCord app shell"
```

Expected:

```text
[main ...] feat: add WeCord app shell
```

## Task 7: Add Local Run Documentation

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create README**

Create `README.md`:

```markdown
# WeCord

WeCord is a familiar-social real-time chat app: WeChat-first private and group messaging with a lightweight Discord-style circles and channels layer.

## Stack

- Flutter for iOS, macOS, and Web
- Supabase Auth, Postgres, Realtime, Storage, and Edge Functions
- LiveKit reserved for future voice and video features

## Local Setup

1. Install Flutter.
2. Copy `.env.example` to `.env`.
3. Add `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
4. Run `flutter pub get`.
5. Run `flutter test`.
6. Run one client with local config:

```bash
flutter run -d macos --dart-define-from-file=.env
flutter run -d chrome --dart-define-from-file=.env
```

## Current Status

The foundation milestone contains app setup, typed configuration, theme, routing, and stub screens. Private chat is the next implementation milestone.
```

- [ ] **Step 2: Run Markdown smoke check**

Run:

```bash
rtk rg -n "T[O]DO|T[B]D|F[I]XME" README.md docs/superpowers/plans/2026-05-17-wecord-foundation.md
```

Expected:

```text
```

The command exits with status 1 when no matches are found. That is acceptable.

- [ ] **Step 3: Commit**

Run:

```bash
rtk git add README.md
rtk git commit -m "docs: add WeCord setup notes"
```

Expected:

```text
[main ...] docs: add WeCord setup notes
```

## Task 8: Foundation Verification

**Files:**
- No new files.

- [ ] **Step 1: Run full test suite**

Run:

```bash
rtk flutter test
```

Expected:

```text
All tests passed!
```

- [ ] **Step 2: Run analyzer**

Run:

```bash
rtk flutter analyze
```

Expected:

```text
No issues found!
```

- [ ] **Step 3: Run macOS app smoke test**

Run:

```bash
rtk flutter run -d macos
```

Expected:

```text
Launching lib/main.dart on macOS in debug mode...
```

The app should open to the Chats tab and show `No conversations yet`.

- [ ] **Step 4: Run Web app smoke test**

Run:

```bash
rtk flutter run -d chrome
```

Expected:

```text
Launching lib/main.dart on Chrome in debug mode...
```

The app should open to the Chats tab and show `No conversations yet`.

- [ ] **Step 5: Confirm clean git state**

Run:

```bash
rtk git status --short
```

Expected:

```text
```

## Self-Review

Spec coverage:

- Target platforms are covered by `flutter create --platforms=ios,macos,web`.
- Supabase setup is covered by typed config and `Supabase.initialize`.
- WeChat-first primary navigation is covered by default `/chats` routing and shell tabs.
- Placeholder feature boundaries match the spec: auth will plug into bootstrap later, chats/contacts/circles/settings each have their own feature folder.
- RLS, database schema, private chat, groups, circles data, media, presence, and notifications are intentionally deferred to later milestone plans.

Placeholder scan:

- The plan contains no unfinished-work markers.
- Every code-writing step includes exact file content.

Type consistency:

- `WeCordApp`, `appRouterProvider`, `WeCordTheme`, `WeCordShell`, and screen `path` constants are defined before they are used in committed code.
- Route paths are `/chats`, `/contacts`, `/circles`, and `/me`, matching the app shell destination order.
