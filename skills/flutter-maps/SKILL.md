---
name: flutter-maps
description: Flutter skill — Google Maps integration, device location services, geolocation, route drawing, markers, and location tracking patterns
---

# Flutter Google Maps & Location Services

Production-ready patterns for Google Maps integration and location services in Flutter 2026. Covers GoogleMap widget configuration, custom markers and clustering, polyline route drawing, device geolocation with the geolocator package, location permission flows, real-time location tracking, Google Directions API integration, map utilities, and testing strategies. All state management examples use Riverpod.

## Table of Contents

1. [Google Maps Setup](#google-maps-setup)
2. [Markers and InfoWindows](#markers-and-infowindows)
3. [Polylines and Routes](#polylines-and-routes)
4. [Location Services](#location-services)
5. [Location Permission Flow](#location-permission-flow)
6. [Real-Time Location Tracking](#real-time-location-tracking)
7. [Directions and Distance](#directions-and-distance)
8. [Map Utilities](#map-utilities)
9. [Testing Maps](#testing-maps)
10. [Best Practices](#best-practices)
11. [Anti-Patterns](#anti-patterns)
12. [Sources & References](#sources--references)

---

## Purpose

This skill provides battle-tested patterns for building map-centric Flutter applications such as logistics dashboards, delivery tracking, fleet management, and ride-hailing apps. It covers the full stack of map functionality: rendering maps with `google_maps_flutter`, obtaining device location with `geolocator`, drawing routes via the Google Directions API, managing location permissions gracefully, and tracking moving objects in real time. All examples follow the Riverpod provider pattern for clean dependency injection and testability.

---

## Google Maps Setup

### API Key Configuration

**Android** -- add to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest ...>
  <application ...>
    <meta-data
      android:name="com.google.android.geo.API_KEY"
      android:value="${MAPS_API_KEY}" />
  </application>
</manifest>
```

Store the actual key in `android/local.properties` (gitignored):

```properties
MAPS_API_KEY=AIzaSyB...your_key_here
```

And reference it in `android/app/build.gradle`:

```groovy
android {
    defaultConfig {
        manifestPlaceholders += [MAPS_API_KEY: localProperties['MAPS_API_KEY']]
    }
}
```

**iOS** -- add to `ios/Runner/AppDelegate.swift`:

```swift
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("YOUR_API_KEY")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

For production, load the iOS key from a plist or Dart-define rather than hardcoding it.

### GoogleMap Widget and Controller

```dart
// lib/features/map/presentation/screens/map_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  GoogleMapController? _mapController;

  // Default camera: Bangkok
  static const _initialPosition = CameraPosition(
    target: LatLng(13.7563, 100.5018),
    zoom: 12.0,
  );

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markers = ref.watch(markersProvider);
    final polylines = ref.watch(polylinesProvider);

    return Scaffold(
      body: GoogleMap(
        initialCameraPosition: _initialPosition,
        onMapCreated: (controller) {
          _mapController = controller;
          _applyMapStyle(controller);
        },
        markers: markers,
        polylines: polylines,
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        compassEnabled: true,
        mapType: MapType.normal,
        onTap: _onMapTapped,
        onCameraMove: _onCameraMove,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _goToCurrentLocation,
        child: const Icon(Icons.my_location),
      ),
    );
  }

  Future<void> _applyMapStyle(GoogleMapController controller) async {
    final style = await DefaultAssetBundle.of(context)
        .loadString('assets/map_style.json');
    await controller.setMapStyle(style);
  }

  void _onMapTapped(LatLng position) {
    // Handle map tap -- e.g. place a pin or dismiss info
  }

  void _onCameraMove(CameraPosition position) {
    // Track camera for bounds-based queries
  }

  Future<void> _goToCurrentLocation() async {
    final location = await ref.read(currentLocationProvider.future);
    if (location != null && _mapController != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: location, zoom: 15.0),
        ),
      );
    }
  }
}
```

---

## Markers and InfoWindows

### Custom Markers with BitmapDescriptor

```dart
// lib/features/map/presentation/providers/marker_provider.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'marker_provider.g.dart';

@riverpod
class MarkerNotifier extends _$MarkerNotifier {
  @override
  Set<Marker> build() => {};

  /// Create a marker with a custom icon from an asset image.
  Future<BitmapDescriptor> _createCustomIcon(
    String assetPath, {
    int width = 96,
  }) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  /// Add a delivery stop marker with a custom icon and info window.
  Future<void> addDeliveryMarker({
    required String id,
    required LatLng position,
    required String title,
    required String snippet,
    String iconAsset = 'assets/icons/pin_delivery.png',
    VoidCallback? onTap,
  }) async {
    final icon = await _createCustomIcon(iconAsset);

    final marker = Marker(
      markerId: MarkerId(id),
      position: position,
      icon: icon,
      infoWindow: InfoWindow(
        title: title,
        snippet: snippet,
        onTap: onTap,
      ),
      anchor: const Offset(0.5, 1.0),
      onTap: () {
        // Show custom bottom sheet instead of default info window
        onTap?.call();
      },
    );

    state = {...state, marker};
  }

  /// Remove a marker by its ID.
  void removeMarker(String id) {
    state = state.where((m) => m.markerId.value != id).toSet();
  }

  /// Clear all markers from the map.
  void clearMarkers() {
    state = {};
  }
}

// Color-coded marker from canvas (no asset needed)
Future<BitmapDescriptor> createColoredMarker(
  Color color, {
  String? label,
  double size = 48,
}) async {
  final pictureRecorder = ui.PictureRecorder();
  final canvas = Canvas(pictureRecorder);
  final paint = Paint()..color = color;

  // Circle pin
  canvas.drawCircle(Offset(size / 2, size / 2), size / 2, paint);

  // Optional label
  if (label != null) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.35,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        (size - textPainter.width) / 2,
        (size - textPainter.height) / 2,
      ),
    );
  }

  final image = await pictureRecorder.endRecording().toImage(
        size.toInt(),
        size.toInt(),
      );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
}
```

### Marker Clustering

For maps with many markers, use the `google_maps_cluster_manager` package to group nearby markers:

```dart
// lib/features/map/presentation/providers/cluster_provider.dart
import 'package:google_maps_cluster_manager/google_maps_cluster_manager.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cluster_provider.g.dart';

class DeliveryClusterItem with ClusterItem {
  final String id;
  final String name;
  @override
  final LatLng location;

  DeliveryClusterItem({
    required this.id,
    required this.name,
    required this.location,
  });
}

@riverpod
class ClusterNotifier extends _$ClusterNotifier {
  late ClusterManager<DeliveryClusterItem> _clusterManager;

  @override
  Set<Marker> build() {
    _clusterManager = ClusterManager<DeliveryClusterItem>(
      [],
      _updateMarkers,
      markerBuilder: _markerBuilder,
      levels: const [1, 4.25, 6.75, 8.25, 11.5, 14.5, 16, 16.5, 20],
      extraPercent: 0.2,
    );
    return {};
  }

  Future<Marker> _markerBuilder(Cluster<DeliveryClusterItem> cluster) async {
    if (cluster.isMultiple) {
      final icon = await createColoredMarker(
        Colors.blue,
        label: '${cluster.count}',
        size: 64,
      );
      return Marker(
        markerId: MarkerId(cluster.getId()),
        position: cluster.location,
        icon: icon,
      );
    }

    return Marker(
      markerId: MarkerId(cluster.items.first.id),
      position: cluster.location,
      infoWindow: InfoWindow(title: cluster.items.first.name),
    );
  }

  void _updateMarkers(Set<Marker> markers) {
    state = markers;
  }

  void setItems(List<DeliveryClusterItem> items) {
    _clusterManager.setItems(items);
  }

  void onCameraMove(CameraPosition position) {
    _clusterManager.onCameraMove(position);
  }

  void updateMap() {
    _clusterManager.updateMap();
  }
}
```

---

## Polylines and Routes

### Drawing Routes with the Directions API

```dart
// lib/features/map/data/services/directions_service.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'directions_service.g.dart';

class DirectionsResult {
  final List<LatLng> polylinePoints;
  final String distanceText;
  final int distanceMeters;
  final String durationText;
  final int durationSeconds;
  final String? startAddress;
  final String? endAddress;
  final LatLngBounds bounds;

  const DirectionsResult({
    required this.polylinePoints,
    required this.distanceText,
    required this.distanceMeters,
    required this.durationText,
    required this.durationSeconds,
    this.startAddress,
    this.endAddress,
    required this.bounds,
  });
}

@riverpod
class DirectionsService extends _$DirectionsService {
  static const _baseUrl = 'https://maps.googleapis.com/maps/api/directions/json';

  @override
  FutureOr<void> build() {}

  /// Fetch directions between two points, optionally with waypoints.
  Future<DirectionsResult?> getDirections({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? waypoints,
    bool optimizeWaypoints = true,
  }) async {
    final dio = ref.read(dioClientProvider);
    final apiKey = ref.read(mapsApiKeyProvider);

    final queryParams = <String, dynamic>{
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'key': apiKey,
      'mode': 'driving',
      'language': 'th',
      'units': 'metric',
    };

    if (waypoints != null && waypoints.isNotEmpty) {
      final waypointStr = waypoints
          .map((wp) => '${wp.latitude},${wp.longitude}')
          .join('|');
      queryParams['waypoints'] =
          optimizeWaypoints ? 'optimize:true|$waypointStr' : waypointStr;
    }

    try {
      final response = await dio.get(_baseUrl, queryParameters: queryParams);
      final data = response.data as Map<String, dynamic>;

      if (data['status'] != 'OK') {
        return null;
      }

      final route = data['routes'][0] as Map<String, dynamic>;
      final leg = route['legs'][0] as Map<String, dynamic>;
      final overviewPolyline = route['overview_polyline']['points'] as String;
      final bounds = route['bounds'] as Map<String, dynamic>;

      return DirectionsResult(
        polylinePoints: decodePolyline(overviewPolyline),
        distanceText: leg['distance']['text'] as String,
        distanceMeters: leg['distance']['value'] as int,
        durationText: leg['duration']['text'] as String,
        durationSeconds: leg['duration']['value'] as int,
        startAddress: leg['start_address'] as String?,
        endAddress: leg['end_address'] as String?,
        bounds: LatLngBounds(
          southwest: LatLng(
            bounds['southwest']['lat'] as double,
            bounds['southwest']['lng'] as double,
          ),
          northeast: LatLng(
            bounds['northeast']['lat'] as double,
            bounds['northeast']['lng'] as double,
          ),
        ),
      );
    } catch (e) {
      return null;
    }
  }
}

/// Decode an encoded polyline string into a list of LatLng points.
/// Uses the Google Polyline Encoding Algorithm.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  int index = 0;
  int lat = 0;
  int lng = 0;

  while (index < encoded.length) {
    int shift = 0;
    int result = 0;

    // Decode latitude
    int byte;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1F) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    // Decode longitude
    shift = 0;
    result = 0;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1F) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    points.add(LatLng(lat / 1E5, lng / 1E5));
  }

  return points;
}
```

### Route Polyline Provider

```dart
// lib/features/map/presentation/providers/route_provider.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'route_provider.g.dart';

@riverpod
class RouteNotifier extends _$RouteNotifier {
  @override
  Set<Polyline> build() => {};

  /// Draw a route between origin and destination on the map.
  Future<DirectionsResult?> drawRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? waypoints,
    Color color = Colors.blue,
    int width = 5,
    String routeId = 'main_route',
  }) async {
    final directions = ref.read(directionsServiceProvider.notifier);
    final result = await directions.getDirections(
      origin: origin,
      destination: destination,
      waypoints: waypoints,
    );

    if (result == null) return null;

    final polyline = Polyline(
      polylineId: PolylineId(routeId),
      points: result.polylinePoints,
      color: color,
      width: width,
      patterns: const [],
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      geodesic: true,
    );

    state = {
      ...state.where((p) => p.polylineId.value != routeId).toSet(),
      polyline,
    };

    return result;
  }

  /// Draw a dashed polyline for a planned but inactive route.
  void drawDashedRoute({
    required String routeId,
    required List<LatLng> points,
    Color color = Colors.grey,
    int width = 3,
  }) {
    final polyline = Polyline(
      polylineId: PolylineId(routeId),
      points: points,
      color: color,
      width: width,
      patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      geodesic: true,
    );

    state = {
      ...state.where((p) => p.polylineId.value != routeId).toSet(),
      polyline,
    };
  }

  /// Remove a specific route by ID.
  void removeRoute(String routeId) {
    state = state.where((p) => p.polylineId.value != routeId).toSet();
  }

  /// Clear all routes.
  void clearRoutes() {
    state = {};
  }
}
```

---

## Location Services

### Getting Device Location with Geolocator

```dart
// lib/features/location/data/services/location_service.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'location_service.g.dart';

@riverpod
class LocationService extends _$LocationService {
  StreamSubscription<Position>? _positionSubscription;

  @override
  FutureOr<void> build() {}

  /// Get the current device position once.
  Future<LatLng?> getCurrentPosition() async {
    final hasPermission = await _checkAndRequestPermission();
    if (!hasPermission) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      return null;
    }
  }

  /// Get the last known position (fast, may be stale).
  Future<LatLng?> getLastKnownPosition() async {
    final position = await Geolocator.getLastKnownPosition();
    if (position == null) return null;
    return LatLng(position.latitude, position.longitude);
  }

  /// Start a continuous location stream.
  Stream<LatLng> getPositionStream({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 10,
    Duration? intervalDuration,
  }) {
    final settings = AndroidSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
      intervalDuration: intervalDuration ?? const Duration(seconds: 5),
      forceLocationManager: false,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Location Tracking',
        notificationText: 'App is tracking your location',
        enableWakeLock: true,
      ),
    );

    return Geolocator.getPositionStream(locationSettings: settings).map(
      (position) => LatLng(position.latitude, position.longitude),
    );
  }

  /// Calculate distance in meters between two coordinates.
  double distanceBetween(LatLng from, LatLng to) {
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }

  /// Calculate bearing in degrees between two coordinates.
  double bearingBetween(LatLng from, LatLng to) {
    return Geolocator.bearingBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }

  Future<bool> _checkAndRequestPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}

// Convenience provider for the current location as a simple future.
@riverpod
Future<LatLng?> currentLocation(CurrentLocationRef ref) async {
  final service = ref.watch(locationServiceProvider.notifier);
  return service.getCurrentPosition();
}
```

---

## Location Permission Flow

Handling location permissions correctly is critical for user trust and app store approval. Always explain why the app needs location before requesting it.

```dart
// lib/features/location/presentation/providers/permission_provider.dart
import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'permission_provider.g.dart';

enum LocationPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  serviceDisabled,
  unknown,
}

@riverpod
class LocationPermissionNotifier extends _$LocationPermissionNotifier {
  @override
  LocationPermissionStatus build() => LocationPermissionStatus.unknown;

  /// Full permission check and request flow.
  Future<LocationPermissionStatus> checkAndRequest() async {
    // Step 1: Check if location services are enabled at device level.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      state = LocationPermissionStatus.serviceDisabled;
      return state;
    }

    // Step 2: Check current permission status.
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      // Step 3: Request permission from the user.
      permission = await Geolocator.requestPermission();
    }

    // Step 4: Map result to our status enum.
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        state = LocationPermissionStatus.granted;
      case LocationPermission.denied:
        state = LocationPermissionStatus.denied;
      case LocationPermission.deniedForever:
        state = LocationPermissionStatus.permanentlyDenied;
      case LocationPermission.unableToDetermine:
        state = LocationPermissionStatus.unknown;
    }

    return state;
  }

  /// Open device settings so the user can enable location manually.
  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }

  /// Open device location settings (for when service is off).
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}
```

### Permission Rationale Dialog

```dart
// lib/features/location/presentation/widgets/location_permission_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LocationPermissionDialog extends ConsumerWidget {
  const LocationPermissionDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionStatus = ref.watch(locationPermissionNotifierProvider);

    return switch (permissionStatus) {
      LocationPermissionStatus.serviceDisabled => _buildDialog(
          context,
          ref,
          icon: Icons.location_off,
          title: 'Location Services Disabled',
          message:
              'Please enable location services in your device settings to use tracking features.',
          primaryAction: 'Open Settings',
          onPrimary: () {
            ref
                .read(locationPermissionNotifierProvider.notifier)
                .openLocationSettings();
          },
        ),
      LocationPermissionStatus.permanentlyDenied => _buildDialog(
          context,
          ref,
          icon: Icons.location_disabled,
          title: 'Location Permission Required',
          message:
              'Location access has been permanently denied. Please enable it in app settings to continue.',
          primaryAction: 'Open App Settings',
          onPrimary: () {
            ref
                .read(locationPermissionNotifierProvider.notifier)
                .openSettings();
          },
        ),
      LocationPermissionStatus.denied => _buildDialog(
          context,
          ref,
          icon: Icons.location_searching,
          title: 'Location Access Needed',
          message:
              'We need your location to show nearby deliveries and provide real-time tracking.',
          primaryAction: 'Allow Location',
          onPrimary: () {
            ref
                .read(locationPermissionNotifierProvider.notifier)
                .checkAndRequest();
            Navigator.of(context).pop();
          },
        ),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildDialog(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String title,
    required String message,
    required String primaryAction,
    required VoidCallback onPrimary,
  }) {
    return AlertDialog(
      icon: Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      content: Text(message, textAlign: TextAlign.center),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Not Now'),
        ),
        FilledButton(
          onPressed: onPrimary,
          child: Text(primaryAction),
        ),
      ],
    );
  }
}
```

---

## Real-Time Location Tracking

### Location Tracking Provider

```dart
// lib/features/tracking/presentation/providers/tracking_provider.dart
import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tracking_provider.g.dart';

class TrackingState {
  final LatLng? currentPosition;
  final List<LatLng> path;
  final double totalDistanceMeters;
  final bool isTracking;
  final DateTime? startedAt;

  const TrackingState({
    this.currentPosition,
    this.path = const [],
    this.totalDistanceMeters = 0,
    this.isTracking = false,
    this.startedAt,
  });

  TrackingState copyWith({
    LatLng? currentPosition,
    List<LatLng>? path,
    double? totalDistanceMeters,
    bool? isTracking,
    DateTime? startedAt,
  }) {
    return TrackingState(
      currentPosition: currentPosition ?? this.currentPosition,
      path: path ?? this.path,
      totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
      isTracking: isTracking ?? this.isTracking,
      startedAt: startedAt ?? this.startedAt,
    );
  }
}

@riverpod
class TrackingNotifier extends _$TrackingNotifier {
  StreamSubscription<LatLng>? _locationSubscription;

  @override
  TrackingState build() => const TrackingState();

  /// Start tracking the device location in real time.
  Future<void> startTracking({
    GoogleMapController? mapController,
    bool followCamera = true,
  }) async {
    if (state.isTracking) return;

    final locationService = ref.read(locationServiceProvider.notifier);
    final initialPosition = await locationService.getCurrentPosition();

    state = state.copyWith(
      isTracking: true,
      currentPosition: initialPosition,
      path: initialPosition != null ? [initialPosition] : [],
      totalDistanceMeters: 0,
      startedAt: DateTime.now(),
    );

    _locationSubscription = locationService
        .getPositionStream(distanceFilter: 10)
        .listen((newPosition) {
      final previousPosition = state.currentPosition;
      double addedDistance = 0;

      if (previousPosition != null) {
        addedDistance = locationService.distanceBetween(
          previousPosition,
          newPosition,
        );
      }

      state = state.copyWith(
        currentPosition: newPosition,
        path: [...state.path, newPosition],
        totalDistanceMeters: state.totalDistanceMeters + addedDistance,
      );

      // Keep camera centered on the user
      if (followCamera && mapController != null) {
        mapController.animateCamera(
          CameraUpdate.newLatLng(newPosition),
        );
      }
    });
  }

  /// Stop tracking and return the recorded path.
  List<LatLng> stopTracking() {
    _locationSubscription?.cancel();
    _locationSubscription = null;

    final recordedPath = state.path;
    state = state.copyWith(isTracking: false);
    return recordedPath;
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }
}
```

### Drawing the Tracked Path on the Map

```dart
// lib/features/tracking/presentation/widgets/tracking_map.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TrackingMap extends ConsumerWidget {
  const TrackingMap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingState = ref.watch(trackingNotifierProvider);
    final routePolylines = ref.watch(routeNotifierProvider);

    // Build the tracked-path polyline from the recording
    final Set<Polyline> allPolylines = {...routePolylines};

    if (trackingState.path.length >= 2) {
      allPolylines.add(
        Polyline(
          polylineId: const PolylineId('tracked_path'),
          points: trackingState.path,
          color: Colors.green,
          width: 4,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: trackingState.currentPosition ??
                const LatLng(13.7563, 100.5018),
            zoom: 15.0,
          ),
          polylines: allPolylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
        ),
        // Distance overlay
        Positioned(
          bottom: 24,
          left: 16,
          right: 16,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _InfoTile(
                    label: 'Distance',
                    value: _formatDistance(trackingState.totalDistanceMeters),
                  ),
                  _InfoTile(
                    label: 'Duration',
                    value: _formatDuration(trackingState.startedAt),
                  ),
                  _InfoTile(
                    label: 'Points',
                    value: '${trackingState.path.length}',
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  String _formatDuration(DateTime? startedAt) {
    if (startedAt == null) return '--:--';
    final elapsed = DateTime.now().difference(startedAt);
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (elapsed.inHours > 0) {
      return '${elapsed.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
```

---

## Directions and Distance

### Caching Directions Responses

```dart
// lib/features/map/data/services/cached_directions_service.dart
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cached_directions_service.g.dart';

@riverpod
class CachedDirectionsService extends _$CachedDirectionsService {
  final Map<String, DirectionsResult> _cache = {};

  @override
  FutureOr<void> build() {}

  /// Generate a cache key from origin, destination, and waypoints.
  String _cacheKey(LatLng origin, LatLng destination, List<LatLng>? waypoints) {
    final wpKey = waypoints?.map((w) => '${w.latitude},${w.longitude}').join('|') ?? '';
    return '${origin.latitude},${origin.longitude}'
        '->${destination.latitude},${destination.longitude}'
        '|$wpKey';
  }

  /// Get directions with caching to minimize API calls.
  Future<DirectionsResult?> getDirections({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? waypoints,
    bool forceRefresh = false,
  }) async {
    final key = _cacheKey(origin, destination, waypoints);

    if (!forceRefresh && _cache.containsKey(key)) {
      return _cache[key];
    }

    final directionsService = ref.read(directionsServiceProvider.notifier);
    final result = await directionsService.getDirections(
      origin: origin,
      destination: destination,
      waypoints: waypoints,
    );

    if (result != null) {
      _cache[key] = result;
    }

    return result;
  }

  /// Clear the directions cache.
  void clearCache() {
    _cache.clear();
  }
}
```

### ETA and Distance Matrix

```dart
// lib/features/map/data/services/distance_matrix_service.dart
import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'distance_matrix_service.g.dart';

class DistanceMatrixEntry {
  final String distanceText;
  final int distanceMeters;
  final String durationText;
  final int durationSeconds;
  final String durationInTrafficText;
  final int durationInTrafficSeconds;

  const DistanceMatrixEntry({
    required this.distanceText,
    required this.distanceMeters,
    required this.durationText,
    required this.durationSeconds,
    required this.durationInTrafficText,
    required this.durationInTrafficSeconds,
  });

  /// Calculate estimated arrival time from now.
  DateTime get estimatedArrival =>
      DateTime.now().add(Duration(seconds: durationInTrafficSeconds));
}

@riverpod
Future<List<DistanceMatrixEntry>> distanceMatrix(
  DistanceMatrixRef ref, {
  required LatLng origin,
  required List<LatLng> destinations,
}) async {
  final dio = ref.watch(dioClientProvider);
  final apiKey = ref.watch(mapsApiKeyProvider);

  final destStr = destinations
      .map((d) => '${d.latitude},${d.longitude}')
      .join('|');

  final response = await dio.get(
    'https://maps.googleapis.com/maps/api/distancematrix/json',
    queryParameters: {
      'origins': '${origin.latitude},${origin.longitude}',
      'destinations': destStr,
      'key': apiKey,
      'mode': 'driving',
      'departure_time': 'now',
      'traffic_model': 'best_guess',
    },
  );

  final data = response.data as Map<String, dynamic>;
  if (data['status'] != 'OK') return [];

  final elements = data['rows'][0]['elements'] as List;

  return elements
      .where((e) => e['status'] == 'OK')
      .map((e) => DistanceMatrixEntry(
            distanceText: e['distance']['text'] as String,
            distanceMeters: e['distance']['value'] as int,
            durationText: e['duration']['text'] as String,
            durationSeconds: e['duration']['value'] as int,
            durationInTrafficText:
                (e['duration_in_traffic']?['text'] ?? e['duration']['text']) as String,
            durationInTrafficSeconds:
                (e['duration_in_traffic']?['value'] ?? e['duration']['value']) as int,
          ))
      .toList();
}
```

---

## Map Utilities

### Bounds Calculation and Camera Animation

```dart
// lib/features/map/core/utils/map_utils.dart
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapUtils {
  /// Calculate bounds that enclose all given points.
  static LatLngBounds boundsFromLatLngList(List<LatLng> points) {
    assert(points.isNotEmpty, 'Points list must not be empty');

    double south = points.first.latitude;
    double north = points.first.latitude;
    double west = points.first.longitude;
    double east = points.first.longitude;

    for (final point in points) {
      if (point.latitude < south) south = point.latitude;
      if (point.latitude > north) north = point.latitude;
      if (point.longitude < west) west = point.longitude;
      if (point.longitude > east) east = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  /// Animate the camera to fit all points with padding.
  static Future<void> fitBounds(
    GoogleMapController controller,
    List<LatLng> points, {
    double padding = 60.0,
  }) async {
    if (points.isEmpty) return;

    if (points.length == 1) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: points.first, zoom: 15.0),
        ),
      );
      return;
    }

    final bounds = boundsFromLatLngList(points);
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, padding),
    );
  }

  /// Calculate the center point of a list of coordinates.
  static LatLng centerOfPoints(List<LatLng> points) {
    assert(points.isNotEmpty, 'Points list must not be empty');

    double latSum = 0;
    double lngSum = 0;

    for (final point in points) {
      latSum += point.latitude;
      lngSum += point.longitude;
    }

    return LatLng(latSum / points.length, lngSum / points.length);
  }

  /// Format a LatLng into a human-readable string.
  static String formatCoordinate(LatLng coord, {int decimals = 6}) {
    final lat = coord.latitude.toStringAsFixed(decimals);
    final lng = coord.longitude.toStringAsFixed(decimals);
    final latDir = coord.latitude >= 0 ? 'N' : 'S';
    final lngDir = coord.longitude >= 0 ? 'E' : 'W';
    return '$lat$latDir, $lng$lngDir';
  }

  /// Calculate the approximate zoom level needed to show a given radius in meters.
  static double zoomForRadius(double radiusMeters, double latitude) {
    const double earthCircumference = 40075016.686;
    final metersPerPixel =
        earthCircumference * cos(latitude * pi / 180) / pow(2, 20);
    final zoom = log(radiusMeters / metersPerPixel) / log(2);
    return 20 - zoom;
  }

  /// Check whether a point lies inside a polygon defined by vertices.
  static bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
    bool inside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].latitude > point.latitude) !=
              (polygon[j].latitude > point.latitude) &&
          point.longitude <
              (polygon[j].longitude - polygon[i].longitude) *
                      (point.latitude - polygon[i].latitude) /
                      (polygon[j].latitude - polygon[i].latitude) +
                  polygon[i].longitude) {
        inside = !inside;
      }
      j = i;
    }

    return inside;
  }
}
```

---

## Testing Maps

### Mocking Location Services

```dart
// test/features/location/mocks/mock_location_service.dart
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([LocationService])
import 'mock_location_service.mocks.dart';

MockLocationService createMockLocationService({
  LatLng? currentPosition,
  List<LatLng>? streamPositions,
}) {
  final mock = MockLocationService();

  when(mock.getCurrentPosition()).thenAnswer(
    (_) async => currentPosition ?? const LatLng(13.7563, 100.5018),
  );

  when(mock.getLastKnownPosition()).thenAnswer(
    (_) async => currentPosition,
  );

  if (streamPositions != null) {
    when(mock.getPositionStream(
      accuracy: anyNamed('accuracy'),
      distanceFilter: anyNamed('distanceFilter'),
      intervalDuration: anyNamed('intervalDuration'),
    )).thenAnswer(
      (_) => Stream.fromIterable(streamPositions),
    );
  }

  when(mock.distanceBetween(any, any)).thenAnswer((invocation) {
    final from = invocation.positionalArguments[0] as LatLng;
    final to = invocation.positionalArguments[1] as LatLng;
    // Simplified distance for testing (not Haversine)
    final dx = (to.latitude - from.latitude) * 111000;
    final dy = (to.longitude - from.longitude) * 111000;
    return (dx * dx + dy * dy).abs();
  });

  return mock;
}
```

### Testing Map Interactions

```dart
// test/features/map/providers/route_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mockito/mockito.dart';

void main() {
  late ProviderContainer container;
  late MockDirectionsService mockDirections;

  setUp(() {
    mockDirections = MockDirectionsService();

    container = ProviderContainer(
      overrides: [
        directionsServiceProvider.overrideWith((_) => mockDirections),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('RouteNotifier', () {
    test('drawRoute adds polyline from directions result', () async {
      const origin = LatLng(13.7563, 100.5018);
      const destination = LatLng(13.7300, 100.5200);

      when(mockDirections.getDirections(
        origin: origin,
        destination: destination,
        waypoints: null,
      )).thenAnswer((_) async => DirectionsResult(
            polylinePoints: [origin, destination],
            distanceText: '3.2 km',
            distanceMeters: 3200,
            durationText: '12 mins',
            durationSeconds: 720,
            bounds: LatLngBounds(southwest: origin, northeast: destination),
          ));

      final notifier = container.read(routeNotifierProvider.notifier);
      final result = await notifier.drawRoute(
        origin: origin,
        destination: destination,
      );

      expect(result, isNotNull);
      expect(result!.distanceMeters, 3200);

      final polylines = container.read(routeNotifierProvider);
      expect(polylines.length, 1);
      expect(polylines.first.polylineId.value, 'main_route');
    });

    test('removeRoute clears specific route', () async {
      final notifier = container.read(routeNotifierProvider.notifier);

      // Manually set two routes
      notifier.drawDashedRoute(
        routeId: 'route_a',
        points: [const LatLng(0, 0), const LatLng(1, 1)],
      );
      notifier.drawDashedRoute(
        routeId: 'route_b',
        points: [const LatLng(2, 2), const LatLng(3, 3)],
      );

      expect(container.read(routeNotifierProvider).length, 2);

      notifier.removeRoute('route_a');
      final remaining = container.read(routeNotifierProvider);
      expect(remaining.length, 1);
      expect(remaining.first.polylineId.value, 'route_b');
    });
  });

  group('MapUtils', () {
    test('boundsFromLatLngList calculates correct bounds', () {
      final points = [
        const LatLng(13.7000, 100.4000),
        const LatLng(13.8000, 100.6000),
        const LatLng(13.7500, 100.5000),
      ];

      final bounds = MapUtils.boundsFromLatLngList(points);

      expect(bounds.southwest.latitude, 13.7000);
      expect(bounds.southwest.longitude, 100.4000);
      expect(bounds.northeast.latitude, 13.8000);
      expect(bounds.northeast.longitude, 100.6000);
    });

    test('formatCoordinate returns correct direction labels', () {
      expect(
        MapUtils.formatCoordinate(const LatLng(13.756300, 100.501800)),
        '13.756300N, 100.501800E',
      );
      expect(
        MapUtils.formatCoordinate(const LatLng(-33.868800, -151.209300)),
        '-33.868800S, -151.209300W',
      );
    });

    test('isPointInPolygon returns correct results', () {
      final polygon = [
        const LatLng(0, 0),
        const LatLng(0, 10),
        const LatLng(10, 10),
        const LatLng(10, 0),
      ];

      expect(MapUtils.isPointInPolygon(const LatLng(5, 5), polygon), isTrue);
      expect(MapUtils.isPointInPolygon(const LatLng(15, 15), polygon), isFalse);
    });
  });

  group('decodePolyline', () {
    test('decodes a known encoded string', () {
      // This is a well-known test string from Google's documentation
      const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
      final points = decodePolyline(encoded);

      expect(points.length, 3);
      expect(points[0].latitude, closeTo(38.5, 0.001));
      expect(points[0].longitude, closeTo(-120.2, 0.001));
    });
  });
}
```

### Platform Test Setup

When running widget tests that include `GoogleMap`, the native map view cannot render. Use a platform-view stub:

```dart
// test/helpers/map_test_helpers.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void setupGoogleMapsMock() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Stub the platform view so GoogleMap widget does not crash in tests.
  const channel = MethodChannel('plugins.flutter.dev/google_maps_flutter');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'map#waitForMap':
        return null;
      case 'map#update':
        return null;
      case 'markers#update':
        return null;
      case 'polylines#update':
        return null;
      default:
        return null;
    }
  });
}
```

---

## Best Practices

1. **Store API keys outside version control** -- use `local.properties` on Android and `--dart-define` or `.xcconfig` on iOS; never hardcode keys in source files
2. **Always check both service and permission status** before requesting location -- call `isLocationServiceEnabled()` before `checkPermission()` to distinguish between device-off and user-denied
3. **Show a permission rationale dialog before requesting** -- explain why the app needs location so the system prompt makes sense to the user
4. **Use `distanceFilter` on location streams** to avoid excessive updates -- a filter of 10-50 meters is appropriate for most logistics apps
5. **Cache Directions API responses** -- routes between the same origin/destination rarely change; caching saves quota and latency
6. **Dispose location stream subscriptions** in the provider or widget dispose method to prevent memory leaks and battery drain
7. **Fit map bounds after drawing routes** -- call `newLatLngBounds` with padding so the full route is visible without manual zooming
8. **Use foreground service notification on Android** when tracking location continuously -- required by Android 10+ and prevents the OS from killing the app

---

## Anti-Patterns

- Requesting `LocationPermission.always` when `whileInUse` is sufficient (triggers extra OS prompt and review scrutiny)
- Calling `getCurrentPosition()` on every build without caching (drains battery and blocks the UI)
- Creating a new `Dio` instance for each Directions API call instead of sharing a singleton client
- Hardcoding the Google Maps API key in Dart source code (exposed in decompiled APK)
- Not handling the case where location services are disabled at the device level (app appears broken)
- Polling location with a `Timer` instead of using `getPositionStream` (inefficient and inaccurate)
- Drawing thousands of polyline points without simplification (causes map rendering jank)
- Ignoring the `dispose` lifecycle for `GoogleMapController` and stream subscriptions (memory leaks on navigation)

---

## Sources & References

- [google_maps_flutter Package](https://pub.dev/packages/google_maps_flutter)
- [geolocator Package](https://pub.dev/packages/geolocator)
- [location Package](https://pub.dev/packages/location)
- [Google Maps Platform - Directions API](https://developers.google.com/maps/documentation/directions/overview)
- [Google Maps Platform - Distance Matrix API](https://developers.google.com/maps/documentation/distance-matrix/overview)
- [Polyline Encoding Algorithm](https://developers.google.com/maps/documentation/utilities/polylinealgorithm)
- [Flutter Google Maps Tutorial (Official)](https://codelabs.developers.google.com/codelabs/google-maps-in-flutter)
- [Riverpod Documentation](https://riverpod.dev/)
- [google_maps_cluster_manager Package](https://pub.dev/packages/google_maps_cluster_manager)
