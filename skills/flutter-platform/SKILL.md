---
name: flutter-platform
description: Flutter skill — platform channels (MethodChannel/EventChannel), background services, runtime permissions, and native iOS/Android integration
---

# Flutter Platform Integration

Platform integration patterns for the ironmove-app. Covers NativeLocationService with platform channels (`com.ironmove.location_service`) for 30-second background GPS tracking, LocationService abstraction with the `location` package, progressive permission requests (whileInUse then always), FlutterSecureStorage with `@visibleForTesting` constructor for testability, ImagePickerService abstraction with max 5 images per expense, and iOS SMS auto-fill with zero-width character backspace detection.

## Table of Contents

1. [Native Location Service](#native-location-service)
2. [Location Abstraction](#location-abstraction)
3. [Permissions](#permissions)
4. [Secure Storage](#secure-storage)
5. [Image Picker](#image-picker)
6. [SMS Auto-Fill Pattern](#sms-auto-fill-pattern)
7. [Best Practices](#best-practices)
8. [Anti-Patterns](#anti-patterns)

---

## Native Location Service

The `NativeLocationService` uses a `MethodChannel` with the channel name `com.ironmove.location_service` to start and stop a native Android/iOS background location service. All methods are static. The native service posts asset locations to the backend at 30-second intervals.

```dart
// lib/services/native_location_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeLocationService {
  static const MethodChannel _channel = MethodChannel('com.ironmove.location_service');

  /// Start native location tracking service.
  /// Passes API token, task ID, and asset ID to the native layer
  /// which handles 30-second interval location posting to the backend.
  static Future<void> startNativeTracking({
    required String apiToken,
    required String taskId,
    required String assetId,
  }) async {
    try {
      await _channel.invokeMethod('startLocationService', {
        'api_token': apiToken,
        'task_id': taskId,
        'asset_id': assetId,
      });
    } on PlatformException catch (e) {
      throw Exception("Failed to start native location service: ${e.message}");
    }
  }

  /// Stop native location tracking service
  static Future<void> stopNativeTracking() async {
    try {
      await _channel.invokeMethod('stopLocationService');
    } on PlatformException catch (e) {
      throw Exception("Failed to stop native location service: ${e.message}");
    }
  }

  /// Check if native location service is currently running
  static Future<bool> isTrackingActive() async {
    try {
      return await _channel.invokeMethod('isLocationServiceActive') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
```

Key design decisions:
- **Static methods** -- the native service is a system-level singleton managed by the OS, so Dart-side state is unnecessary
- **Three method channel calls**: `startLocationService`, `stopLocationService`, `isLocationServiceActive`
- **Asset location posting** -- the native layer uses the `api_token` to POST location updates for the given `asset_id` to the backend, so tracking persists across app restarts
- **PlatformException handling** -- every method call wraps in try/catch for `PlatformException`

---

## Location Abstraction

The `LocationService` is an abstract class backed by the `location` package. It provides a clean interface for location operations that can be swapped with a `MockLocationService` in tests.

```dart
// lib/services/location_service.dart
import 'dart:async';
import 'package:location/location.dart' as loc;

abstract class LocationService {
  Future<bool> serviceEnabled();
  Future<bool> requestService();
  Future<loc.PermissionStatus> hasPermission();
  Future<loc.PermissionStatus> requestPermission();
  Future<loc.LocationData> getLocation();
  Stream<loc.LocationData> get onLocationChanged;
}

class LocationServiceImpl implements LocationService {
  final loc.Location _location = loc.Location();

  @override
  Future<bool> serviceEnabled() => _location.serviceEnabled();

  @override
  Future<bool> requestService() => _location.requestService();

  @override
  Future<loc.PermissionStatus> hasPermission() => _location.hasPermission();

  @override
  Future<loc.PermissionStatus> requestPermission() => _location.requestPermission();

  @override
  Future<loc.LocationData> getLocation() => _location.getLocation();

  @override
  Stream<loc.LocationData> get onLocationChanged => _location.onLocationChanged;
}
```

### Mock Implementation for Testing

```dart
// lib/services/location_service.dart
class MockLocationService implements LocationService {
  final StreamController<loc.LocationData> _locationController =
      StreamController<loc.LocationData>.broadcast();

  bool _serviceEnabled = true;
  loc.PermissionStatus _permissionStatus = loc.PermissionStatus.granted;
  loc.LocationData? _currentLocation;
  bool _shouldThrowError = false;

  @override
  Stream<loc.LocationData> get onLocationChanged => _locationController.stream;

  @override
  Future<bool> serviceEnabled() async {
    if (_shouldThrowError) throw Exception('Service check failed');
    return _serviceEnabled;
  }

  @override
  Future<loc.PermissionStatus> hasPermission() async {
    if (_shouldThrowError) throw Exception('Permission check failed');
    return _permissionStatus;
  }

  @override
  Future<loc.PermissionStatus> requestPermission() async {
    if (_shouldThrowError) throw Exception('Permission request failed');
    return _permissionStatus = loc.PermissionStatus.granted;
  }

  @override
  Future<loc.LocationData> getLocation() async {
    if (_shouldThrowError) throw Exception('Location fetch failed');
    if (_currentLocation == null) throw Exception('No location available');
    return _currentLocation!;
  }

  // Mock control methods
  void setServiceEnabled(bool enabled) => _serviceEnabled = enabled;
  void setPermissionStatus(loc.PermissionStatus status) => _permissionStatus = status;
  void setShouldThrowError(bool shouldThrow) => _shouldThrowError = shouldThrow;

  void setCurrentLocation(double latitude, double longitude) {
    _currentLocation = loc.LocationData.fromMap({
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': 5.0,
      'altitude': 0.0,
      'speed': 0.0,
      'speed_accuracy': 0.0,
      'heading': 0.0,
      'time': DateTime.now().millisecondsSinceEpoch.toDouble(),
    });
  }

  void emitLocationData(double latitude, double longitude) {
    final locationData = loc.LocationData.fromMap({
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': 5.0,
      'altitude': 0.0,
      'speed': 0.0,
      'speed_accuracy': 0.0,
      'heading': 0.0,
      'time': DateTime.now().millisecondsSinceEpoch.toDouble(),
    });
    _locationController.add(locationData);
  }

  void dispose() => _locationController.close();
}
```

### Location Provider

The `LocationService` is exposed via a Riverpod provider for dependency injection:

```dart
// lib/providers/location_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ironmove_app/services/location_service.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationServiceImpl();
});
```

---

## Permissions

The ironmove-app uses the `location` package's built-in permission API (not `permission_handler`). The permission flow is progressive: request "when in use" first, then upgrade to "always" for background tracking.

### Progressive Permission Request Flow

1. Check if location services are enabled on the device
2. Request "when in use" location permission
3. Once granted, request "always" permission for background tracking
4. If denied, show rationale and fallback gracefully

```dart
// Typical flow in a location-dependent feature:
final locationService = ref.read(locationServiceProvider);

// Step 1: Check service enabled
bool serviceEnabled = await locationService.serviceEnabled();
if (!serviceEnabled) {
  serviceEnabled = await locationService.requestService();
  if (!serviceEnabled) return; // User declined
}

// Step 2: Check permission
var permission = await locationService.hasPermission();
if (permission == loc.PermissionStatus.denied) {
  permission = await locationService.requestPermission();
  if (permission != loc.PermissionStatus.granted &&
      permission != loc.PermissionStatus.grantedLimited) {
    return; // User denied
  }
}

// Step 3: Get location
final locationData = await locationService.getLocation();
```

### Background Location

For background tracking, the native location service is started via `NativeLocationService.startNativeTracking()`. This uses the native Android foreground service / iOS background location capability, which requires the "always" permission. The native layer handles:
- 30-second interval location updates
- Posting location to the backend via the provided API token
- Persistence across app restarts (the service runs independently of the Flutter engine)

---

## Secure Storage

The `SecureStorageService` wraps `FlutterSecureStorage` for storing auth tokens, user info, and session data. It uses Android encrypted shared preferences and provides a `@visibleForTesting` constructor for test injection.

```dart
// lib/services/secure_storage_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ironmove_app/core/result.dart';
import 'package:ironmove_app/core/exceptions.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage;

  // Default constructor with Android encrypted shared preferences
  SecureStorageService() : _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // Constructor for testing with dependency injection
  @visibleForTesting
  SecureStorageService.withStorage(this._storage);

  // Storage keys
  static const String _keyAuthToken = 'auth_token';
  static const String _keyUserId = 'user_id';
  static const String _keyUserName = 'user_name';
  static const String _keyUserPhone = 'user_phone';
  static const String _keySessionExpiry = 'session_expiry';

  static const Duration sessionDuration = Duration(minutes: 30);
}
```

### Token Management with Result Type

All storage operations return `Result<T>` to handle errors without exceptions:

```dart
// lib/services/secure_storage_service.dart
Future<Result<void>> saveToken(String token) async {
  try {
    await _storage.write(key: _keyAuthToken, value: token);
    final expiry = DateTime.now().add(sessionDuration);
    await _storage.write(key: _keySessionExpiry, value: expiry.toIso8601String());
    return const Success(null);
  } catch (e) {
    return Failure(
      'Failed to save token',
      exception: AppException('Failed to save token', originalError: e),
    );
  }
}

Future<Result<String?>> getToken() async {
  try {
    final token = await _storage.read(key: _keyAuthToken);
    return Success(token);
  } catch (e) {
    return Failure(
      'Failed to read token',
      exception: AppException('Failed to read token', originalError: e),
    );
  }
}

Future<Result<void>> clearAll() async {
  try {
    await _storage.deleteAll();
    return const Success(null);
  } catch (e) {
    return Failure(
      'Failed to clear storage',
      exception: AppException('Failed to clear storage', originalError: e),
    );
  }
}
```

### User Info Storage

```dart
// lib/services/secure_storage_service.dart
Future<Result<void>> saveUserInfo({
  required String userId,
  required String name,
  required String phone,
}) async {
  try {
    await _storage.write(key: _keyUserId, value: userId);
    await _storage.write(key: _keyUserName, value: name);
    await _storage.write(key: _keyUserPhone, value: phone);
    return const Success(null);
  } catch (e) {
    return Failure(
      'Failed to save user info',
      exception: AppException('Failed to save user info', originalError: e),
    );
  }
}

Future<Result<Map<String, String>?>> getUserInfo() async {
  try {
    final userId = await _storage.read(key: _keyUserId);
    final name = await _storage.read(key: _keyUserName);
    final phone = await _storage.read(key: _keyUserPhone);

    if (userId == null || name == null || phone == null) {
      return const Success(null);
    }

    return Success({'userId': userId, 'name': name, 'phone': phone});
  } catch (e) {
    return Failure(
      'Failed to read user info',
      exception: AppException('Failed to read user info', originalError: e),
    );
  }
}
```

### Testing with @visibleForTesting Constructor

```dart
// In tests, inject a mock FlutterSecureStorage:
final mockStorage = MockFlutterSecureStorage();
final service = SecureStorageService.withStorage(mockStorage);
```

---

## Image Picker

The `ImagePickerService` is an abstract class with an `ImagePickerServiceImpl` that wraps the `image_picker` package. The expense feature limits uploads to a maximum of 5 images per expense.

```dart
// lib/services/image_picker_service.dart
import 'dart:io';
import 'package:image_picker/image_picker.dart';

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
```

### Mock Implementation for Testing

```dart
// lib/services/image_picker_service.dart
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
    if (_shouldThrowError) throw Exception('Failed to pick image');
    return _mockImageFile;
  }
}
```

### Provider Registration

```dart
// lib/providers/auth_provider.dart
final imagePickerServiceProvider = Provider<ImagePickerService>((ref) {
  return ImagePickerServiceImpl();
});
```

---

## SMS Auto-Fill Pattern

The OTP screen uses a zero-width character (`\u200b`) pattern for iOS SMS auto-fill and backspace detection. On Android, `KeyboardListener` handles backspace natively.

### Zero-Width Character for iOS Backspace Detection

iOS does not reliably fire `onChanged` when backspace is pressed on an empty `TextField`. The workaround is to pre-fill each field with a zero-width space so the field is never truly empty:

```dart
// lib/screens/auth/otp_screen.dart
static const String _zeroWidthChar = '\u200b';

void _handleIOSFocus(int index) {
  // Don't add zero-width char on initial auto-focus to allow SMS autofill
  if (_isInitialFocus && index == 0) {
    _isInitialFocus = false;
    return;
  }
  // Only add zero-width char when field gets focus and is empty
  if (_focusNodes[index].hasFocus && _controllers[index].text.isEmpty) {
    _controllers[index].text = _zeroWidthChar;
  }
}
```

### iOS Autofill Detection

When iOS auto-fills the OTP from SMS, it drops all 6 digits into a single field. The listener detects this and distributes digits across all fields:

```dart
// lib/screens/auth/otp_screen.dart
void _handleIOSAutofill(int index) {
  final text = _controllers[index].text.replaceAll(_zeroWidthChar, '');
  // If we get 6 digits in any field, it's likely iOS autofill
  if (text.length == 6 && !_isPasting) {
    _handleFullPaste(text, 0);
  }
}

void _handleFullPaste(String value, int startIndex) {
  _isPasting = true;
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');

  // Distribute digits across all fields
  for (int i = 0; i < digits.length && i < 6; i++) {
    if (startIndex + i < 6) {
      if (Platform.isIOS) {
        _controllers[startIndex + i].text = digits[i] + _zeroWidthChar;
      } else {
        _controllers[startIndex + i].text = digits[i];
      }
    }
  }

  // Auto verify when all fields are filled from paste
  final filledCount = Platform.isIOS
      ? _controllers.where((c) => c.text.replaceAll(_zeroWidthChar, '').isNotEmpty).length
      : _controllers.where((c) => c.text.isNotEmpty).length;

  if (filledCount >= 6) {
    _focusNodes[5].unfocus();
    _verifyOtp();
  }

  Future.delayed(const Duration(milliseconds: 100), () {
    _isPasting = false;
  });
}
```

### Platform-Specific OTP Field Building

Android uses `KeyboardListener` for reliable backspace handling. iOS relies on the zero-width character approach:

```dart
// lib/screens/auth/otp_screen.dart
Widget _buildOtpField(int index) {
  if (Platform.isAndroid) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace) {
          if (_controllers[index].text.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
            _controllers[index - 1].clear();
          }
        }
      },
      child: _buildTextField(index),
    );
  } else {
    return _buildTextField(index);
  }
}
```

### AutofillHints for SMS

The first field (or all fields on iOS) uses `AutofillHints.oneTimeCode` wrapped in an `AutofillGroup`:

```dart
// lib/screens/auth/otp_screen.dart
AutofillGroup(
  child: Row(
    children: List.generate(6, (index) {
      return _buildOtpField(index);
    }),
  ),
)

// In _buildTextField:
autofillHints: (Platform.isIOS || index == 0)
    ? const [AutofillHints.oneTimeCode]
    : null,
```

---

## Best Practices

1. **Use a single MethodChannel per native module** -- `NativeLocationService` uses one channel (`com.ironmove.location_service`) and multiplexes via method names (`startLocationService`, `stopLocationService`, `isLocationServiceActive`).

2. **Always handle PlatformException** -- every `invokeMethod` call can throw `PlatformException`. Wrap in try/catch and convert to a domain-specific exception or return a `Result` type.

3. **Abstract platform services behind interfaces** -- `LocationService`, `ImagePickerService`, and `SecureStorageService` all have abstract interfaces with concrete and mock implementations for testability.

4. **Use @visibleForTesting for test-only constructors** -- `SecureStorageService.withStorage()` allows injecting a mock `FlutterSecureStorage` without exposing internals publicly.

5. **Request permissions progressively** -- ask for foreground location first, then background. Never request all permissions at app startup.

6. **Use FlutterSecureStorage instead of SharedPreferences for tokens** -- `AndroidOptions(encryptedSharedPreferences: true)` ensures encryption on Android. iOS uses the Keychain by default.

7. **Handle platform differences in OTP input** -- iOS needs the zero-width character trick for backspace detection, while Android uses `KeyboardListener`. Branch on `Platform.isIOS` / `Platform.isAndroid`.

8. **Use the _isPasting flag to prevent double verification** -- when auto-fill or paste fills all 6 OTP fields, the flag prevents `_verifyOtp` from being called multiple times.

---

## Anti-Patterns

- **Creating a new MethodChannel instance on every method call** -- reuse a single `const MethodChannel` instance. The ironmove-app correctly uses `static const MethodChannel _channel`.

- **Not handling PlatformException** -- native code can fail at any time. Missing try/catch leads to unhandled exceptions that crash the app.

- **Storing tokens in SharedPreferences instead of FlutterSecureStorage** -- SharedPreferences is unencrypted and readable by rooted/jailbroken devices.

- **Requesting "always" location permission without first obtaining "when in use"** -- the OS will reject the request on both Android and iOS. Always request progressively.

- **Using a single TextField for 6-digit OTP** -- separate fields per digit allow better UX and platform-specific handling. The zero-width character pattern only works with individual fields.

- **Not gating zero-width character logic on Platform.isIOS** -- adding zero-width characters on Android breaks `KeyboardListener` backspace detection and input formatting.

- **Forgetting the @pragma('vm:entry-point') on background entry points** -- without this annotation, tree-shaking may remove the function in release builds, causing native callbacks to fail.

- **Tight-coupling platform services to Riverpod** -- the services themselves should be plain Dart classes. Riverpod providers wrap them at the DI layer, keeping the services testable without a `ProviderContainer`.
