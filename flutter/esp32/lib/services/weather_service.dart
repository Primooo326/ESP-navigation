import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class WeatherData {
  final int temperatureC;
  final int weatherCode;

  const WeatherData({
    required this.temperatureC,
    required this.weatherCode,
  });
}

class WeatherService {
  Future<WeatherData?> fetchCurrentWeather(LatLng location) async {
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${location.latitude}&longitude=${location.longitude}&current_weather=true',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final currentWeather = data['current_weather'] as Map<String, dynamic>?;
        if (currentWeather != null) {
          final temp = (currentWeather['temperature'] as num?)?.round() ?? 20;
          final code = (currentWeather['weathercode'] as num?)?.toInt() ?? 0;
          return WeatherData(temperatureC: temp, weatherCode: code);
        }
      }
    } catch (e) {
      debugPrint('Error obteniendo clima desde Open-Meteo: $e');
    }
    return null;
  }
}
