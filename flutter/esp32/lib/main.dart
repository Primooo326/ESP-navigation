import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'models/navigation_packet.dart';
import 'services/osrm_service.dart';
import 'services/navigation_engine.dart';
import 'services/ble_service.dart';
import 'services/location_service.dart';

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

class MainHudScreen extends StatefulWidget {
  const MainHudScreen({super.key});

  @override
  State<MainHudScreen> createState() => _MainHudScreenState();
}

class PresetDestination {
  final String title;
  final String subtitle;
  final LatLng location;
  final IconData icon;

  const PresetDestination({
    required this.title,
    required this.subtitle,
    required this.location,
    required this.icon,
  });
}

class _MainHudScreenState extends State<MainHudScreen> {
  // Desacoplamiento de Servicios (SOLID - Single Responsibility / Dependency Inversion)
  final BleService _bleService = BleService();
  final LocationService _locationService = LocationService();
  final OSRMService _osrmService = OSRMService();
  final NavigationEngine _navEngine = NavigationEngine();

  // Mapa y Posición
  final MapController _mapController = MapController();
  LatLng _userPosition = const LatLng(4.60971, -74.08175); // Bogotá por defecto
  LatLng? _destinationPosition;
  String _destinationName = 'Destino seleccionado';

  final ValueNotifier<double> _compassHeadingNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<NavigationPacket?> _lastPacketNotifier = ValueNotifier<NavigationPacket?>(null);

  OSRMRoute? _currentRoute;
  bool _isLoadingRoute = false;

  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _bleHeartbeatTimer;

  // Lista de destinos rápidos multilocalización
  final List<PresetDestination> _presetLocations = const [
    PresetDestination(
      title: 'Chapinero Calle 72',
      subtitle: 'Bogotá Zona Financiera',
      location: LatLng(4.64862, -74.06284),
      icon: Icons.business,
    ),
    PresetDestination(
      title: 'Plaza de Bolívar',
      subtitle: 'Centro Histórico',
      location: LatLng(4.5981, -74.0760),
      icon: Icons.account_balance,
    ),
    PresetDestination(
      title: 'Zona Rosa / Calle 85',
      subtitle: 'Zona T - Chapinero Norte',
      location: LatLng(4.6669, -74.0538),
      icon: Icons.local_activity,
    ),
    PresetDestination(
      title: 'Aeropuerto El Dorado',
      subtitle: 'Terminal Internacional T1',
      location: LatLng(4.7016, -74.1469),
      icon: Icons.flight_takeoff,
    ),
    PresetDestination(
      title: 'Parque de la 93',
      subtitle: 'Chicó - Gastronomía',
      location: LatLng(4.6766, -74.0482),
      icon: Icons.park,
    ),
    PresetDestination(
      title: 'Centro Mayor',
      subtitle: 'Autopista Sur',
      location: LatLng(4.5714, -74.1221),
      icon: Icons.shopping_bag,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initAppServices();
    _setupNavEngineCallbacks();
  }

  void _setupNavEngineCallbacks() {
    _navEngine.onPacketGenerated = (NavigationPacket packet) {
      _lastPacketNotifier.value = packet;
      _sendBlePacket(packet);
    };

    _navEngine.onReRouteRequested = (LatLng currentPos) async {
      if (_destinationPosition != null) {
        final newRoute = await _osrmService.fetchRoute(currentPos, _destinationPosition!);
        if (newRoute != null && mounted) {
          setState(() {
            _currentRoute = newRoute;
          });
          _navEngine.startNavigation(newRoute);
        }
      }
    };
  }

  Future<void> _initAppServices() async {
    await _locationService.requestPermissions();
    LatLng? userPos = await _locationService.getCurrentUserPosition();
    if (userPos != null && mounted) {
      setState(() {
        _userPosition = userPos;
      });
      _mapController.move(_userPosition, 15.0);
    }

    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (event.heading != null) {
        final heading = (360.0 - event.heading!) % 360.0;
        _compassHeadingNotifier.value = heading;
        _navEngine.setCompassHeading(heading);
      }
    });

