---
name: flutter-architecture
description: ironmove-app layer-based project structure, Riverpod StateNotifier patterns, GoRouter navigation with nested routes and guards, Result sealed class, exception hierarchy, Freezed models, and singleton services
---

# Flutter Architecture & State Management

Architecture patterns used in ironmove-app. Covers layer-based project structure, Riverpod with StateNotifier + State classes, GoRouter with nested routes and route guards, Result pattern for error handling, custom exception hierarchy, Freezed immutable models, and singleton service patterns.

## Table of Contents

1. [Layer-Based Project Structure](#layer-based-project-structure)
2. [Riverpod State Management](#riverpod-state-management)
3. [GoRouter Navigation](#gorouter-navigation)
4. [Result Pattern](#result-pattern)
5. [Exception Hierarchy](#exception-hierarchy)
6. [Freezed Models](#freezed-models)
7. [Singleton Services](#singleton-services)
8. [Theme Setup](#theme-setup)
9. [Best Practices](#best-practices)
10. [Anti-Patterns](#anti-patterns)

---

## Layer-Based Project Structure

ironmove-app uses a layer-based structure (NOT feature-first). Each top-level directory groups files by their role in the application:

```
lib/
├── main.dart
├── firebase_options.dart
├── core/
│   ├── dio_client.dart          # HTTP client singleton
│   ├── env.dart                 # Environment config
│   ├── exceptions.dart          # Exception hierarchy
│   ├── result.dart              # Result sealed class
│   ├── router.dart              # GoRouter setup
│   └── theme.dart               # AppTheme + AppColors
├── models/
│   ├── task.dart                # Freezed task model
│   ├── expense.dart             # Freezed expense model
│   ├── location.dart            # Freezed location model
│   └── user.dart                # User model
├── services/
│   ├── api_service.dart         # Centralized API client
│   ├── analytics_service.dart   # Firebase Analytics singleton
│   ├── directions_cache_service.dart  # LRU directions cache
│   ├── push_notification_service.dart # FCM singleton
│   ├── secure_storage_service.dart    # Token/user storage
│   └── image_picker_service.dart      # Camera/gallery
├── providers/
│   ├── auth_provider.dart       # AuthNotifier + AuthState
│   ├── task_provider.dart       # Task state management
│   └── route_guard_provider.dart # Navigation guards
├── screens/
│   ├── splash_screen.dart
│   ├── error_screen.dart
│   ├── auth/
│   │   ├── enter_number_screen.dart
│   │   └── otp_screen.dart
│   ├── tasks/
│   │   ├── task_list_screen.dart
│   │   ├── task_details_screen.dart
│   │   ├── ongoing_task_screen.dart
│   │   └── complete_task_screen.dart
│   └── expenses/
│       └── expense_form_screen.dart
├── widgets/                     # Shared reusable widgets
├── utils/                       # Utility functions
└── l10n/                        # Localization files
```

**Key Principles:**
- Layer-based: Group by role (`core/`, `models/`, `services/`, `providers/`, `screens/`, `widgets/`, `utils/`, `l10n/`)
- `core/` holds foundational concerns (HTTP, routing, theming, errors)
- `services/` holds business logic and external integrations
- `providers/` holds Riverpod state management
- `screens/` holds UI pages, sub-grouped by domain (auth, tasks, expenses)

---

## Riverpod State Management

ironmove-app uses **StateNotifier + State classes** with `copyWith` for state management.

### State Class Pattern

```dart
// lib/providers/auth_provider.dart

class AuthState {
  final bool isAuthenticated;
  final User? user;
  final String? phoneNumber;
  final String? accessToken;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.user,
    this.phoneNumber,
    this.accessToken,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    User? user,
    String? phoneNumber,
    String? accessToken,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      accessToken: accessToken ?? this.accessToken,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}
```

### StateNotifier Pattern

```dart
// lib/providers/auth_provider.dart

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _apiService;
  final SecureStorageService _storageService;

  AuthNotifier(this._apiService, this._storageService) : super(const AuthState()) {
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    state = state.copyWith(isLoading: true);

    try {
      final tokenResult = await _storageService.getToken();

      if (tokenResult.isSuccess) {
        final token = tokenResult.dataOrNull;
        if (token != null && token.isNotEmpty) {
          DioClient.instance.dio.options.headers['Authorization'] = 'Bearer $token';
          await _apiService.getTasks(); // Validate token

          state = state.copyWith(
            isAuthenticated: true,
            accessToken: token,
            isLoading: false,
          );
          return;
        }
      }

      state = state.copyWith(isAuthenticated: false, isLoading: false);
    } catch (e) {
      await _storageService.clearAll();
      state = state.copyWith(
        isAuthenticated: false,
        isLoading: false,
        error: 'Failed to initialize: ${e.toString()}',
      );
    }
  }

  Future<void> sendOtp(String phoneNumber) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      String formattedPhone = phoneNumber.replaceAll(' ', '');
      if (!formattedPhone.startsWith('+')) {
        formattedPhone = '+66${formattedPhone.substring(1)}';
      }
      await _apiService.sendAuthCode(formattedPhone);
      state = state.copyWith(phoneNumber: formattedPhone, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> logout() async {
    await _storageService.clearAll();
    DioClient.instance.dio.options.headers.remove('Authorization');
    state = const AuthState();
  }

  bool get isAuthenticated => state.isAuthenticated;
}
```

### Provider Definitions

```dart
// Service providers (simple Provider for singletons)
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

// StateNotifier provider (for complex state)
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final storageService = ref.watch(secureStorageServiceProvider);
  return AuthNotifier(apiService, storageService);
});
```

---

## GoRouter Navigation

ironmove-app uses GoRouter with named routes, deeply nested routes, route guards via redirect, and a global navigator key.

### Router Setup

```dart
// lib/core/router.dart

// Global navigator key for accessing overlay context
final _navigatorKey = GlobalKey<NavigatorState>();
GlobalKey<NavigatorState> get appNavigatorKey => _navigatorKey;

final routerProvider = Provider<GoRouter>((ref) {
  final routeGuard = ref.watch(routeGuardProvider);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    navigatorKey: _navigatorKey,
    errorBuilder: (context, state) => ErrorScreen(error: state.error),
    redirect: (context, state) => routeGuard.redirect(context, state),
    routes: [
      // Splash screen (initial route)
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),

      // Authentication routes
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const EnterNumberScreen(),
      ),
      GoRoute(
        path: '/otp',
        name: 'otp',
        builder: (context, state) {
          final phone = state.extra as String?;
          return OtpScreen(phoneNumber: phone ?? '');
        },
      ),

      // Task routes (protected, deeply nested)
      GoRoute(
        path: '/tasks',
        name: 'tasks',
        builder: (context, state) => const TaskListScreen(),
        routes: [
          GoRoute(
            path: ':id',
            name: 'task-details',
            builder: (context, state) {
              final taskId = state.pathParameters['id']!;
              return TaskDetailsScreen(taskId: taskId);
            },
            routes: [
              GoRoute(
                path: 'ongoing',
                name: 'ongoing-task',
                builder: (context, state) {
                  final taskId = state.pathParameters['id']!;
                  return OngoingTaskScreen(taskId: taskId);
                },
                routes: [
                  GoRoute(
                    path: 'map',
                    name: 'ongoing-task-full-map',
                    builder: (context, state) {
                      final taskId = state.pathParameters['id']!;
                      return OngoingTaskFullMapScreen(taskId: taskId);
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'complete',
                name: 'task-complete',
                builder: (context, state) {
                  final taskId = state.pathParameters['id']!;
                  return CompleteTaskScreen(taskId: taskId);
                },
              ),
              GoRoute(
                path: 'expenses/new',
                name: 'expense-new',
                builder: (context, state) {
                  final taskId = state.pathParameters['id']!;
                  return ExpenseFormScreen(taskId: taskId);
                },
              ),
              GoRoute(
                path: 'expenses/:expenseId',
                name: 'expense-edit',
                builder: (context, state) {
                  final taskId = state.pathParameters['id']!;
                  final expenseId = state.pathParameters['expenseId']!;
                  return ExpenseFormScreen(taskId: taskId, expenseId: expenseId);
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
```

### Route Structure

| Path | Name | Screen |
|------|------|--------|
| `/` | `splash` | SplashScreen |
| `/login` | `login` | EnterNumberScreen |
| `/otp` | `otp` | OtpScreen |
| `/tasks` | `tasks` | TaskListScreen |
| `/tasks/:id` | `task-details` | TaskDetailsScreen |
| `/tasks/:id/ongoing` | `ongoing-task` | OngoingTaskScreen |
| `/tasks/:id/ongoing/map` | `ongoing-task-full-map` | OngoingTaskFullMapScreen |
| `/tasks/:id/complete` | `task-complete` | CompleteTaskScreen |
| `/tasks/:id/expenses/new` | `expense-new` | ExpenseFormScreen |
| `/tasks/:id/expenses/:expenseId` | `expense-edit` | ExpenseFormScreen |

### Navigation Usage

```dart
// Navigate by name with path parameters
context.goNamed('task-details', pathParameters: {'id': taskId});

// Navigate with extra data
context.goNamed('otp', extra: phoneNumber);

// Push (adds to stack instead of replacing)
context.pushNamed('expense-new', pathParameters: {'id': taskId});
```

---

## Result Pattern

ironmove-app uses a sealed `Result<T>` class for explicit success/failure handling.

```dart
// lib/core/result.dart

sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;
  T? get dataOrNull => isSuccess ? (this as Success<T>).data : null;
  String? get errorOrNull => isFailure ? (this as Failure<T>).message : null;

  R when<R>({
    required R Function(T data) success,
    required R Function(String message, Exception? exception, int? statusCode) failure,
  }) {
    if (this is Success<T>) {
      return success((this as Success<T>).data);
    } else {
      final fail = this as Failure<T>;
      return failure(fail.message, fail.exception, fail.statusCode);
    }
  }

  Result<R> map<R>(R Function(T) mapper) {
    if (isSuccess) {
      return Success(mapper((this as Success<T>).data));
    }
    return Failure((this as Failure).message,
      exception: (this as Failure).exception,
      statusCode: (this as Failure).statusCode,
    );
  }
}

class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

class Failure<T> extends Result<T> {
  final String message;
  final Exception? exception;
  final int? statusCode;

  const Failure(this.message, {this.exception, this.statusCode});
}
```

### Usage in Services

```dart
// Returning Result from storage operations
Future<Result<void>> saveToken(String token) async {
  try {
    await _storage.write(key: _keyAuthToken, value: token);
    return const Success(null);
  } catch (e) {
    return Failure(
      'Failed to save token',
      exception: AppException('Failed to save token', originalError: e),
    );
  }
}

// Consuming Result in providers
final tokenResult = await _storageService.getToken();
if (tokenResult.isSuccess) {
  final token = tokenResult.dataOrNull;
  // use token...
}

// Pattern matching with when()
tokenResult.when(
  success: (token) => debugPrint('Token: $token'),
  failure: (message, exception, statusCode) => debugPrint('Error: $message'),
);
```

---

## Exception Hierarchy

ironmove-app defines a structured exception hierarchy rooted at `AppException`, with `ExceptionMessages` for user-friendly Thai localization.

```dart
// lib/core/exceptions.dart

class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const AppException(this.message, {this.code, this.originalError});
}

class NetworkException extends AppException {
  final int? statusCode;
  final String? url;

  const NetworkException(super.message, {
    this.statusCode, this.url, super.code, super.originalError,
  });

  bool get isNoConnection => code == 'NO_CONNECTION';
  bool get isTimeout => code == 'TIMEOUT';
  bool get isServerError => statusCode != null && statusCode! >= 500;
}

class AuthException extends AppException {
  final bool isSessionExpired;

  const AuthException(super.message, {
    this.isSessionExpired = false, super.code, super.originalError,
  });
}

class ValidationException extends AppException {
  final Map<String, String>? fieldErrors;

  const ValidationException(super.message, {
    this.fieldErrors, super.code, super.originalError,
  });

  bool hasFieldError(String field) => fieldErrors?.containsKey(field) ?? false;
  String? getFieldError(String field) => fieldErrors?[field];
}

class ParseException extends AppException {
  final String? fieldName;
  final Type? expectedType;

  const ParseException(super.message, {
    this.fieldName, this.expectedType, super.code, super.originalError,
  });
}
```

### User-Friendly Error Messages

```dart
class ExceptionMessages {
  static String getUserMessage(Exception exception) {
    if (exception is NetworkException) {
      if (exception.isNoConnection) return 'No internet connection';
      if (exception.isTimeout) return 'Connection timed out';
      if (exception.isServerError) return 'Server error, try again later';
      if (exception.statusCode == 404) return 'Resource not found';
      return 'Connection error';
    }
    if (exception is AuthException) {
      if (exception.isSessionExpired) return 'Session expired, please log in again';
      if (exception.code == 'INVALID_OTP') return 'Invalid OTP code';
      return 'Authentication failed';
    }
    if (exception is ValidationException) return exception.message;
    if (exception is ParseException) return 'Invalid data format';
    return 'An unknown error occurred';
  }
}
```

---

## Freezed Models

ironmove-app uses `@freezed` for immutable data models with JSON serialization.

```dart
// lib/models/task.dart

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ironmove_app/models/location.dart';
import 'package:ironmove_app/models/expense.dart';

part 'task.freezed.dart';
part 'task.g.dart';

@freezed
class Task with _$Task {
  const Task._(); // Private constructor for custom getters

  const factory Task({
    required String id,
    required String referenceNo,
    required DateTime startDateTime,
    DateTime? endDateTime,
    required String assetPlateNumber,
    String? assetId,
    required String driverName,
    double? plannedDuration,
    required List<Location> places,
    required String status, // ready | in_progress | completed
    int? currentSequence,
    @Default([]) List<Expense> expenses,
  }) = _Task;

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);

  // Custom derived getter
  int? get currentPlaceIndex {
    if (currentSequence == null) return null;
    final index = places.indexWhere((place) => place.sequence == currentSequence);
    return index >= 0 ? index : null;
  }
}
```

**Key patterns:**
- `const Task._()` enables custom getters and methods on the Freezed class
- `@Default([])` provides default values for optional collections
- `fromJson` factory for JSON:API response deserialization
- Custom getters for derived state (`currentPlaceIndex`)

---

## Singleton Services

ironmove-app uses the classic Dart singleton pattern for services that need a single global instance.

### DioClient Singleton

```dart
// lib/core/dio_client.dart

class DioClient {
  static final DioClient _instance = DioClient._internal();
  static DioClient get instance => _instance;

  late final Dio dio;

  DioClient._internal() {
    dio = Dio(BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      error: true,
    ));
  }
}
```

### AnalyticsService Singleton

```dart
// lib/services/analytics_service.dart

class AnalyticsService {
  static AnalyticsService? _instance;
  static AnalyticsService get instance => _instance ??= AnalyticsService._();
  AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  bool get _isEnabled => kReleaseMode;

  Future<void> initialize() async {
    if (!_isEnabled) return;
    await _analytics.setAnalyticsCollectionEnabled(true);
    await logEvent('app_opened');
  }

  Future<void> logEvent(String name, {Map<String, dynamic>? parameters}) async {
    if (!_isEnabled) return;
    await _analytics.logEvent(name: name, parameters: parameters?.map(
      (key, value) => MapEntry(key, value as Object),
    ));
  }
}
```

### DirectionsCacheService Singleton

```dart
// lib/services/directions_cache_service.dart

class DirectionsCacheService {
  static final DirectionsCacheService _instance = DirectionsCacheService._internal();
  factory DirectionsCacheService() => _instance;
  DirectionsCacheService._internal();

  final Map<String, DirectionsCacheEntry> _cache = {};
  static const Duration _defaultCacheDuration = Duration(hours: 1);
  static const int _maxCacheSize = 50;

  // LRU cache with TTL validation
  List<LatLng>? getCachedDirections(LatLng origin, LatLng destination, {
    Duration maxAge = _defaultCacheDuration,
  }) {
    final key = _generateCacheKey(origin, destination);
    final entry = _cache[key];
    if (entry != null && entry.isValid(maxAge: maxAge)) {
      _cache.remove(key);
      _cache[key] = entry; // Move to end (LRU)
      return entry.points;
    }
    return null;
  }
}
```

**Singleton patterns used in ironmove-app:**
- `DioClient`: `static final _instance` with private `_internal()` constructor
- `AnalyticsService`: Lazy `static AnalyticsService?` with `??=` initialization
- `DirectionsCacheService`: `static final _instance` with `factory` constructor redirect
- `PushNotificationService`: Same pattern as AnalyticsService

---

## Theme Setup

ironmove-app centralizes colors in `AppColors` and theme in `AppTheme`, using Google Fonts (Noto Sans Thai) and Material 3.

```dart
// lib/core/theme.dart

class AppColors {
  static const Color primary = Color(0xFF6366F6);
  static const Color text = Color(0xFF212933);
  static const Color background = Color(0xFFF2F3F6);
  static const Color card = Color(0xFFFFFFFF);
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        surface: AppColors.card,
        error: AppColors.error,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.notoSansThai(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
      textTheme: GoogleFonts.notoSansThaiTextTheme(/* ... */),
    );
  }
}
```

---

## Best Practices

1. **Layer-based structure** with `core/`, `models/`, `services/`, `providers/`, `screens/`, `widgets/`, `utils/`, `l10n/`
2. **StateNotifier + State classes** with `copyWith` for predictable state transitions
3. **Simple Provider** for singleton services, **StateNotifierProvider** for complex state
4. **GoRouter with named routes** for type-safe, deep-linkable navigation
5. **Result sealed class** for explicit success/failure handling in services
6. **Structured exception hierarchy** with user-friendly message mapping via `ExceptionMessages`
7. **Freezed models** with `@Default`, custom getters via `const Model._()`, and `fromJson`
8. **Singleton pattern** for DioClient, AnalyticsService, PushNotificationService, DirectionsCacheService

---

## Anti-Patterns

- Using feature-first structure in ironmove-app (the project uses layer-based)
- Using `setState` for shared or complex state (use StateNotifier + Riverpod)
- Creating multiple Dio instances instead of using the DioClient singleton
- Throwing raw exceptions without mapping to the AppException hierarchy
- Returning raw values from storage/network operations instead of wrapping in Result
- Putting business logic in screens instead of in providers/services
- Skipping `const` constructors on State classes and Freezed factories
- Not providing `copyWith` on hand-written State classes
