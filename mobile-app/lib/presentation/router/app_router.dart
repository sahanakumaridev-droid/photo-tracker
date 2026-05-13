import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/profile_model.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/home/edit_location_screen.dart';
import '../screens/home/home_screen_v2.dart';
import '../screens/home/map_view_screen.dart';
import '../screens/home/photo_detail_screen.dart';
import '../screens/log/log_screen_v2.dart';
import '../screens/settings/profiles_list_screen.dart';
import '../screens/settings/profiles_management_screen.dart';
import '../screens/settings/settings_screen_v2.dart';
import '../screens/upload/upload_screen_v2.dart';
import '../widgets/common/bottom_nav.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isAuthenticated = authState.isAuthenticated;
      final location = state.matchedLocation;

      // Always allow splash through
      if (location == '/splash') return null;

      if (!isAuthenticated && location != '/login') {
        return '/login';
      }

      if (isAuthenticated && location == '/login') {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => _ShellScaffold(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreenV2(),
          ),
          GoRoute(
            path: '/map',
            builder: (context, state) => const MapViewScreen(),
          ),
          GoRoute(
            path: '/upload',
            builder: (context, state) => const UploadScreenV2(),
          ),
          GoRoute(
            path: '/log',
            builder: (context, state) => const LogScreenV2(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreenV2(),
          ),
        ],
      ),
      GoRoute(
        path: '/profiles-management',
        builder: (context, state) {
          final profile = state.extra as ProfileModel?;
          return ProfilesManagementScreen(profileToEdit: profile);
        },
      ),
      GoRoute(
        path: '/profiles-list',
        builder: (context, state) => const ProfilesListScreen(),
      ),
      GoRoute(
        path: '/photo/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return PhotoDetailScreen(photoId: id);
        },
      ),
      GoRoute(
        path: '/edit-location',
        builder: (context, state) {
          final photo = state.extra as dynamic;
          return EditLocationScreen(photo: photo);
        },
      ),
    ],
  );
});

class _ShellScaffold extends StatefulWidget {

  const _ShellScaffold({required this.child});
  final Widget child;

  @override
  State<_ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends State<_ShellScaffold> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
      body: widget.child,
      bottomNavigationBar: BottomNav(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
          _navigateToTab(index);
        },
      ),
    );

  void _navigateToTab(int index) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/map');
        break;
      case 2:
        context.go('/upload');
        break;
      case 3:
        context.go('/log');
        break;
      case 4:
        context.go('/settings');
        break;
    }
  }
}
