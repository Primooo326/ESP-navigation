import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';

import 'models/navigation_packet.dart';
import 'services/osrm_service.dart';
import 'services/navigation_engine.dart';
import 'services/ble_service.dart';
import 'services/location_service.dart';
import 'services/weather_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Esp32HudApp());
}

class Esp32HudApp extends StatelessWidget {
  const Esp32HudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Smart HUD Navigation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF09090B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00B0FF),
          surface: Color(0xFF18181B),
        ),
      ),
      home: const MainHudScreen(),
    );
  }
}

class SavedRoute {
  final String title;
  final List<LatLng> waypoints;
  final List<String> waypointNames;
  final double distanceKm;
  final int durationMin;

  SavedRoute({
    required this.title,
    required this.waypoints,
    required this.waypointNames,
    required this.distanceKm,
    required this.durationMin,
  });
}

class MainHudScreen extends StatefulWidget {
  const MainHudScreen({super.key});

  @override
  State<MainHudScreen> createState() => _MainHudScreenState();
}

class _MainHudScreenState extends State<MainHudScreen> {
  // Servicios
  final BleService _bleService = BleService();
  final LocationService _locationService = LocationService();
  final OSRMService _osrmService = OSRMService();
  final NavigationEngine _navEngine = NavigationEngine();
  final WeatherService _weatherService = WeatherService();
  final FlutterTts _flutterTts = FlutterTts();

  // Clima actual (Open-Meteo API)
  int _currentTemperature = 20;
  int _currentWeatherCode = 0;
  Timer? _weatherTimer;

  // Mapa, Posición y Multi-Puntos
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  LatLng _userPosition = const LatLng(4.60971, -74.08175); // Bogotá por defecto
  
  bool _isTracking = true; // Auto-centrado y rotación Waze activa por defecto
  DateTime? _lastBleCompassSendTime;
  
  // Lista de puntos de ruta (Waypoints / Destinos)
  final List<LatLng> _waypoints = [];
  final List<String> _waypointNames = [];

  // Rutas Guardadas por el Usuario
  final List<SavedRoute> _savedRoutes = [];

  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  Timer? _debounceTimer;

  double _compassOffset = 0.0;
  double _rawCompassHeading = 0.0;

  final ValueNotifier<double> _compassHeadingNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<NavigationPacket?> _lastPacketNotifier = ValueNotifier<NavigationPacket?>(null);
  NavigationPacket? _activeCatalogTestPacket;

  OSRMRoute? _currentRoute;
  bool _isLoadingRoute = false;

  StreamSubscription<CompassEvent>? _compassSubscription;
  StreamSubscription<Position>? _gpsStreamSubscription;
  Timer? _bleHeartbeatTimer;

  @override
  void initState() {
    super.initState();
    _initTts();
    _initAppServices();
    _setupNavEngineCallbacks();
  }

  void _initTts() {
    _flutterTts.setLanguage('es-ES');
    _flutterTts.setSpeechRate(0.48);
    _flutterTts.setVolume(1.0);
    _flutterTts.setPitch(1.0);
  }

  void _setupNavEngineCallbacks() {
    _navEngine.onPacketGenerated = (NavigationPacket packet) {
      _lastPacketNotifier.value = packet;
      _sendBlePacket(packet);
    };

    _navEngine.onVoicePromptRequested = (String promptText) async {
      await _flutterTts.speak(promptText);
    };

    _navEngine.onReRouteRequested = (LatLng currentPos) async {
      if (_waypoints.isNotEmpty) {
        final newRoute = await _osrmService.fetchRoute(
          currentPos,
          _waypoints.last,
          waypoints: _waypoints.length > 1 ? _waypoints.sublist(0, _waypoints.length - 1) : null,
        );
        if (newRoute != null && mounted) {
          setState(() {
            _currentRoute = newRoute;
          });
          _navEngine.startNavigation(newRoute);
        }
      }
    };
  }

