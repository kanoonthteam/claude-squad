---
name: flutter-networking
description: ironmove-app networking with DioClient singleton, ApiService centralized client, JSON:API response parsing, auth token flow, error handling with DioException mapping, presigned URL image upload, and directions caching
---

# Flutter Networking & API Integration

Networking patterns used in ironmove-app. Covers DioClient singleton setup, ApiService as the centralized API client, JSON:API response handling with included relationships, Bearer token authentication flow, DioException-to-custom-exception mapping, presigned URL image uploads to S3, secure token storage, and LRU directions caching.

## Table of Contents

1. [DioClient Singleton](#dioclient-singleton)
2. [ApiService Pattern](#apiservice-pattern)
3. [JSON:API Response Handling](#jsonapi-response-handling)
4. [Auth Token Flow](#auth-token-flow)
5. [Error Handling](#error-handling)
6. [Image Upload with Presigned URLs](#image-upload-with-presigned-urls)
7. [Secure Token Storage](#secure-token-storage)
8. [Directions Caching](#directions-caching)
9. [Best Practices](#best-practices)
10. [Anti-Patterns](#anti-patterns)

---

## DioClient Singleton

ironmove-app uses a single `DioClient` singleton that provides the configured Dio instance to all services.

```dart
// lib/core/dio_client.dart

import 'package:dio/dio.dart';
import 'package:ironmove_app/core/env.dart';

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

    // Logging interceptor for debugging
    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      error: true,
    ));
  }
}
```

**Key details:**
- Base URL loaded from `Env.apiBaseUrl` (environment config)
- 30-second connect and receive timeouts
- JSON content-type headers set as defaults
- `LogInterceptor` logs full request/response bodies for debugging
- Auth header (`Authorization: Bearer ...`) is set dynamically at login time on the singleton's `dio.options.headers`

---

## ApiService Pattern

ironmove-app centralizes all API calls in a single `ApiService` class that uses the DioClient singleton. It includes helper methods for parsing JSON:API responses.

```dart
// lib/services/api_service.dart

class ApiService {
  final Dio _dio;

  ApiService({Dio? dio}) : _dio = dio ?? DioClient.instance.dio;

  // Getter for dio (for extensions if needed)
  Dio get dio => _dio;

  // Helper: parse duration from API (can be String or num)
  double? _parseDuration(dynamic duration) {
    if (duration == null) return null;
    if (duration is String) return double.tryParse(duration);
    if (duration is num) return duration.toDouble();
    return null;
  }

  // Task Endpoints
  Future<List<Task>> getTasks({int? role}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (role != null) queryParams['role'] = role;

      final response = await _dio.get('/api/tasks', queryParameters: queryParams);
      final List<dynamic> data = response.data['data'] ?? response.data;
      final List<dynamic>? included = response.data['included'];

      return data.map((item) {
        final attrs = item['attributes'] ?? item;
        final taskData = {
          'id': item['id'] ?? attrs['id'] ?? '',
          'referenceNo': attrs['reference_no'] ?? '',
          'startDateTime': attrs['starts_at'] ?? DateTime.now().toIso8601String(),
          'endDateTime': attrs['ends_at'],
          'assetPlateNumber': _getAssetPlateNumber(item, included),
          'assetId': _getAssetId(item, included),
          'driverName': _getUserName(item, included),
          'plannedDuration': _parseDuration(attrs['duration']),
          'places': _parseLocationsToJson(attrs['locations'] ?? []),
          'status': attrs['status'] ?? 'ready',
          'currentSequence': attrs['current_sequence'],
          'expenses': _parseExpensesToJson(attrs['expenses'] ?? []),
        };
        return Task.fromJson(taskData);
      }).toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Authentication Endpoints
  Future<Map<String, dynamic>> sendAuthCode(String phoneNumber) async {
    try {
      final response = await _dio.post('/api/users/send_auth_code', data: {
        'client_id': Env.clientId,
        'phone_number': phoneNumber,
      });
      if (response.data is Map<String, dynamic>) return response.data;
      return {'success': true, 'message': 'OTP sent successfully'};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }
}
```

**Key patterns:**
- Constructor accepts optional `Dio` for testing: `ApiService({Dio? dio})`
- All methods catch `DioException` and remap via `_handleError()`
- Helper methods (`_parseDuration`, `_getAssetPlateNumber`, etc.) encapsulate JSON:API parsing logic
- Response types are mapped from snake_case API fields to camelCase model fields

---

## JSON:API Response Handling

The backend returns JSON:API-formatted responses with `data`, `attributes`, `relationships`, and `included` arrays. ironmove-app extracts related objects from `included`.

### Extracting from Included Relationships

```dart
// lib/services/api_service.dart

String _getAssetPlateNumber(Map<String, dynamic> item, List<dynamic>? included) {
  // Try to get from relationships + included array first
  final assetRelation = item['relationships']?['asset'];
  if (assetRelation != null && included != null) {
    final assetId = assetRelation['data']?['id'];
    if (assetId != null) {
      final asset = included.firstWhere(
        (inc) => inc['type'] == 'Asset' && inc['id'].toString() == assetId.toString(),
        orElse: () => null,
      );
      if (asset != null) {
        return asset['attributes']?['plate_number'] ??
               asset['attributes']?['name'] ??
               'N/A';
      }
    }
  }

  // Fallback to direct attributes
  final attrs = item['attributes'] ?? item;
  return attrs['asset']?['plate_number'] ??
         attrs['asset']?['name'] ??
         attrs['asset_plate_number'] ??
         'N/A';
}

String _getUserName(Map<String, dynamic> item, List<dynamic>? included) {
  final userRelation = item['relationships']?['user'];
  if (userRelation != null && included != null) {
    final userId = userRelation['data']?['id'];
    if (userId != null) {
      final user = included.firstWhere(
        (inc) => inc['type'] == 'User' && inc['id'].toString() == userId.toString(),
        orElse: () => null,
      );
      if (user != null) return user['attributes']?['name'] ?? 'Driver';
    }
  }

  final attrs = item['attributes'] ?? item;
  return attrs['user']?['name'] ??
         attrs['driver']?['name'] ??
         attrs['driver_name'] ??
         'Driver';
}
```

### Parsing Nested Collections

```dart
List<Map<String, dynamic>> _parseLocationsToJson(List<dynamic> locations) {
  return locations.map((loc) {
    return {
      'id': loc['id']?.toString() ?? '',
      'name': loc['name'] ?? '',
      'lat': double.tryParse(loc['latitude']?.toString() ?? ''),
      'lng': double.tryParse(loc['longitude']?.toString() ?? ''),
      'phone': loc['phone_number'],
      'address': loc['address'] ?? '',
      'note': loc['note'],
      'type': loc['location_type'] ?? 'origin',
      'sequence': loc['sequence'] ?? 0,
    };
  }).toList();
}

List<Map<String, dynamic>> _parseExpensesToJson(List<dynamic> expenses) {
  return expenses.map((expense) {
    return {
      'id': expense['id']?.toString() ?? '',
      'taskId': expense['task_id']?.toString() ?? '',
      'type': expense['type'] ?? expense['name'] ?? expense['expense_type'] ?? '',
      'amount': (expense['amount'] ?? 0).toDouble(),
      'note': expense['note'],
      'imageUrls': expense['images'] != null
          ? List<String>.from(expense['images'])
          : expense['image_urls'] != null
              ? List<String>.from(expense['image_urls'])
              : null,
    };
  }).toList();
}
```

---

## Auth Token Flow

ironmove-app uses a Bearer token flow: OTP login returns a token, which is stored securely and set on the DioClient singleton's headers.

### Login Flow

```
1. User enters phone number
2. ApiService.sendAuthCode(phone) → backend sends OTP
3. User enters OTP code
4. ApiService.verifyAuthCode(phone, code) → returns { access_token: "..." }
5. Token set on DioClient: dio.options.headers['Authorization'] = 'Bearer $token'
6. Token saved to SecureStorageService
7. AuthState updated: isAuthenticated = true
```

### Token Set on Login

```dart
// In AuthNotifier.verifyOtp()
final response = await _apiService.verifyAuthCode(state.phoneNumber!, code);
final accessToken = response['access_token'] as String?;

if (accessToken != null) {
  // Set token on the shared Dio instance
  DioClient.instance.dio.options.headers['Authorization'] = 'Bearer $accessToken';

  // Persist to secure storage
  await _storageService.saveToken(accessToken);
}
```

### Token Validation on App Start

```dart
// In AuthNotifier._initializeAuth()
final tokenResult = await _storageService.getToken();
if (tokenResult.isSuccess) {
  final token = tokenResult.dataOrNull;
  if (token != null && token.isNotEmpty) {
    DioClient.instance.dio.options.headers['Authorization'] = 'Bearer $token';

    try {
      await _apiService.getTasks(); // Validate token with a real API call
      state = state.copyWith(isAuthenticated: true, accessToken: token, isLoading: false);
    } catch (e) {
      // Token invalid/expired
      await _storageService.clearAll();
      DioClient.instance.dio.options.headers.remove('Authorization');
      state = state.copyWith(isAuthenticated: false, isLoading: false);
    }
  }
}
```

### Logout

```dart
Future<void> logout() async {
  await _storageService.clearAll();
  DioClient.instance.dio.options.headers.remove('Authorization');
  state = const AuthState();
}
```

---

## Error Handling

ironmove-app maps `DioException` types to domain-specific exceptions in `ApiService._handleError()`.

### DioException Mapping

```dart
// lib/services/api_service.dart

Exception _handleError(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return TimeoutException('Connection timeout');

    case DioExceptionType.connectionError:
      return NetworkException('No internet connection');

    case DioExceptionType.badResponse:
      final statusCode = error.response?.statusCode ?? 0;
      final message = error.response?.data?['message'] ??
                      error.response?.data?['error'] ??
                      'Unknown error occurred';

      switch (statusCode) {
        case 400: return BadRequestException(message);
        case 401: return UnauthorizedException('Unauthorized access');
        case 403: return ForbiddenException('Access forbidden');
        case 404: return NotFoundException('Resource not found');
        case 422: return ValidationException(message, error.response?.data?['errors']);
        case 500:
        case 502:
        case 503: return ServerException('Server error');
        default: return ApiException(message);
      }

    case DioExceptionType.cancel:
      return ApiException('Request cancelled');

    default:
      return ApiException('An unexpected error occurred');
  }
}
```

### Exception Classes in ApiService

```dart
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override String toString() => message;
}

class NetworkException extends ApiException {
  NetworkException(super.message);
}

class TimeoutException extends ApiException {
  TimeoutException(super.message);
}

class BadRequestException extends ApiException {
  BadRequestException(super.message);
}

class UnauthorizedException extends ApiException {
  UnauthorizedException(super.message);
}

class ForbiddenException extends ApiException {
  ForbiddenException(super.message);
}

class NotFoundException extends ApiException {
  NotFoundException(super.message);
}

class ValidationException extends ApiException {
  final Map<String, dynamic>? errors;
  ValidationException(super.message, this.errors);
}

class ServerException extends ApiException {
  ServerException(super.message);
}
```

### Exception Hierarchy in Core

ironmove-app also has a separate `core/exceptions.dart` hierarchy (AppException, NetworkException, AuthException, ValidationException, ParseException) with `ExceptionMessages` for Thai-language user-facing messages. See the flutter-architecture skill for details.

---

## Image Upload with Presigned URLs

ironmove-app uploads images to S3 via a two-step presigned URL flow.

```dart
// Step 1: Get presigned URL from backend
Future<Map<String, String>> getPresignedUrl({
  required String filename,
  required String contentType,
  required String resourceType,
  required int resourceId,
}) async {
  try {
    final response = await _dio.post('/api/presigned_urls', data: {
      'filename': filename,
      'content_type': contentType,
      'resource_type': resourceType,
      'resource_id': resourceId,
    });

    return {
      'url': response.data['url'],     // Presigned S3 upload URL
      'image': response.data['image'],  // Final image URL to store
    };
  } on DioException catch (e) {
    throw _handleError(e);
  }
}

// Step 2: Upload image bytes directly to S3
Future<void> uploadImageToS3(String presignedUrl, File imageFile) async {
  try {
    final bytes = await imageFile.readAsBytes();
    final dio = Dio(); // New Dio instance WITHOUT auth interceptor
    await dio.put(
      presignedUrl,
      data: bytes,
      options: Options(
        headers: {
          'Content-Type': 'image/jpeg',
          'Content-Length': bytes.length.toString(),
        },
      ),
    );
  } on DioException catch (e) {
    throw _handleError(e);
  }
}
```

**Key details:**
- Step 1 uses the authenticated DioClient to get a presigned URL
- Step 2 uses a **new, bare Dio instance** (no auth header) to upload directly to S3
- The `image` field returned in Step 1 is the final URL to store in the expense record

---

## Secure Token Storage

ironmove-app uses `flutter_secure_storage` wrapped in a `SecureStorageService` that returns `Result<T>` for all operations.

```dart
// lib/services/secure_storage_service.dart

class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService() : _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @visibleForTesting
  SecureStorageService.withStorage(this._storage);

  static const String _keyAuthToken = 'auth_token';
  static const String _keyUserId = 'user_id';
  static const String _keyUserName = 'user_name';
  static const String _keyUserPhone = 'user_phone';
  static const String _keySessionExpiry = 'session_expiry';

  Future<Result<void>> saveToken(String token) async {
    try {
      await _storage.write(key: _keyAuthToken, value: token);
      return const Success(null);
    } catch (e) {
      return Failure('Failed to save token',
        exception: AppException('Failed to save token', originalError: e),
      );
    }
  }

  Future<Result<String?>> getToken() async {
    try {
      final token = await _storage.read(key: _keyAuthToken);
      return Success(token);
    } catch (e) {
      return Failure('Failed to read token',
        exception: AppException('Failed to read token', originalError: e),
      );
    }
  }

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
      return Failure('Failed to save user info',
        exception: AppException('Failed to save user info', originalError: e),
      );
    }
  }

  Future<Result<void>> clearAll() async {
    try {
      await _storage.deleteAll();
      return const Success(null);
    } catch (e) {
      return Failure('Failed to clear storage',
        exception: AppException('Failed to clear storage', originalError: e),
      );
    }
  }
}
```

**Key details:**
- Android uses `encryptedSharedPreferences: true` for hardware-backed encryption
- All methods return `Result<T>` (never throw)
- `@visibleForTesting` constructor for injecting mock storage
- Stores auth token, user ID, user name, user phone, and session expiry

---

## Directions Caching

ironmove-app caches Google Directions API responses with an LRU strategy, 1-hour TTL, and 50-entry maximum.

```dart
// lib/services/directions_cache_service.dart

class DirectionsCacheEntry {
  final List<LatLng> points;
  final DateTime timestamp;
  final String key;

  DirectionsCacheEntry({required this.points, required this.timestamp, required this.key});

  bool isValid({Duration maxAge = const Duration(hours: 1)}) {
    return DateTime.now().difference(timestamp) < maxAge;
  }
}

class DirectionsCacheService {
  static final DirectionsCacheService _instance = DirectionsCacheService._internal();
  factory DirectionsCacheService() => _instance;
  DirectionsCacheService._internal();

  final Map<String, DirectionsCacheEntry> _cache = {};
  static const Duration _defaultCacheDuration = Duration(hours: 1);
  static const int _maxCacheSize = 50;

  // Cache key: round coordinates to 5 decimal places to handle GPS jitter
  String _generateCacheKey(LatLng origin, LatLng destination) {
    final originKey = '${origin.latitude.toStringAsFixed(5)},${origin.longitude.toStringAsFixed(5)}';
    final destKey = '${destination.latitude.toStringAsFixed(5)},${destination.longitude.toStringAsFixed(5)}';
    return '$originKey->$destKey';
  }

  // Get cached directions (LRU: move accessed entry to end)
  List<LatLng>? getCachedDirections(LatLng origin, LatLng destination, {
    Duration maxAge = _defaultCacheDuration,
  }) {
    final key = _generateCacheKey(origin, destination);
    final entry = _cache[key];

    if (entry != null && entry.isValid(maxAge: maxAge)) {
      _cache.remove(key);
      _cache[key] = entry; // Move to end (LRU behavior)
      return entry.points;
    }
    return null;
  }

  // Store directions (LRU eviction if at capacity)
  void cacheDirections(LatLng origin, LatLng destination, List<LatLng> points) {
    final key = _generateCacheKey(origin, destination);

    if (_cache.length >= _maxCacheSize && !_cache.containsKey(key)) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey); // Evict oldest entry
    }

    _cache[key] = DirectionsCacheEntry(
      points: points,
      timestamp: DateTime.now(),
      key: key,
    );
  }

  // Clear expired entries
  void clearExpiredEntries({Duration maxAge = _defaultCacheDuration}) {
    final keysToRemove = <String>[];
    _cache.forEach((key, entry) {
      if (!entry.isValid(maxAge: maxAge)) keysToRemove.add(key);
    });
    for (final key in keysToRemove) {
      _cache.remove(key);
    }
  }

  void clearCache() => _cache.clear();

  Map<String, dynamic> getCacheStats() {
    int validCount = 0;
    int expiredCount = 0;
    _cache.forEach((key, entry) {
      if (entry.isValid()) { validCount++; } else { expiredCount++; }
    });
    return {'total': _cache.length, 'valid': validCount, 'expired': expiredCount, 'maxSize': _maxCacheSize};
  }
}
```

**Key design decisions:**
- **LRU eviction**: On access, entry is removed and re-inserted at end of map; on capacity overflow, `_cache.keys.first` is evicted
- **1-hour TTL**: Each entry has a timestamp; `isValid()` checks age against `maxAge`
- **50-entry max**: Prevents unbounded memory growth
- **Cache key rounding**: Coordinates rounded to 5 decimal places (~1m precision) to handle minor GPS drift

---

## Best Practices

1. **Single DioClient singleton** shared across all services (not one Dio per service)
2. **Centralized ApiService** with all endpoints and a single `_handleError()` method
3. **Map DioException to domain exceptions** in one place (not in each endpoint method)
4. **Use a separate bare Dio instance** for S3/external uploads (no auth headers)
5. **Return Result<T> from storage operations** instead of throwing
6. **Store tokens in flutter_secure_storage** with `encryptedSharedPreferences` on Android
7. **Validate stored tokens on app start** by making a real API call
8. **Cache expensive API responses** (directions) with TTL and LRU eviction
9. **Round GPS coordinates** in cache keys to absorb minor location drift

---

## Anti-Patterns

- Creating a new Dio instance per request instead of using the DioClient singleton
- Setting auth headers per-request instead of on the shared Dio instance
- Hardcoding base URLs instead of using `Env.apiBaseUrl`
- Throwing raw DioException to callers instead of mapping to domain exceptions
- Storing tokens in SharedPreferences (not encrypted)
- Uploading to S3 presigned URLs with the authenticated Dio instance (will fail with extra headers)
- Not handling 401 responses (app appears broken when token expires)
- Unbounded caching without TTL or size limits
- Using exact GPS coordinates as cache keys (cache misses from GPS jitter)
