---
name: flutter-testing
description: Flutter testing with manual mock classes, Riverpod ProviderContainer testing, Result type tests, widget tests, screen tests, and @visibleForTesting patterns for ironmove-app
---

# Flutter Testing Patterns

Testing patterns used in ironmove-app. Uses manual mock classes (NO mockito/code generation), ProviderContainer for Riverpod testing, and mirrors `lib/` structure in `test/`. Target coverage: 74%+ line coverage.

## Table of Contents

1. [Manual Mock Classes](#manual-mock-classes)
2. [Unit Testing with Result Type](#unit-testing-with-result-type)
3. [Service Tests](#service-tests)
4. [Riverpod Provider Tests](#riverpod-provider-tests)
5. [Widget Tests](#widget-tests)
6. [Screen Tests](#screen-tests)
7. [Test Organization](#test-organization)
8. [Test Helpers](#test-helpers)
9. [Best Practices](#best-practices)
10. [Anti-Patterns](#anti-patterns)

---

## Manual Mock Classes

**CRITICAL: Do NOT use mockito or any auto-generated mocks.** All mocks are hand-written classes that implement the interface directly. This gives full control over behavior and avoids code generation complexity.

### Implementing an Interface Mock

```dart
// test/providers/auth_provider_test.dart
// Mock that implements ApiService with function callbacks for behavior control
class MockApiService implements ApiService {
  Function? onSendAuthCode;
  Function? onVerifyAuthCode;
  Function? onGetTasks;

  @override
  Future<Map<String, dynamic>> sendAuthCode(String phone) async {
    if (onSendAuthCode != null) {
      return onSendAuthCode!(phone);
    }
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> verifyAuthCode(String phone, String code, {String? fcmToken}) async {
    if (onVerifyAuthCode != null) {
      return onVerifyAuthCode!(phone, code);
    }
    return {
      'access_token': 'mock-token-123',
      'user': {
        'id': '1',
        'phone': phone,
        'name': 'Test Driver',
      },
    };
  }

  @override
  Future<List<Task>> getTasks({int? role}) async {
    if (onGetTasks != null) {
      return onGetTasks!();
    }
    return [];
  }

  // Stub unused methods with UnimplementedError
  @override
  Future<Task> getTaskDetails(String taskId) async {
    throw UnimplementedError();
  }

  // ... other stubs
}
```

### Mock with State Tracking

```dart
// test/providers/auth_provider_test.dart
class MockSecureStorageService implements SecureStorageService {
  String? storedToken;
  Map<String, String>? storedUserInfo;
  bool shouldFailGetToken = false;
  bool shouldReturnEmptyToken = false;

  @override
  Future<Result<String?>> getToken() async {
    if (shouldFailGetToken) {
      return Failure('Failed to get token');
    }
    if (shouldReturnEmptyToken) {
      return Success(null);
    }
    return Success(storedToken);
  }

  @override
  Future<Result<void>> saveToken(String token) async {
    storedToken = token;
    return Success(null);
  }

  @override
  Future<Result<void>> clearAll() async {
    storedToken = null;
    storedUserInfo = null;
    return Success(null);
  }

  @override
  Future<bool> isLoggedIn() async {
    final tokenResult = await getToken();
    return tokenResult.isSuccess && tokenResult.dataOrNull != null;
  }
}
```

### Mock Implementation in Production Code

```dart
// lib/services/image_picker_service.dart
// Abstract interface + concrete implementation + mock in same file
abstract class ImagePickerService {
  Future<File?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  });
}

class ImagePickerServiceImpl implements ImagePickerService {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<File?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );
      if (image != null) {
        return File(image.path);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

// Mock implementation for testing
class MockImagePickerService implements ImagePickerService {
  File? _mockImageFile;
  bool _shouldThrowError = false;

  void setMockImageFile(File? file) => _mockImageFile = file;
  void setShouldThrowError(bool shouldThrow) => _shouldThrowError = shouldThrow;

  @override
  Future<File?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    if (_shouldThrowError) {
      throw Exception('Failed to pick image');
    }
    return _mockImageFile;
  }
}
```

---

## Unit Testing with Result Type

The `Result<T>` type (Success/Failure) is the core error-handling pattern. Test both paths thoroughly.

```dart
// test/core/result_test.dart
void main() {
  group('Success', () {
    test('creates success result with data', () {
      const result = Success('test data');

      expect(result.data, 'test data');
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
    });

    test('when executes success function', () {
      const result = Success(100);

      final output = result.when<String>(
        success: (data) => 'Success: $data',
        failure: (message, exception, statusCode) => 'Failure: $message',
      );

      expect(output, 'Success: 100');
    });

    test('map transforms success data', () {
      const result = Success(10);

      final mapped = result.map<String>((value) => 'Number: $value');

      expect(mapped, isA<Success<String>>());
      expect(mapped.dataOrNull, 'Number: 10');
    });
  });

  group('Failure', () {
    test('creates failure result with all parameters', () {
      final exception = Exception('Original error');
      final result = Failure(
        'Network error',
        exception: exception,
        statusCode: 500,
      );

      expect(result.message, 'Network error');
      expect(result.exception, exception);
      expect(result.statusCode, 500);
    });

    test('map preserves failure', () {
      const result = Failure<int>('Original error', statusCode: 400);

      final mapped = result.map<String>((value) => 'Transformed: $value');

      expect(mapped, isA<Failure<String>>());
      expect(mapped.errorOrNull, 'Original error');
      expect((mapped as Failure).statusCode, 400);
    });

    test('map stops transformation on failure', () {
      const result = Failure<int>('Initial error');

      final chainedResult = result
          .map<int>((value) => value * 2)
          .map<String>((value) => 'Result: $value');

      expect(chainedResult, isA<Failure<String>>());
      expect(chainedResult.errorOrNull, 'Initial error');
    });
  });

  group('Result with different types', () {
    test('works with nullable type', () {
      const success = Success<String?>(null);
      const failure = Failure<String?>('Error');

      expect(success.dataOrNull, isNull);
      expect(success.isSuccess, isTrue);
      expect(failure.dataOrNull, isNull);
      expect(failure.isSuccess, isFalse);
    });
  });
}
```

---

## Service Tests

### Testing with @visibleForTesting Constructor

Services use `@visibleForTesting` constructors to inject mock dependencies.

```dart
// lib/services/secure_storage_service.dart
class SecureStorageService {
  final FlutterSecureStorage _storage;

  // Default constructor with standard configuration
  SecureStorageService() : _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Constructor for testing with dependency injection
  @visibleForTesting
  SecureStorageService.withStorage(this._storage);

  static const Duration sessionDuration = Duration(minutes: 30);

  Future<Result<void>> saveToken(String token) async {
    try {
      await _storage.write(key: 'auth_token', value: token);
      return const Success(null);
    } catch (e) {
      return Failure('Cannot save token');
    }
  }
}
```

```dart
// test/services/secure_storage_service_test.dart
class MockFlutterSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _storage = {};
  bool shouldThrowError = false;

  MockFlutterSecureStorage() : super();

  @override
  Future<String?> read({required String key, ...}) async {
    if (shouldThrowError) throw Exception('Failed to read');
    return _storage[key];
  }

  @override
  Future<void> write({required String key, required String? value, ...}) async {
    if (shouldThrowError) throw Exception('Failed to write');
    if (value != null) _storage[key] = value;
  }

  void setMockData(Map<String, String> data) {
    _storage.clear();
    _storage.addAll(data);
  }
}

void main() {
  group('SecureStorageService', () {
    late MockFlutterSecureStorage mockStorage;
    late SecureStorageService service;

    setUp(() {
      mockStorage = MockFlutterSecureStorage();
      service = SecureStorageService.withStorage(mockStorage);  // <-- @visibleForTesting
    });

    group('saveToken', () {
      test('should save token successfully', () async {
        final result = await service.saveToken('test_token_123');

        expect(result.isSuccess, true);
        expect(mockStorage.storage['auth_token'], 'test_token_123');
      });

      test('should return failure when storage throws error', () async {
        mockStorage.shouldThrowError = true;

        final result = await service.saveToken('test_token');

        expect(result.isFailure, true);
      });
    });

    group('Integration tests', () {
      test('should handle complete login flow', () async {
        var result = await service.saveToken('auth_token_123');
        expect(result.isSuccess, true);

        result = await service.saveUserInfo(
          userId: 'user_123', name: 'John Doe', phone: '0891234567',
        );
        expect(result.isSuccess, true);

        final isLoggedIn = await service.isLoggedIn();
        expect(isLoggedIn, true);

        final tokenResult = await service.getToken();
        expect(tokenResult.dataOrNull, 'auth_token_123');
      });

      test('should handle complete logout flow', () async {
        mockStorage.setMockData({
          'auth_token': 'token',
          'user_id': 'user_123',
          'user_name': 'John Doe',
          'user_phone': '0891234567',
        });

        var isLoggedIn = await service.isLoggedIn();
        expect(isLoggedIn, true);

        final result = await service.clearAll();
        expect(result.isSuccess, true);

        isLoggedIn = await service.isLoggedIn();
        expect(isLoggedIn, false);
      });
    });
  });
}
```

### Singleton Service Test

```dart
// test/services/directions_cache_service_test.dart
void main() {
  group('DirectionsCacheService', () {
    late DirectionsCacheService cacheService;

    setUp(() {
      cacheService = DirectionsCacheService();
      cacheService.clearCache();
    });

    tearDown(() {
      cacheService.clearCache();
    });

    test('should cache and retrieve directions', () {
      const origin = LatLng(13.7563, 100.5018);
      const destination = LatLng(13.7469, 100.5350);
      final points = [origin, const LatLng(13.7550, 100.5100), destination];

      cacheService.cacheDirections(origin, destination, points);

      final cached = cacheService.getCachedDirections(origin, destination);
      expect(cached, isNotNull);
      expect(cached, equals(points));
    });

    test('should return null for cache miss', () {
      const origin = LatLng(13.7563, 100.5018);
      const destination = LatLng(13.7469, 100.5350);

      final cached = cacheService.getCachedDirections(origin, destination);
      expect(cached, isNull);
    });

    group('Singleton Pattern', () {
      test('should return same instance', () {
        final instance1 = DirectionsCacheService();
        final instance2 = DirectionsCacheService();
        expect(identical(instance1, instance2), isTrue);
      });

      test('should share cache between instances', () {
        final instance1 = DirectionsCacheService();
        final instance2 = DirectionsCacheService();
        const origin = LatLng(13.7563, 100.5018);
        const destination = LatLng(13.7469, 100.5350);

        instance1.cacheDirections(origin, destination, [origin, destination]);
        final cached = instance2.getCachedDirections(origin, destination);
        expect(cached, isNotNull);
      });
    });
  });
}
```

---

## Riverpod Provider Tests

Use `ProviderContainer` with overrides. No widget tree needed for pure provider logic.

```dart
// test/providers/auth_provider_test.dart
void main() {
  group('Auth Provider Tests', () {
    late ProviderContainer container;
    late MockApiService mockApiService;
    late MockSecureStorageService mockStorageService;
    late MockImagePickerService mockImagePickerService;

    setUp(() {
      mockApiService = MockApiService();
      mockStorageService = MockSecureStorageService();
      mockImagePickerService = MockImagePickerService();

      container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(mockApiService),
          secureStorageServiceProvider.overrideWithValue(mockStorageService),
          imagePickerServiceProvider.overrideWithValue(mockImagePickerService),
        ],
      );
    });

    tearDown(() {
      container.dispose();  // Always dispose to prevent memory leaks
    });

    group('AuthState', () {
      test('should have correct default values', () {
        const state = AuthState();
        expect(state.isAuthenticated, false);
        expect(state.user, null);
        expect(state.isLoading, false);
        expect(state.error, null);
      });

      test('copyWith should update specific fields', () {
        const state = AuthState();
        final newState = state.copyWith(
          isAuthenticated: true,
          phoneNumber: '+66812345678',
        );
        expect(newState.isAuthenticated, true);
        expect(newState.phoneNumber, '+66812345678');
        expect(newState.user, null); // unchanged
      });
    });

    group('AuthNotifier', () {
      test('should send OTP successfully', () async {
        final notifier = container.read(authProvider.notifier);

        await notifier.sendOtp('0812345678');

        final state = container.read(authProvider);
        expect(state.phoneNumber, '+66812345678');
        expect(state.isLoading, false);
        expect(state.error, null);
      });

      test('should handle sendOtp error', () async {
        mockApiService.onSendAuthCode = (phone) => throw Exception('Network error');
        final notifier = container.read(authProvider.notifier);

        try {
          await notifier.sendOtp('0812345678');
          fail('Should have thrown an exception');
        } catch (e) {
          expect(e.toString(), contains('Network error'));
        }

        final state = container.read(authProvider);
        expect(state.isLoading, false);
        expect(state.error, contains('Network error'));
      });

      test('should verify OTP and save token', () async {
        final notifier = container.read(authProvider.notifier);

        await notifier.sendOtp('0812345678');
        await notifier.verifyOtp('123456');

        final state = container.read(authProvider);
        expect(state.isAuthenticated, true);
        expect(state.accessToken, 'mock-token-123');
        expect(mockStorageService.storedToken, 'mock-token-123');
      });

      test('should clear all auth data on logout', () async {
        final notifier = container.read(authProvider.notifier);

        // Setup authenticated state
        await notifier.sendOtp('0812345678');
        await notifier.verifyOtp('123456');
        expect(container.read(authProvider).isAuthenticated, true);

        // Logout
        await notifier.logout();

        final state = container.read(authProvider);
        expect(state.isAuthenticated, false);
        expect(state.user, null);
        expect(state.accessToken, null);
        expect(mockStorageService.storedToken, null);
      });
    });

    group('Initialization', () {
      test('should restore authenticated state from stored token', () async {
        mockStorageService.storedToken = 'valid-token';
        mockStorageService.storedUserInfo = {
          'userId': '1',
          'phone': '+66812345678',
          'name': 'Test Driver',
        };

        final testContainer = ProviderContainer(
          overrides: [
            apiServiceProvider.overrideWithValue(mockApiService),
            secureStorageServiceProvider.overrideWithValue(mockStorageService),
          ],
        );

        // Poll until initialization completes
        for (int i = 0; i < 20; i++) {
          await Future.delayed(Duration(milliseconds: 100));
          final state = testContainer.read(authProvider);
          if (!state.isLoading) break;
        }

        final state = testContainer.read(authProvider);
        expect(state.isAuthenticated, true);
        expect(state.accessToken, 'valid-token');

        testContainer.dispose();
      });
    });
  });
}
```

---

## Widget Tests

Test widgets in isolation with `MaterialApp` wrapper.

```dart
// test/widgets/shared/buttons/primary_button_test.dart
void main() {
  group('PrimaryButton', () {
    testWidgets('displays label text', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrimaryButton(
              label: 'Click Me',
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.text('Click Me'), findsOneWidget);
    });

    testWidgets('shows loading indicator when isLoading is true', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrimaryButton(
              label: 'Loading',
              onPressed: () {},
              isLoading: true,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('disables button when isEnabled is false', (WidgetTester tester) async {
      bool wasPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrimaryButton(
              label: 'Disabled',
              onPressed: () => wasPressed = true,
              isEnabled: false,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(PrimaryButton));
      expect(wasPressed, isFalse);
    });

    testWidgets('executes onPressed callback when tapped', (WidgetTester tester) async {
      bool wasPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrimaryButton(
              label: 'Tap Me',
              onPressed: () => wasPressed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(PrimaryButton));
      expect(wasPressed, isTrue);
    });

    testWidgets('shows outlined button when type is outlined', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrimaryButton(
              label: 'Test',
              onPressed: () {},
              type: PrimaryButtonType.outlined,
            ),
          ),
        ),
      );

      expect(find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_OutlinedButtonWithIcon',
      ), findsOneWidget);
    });

    testWidgets('expands width by default', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrimaryButton(
              label: 'Full Width',
              onPressed: () {},
            ),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, double.infinity);
    });
  });
}
```

---

## Screen Tests

Screen tests use `ProviderScope` + localization delegates + mock router.

```dart
// test/screens/auth/enter_number_screen_test.dart
class MockGoRouter implements GoRouter {
  String? lastPushedLocation;
  Object? lastPushedExtra;

  @override
  void go(String location, {Object? extra}) {}

  @override
  Future<T?> push<T extends Object?>(String location, {Object? extra}) async {
    lastPushedLocation = location;
    lastPushedExtra = extra;
    return null;
  }

  @override
  void pop<T extends Object?>([T? result]) {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget createTestWidget({
  required Widget child,
  MockGoRouter? mockGoRouter,
}) {
  mockGoRouter ??= MockGoRouter();

  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: InheritedGoRouter(
        goRouter: mockGoRouter,
        child: child,
      ),
    ),
  );
}

void main() {
  group('EnterNumberScreen', () {
    testWidgets('should display all UI components', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        child: const EnterNumberScreen(),
      ));

      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget);
      expect(find.byIcon(Icons.phone_android), findsOneWidget);
    });

    testWidgets('should enable button only when valid phone is entered', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        child: const EnterNumberScreen(),
      ));

      // Initially disabled
      expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).isEnabled, false);

      // Enter partial number - still disabled
      await tester.enterText(find.byType(TextField), '081234');
      await tester.pump();
      expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).isEnabled, false);

      // Enter valid number - enabled
      await tester.enterText(find.byType(TextField), '0812345678');
      await tester.pump();
      expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).isEnabled, true);

      // Clear text - disabled again
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).isEnabled, false);
    });

    testWidgets('button should not navigate when phone is invalid', (WidgetTester tester) async {
      final mockGoRouter = MockGoRouter();

      await tester.pumpWidget(createTestWidget(
        child: const EnterNumberScreen(),
        mockGoRouter: mockGoRouter,
      ));

      await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
      await tester.pump();

      expect(mockGoRouter.lastPushedLocation, isNull);
    });

    testWidgets('should have correct TextField configuration', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        child: const EnterNumberScreen(),
      ));

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.keyboardType, TextInputType.phone);
      expect(textField.decoration?.filled, true);
      expect(textField.inputFormatters, isNotNull);
    });
  });
}
```

---

## Test Organization

The test directory mirrors `lib/` structure exactly:

```
test/
  core/
    dio_client_test.dart
    env_test.dart
    exceptions_test.dart
    extensions_test.dart
    result_test.dart
    router_test.dart
    theme_test.dart
  helpers/
    notification_toast_helper_test.dart
  models/
    asset_location_test.dart
    expense_test.dart
    location_test.dart
    task_test.dart
    user_test.dart
  providers/
    auth_provider_test.dart
    location_provider_test.dart
    route_guard_provider_test.dart
    tasks_provider_test.dart
  screens/
    auth/
      enter_number_screen_test.dart
      otp_screen_test.dart
    error_screen_test.dart
    expenses/
      expense_form_screen_test.dart
    splash_screen_test.dart
    tasks/
      complete_task_screen_test.dart
      ongoing_task_full_map_screen_test.dart
      ongoing_task_screen_test.dart
      task_details_screen_test.dart
      task_list_screen_test.dart
  services/
    api_service_test.dart
    directions_cache_service_test.dart
    google_api_service_cache_test.dart
    google_api_service_test.dart
    image_picker_service_test.dart
    location_service_test.dart
    native_location_service_test.dart
    push_notification_service_test.dart
    secure_storage_service_test.dart
  utils/
    map_utils_test.dart
    task_utils_test.dart
    validators_test.dart
  widgets/
    expenses/
      expense_card_test.dart
    location/
      tracking_indicator_test.dart
    shared/
      buttons/
        primary_button_test.dart
        slide_action_button_test.dart
      cards/
        app_card_test.dart
      feedback/
        custom_toast_test.dart
        empty_display_test.dart
        error_display_test.dart
        loading_display_test.dart
      progress/
        animated_location_progress_test.dart
        location_progress_bar_test.dart
    tasks/
      task_card_test.dart
```

---

## Test Helpers

### createTestWidget Helper

Wrap screens in ProviderScope + MaterialApp + router + localization for consistent test setup:

```dart
Widget createTestWidget({
  required Widget child,
  MockGoRouter? mockGoRouter,
  List<Override> overrides = const [],
}) {
  mockGoRouter ??= MockGoRouter();

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: InheritedGoRouter(
        goRouter: mockGoRouter,
        child: child,
      ),
    ),
  );
}
```

### @visibleForTesting Pattern

Use `@visibleForTesting` named constructors on services so tests can inject mock dependencies without changing the public API:

```dart
// Production code
class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService() : _storage = const FlutterSecureStorage(...);

  @visibleForTesting
  SecureStorageService.withStorage(this._storage);
}

// Test code
final service = SecureStorageService.withStorage(mockStorage);
```

### Polling for Async Initialization

When testing providers that initialize asynchronously, poll until the state stabilizes:

```dart
// Wait for initialization to complete
for (int i = 0; i < 20; i++) {
  await Future.delayed(Duration(milliseconds: 100));
  final state = container.read(authProvider);
  if (!state.isLoading) break;
}
```

---

## Best Practices

1. **Use manual mock classes, never mockito** -- implement the interface directly with function callbacks for behavior control
2. **Always dispose ProviderContainer** in `tearDown` to prevent memory leaks
3. **Test behavior, not implementation** -- verify what the user sees, not widget internals
4. **Use `@visibleForTesting` constructors** on services to inject mock dependencies
5. **Mirror `lib/` structure in `test/`** exactly for easy navigation
6. **Test all state transitions**: loading, success, error, empty
7. **Use `ProviderContainer` for unit testing** Riverpod providers (no widget tree needed)
8. **Wrap screen tests with localization delegates** -- ironmove-app uses Thai localization
9. **Use `setUp` and `tearDown`** for proper test isolation
10. **Target 74%+ line coverage** -- focus on critical paths and edge cases

---

## Anti-Patterns

- **Using mockito or code-generated mocks** -- always use manual mock classes that implement the interface
- **Not disposing ProviderContainer in tearDown** -- causes memory leaks between tests
- **Using `find.byType(Container)` for assertions** -- too fragile, use semantic finders
- **Testing widget internals instead of visible behavior** -- test what users see
- **Not testing error/loading/empty states** -- only testing happy path leaves gaps
- **Skipping `setUp`/`tearDown` for test isolation** -- state leaks between tests
- **Hardcoding localized strings in assertions** -- use `context.l10n` references
- **Using `tester.pumpAndSettle()` with infinite animations** -- will timeout, use `pump()` with specific duration instead
- **Not cleaning up singleton state between tests** -- call `clearCache()` or equivalent in setUp/tearDown
