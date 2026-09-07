import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/navigation_packet.dart';
import 'osrm_service.dart';

typedef OnPacketGeneratedCallback = void Function(NavigationPacket packet);
typedef OnReRouteRequestedCallback = void Function(LatLng currentPos);
typedef OnVoicePromptRequestedCallback = void Function(String prompt);

class NavigationEngine {
  final Distance _distanceCalculator = const Distance();

  OSRMRoute? _activeRoute;
  int _currentStepIndex = 0;
  bool _isNavigating = false;
  bool _isSimulating = false;
  Timer? _simulationTimer;

  Position? _currentPosition;
  double _currentHeading = 0.0;
  double _currentSpeedKmh = 0.0;

  StreamSubscription<Position>? _positionSubscription;
  OnPacketGeneratedCallback? onPacketGenerated;
  OnReRouteRequestedCallback? onReRouteRequested;
  OnVoicePromptRequestedCallback? onVoicePromptRequested;

  DateTime? _lastReRouteTime;
  int _lastSpokenStepIndex = -1;

  final ValueNotifier<int> currentStepNotifier = ValueNotifier<int>(0);

  bool get isNavigating => _isNavigating;
  bool get isSimulating => _isSimulating;
  OSRMRoute? get activeRoute => _activeRoute;
  int get currentStepIndex => _currentStepIndex;
  Position? get currentPosition => _currentPosition;

  void startNavigation(OSRMRoute route) {
    stopSimulation();
    _activeRoute = route;
    _currentStepIndex = 0;
    _lastSpokenStepIndex = -1;
    currentStepNotifier.value = 0;
    _isNavigating = true;
    if (_positionSubscription == null) {
      _initGpsStream();
    }
  }

  void startSimulation(OSRMRoute route) {
    stopNavigation();
    _activeRoute = route;
    _currentStepIndex = 0;
    _lastSpokenStepIndex = -1;
    currentStepNotifier.value = 0;
    _isNavigating = true;
    _isSimulating = true;

    if (route.polylinePoints.isEmpty) return;

    int currentPolyIdx = 0;
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!_isNavigating || _activeRoute == null || currentPolyIdx >= _activeRoute!.polylinePoints.length) {
        timer.cancel();
        _isSimulating = false;
        _emitArrivedPacket();
        return;
      }

      LatLng currentPt = _activeRoute!.polylinePoints[currentPolyIdx];
      currentPolyIdx++;

      Position simPos = Position(
        longitude: currentPt.longitude,
        latitude: currentPt.latitude,
        timestamp: DateTime.now(),
        accuracy: 1.0,
        altitude: 2600.0,
        altitudeAccuracy: 1.0,
        heading: 45.0,
        headingAccuracy: 1.0,
        speed: 12.5, // ~45 km/h
        speedAccuracy: 1.0,
      );

      _processGpsPosition(simPos);
    });
  }

  void stopSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _isSimulating = false;
  }

  void stopNavigation() {
    stopSimulation();
    _isNavigating = false;
    _activeRoute = null;
    _currentStepIndex = 0;
    _lastSpokenStepIndex = -1;
    currentStepNotifier.value = 0;
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  int _currentTemperature = 20;
  int _currentWeatherCode = 0;

  void setWeatherInfo(int tempC, int code) {
    _currentTemperature = tempC;
    _currentWeatherCode = code;
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

    // 2. Transición automática al siguiente paso al acercarse a <25 metros del cruce
    if (distToStep < 25.0 && _currentStepIndex < _activeRoute!.steps.length - 1) {
      _currentStepIndex++;
      currentStepNotifier.value = _currentStepIndex;
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

    if (_lastSpokenStepIndex != upcomingIndex) {
      _lastSpokenStepIndex = upcomingIndex;
      String prompt = 'En ${distToStep.round()} metros, en ${targetStep.streetName}';
      onVoicePromptRequested?.call(prompt);
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

    // 5. Generar paquete binario para BLE con el icono, rumbo relativo y calle de la próxima maniobra
    double targetBearing = _distanceCalculator.bearing(userPos, targetStep.location);
    double currentHeading = (_currentHeading.isNaN || _currentHeading.isInfinite) ? 0.0 : _currentHeading;
    double relativeTargetAngle = (targetBearing - currentHeading + 360.0) % 360.0;
    if (relativeTargetAngle.isNaN || relativeTargetAngle.isInfinite) relativeTargetAngle = 0.0;

    LatLng? destinationPos = _activeRoute?.polylinePoints.isNotEmpty == true
        ? _activeRoute!.polylinePoints.last
        : (_activeRoute?.steps.isNotEmpty == true ? _activeRoute!.steps.last.location : null);

    double relativeFinalAngle = 0.0;
    if (destinationPos != null) {
      double finalBearing = _distanceCalculator.bearing(userPos, destinationPos);
      relativeFinalAngle = (finalBearing - currentHeading + 360.0) % 360.0;
      if (relativeFinalAngle.isNaN || relativeFinalAngle.isInfinite) relativeFinalAngle = 0.0;
    }

    final now = DateTime.now();
    NavigationPacket packet = NavigationPacket(
      navState: 1, // 1 = Navegación Activa
      turnIcon: targetStep.turnIcon,
      distanceMeters: distToStep.round(),
      totalRemainingMeters: totalRemaining.round(),
      speedKmh: _currentSpeedKmh.round(),
      headingDeg: relativeTargetAngle.round(),
      vehicleHeadingDeg: currentHeading.round(),
      currentHour: now.hour,
      currentMinute: now.minute,
      temperatureC: _currentTemperature,
      weatherCode: _currentWeatherCode,
      finalHeadingDeg: relativeFinalAngle.round(),
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
      vehicleHeadingDeg: _currentHeading.round(),
      currentHour: now.hour,
      currentMinute: now.minute,
      temperatureC: _currentTemperature,
      weatherCode: _currentWeatherCode,
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
