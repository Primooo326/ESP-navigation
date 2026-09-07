import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/navigation_packet.dart';

class OSRMStep {
  final String streetName;
  final double distanceMeters;
  final TurnIcon turnIcon;
  final LatLng location;

  OSRMStep({
    required this.streetName,
    required this.distanceMeters,
    required this.turnIcon,
    required this.location,
  });

  factory OSRMStep.fromJson(Map<String, dynamic> json) {
    String name = json['name'] as String? ?? 'Vía local';
    if (name.trim().isEmpty) name = 'Sigue la ruta';

    double dist = (json['distance'] as num?)?.toDouble() ?? 0.0;

    Map<String, dynamic>? maneuver = json['maneuver'] as Map<String, dynamic>?;
    String type = maneuver?['type'] as String? ?? '';
    String modifier = maneuver?['modifier'] as String? ?? '';
    int bearingBefore = (maneuver?['bearing_before'] as num?)?.toInt() ?? 0;
    int bearingAfter = (maneuver?['bearing_after'] as num?)?.toInt() ?? 0;

    int? exitNumber = (maneuver?['exit'] as num?)?.toInt();
    TurnIcon icon = _parseManeuverIcon(type, modifier, bearingBefore, bearingAfter, exitNumber);

    List<dynamic>? locationArr = maneuver?['location'] as List<dynamic>?;
    double lat = (locationArr != null && locationArr.length >= 2) ? (locationArr[1] as num).toDouble() : 0.0;
    double lng = (locationArr != null && locationArr.length >= 2) ? (locationArr[0] as num).toDouble() : 0.0;

    return OSRMStep(
      streetName: name,
      distanceMeters: dist,
      turnIcon: icon,
      location: LatLng(lat, lng),
    );
  }

  static TurnIcon _parseManeuverIcon(String type, String modifier, int bearingBefore, int bearingAfter, int? exitNumber) {
    if (type == 'arrive') return TurnIcon.arrived;
    if (type == 'uturn' || modifier == 'uturn' || modifier == 'u turn') return TurnIcon.uTurn;
    if (type == 'fork') {
      return modifier.contains('left') ? TurnIcon.forkLeft : TurnIcon.forkRight;
    }
    if (type == 'on ramp' || type == 'ramp') return TurnIcon.onRamp;
    if (type == 'off ramp') return TurnIcon.offRamp;

    if (type == 'roundabout' || type == 'rotary' || type == 'roundabout turn') {
      if (exitNumber != null) {
        if (exitNumber == 1) return TurnIcon.roundaboutExit1;
        if (exitNumber == 2) return TurnIcon.roundaboutExit2;
        if (exitNumber == 3) return TurnIcon.roundaboutExit3;
        if (exitNumber >= 4) return TurnIcon.roundaboutExit4;
      }
      switch (modifier.toLowerCase().trim()) {
        case 'right':
        case 'slight right':
          return TurnIcon.roundaboutExit1;
        case 'straight':
          return TurnIcon.roundaboutExit2;
        case 'left':
        case 'slight left':
          return TurnIcon.roundaboutExit3;
        case 'sharp left':
        case 'sharp right':
        case 'uturn':
          return TurnIcon.roundaboutExit4;
      }
      return TurnIcon.roundaboutExit2;
    }

    switch (modifier.toLowerCase().trim()) {
      case 'straight':
        return TurnIcon.straight;
      case 'right':
        return TurnIcon.turnRight;
      case 'left':
        return TurnIcon.turnLeft;
      case 'slight right':
        return TurnIcon.slightRight;
      case 'slight left':
        return TurnIcon.slightLeft;
      case 'sharp right':
        return TurnIcon.sharpRight;
      case 'sharp left':
        return TurnIcon.sharpLeft;
      case 'uturn':
      case 'u turn':
        return TurnIcon.uTurn;
    }

    int turnAngle = (bearingAfter - bearingBefore) % 360;
    if (turnAngle < -180) turnAngle += 360;
    if (turnAngle > 180) turnAngle -= 360;

    if (turnAngle >= 20 && turnAngle < 65) return TurnIcon.slightRight;
    if (turnAngle >= 65 && turnAngle < 120) return TurnIcon.turnRight;
    if (turnAngle >= 120) return TurnIcon.sharpRight;

    if (turnAngle <= -20 && turnAngle > -65) return TurnIcon.slightLeft;
    if (turnAngle <= -65 && turnAngle > -120) return TurnIcon.turnLeft;
    if (turnAngle <= -120) return TurnIcon.sharpLeft;

    return TurnIcon.straight;
  }
}

class OSRMRoute {
  final double totalDistanceMeters;
  final double totalDurationSeconds;
  final List<LatLng> polylinePoints;
  final List<OSRMStep> steps;

  OSRMRoute({
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    required this.polylinePoints,
    required this.steps,
  });
}

class OSRMService {
  String baseUrl;
  static const String fallbackBaseUrl = 'https://router.project-osrm.org/route/v1/driving';

  OSRMService({
    this.baseUrl = 'https://osrm.oberon360.com/osrm/moto/route/v1/driving',
  });

  Future<OSRMRoute?> fetchRoute(LatLng start, LatLng destination, {List<LatLng>? waypoints}) async {
    List<LatLng> pointsList = [start];
    if (waypoints != null && waypoints.isNotEmpty) {
      pointsList.addAll(waypoints);
    } else {
      pointsList.add(destination);
    }

    final coordinatesStr = pointsList.map((p) => '${p.longitude},${p.latitude}').join(';');

    OSRMRoute? route = await _tryFetchUrl('$baseUrl/$coordinatesStr?overview=full&geometries=polyline&steps=true');
    if (route == null && baseUrl != fallbackBaseUrl) {
      debugPrint('>> [OSRMService] Servidor principal no respondió. Probando servidor de respaldo público...');
      route = await _tryFetchUrl('$fallbackBaseUrl/$coordinatesStr?overview=full&geometries=polyline&steps=true');
    }
    return route;
  }

  Future<OSRMRoute?> _tryFetchUrl(String urlStr) async {
    try {
      final url = Uri.parse(urlStr);
      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final firstRoute = routes[0] as Map<String, dynamic>;
          double totalDist = (firstRoute['distance'] as num?)?.toDouble() ?? 0.0;
          double totalDur = (firstRoute['duration'] as num?)?.toDouble() ?? 0.0;
          String encodedPoly = firstRoute['geometry'] as String? ?? '';

          List<LatLng> polyline = _decodePolyline(encodedPoly);

          List<OSRMStep> steps = [];
          final legs = firstRoute['legs'] as List<dynamic>?;
          if (legs != null) {
            for (var leg in legs) {
              final legSteps = leg['steps'] as List<dynamic>?;
              if (legSteps != null) {
                for (var s in legSteps) {
                  steps.add(OSRMStep.fromJson(s as Map<String, dynamic>));
                }
              }
            }
          }

          return OSRMRoute(
            totalDistanceMeters: totalDist,
            totalDurationSeconds: totalDur,
            polylinePoints: polyline,
            steps: steps,
          );
        }
      }
    } catch (e) {
      debugPrint('Error al consultar OSRM ($urlStr): $e');
    }
    return null;
  }

  /// Decodificador de Polyline algoritmo OSRM / Google Maps (factor 1e5)
  static List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }
}
