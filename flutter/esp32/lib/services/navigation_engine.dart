import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/navigation_packet.dart';
import 'osrm_service.dart';

typedef OnPacketGeneratedCallback = void Function(NavigationPacket packet);
typedef OnReRouteRequestedCallback = void Function(LatLng currentPos);

class NavigationEngine {
  final Distance _distanceCalculator = const Distance();

  OSRMRoute? _activeRoute;
  int _currentStepIndex = 0;
  bool _isNavigating = false;

  Position? _currentPosition;
  double _currentHeading = 0.0;
  double _currentSpeedKmh = 0.0;

  StreamSubscription<Position>? _positionSubscription;
  OnPacketGeneratedCallback? onPacketGenerated;
  OnReRouteRequestedCallback? onReRouteRequested;

  DateTime? _lastReRouteTime;

  bool get isNavigating => _isNavigating;
  OSRMRoute? get activeRoute => _activeRoute;
  int get currentStepIndex => _currentStepIndex;
  Position? get currentPosition => _currentPosition;

  void startNavigation(OSRMRoute route) {
    _activeRoute = route;
    _currentStepIndex = 0;
    _isNavigating = true;
    if (_positionSubscription == null) {
      _initGpsStream();
    }
  }

  void stopNavigation() {
    _isNavigating = false;
    _activeRoute = null;
    _currentStepIndex = 0;
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void setCompassHeading(double heading) {
    _currentHeading = heading;
  }

  void _initGpsStream() {
    _positionSubscription?.cancel();

    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
      forceLocationManager: false,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: "Smart HUD Navegación Activa",
        notificationText: "Transmitiendo datos TBT al ESP32-C3",
        notificationIcon: AndroidResource(name: 'ic_launcher'),
        enableWakeLock: true,
      ),
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _processGpsPosition(position);
    });
  }

  void _processGpsPosition(Position position) {
    _currentPosition = position;
    _currentSpeedKmh = (position.speed > 0) ? (position.speed * 3.6) : 0.0;

    if (!_isNavigating || _activeRoute == null || _activeRoute!.steps.isEmpty) {
      return;
    }

    LatLng userPos = LatLng(position.latitude, position.longitude);

    // 1. Obtener paso actual y paso objetivo de la próxima maniobra
    if (_currentStepIndex >= _activeRoute!.steps.length) {
      // Destino alcanzado
      _emitArrivedPacket();
      return;
    }

    int upcomingIndex = (_currentStepIndex + 1 < _activeRoute!.steps.length)
        ? _currentStepIndex + 1
        : _currentStepIndex;

    OSRMStep targetStep = _activeRoute!.steps[upcomingIndex];
    double distToStep = _distanceCalculator.as(
      LengthUnit.Meter,
      userPos,
      targetStep.location,
    );

    // 2. Transición automática al siguiente paso al acercarse a <20 metros del cruce
    if (distToStep < 20.0 && _currentStepIndex < _activeRoute!.steps.length - 1) {
      _currentStepIndex++;
      upcomingIndex = (_currentStepIndex + 1 < _activeRoute!.steps.length)
          ? _currentStepIndex + 1
          : _currentStepIndex;
      targetStep = _activeRoute!.steps[upcomingIndex];
      distToStep = _distanceCalculator.as(
        LengthUnit.Meter,
        userPos,
        targetStep.location,
      );
    }

    // 3. Verificación de desvío de ruta (>60 metros fuera del trazado con cooldown de 10s)
    double minDistToPolyline = _calculateMinDistanceToPolyline(userPos, _activeRoute!.polylinePoints);
    if (minDistToPolyline > 60.0) {
      final now = DateTime.now();
      if (_lastReRouteTime == null || now.difference(_lastReRouteTime!).inSeconds >= 10) {
        _lastReRouteTime = now;
        debugPrint('>> [NavEngine] Desvío detectado ($minDistToPolyline m). Solicitando recálculo OSRM...');
        onReRouteRequested?.call(userPos);
      }
      return;
    }

    // 4. Calcular metros restantes totales del viaje completo
    double totalRemaining = distToStep;
    for (int i = upcomingIndex; i < _activeRoute!.steps.length; i++) {
      totalRemaining += _activeRoute!.steps[i].distanceMeters;
    }

    // 5. Generar paquete binario para BLE con el icono y calle de la próxima maniobra
    final now = DateTime.now();
    NavigationPacket packet = NavigationPacket(
      navState: 1, // 1 = Navegación Activa
      turnIcon: targetStep.turnIcon,
      distanceMeters: distToStep.round(),
      totalRemainingMeters: totalRemaining.round(),
      speedKmh: _currentSpeedKmh.round(),
      headingDeg: (position.heading > 0) ? position.heading.round() : _currentHeading.round(),
      currentHour: now.hour,
      currentMinute: now.minute,
      streetName: targetStep.streetName,
    );

    onPacketGenerated?.call(packet);
  }

  void _emitArrivedPacket() {
    final now = DateTime.now();
    NavigationPacket packet = NavigationPacket(
      navState: 2, // 2 = Llegado al destino
      turnIcon: TurnIcon.arrived,
      distanceMeters: 0,
      totalRemainingMeters: 0,
      speedKmh: 0,
      headingDeg: _currentHeading.round(),
      currentHour: now.hour,
      currentMinute: now.minute,
      streetName: '¡Llegaste!',
    );
    onPacketGenerated?.call(packet);
  }

  double _calculateMinDistanceToPolyline(LatLng userPos, List<LatLng> polyline) {
    if (polyline.isEmpty) return 0.0;
    double minDistance = double.infinity;
    for (int i = 0; i < polyline.length; i++) {
      double dist = _distanceCalculator.as(LengthUnit.Meter, userPos, polyline[i]);
      if (dist < minDistance) {
        minDistance = dist;
      }
    }
    return minDistance;
  }
}