  // Búsqueda Nominatim con Autocomplete en tiempo real
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      if (mounted) setState(() => _searchResults = []);
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5');
        final response = await http.get(url, headers: {'User-Agent': 'com.example.esp32'}).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as List<dynamic>;
          if (mounted) {
            setState(() {
              _searchResults = data.cast<Map<String, dynamic>>();
            });
          }
        }
      } catch (e) {
        debugPrint('Error en autocomplete: $e');
      }
    });
  }

  void _selectSearchResult(Map<String, dynamic> item) {
    final lat = double.parse(item['lat']);
    final lon = double.parse(item['lon']);
    final displayName = item['display_name'] as String;
    final pos = LatLng(lat, lon);
    final shortName = displayName.split(',')[0];

    _searchController.text = shortName;
    setState(() => _searchResults = []);
    FocusScope.of(context).unfocus();
    _mapController.move(pos, 15.0);
    _addWaypoint(pos, shortName);
  }

  Future<void> _searchAddress(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);
    FocusScope.of(context).unfocus();

    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1');
      final response = await http.get(url, headers: {'User-Agent': 'com.example.esp32'}).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        if (data.isNotEmpty) {
          _selectSearchResult(data[0] as Map<String, dynamic>);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No se encontraron resultados para la búsqueda')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error en geocoding: $e');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  // Agregar Punto a la lista (Soporta múltiples puntos / waypoints)
  Future<void> _addWaypoint(LatLng point, String name) async {
    setState(() {
      _waypoints.add(point);
      _waypointNames.add(name);
      _isLoadingRoute = true;
    });

    final route = await _osrmService.fetchRoute(
      _userPosition,
      _waypoints.last,
      waypoints: _waypoints.length > 1 ? _waypoints.sublist(0, _waypoints.length - 1) : null,
    );

    if (!mounted) return;

    setState(() {
      _isLoadingRoute = false;
      _currentRoute = route;
    });

    if (route != null) {
      if (_navEngine.isNavigating) {
        _navEngine.startNavigation(route);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Punto ${_waypoints.length} agregado ($name): ${(route.totalDistanceMeters / 1000).toStringAsFixed(1)} km '
            '(${(route.totalDurationSeconds / 60).round()} min)',
          ),
          backgroundColor: const Color(0xFF00E676),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al calcular la ruta multi-punto'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // Guardar la ruta actual activa para uso posterior
  void _saveCurrentRoute() {
    if (_currentRoute == null || _waypoints.isEmpty) return;

    TextEditingController titleController = TextEditingController(
      text: 'Ruta a ${_waypointNames.last}',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF18181B),
          title: const Text('Guardar Ruta Actual', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: titleController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Nombre de la ruta...',
              hintStyle: TextStyle(color: Colors.white38),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              onPressed: () {
                final name = titleController.text.trim();
                if (name.isNotEmpty) {
                  setState(() {
                    _savedRoutes.add(SavedRoute(
                      title: name,
                      waypoints: List.from(_waypoints),
                      waypointNames: List.from(_waypointNames),
                      distanceKm: _currentRoute!.totalDistanceMeters / 1000.0,
                      durationMin: (_currentRoute!.totalDurationSeconds / 60.0).round(),
                    ));
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ruta "$name" guardada exitosamente'),
                      backgroundColor: const Color(0xFF00E676),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
              child: const Text('Guardar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // Modal para ver y cargar Rutas Guardadas
  void _showSavedRoutesModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18181B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Mis Rutas Guardadas',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24),
                  if (_savedRoutes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No tienes rutas guardadas aún.\nCrea una ruta en el mapa y presiona "Guardar Ruta".',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _savedRoutes.length,
                        itemBuilder: (context, index) {
                          final route = _savedRoutes[index];
                          return Card(
                            color: const Color(0xFF27272A),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFF00E676),
                                child: Icon(Icons.bookmark, color: Colors.black),
                              ),
                              title: Text(route.title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                              subtitle: Text(
                                '${route.distanceKm.toStringAsFixed(1)} km | ${route.durationMin} min | ${route.waypoints.length} puntos',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                                onPressed: () {
                                  setState(() {
                                    _savedRoutes.removeAt(index);
                                  });
                                  setModalState(() {});
                                },
                              ),
                              onTap: () async {
                                Navigator.pop(context);
                                setState(() {
                                  _waypoints.clear();
                                  _waypointNames.clear();
                                  _waypoints.addAll(route.waypoints);
                                  _waypointNames.addAll(route.waypointNames);
                                });
                                if (_waypoints.isNotEmpty) {
                                  _mapController.move(_waypoints.last, 15.0);
                                  final loadedRoute = await _osrmService.fetchRoute(
                                    _userPosition,
                                    _waypoints.last,
                                    waypoints: _waypoints.length > 1 ? _waypoints.sublist(0, _waypoints.length - 1) : null,
                                  );
                                  if (loadedRoute != null && mounted) {
                                    setState(() => _currentRoute = loadedRoute);
                                    if (_navEngine.isNavigating) {
                                      _navEngine.startNavigation(loadedRoute);
                                    }
                                  }
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Borrar todos los puntos y comenzar desde 0
  void _clearRouteAndPoints() {
    _navEngine.stopNavigation();
    setState(() {
      _waypoints.clear();
      _waypointNames.clear();
      _currentRoute = null;
      _searchResults = [];
      _searchController.clear();
      _lastPacketNotifier.value = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Puntos y ruta reiniciados a 0'),
        backgroundColor: Colors.orangeAccent,
      ),
    );
  }

  Future<void> _initAppServices() async {
    await _locationService.requestPermissions();
    LatLng? userPos = await _locationService.getCurrentUserPosition();
    if (userPos != null && mounted) {
      setState(() {
        _userPosition = userPos;
      });
      _mapController.move(_userPosition, 18.0);
    }

    _bleService.checkAndAutoConnect();

    _gpsStreamSubscription?.cancel();
    _gpsStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen((Position pos) {
      if (mounted) {
        LatLng newPos = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _userPosition = newPos;
        });

        double speedKmh = (pos.speed > 0) ? pos.speed * 3.6 : 0.0;
        if (speedKmh > 5.0 && pos.heading >= 0 && !pos.heading.isNaN && !pos.heading.isInfinite) {
          double gpsHeading = pos.heading % 360.0;
          _compassHeadingNotifier.value = gpsHeading;
          _navEngine.setCompassHeading(gpsHeading);
          _sendThrottledBleCompass(gpsHeading);
        }

        if (_isTracking) {
          double mapRotation = (360.0 - _compassHeadingNotifier.value) % 360.0;
          _mapController.moveAndRotate(newPos, _mapController.camera.zoom, mapRotation);
        }
      }
    });

    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (event.heading != null && !event.heading!.isNaN && !event.heading!.isInfinite) {
        double rawHeading = event.heading!;
        if (rawHeading < 0) rawHeading += 360.0;
        _rawCompassHeading = rawHeading % 360.0;

        double currentSpeed = (_navEngine.currentPosition?.speed ?? 0.0) * 3.6;
        if (currentSpeed <= 5.0) {
          final heading = (_rawCompassHeading + _compassOffset + 360.0) % 360.0;
          _compassHeadingNotifier.value = heading;
          _navEngine.setCompassHeading(heading);

          if (_isTracking && mounted) {
            double mapRotation = (360.0 - heading) % 360.0;
            _mapController.moveAndRotate(_userPosition, _mapController.camera.zoom, mapRotation);
          }

          _sendThrottledBleCompass(heading);
        }
      }
    });

    _bleService.isConnectedNotifier.addListener(() {
      if (_bleService.isConnectedNotifier.value) {
        _startBleHeartbeatTimer();
      } else {
        _bleHeartbeatTimer?.cancel();
      }
    });

    _fetchAndApplyWeather();
    _weatherTimer?.cancel();
    _weatherTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _fetchAndApplyWeather();
    });
  }

  Future<void> _fetchAndApplyWeather() async {
    final w = await _weatherService.fetchCurrentWeather(_userPosition);
    if (w != null) {
      _currentTemperature = w.temperatureC;
      _currentWeatherCode = w.weatherCode;
      _navEngine.setWeatherInfo(w.temperatureC, w.weatherCode);
      debugPrint('>> [Weather] Clima actualizado: ${w.temperatureC}°C, código: ${w.weatherCode}');
    }
  }

  void _calibrateCompassToNorth() {
    setState(() {
      _compassOffset = (360.0 - _rawCompassHeading) % 360.0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Brújula calibrada al Norte (0°). Offset: ${_compassOffset.round()}°'),
        backgroundColor: const Color(0xFF00E676),
      ),
    );
  }

  void _adjustCompassOffset(double delta) {
    setState(() {
      _compassOffset = (_compassOffset + delta + 360.0) % 360.0;
    });
  }

  void _showCompassCalibrationModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18181B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            double calibratedHeading = (_rawCompassHeading + _compassOffset + 360.0) % 360.0;
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Calibración de Brújula',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 10),
                  Text(
                    'Rumbo Actual: ${calibratedHeading.round()}° (Offset: ${_compassOffset.round()}°)',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00E676)),
                  ),
                  Text(
                    'Lectura Sensor Raw: ${_rawCompassHeading.round()}°',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      _calibrateCompassToNorth();
                      setModalState(() {});
                    },
                    icon: const Icon(Icons.compass_calibration, color: Colors.black),
                    label: const Text('Fijar Posición Actual como Norte (0°)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      minimumSize: const Size(double.infinity, 45),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Ajuste Fino Manual:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          _adjustCompassOffset(-5);
                          setModalState(() {});
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27272A)),
                        child: const Text('-5°', style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          _adjustCompassOffset(-1);
                          setModalState(() {});
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27272A)),
                        child: const Text('-1°', style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          _adjustCompassOffset(1);
                          setModalState(() {});
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27272A)),
                        child: const Text('+1°', style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          _adjustCompassOffset(5);
                          setModalState(() {});
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27272A)),
                        child: const Text('+5°', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      setState(() => _compassOffset = 0.0);
                      setModalState(() {});
                    },
                    child: const Text('Restablecer Offset a 0°', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _sendTestTurnIcon(TurnIcon icon, String title) {
    final now = DateTime.now();
    final cleanTitle = title
        .replaceAll('ó', 'o').replaceAll('Ó', 'O')
        .replaceAll('á', 'a').replaceAll('Á', 'A')
        .replaceAll('é', 'e').replaceAll('É', 'E')
        .replaceAll('í', 'i').replaceAll('Í', 'I')
        .replaceAll('ú', 'u').replaceAll('Ú', 'U')
        .replaceAll('ñ', 'n').replaceAll('Ñ', 'N')
        .replaceAll('¡', '').replaceAll('!', '')
        .replaceAll('ª', 'a');

    NavigationPacket testPacket = NavigationPacket(
      navState: 3, // 3 = Catalog Test Mode (sin círculos periféricos de navegación)
      turnIcon: icon,
      distanceMeters: 150,
      totalRemainingMeters: 2400,
      speedKmh: 45,
      headingDeg: 45,
      vehicleHeadingDeg: _compassHeadingNotifier.value.round(),
      currentHour: now.hour,
      currentMinute: now.minute,
      temperatureC: _currentTemperature,
      weatherCode: _currentWeatherCode,
      finalHeadingDeg: 135,
      streetName: cleanTitle,
    );

    _activeCatalogTestPacket = testPacket;
    _lastPacketNotifier.value = testPacket;
    _sendBlePacket(testPacket);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Enviado a ESP32: $title'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showTurnIconsCatalogModal() {
    final List<Map<String, dynamic>> catalogItems = [
      {'icon': TurnIcon.straight, 'title': 'Recto', 'subtitle': 'Sigue por la vía', 'iconData': Icons.arrow_upward},
      {'icon': TurnIcon.turnRight, 'title': 'Giro Derecha', 'subtitle': 'Giro a 90° derecha', 'iconData': Icons.turn_right},
      {'icon': TurnIcon.turnLeft, 'title': 'Giro Izquierda', 'subtitle': 'Giro a 90° izquierda', 'iconData': Icons.turn_left},
      {'icon': TurnIcon.slightRight, 'title': 'Leve Derecha', 'subtitle': 'Desvío suave derecha', 'iconData': Icons.turn_slight_right},
      {'icon': TurnIcon.slightLeft, 'title': 'Leve Izquierda', 'subtitle': 'Desvío suave izquierda', 'iconData': Icons.turn_slight_left},
      {'icon': TurnIcon.sharpRight, 'title': 'Cerrado Derecha', 'subtitle': 'Giro pronunciado', 'iconData': Icons.turn_sharp_right},
      {'icon': TurnIcon.sharpLeft, 'title': 'Cerrado Izquierda', 'subtitle': 'Giro pronunciado', 'iconData': Icons.turn_sharp_left},
      {'icon': TurnIcon.roundaboutExit1, 'title': 'Rotonda (Salida 1)', 'subtitle': '1ª Salida - Derecha', 'iconData': Icons.rotate_right},
      {'icon': TurnIcon.roundaboutExit2, 'title': 'Rotonda (Salida 2)', 'subtitle': '2ª Salida - Recto', 'iconData': Icons.change_circle},
      {'icon': TurnIcon.roundaboutExit3, 'title': 'Rotonda (Salida 3)', 'subtitle': '3ª Salida - Izquierda', 'iconData': Icons.rotate_left},
      {'icon': TurnIcon.roundaboutExit4, 'title': 'Rotonda (Salida 4)', 'subtitle': '4ª Salida - Retorno', 'iconData': Icons.loop},
      {'icon': TurnIcon.uTurn, 'title': 'Retorno (U-Turn)', 'subtitle': 'Cambio de sentido', 'iconData': Icons.u_turn_left},
      {'icon': TurnIcon.forkRight, 'title': 'Bifurcación Derecha', 'subtitle': 'Mantente a la derecha', 'iconData': Icons.alt_route},
      {'icon': TurnIcon.forkLeft, 'title': 'Bifurcación Izquierda', 'subtitle': 'Mantente a la izquierda', 'iconData': Icons.alt_route},
      {'icon': TurnIcon.onRamp, 'title': 'Incorporación', 'subtitle': 'Entrada a autopista', 'iconData': Icons.merge},
      {'icon': TurnIcon.offRamp, 'title': 'Salida Autopista', 'subtitle': 'Tomar rampa de salida', 'iconData': Icons.call_made},
      {'icon': TurnIcon.arrived, 'title': '¡Llegaste!', 'subtitle': 'Destino alcanzado', 'iconData': Icons.flag},
    ];

    // Enviar inmediatamente la 1ª opción del catálogo al ESP32 al abrir el modal
    _sendTestTurnIcon(catalogItems[0]['icon'] as TurnIcon, catalogItems[0]['title'] as String);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF18181B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Catálogo de Indicaciones HUD',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Text(
                    'Toca una tarjeta para enviar y renderizar la flecha en el ESP32 en tiempo real.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 8),
                  Expanded(
                    child: GridView.builder(
                      controller: scrollController,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 1.6,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: catalogItems.length,
                      itemBuilder: (context, index) {
                        final item = catalogItems[index];
                        final TurnIcon turnIcon = item['icon'] as TurnIcon;
                        final String title = item['title'] as String;
                        final String subtitle = item['subtitle'] as String;
                        final IconData iconData = item['iconData'] as IconData;

                        return Material(
                          color: const Color(0xFF27272A),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              _sendTestTurnIcon(turnIcon, title);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(iconData, color: const Color(0xFF00E676), size: 28),
                                  const SizedBox(height: 6),
                                  Text(
                                    title,
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    subtitle,
                                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _activeCatalogTestPacket = null;
      if (!_navEngine.isNavigating) {
        _lastPacketNotifier.value = null;
      }
    });
  }

  void _sendThrottledBleCompass(double heading) {
    final now = DateTime.now();
    if (_lastBleCompassSendTime != null &&
        now.difference(_lastBleCompassSendTime!).inMilliseconds < 180) {
      return; // Transmisión fluida máxima a ~5.5 paquetes/segundo para evitar congestionar BLE
    }
    _lastBleCompassSendTime = now;

    if (!_bleService.isConnectedNotifier.value) return;

    final lastPacket = _lastPacketNotifier.value;
    final int currentHour = now.hour;
    final int currentMinute = now.minute;

    if (_activeCatalogTestPacket != null) {
      NavigationPacket catalogPacket = NavigationPacket(
        navState: 3,
        turnIcon: _activeCatalogTestPacket!.turnIcon,
        distanceMeters: _activeCatalogTestPacket!.distanceMeters,
        totalRemainingMeters: _activeCatalogTestPacket!.totalRemainingMeters,
        speedKmh: _activeCatalogTestPacket!.speedKmh,
        headingDeg: _activeCatalogTestPacket!.headingDeg,
        vehicleHeadingDeg: heading.round(),
        currentHour: currentHour,
        currentMinute: currentMinute,
        temperatureC: _currentTemperature,
        weatherCode: _currentWeatherCode,
        finalHeadingDeg: _activeCatalogTestPacket!.finalHeadingDeg,
        streetName: _activeCatalogTestPacket!.streetName,
      );
      _lastPacketNotifier.value = catalogPacket;
      _sendBlePacket(catalogPacket);
    } else if (_navEngine.isNavigating && _currentRoute != null && _currentRoute!.steps.isNotEmpty) {
      int upcomingIndex = (_navEngine.currentStepIndex + 1).clamp(0, _currentRoute!.steps.length - 1);
      OSRMStep step = _currentRoute!.steps[upcomingIndex];
      double targetBearing = const Distance().bearing(_userPosition, step.location);
      double relativeTargetAngle = (targetBearing - heading + 360.0) % 360.0;

      double relativeFinalAngle = 0.0;
      if (_currentRoute!.polylinePoints.isNotEmpty) {
        double finalTargetBearing = const Distance().bearing(_userPosition, _currentRoute!.polylinePoints.last);
        relativeFinalAngle = (finalTargetBearing - heading + 360.0) % 360.0;
      }

      NavigationPacket packet = NavigationPacket(
        navState: (lastPacket != null && lastPacket.navState == 2) ? 2 : 1,
        turnIcon: (lastPacket != null && lastPacket.navState == 2) ? TurnIcon.arrived : step.turnIcon,
        distanceMeters: lastPacket?.distanceMeters ?? step.distanceMeters.round(),
        totalRemainingMeters: lastPacket?.totalRemainingMeters ?? _currentRoute!.totalDistanceMeters.round(),
        speedKmh: lastPacket?.speedKmh ?? 0,
        headingDeg: (lastPacket != null && lastPacket.navState == 2) ? 0 : relativeTargetAngle.round(),
        vehicleHeadingDeg: heading.round(),
        currentHour: currentHour,
        currentMinute: currentMinute,
        temperatureC: _currentTemperature,
        weatherCode: _currentWeatherCode,
        finalHeadingDeg: relativeFinalAngle.round(),
        streetName: (lastPacket != null && lastPacket.navState == 2) ? '¡Llegaste!' : step.streetName,
      );

      _lastPacketNotifier.value = packet;
      _sendBlePacket(packet);
    } else {
      NavigationPacket idlePacket = NavigationPacket(
        navState: 0,
        turnIcon: TurnIcon.none,
        distanceMeters: 0,
        totalRemainingMeters: 0,
        speedKmh: 0,
        headingDeg: 0,
        vehicleHeadingDeg: heading.round(),
        currentHour: currentHour,
        currentMinute: currentMinute,
        temperatureC: _currentTemperature,
        weatherCode: _currentWeatherCode,
        streetName: 'Smart HUD',
      );
      _lastPacketNotifier.value = idlePacket;
      _sendBlePacket(idlePacket);
    }
  }

  void _recenterMap() {
    setState(() {
      _isTracking = true;
    });
    double mapRotation = (360.0 - _compassHeadingNotifier.value) % 360.0;
    _mapController.moveAndRotate(_userPosition, 18.0, mapRotation);
  }

  void _zoomInMap() {
    double newZoom = (_mapController.camera.zoom + 1.0).clamp(1.0, 19.0);
    double mapRotation = _isTracking ? (360.0 - _compassHeadingNotifier.value) % 360.0 : _mapController.camera.rotation;
    _mapController.moveAndRotate(_mapController.camera.center, newZoom, mapRotation);
  }

  void _zoomOutMap() {
    double newZoom = (_mapController.camera.zoom - 1.0).clamp(1.0, 19.0);
    double mapRotation = _isTracking ? (360.0 - _compassHeadingNotifier.value) % 360.0 : _mapController.camera.rotation;
    _mapController.moveAndRotate(_mapController.camera.center, newZoom, mapRotation);
  }

  void _toggleNavigation() {
    try {
      if (_navEngine.isNavigating) {
        _navEngine.stopNavigation();
        _lastPacketNotifier.value = null;
        setState(() {});
      } else {
        if (_currentRoute == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selecciona primero una ubicación o toca el mapa')),
          );
          return;
        }
        _navEngine.startNavigation(_currentRoute!);
        
        // Aumentar en +2 el zoom predefinido al iniciar navegación y centrar mapa
        _isTracking = true;
        double newZoom = (_mapController.camera.zoom + 2.0).clamp(1.0, 19.0);
        double mapRotation = (360.0 - _compassHeadingNotifier.value) % 360.0;
        _mapController.moveAndRotate(_userPosition, newZoom, mapRotation);

        setState(() {});
      }
    } catch (e) {
      debugPrint('Error en navegación: $e');
    }
  }

  void _startBleHeartbeatTimer() {
    _bleHeartbeatTimer?.cancel();
    _bleHeartbeatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_bleService.isConnectedNotifier.value) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final lastPacket = _lastPacketNotifier.value;

      if (_activeCatalogTestPacket != null) {
        NavigationPacket catalogPacket = NavigationPacket(
          navState: 3,
          turnIcon: _activeCatalogTestPacket!.turnIcon,
          distanceMeters: _activeCatalogTestPacket!.distanceMeters,
          totalRemainingMeters: _activeCatalogTestPacket!.totalRemainingMeters,
          speedKmh: _activeCatalogTestPacket!.speedKmh,
          headingDeg: _activeCatalogTestPacket!.headingDeg,
          vehicleHeadingDeg: _compassHeadingNotifier.value.round(),
          currentHour: now.hour,
          currentMinute: now.minute,
          temperatureC: _currentTemperature,
          weatherCode: _currentWeatherCode,
          finalHeadingDeg: _activeCatalogTestPacket!.finalHeadingDeg,
          streetName: _activeCatalogTestPacket!.streetName,
        );
        _sendBlePacket(catalogPacket);
      } else if (_navEngine.isNavigating && _currentRoute != null && _currentRoute!.steps.isNotEmpty) {
        int upcomingIndex = (_navEngine.currentStepIndex + 1).clamp(0, _currentRoute!.steps.length - 1);

        OSRMStep step = _currentRoute!.steps[upcomingIndex];

        double distToStep = lastPacket != null
            ? lastPacket.distanceMeters.toDouble()
            : step.distanceMeters;

        double totalRemaining = lastPacket != null
            ? lastPacket.totalRemainingMeters.toDouble()
            : _currentRoute!.totalDistanceMeters;

        int navState = (lastPacket != null && lastPacket.navState == 2) ? 2 : 1;

        double relativeFinalAngle = 0.0;
        if (_currentRoute != null && _currentRoute!.polylinePoints.isNotEmpty) {
          double finalTargetBearing = const Distance().bearing(_userPosition, _currentRoute!.polylinePoints.last);
          relativeFinalAngle = (finalTargetBearing - _compassHeadingNotifier.value + 360.0) % 360.0;
        }

        NavigationPacket packet = NavigationPacket(
          navState: navState,
          turnIcon: navState == 2 ? TurnIcon.arrived : step.turnIcon,
          distanceMeters: navState == 2 ? 0 : distToStep.round(),
          totalRemainingMeters: navState == 2 ? 0 : totalRemaining.round(),
          speedKmh: lastPacket?.speedKmh ?? 0,
          headingDeg: lastPacket?.headingDeg ?? 0,
          vehicleHeadingDeg: _compassHeadingNotifier.value.round(),
          currentHour: now.hour,
          currentMinute: now.minute,
          temperatureC: _currentTemperature,
          weatherCode: _currentWeatherCode,
          finalHeadingDeg: relativeFinalAngle.round(),
          streetName: navState == 2 ? '¡Llegaste!' : step.streetName,
        );

        _sendBlePacket(packet);
      } else {
        NavigationPacket idlePacket = NavigationPacket(
          navState: 0,
          turnIcon: TurnIcon.none,
          distanceMeters: 0,
          totalRemainingMeters: 0,
          speedKmh: 0,
          headingDeg: 0,
          vehicleHeadingDeg: _compassHeadingNotifier.value.round(),
          currentHour: now.hour,
          currentMinute: now.minute,
          temperatureC: _currentTemperature,
          weatherCode: _currentWeatherCode,
          streetName: 'Smart HUD',
        );

        _sendBlePacket(idlePacket);
      }
    });
  }

  Future<void> _sendBlePacket(NavigationPacket packet) async {
    final bytes = packet.toBytes();
    await _bleService.sendPacketBytes(bytes);
  }

  @override
  void dispose() {
    _weatherTimer?.cancel();
    _gpsStreamSubscription?.cancel();
    _bleHeartbeatTimer?.cancel();
    _compassSubscription?.cancel();
    _debounceTimer?.cancel();
    _bleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 Smart HUD Navigation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        backgroundColor: const Color(0xFF18181B),
        elevation: 0,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _bleService.isConnectedNotifier,
            builder: (context, isConnected, _) {
              return IconButton(
                icon: Icon(
                  isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: isConnected ? const Color(0xFF00E676) : const Color(0xFFFFB74D),
                ),
                onPressed: () => _bleService.toggleConnection(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. MAPA INTERACTIVO CON SOPORTE MULTI-PUNTOS Y ROTACIÓN WAZE
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _userPosition,
              initialZoom: 16.0,
              initialRotation: 0.0,
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && _isTracking) {
                  setState(() {
                    _isTracking = false;
                  });
                }
              },
              onTap: (tapPosition, point) {
                String name = 'Punto ${_waypoints.length + 1} (${point.latitude.toStringAsFixed(3)}, ${point.longitude.toStringAsFixed(3)})';
                _addWaypoint(point, name);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.esp32',
                maxZoom: 19,
              ),
              if (_currentRoute != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _currentRoute!.polylinePoints,
                      strokeWidth: 5.0,
                      color: const Color(0xFF00E676),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // Marcador Usuario con orientación por brújula
                  Marker(
                    point: _userPosition,
                    width: 40,
                    height: 40,
                    child: ValueListenableBuilder<double>(
                      valueListenable: _compassHeadingNotifier,
                      builder: (context, heading, _) {
                        return Transform.rotate(
                          angle: (heading * (3.1415926535 / 180.0)),
                          child: const Icon(Icons.navigation, color: Colors.blueAccent, size: 36),
                        );
                      },
                    ),
                  ),
                  // Marcadores de Puntos de Ruta (Waypoints)
                  for (int i = 0; i < _waypoints.length; i++)
                    Marker(
                      point: _waypoints[i],
                      width: 44,
                      height: 44,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: i == _waypoints.length - 1 ? Colors.redAccent : Colors.orangeAccent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              i == _waypoints.length - 1 ? 'FIN' : 'P${i + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Icon(
                            Icons.location_on,
                            color: i == _waypoints.length - 1 ? Colors.redAccent : Colors.orangeAccent,
                            size: 28,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 2. PANEL TOP BAR CON BÚSQUEDA Y BOTONES DE CONTROL DE PUNTOS Y RUTAS (SE OCULTA EN NAVEGACIÓN)
          if (!_navEngine.isNavigating)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Card(
                    color: const Color(0xFF18181B).withValues(alpha: 0.95),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Campo de búsqueda de direcciones Nominatim
                          TextField(
                            controller: _searchController,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            textInputAction: TextInputAction.search,
                            onChanged: _onSearchChanged,
                            onSubmitted: _searchAddress,
                            decoration: InputDecoration(
                              hintText: 'Buscar dirección o lugar...',
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                              prefixIcon: const Icon(Icons.search, color: Color(0xFF00E676), size: 20),
                              suffixIcon: _isSearching
                                  ? const Padding(
                                      padding: EdgeInsets.all(12.0),
                                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E676))),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.send, color: Color(0xFF00E676), size: 18),
                                      onPressed: () => _searchAddress(_searchController.text),
                                    ),
                              filled: true,
                              fillColor: const Color(0xFF27272A),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              ValueListenableBuilder<String>(
                                valueListenable: _bleService.statusTextNotifier,
                                builder: (context, statusText, _) {
                                  return Text(
                                    'BLE: $statusText',
                                    style: TextStyle(
                                      color: _bleService.isConnectedNotifier.value ? const Color(0xFF00E676) : const Color(0xFFFFB74D),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  );
                                },
                              ),
                              Expanded(
                                child: Text(
                                  _waypoints.isNotEmpty
                                      ? 'Puntos: ${_waypoints.length} (${_waypointNames.last})'
                                      : 'Toca el mapa para agregar puntos',
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              // BOTÓN PARA GUARDAR RUTA ACTUAL
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _currentRoute == null ? null : _saveCurrentRoute,
                                  icon: const Icon(Icons.bookmark_add, size: 14),
                                  label: const Text('Guardar', style: TextStyle(fontSize: 11)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00B0FF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // BOTÓN MIS RUTAS GUARDADAS
                              ElevatedButton.icon(
                                onPressed: _showSavedRoutesModal,
                                icon: const Icon(Icons.folder_special, size: 14),
                                label: Text('Rutas (${_savedRoutes.length})', style: const TextStyle(fontSize: 11)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3F3F46),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // BOTÓN PARA REINICIAR Y COMENZAR DE 0
                              ElevatedButton(
                                onPressed: _waypoints.isEmpty ? null : _clearRouteAndPoints,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF5252),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                child: const Icon(Icons.delete_outline, size: 16),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                // DESPLEGABLE AUTOCOMPLETE DE BÚSQUEDA NOMINATIM
                if (_searchResults.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Card(
                    color: const Color(0xFF18181B),
                    elevation: 8,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          separatorBuilder: (context, index) => const Divider(color: Colors.white12, height: 1),
                          itemBuilder: (context, index) {
                            final item = _searchResults[index];
                            final displayName = item['display_name'] as String? ?? 'Dirección';
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.location_on, color: Color(0xFF00E676), size: 20),
                              title: Text(
                                displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                              onTap: () => _selectSearchResult(item),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 3. TARJETA OVERLAY CELEBRATORIA AL LLEGAR AL DESTINO (navState == 2)
          ValueListenableBuilder<NavigationPacket?>(
            valueListenable: _lastPacketNotifier,
            builder: (context, packet, _) {
              if (packet == null || packet.navState != 2) {
                return const SizedBox.shrink();
              }
              return Positioned(
                top: 180,
                left: 20,
                right: 20,
                child: Card(
                  color: const Color(0xFF00E676),
                  elevation: 12,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sports_score, size: 56, color: Colors.black),
                        const SizedBox(height: 8),
                        const Text(
                          '¡HAZ LLEGADO A TU DESTINO!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '¡Recorrido completado con éxito!',
                          style: TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          onPressed: _clearRouteAndPoints,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Iniciar Nuevo Recorrido (Reiniciar a 0)'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // 3.5. BOTONES FLOTANTES DE CONTROL DE RUTA Y MAPA (ZOOM Y CENTRAR ABAJO)
          Positioned(
            right: 16,
            bottom: _currentRoute != null ? 280 : 180,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'catalog_btn',
                  onPressed: _showTurnIconsCatalogModal,
                  backgroundColor: const Color(0xFF18181B),
                  foregroundColor: const Color(0xFF00B0FF),
                  child: const Icon(Icons.grid_view),
                ),
                const SizedBox(height: 6),
                FloatingActionButton.small(
                  heroTag: 'compass_calib_btn',
                  onPressed: _showCompassCalibrationModal,
                  backgroundColor: const Color(0xFF18181B),
                  foregroundColor: const Color(0xFF00E676),
                  child: const Icon(Icons.explore),
                ),
                const SizedBox(height: 6),
                FloatingActionButton.small(
                  heroTag: 'zoom_in_btn',
                  onPressed: _zoomInMap,
                  backgroundColor: const Color(0xFF18181B),
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 6),
                FloatingActionButton.small(
                  heroTag: 'zoom_out_btn',
                  onPressed: _zoomOutMap,
                  backgroundColor: const Color(0xFF18181B),
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.remove),
                ),
                if (!_isTracking) ...[
                  const SizedBox(height: 10),
                  FloatingActionButton.extended(
                    heroTag: 'recenter_btn',
                    onPressed: _recenterMap,
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Centrar', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),

          // 4. PANEL SLIDING SHEET - CONTROL Y LISTADO DE INDICACIONES TBT
          DraggableScrollableSheet(
            initialChildSize: _currentRoute != null ? 0.35 : 0.20,
            minChildSize: 0.18,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF18181B),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 16)],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    // Pull Handle Indicator
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 4, bottom: 12),
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    ValueListenableBuilder<NavigationPacket?>(
                      valueListenable: _lastPacketNotifier,
                      builder: (context, lastPacket, _) {
                        if (!_navEngine.isNavigating || lastPacket == null) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF27272A),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF00E676), width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: const Color(0xFF00E676),
                                    child: Icon(_getTurnIconData(lastPacket.turnIcon), size: 26, color: Colors.black),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${lastPacket.distanceMeters} m - ${lastPacket.streetName}',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        ValueListenableBuilder<int>(
                                          valueListenable: _bleService.packetsSentNotifier,
                                          builder: (context, count, _) {
                                            return Text(
                                              'Velocidad: ${lastPacket.speedKmh} km/h | Restante: ${(lastPacket.totalRemainingMeters / 1000).toStringAsFixed(1)} km',
                                              style: const TextStyle(fontSize: 12, color: Colors.white70),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        );
                      },
                    ),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isLoadingRoute ? null : _toggleNavigation,
                        icon: Icon(
                          _navEngine.isNavigating ? Icons.stop : Icons.navigation,
                          color: Colors.black,
                          size: 20,
                        ),
                        label: Text(
                          _navEngine.isNavigating ? 'DETENER HUD' : 'INICIAR HUD',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _navEngine.isNavigating ? const Color(0xFFFF5252) : const Color(0xFF00E676),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),

                    // LISTA DESLIZABLE DE INDICACIONES PASO A PASO DE LA RUTA
                    if (_currentRoute != null && _currentRoute!.steps.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Indicaciones (Desliza para desplegar)',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF27272A),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_currentRoute!.steps.length} pasadas',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<int>(
                        valueListenable: _navEngine.currentStepNotifier,
                        builder: (context, activeStepIdx, _) {
                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _currentRoute!.steps.length,
                            itemBuilder: (context, index) {
                              final step = _currentRoute!.steps[index];
                              final isCurrent = _navEngine.isNavigating && index == activeStepIdx;
                              final isCompleted = _navEngine.isNavigating && index < activeStepIdx;

                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? const Color(0xFF00E676).withValues(alpha: 0.18)
                                      : (isCompleted ? Colors.white.withValues(alpha: 0.02) : const Color(0xFF27272A).withValues(alpha: 0.6)),
                                  borderRadius: BorderRadius.circular(12),
                                  border: isCurrent
                                      ? Border.all(color: const Color(0xFF00E676), width: 1.5)
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isCurrent
                                            ? const Color(0xFF00E676)
                                            : (isCompleted ? Colors.white24 : const Color(0xFF3F3F46)),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _getTurnIconData(step.turnIcon),
                                        color: isCurrent ? Colors.black : Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  _getTurnInstructionText(step.turnIcon, step.streetName),
                                                  style: TextStyle(
                                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                                    color: isCurrent ? const Color(0xFF00E676) : (isCompleted ? Colors.white38 : Colors.white),
                                                    fontSize: 13,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (isCurrent) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF00E676),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text(
                                                    'AHORA',
                                                    style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'Tramo: ${step.distanceMeters >= 1000 ? '${(step.distanceMeters / 1000).toStringAsFixed(1)} km' : '${step.distanceMeters.round()} m'}',
                                            style: TextStyle(
                                              color: isCompleted ? Colors.white24 : Colors.white60,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  IconData _getTurnIconData(TurnIcon icon) {
    switch (icon) {
      case TurnIcon.straight:
        return Icons.arrow_upward;
      case TurnIcon.turnRight:
        return Icons.turn_right;
      case TurnIcon.turnLeft:
        return Icons.turn_left;
      case TurnIcon.slightRight:
        return Icons.turn_slight_right;
      case TurnIcon.slightLeft:
        return Icons.turn_slight_left;
      case TurnIcon.sharpRight:
        return Icons.turn_sharp_right;
      case TurnIcon.sharpLeft:
        return Icons.turn_sharp_left;
      case TurnIcon.roundaboutExit1:
        return Icons.rotate_right;
      case TurnIcon.roundaboutExit2:
        return Icons.change_circle;
      case TurnIcon.roundaboutExit3:
        return Icons.rotate_left;
      case TurnIcon.roundaboutExit4:
        return Icons.loop;
      case TurnIcon.uTurn:
        return Icons.u_turn_left;
      case TurnIcon.forkRight:
      case TurnIcon.forkLeft:
        return Icons.alt_route;
      case TurnIcon.onRamp:
        return Icons.merge;
      case TurnIcon.offRamp:
        return Icons.call_made;
      case TurnIcon.arrived:
        return Icons.flag;
      default:
        return Icons.navigation;
    }
  }

  String _getTurnInstructionText(TurnIcon icon, String streetName) {
    switch (icon) {
      case TurnIcon.straight:
        return 'Continúa recto por $streetName';
      case TurnIcon.turnRight:
        return 'Gira a la derecha en $streetName';
      case TurnIcon.turnLeft:
        return 'Gira a la izquierda en $streetName';
      case TurnIcon.slightRight:
        return 'Gira levemente a la derecha en $streetName';
      case TurnIcon.slightLeft:
        return 'Gira levemente a la izquierda en $streetName';
      case TurnIcon.sharpRight:
        return 'Gira pronunciado a la derecha en $streetName';
      case TurnIcon.sharpLeft:
        return 'Gira pronunciado a la izquierda en $streetName';
      case TurnIcon.roundaboutExit1:
        return 'En la rotonda, toma la 1ª salida hacia $streetName';
      case TurnIcon.roundaboutExit2:
        return 'En la rotonda, toma la 2ª salida hacia $streetName';
      case TurnIcon.roundaboutExit3:
        return 'En la rotonda, toma la 3ª salida hacia $streetName';
      case TurnIcon.roundaboutExit4:
        return 'En la rotonda, toma la 4ª salida hacia $streetName';
      case TurnIcon.uTurn:
        return 'Realiza un cambio de sentido hacia $streetName';
      case TurnIcon.forkRight:
        return 'En la bifurcación, mantente a la derecha hacia $streetName';
      case TurnIcon.forkLeft:
        return 'En la bifurcación, mantente a la izquierda hacia $streetName';
      case TurnIcon.onRamp:
        return 'Incorpórate a la autopista $streetName';
      case TurnIcon.offRamp:
        return 'Toma la salida hacia $streetName';
      case TurnIcon.arrived:
        return 'Llegada al destino en $streetName';
      default:
        return 'Avanza hacia $streetName';
    }
  }
}