    _bleService.isConnectedNotifier.addListener(() {
      if (_bleService.isConnectedNotifier.value) {
        _startBleHeartbeatTimer();
      } else {
        _bleHeartbeatTimer?.cancel();
      }
    });
  }

  Future<void> _fetchRouteToDestination(LatLng dest, {String? customName}) async {
    setState(() {
      _destinationPosition = dest;
      _destinationName = customName ?? 'Punto en Mapa (${dest.latitude.toStringAsFixed(3)}, ${dest.longitude.toStringAsFixed(3)})';
      _isLoadingRoute = true;
    });

    final route = await _osrmService.fetchRoute(_userPosition, dest);

    if (!mounted) return;

    setState(() {
      _isLoadingRoute = false;
      _currentRoute = route;
    });

    if (route != null) {
      if (_navEngine.isNavigating) {
        // Actualización dinámica de ruta sobre la marcha sin detener el GPS
        _navEngine.startNavigation(route);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ruta cargada a $_destinationName: ${(route.totalDistanceMeters / 1000).toStringAsFixed(1)} km '
            '(${(route.totalDurationSeconds / 60).round()} min)',
          ),
          backgroundColor: const Color(0xFF00E676),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al obtener la ruta OSRM'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
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

      if (_navEngine.isNavigating && _currentRoute != null && _currentRoute!.steps.isNotEmpty) {
        int upcomingIndex = (_navEngine.currentStepIndex + 1 < _currentRoute!.steps.length)
            ? _navEngine.currentStepIndex + 1
            : _currentRoute!.steps.length - 1;

        OSRMStep step = _currentRoute!.steps[upcomingIndex];

        double distToStep = lastPacket != null
            ? lastPacket.distanceMeters.toDouble()
            : step.distanceMeters;

        double totalRemaining = lastPacket != null
            ? lastPacket.totalRemainingMeters.toDouble()
            : _currentRoute!.totalDistanceMeters;

        NavigationPacket packet = NavigationPacket(
          navState: 1,
          turnIcon: step.turnIcon,
          distanceMeters: distToStep.round(),
          totalRemainingMeters: totalRemaining.round(),
          speedKmh: lastPacket?.speedKmh ?? 0,
          headingDeg: _compassHeadingNotifier.value.round(),
          currentHour: now.hour,
          currentMinute: now.minute,
          streetName: step.streetName,
        );

        _sendBlePacket(packet);
      } else {
        NavigationPacket idlePacket = NavigationPacket(
          navState: 0,
          turnIcon: TurnIcon.none,
          distanceMeters: 0,
          totalRemainingMeters: 0,
          speedKmh: 0,
          headingDeg: _compassHeadingNotifier.value.round(),
          currentHour: now.hour,
          currentMinute: now.minute,
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

  void _showLocationPickerModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18181B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
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
                    'Seleccionar Destino Multilocalización',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white24),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _presetLocations.length,
                  itemBuilder: (context, index) {
                    final item = _presetLocations[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF27272A),
                        child: Icon(item.icon, color: const Color(0xFF00E676)),
                      ),
                      title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: Text(item.subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        _mapController.move(item.location, 15.0);
                        _fetchRouteToDestination(item.location, customName: item.title);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _bleHeartbeatTimer?.cancel();
    _compassSubscription?.cancel();
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
          // 1. MAPA INTERACTIVO DE SELECCIÓN DE UBICACIÓN
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _userPosition,
              initialZoom: 15.0,
              onTap: (tapPosition, point) {
                // Permite tocar cualquier punto del mapa para seleccionar nuevo destino en todo momento
                _fetchRouteToDestination(point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.esp32',
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
                  // Marcador Destino
                  if (_destinationPosition != null)
                    Marker(
                      point: _destinationPosition!,
                      width: 44,
                      height: 44,
                      child: const Icon(Icons.location_on, color: Colors.redAccent, size: 44),
                    ),
                ],
              ),
            ],
          ),

          // 2. PANEL TOP BAR - BARRA DE CONEXIÓN BLE Y MULTILOCALIZACIÓN
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              color: const Color(0xFF18181B).withValues(alpha: 0.94),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<String>(
                      valueListenable: _bleService.statusTextNotifier,
                      builder: (context, statusText, _) {
                        return Text(
                          'BLE: $statusText',
                          style: TextStyle(
                            color: _bleService.isConnectedNotifier.value ? const Color(0xFF00E676) : const Color(0xFFFFB74D),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _destinationPosition != null ? 'Destino: $_destinationName' : 'Toca el mapa o usa el selector para fijar destino',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _showLocationPickerModal,
                            icon: const Icon(Icons.place, size: 18),
                            label: const Text('Destinos Rápido'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF27272A),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<bool>(
                          valueListenable: _bleService.isConnectedNotifier,
                          builder: (context, isConnected, _) {
                            return ElevatedButton.icon(
                              onPressed: () => _bleService.toggleConnection(),
                              icon: const Icon(Icons.bluetooth, size: 18),
                              label: Text(isConnected ? 'Conectado' : 'BLE ESP32'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isConnected ? const Color(0xFF00E676) : const Color(0xFFFFB74D),
                                foregroundColor: Colors.black,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. PANEL BOTTOM SHEET - CONTROL DE NAVEGACIÓN
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF18181B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF00E676), width: 1.5),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.navigation, size: 32, color: Color(0xFF00E676)),
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
                                      ),
                                      ValueListenableBuilder<int>(
                                        valueListenable: _bleService.packetsSentNotifier,
                                        builder: (context, count, _) {
                                          return Text(
                                            'Velocidad: ${lastPacket.speedKmh} km/h | Paquetes BLE: $count',
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
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isLoadingRoute ? null : _toggleNavigation,
                      icon: Icon(
                        _navEngine.isNavigating ? Icons.stop : Icons.navigation,
                        color: Colors.black,
                      ),
                      label: Text(
                        _navEngine.isNavigating ? 'DETENER NAVEGACIÓN HUD' : 'INICIAR NAVEGACIÓN SMART HUD',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _navEngine.isNavigating ? const Color(0xFFFF5252) : const Color(0xFF00E676),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
