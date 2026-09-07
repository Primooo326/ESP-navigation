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

    TurnIcon icon = _parseManeuverIcon(type, modifier, bearingBefore, bearingAfter);

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

  static TurnIcon _parseManeuverIcon(String type, String modifier, int bearingBefore, int bearingAfter) {
    if (type == 'arrive') return TurnIcon.arrived;
    if (type == 'roundabout' || type == 'rotary') return TurnIcon.roundabout;

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
        return TurnIcon.sharpLeft;
    }

    // Si modifier viene vacío o desconocido, calcular según la diferencia de rumbo (bearingAfter - bearingBefore)
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

  OSRMService({
    this.baseUrl = 'https://osrm.oberon360.com/osrm/moto/route/v1/driving',
  });

  Future<OSRMRoute?> fetchRoute(LatLng start, LatLng destination) async {
    final url = Uri.parse(
      '$baseUrl/${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=polyline&steps=true',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));

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
          if (legs != null && legs.isNotEmpty) {
            final legSteps = legs[0]['steps'] as List<dynamic>?;
            if (legSteps != null) {
              for (var s in legSteps) {
                steps.add(OSRMStep.fromJson(s as Map<String, dynamic>));
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
      debugPrint('Error al consultar OSRM: $e');
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
