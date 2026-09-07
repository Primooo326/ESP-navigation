import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models/navigation_packet.dart';
import 'services/osrm_service.dart';
import 'services/navigation_engine.dart';

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
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00B0FF),
          surface: Color(0xFF1E1E1E),
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

class _MainHudScreenState extends State<MainHudScreen> {
  static const String targetServiceName = 'ESP32C3_BLE';
  static final Guid serviceUuid = Guid('4fa1c201-1fb5-459e-8fcc-c5c9c331914b');
  static final Guid characteristicUuid = Guid('beb5483e-36e1-4688-b7f5-ea07361b26a8');

  // Map & Location
  final MapController _mapController = MapController();
  LatLng _userPosition = const LatLng(4.60971, -74.08175); // Bogotá por defecto
  LatLng? _destinationPosition;
  final ValueNotifier<double> _compassHeadingNotifier = ValueNotifier<double>(0.0);

  // Navigation & Services
  final OSRMService _osrmService = OSRMService();
  final NavigationEngine _navEngine = NavigationEngine();
  OSRMRoute? _currentRoute;
  bool _isLoadingRoute = false;

  // BLE State
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _bleCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  StreamSubscription<Position>? _positionStreamSub;

  final ValueNotifier<int> _packetsSentNotifier = ValueNotifier<int>(0);
  final ValueNotifier<NavigationPacket?> _lastPacketNotifier = ValueNotifier<NavigationPacket?>(null);
  String _statusText = 'Estado: Desconectado';
  Color _statusColor = const Color(0xFFFFB74D);
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _initAppPermissionsAndLocation();
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

  Future<void> _initAppPermissionsAndLocation() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.locationAlways,
      Permission.notification,
    ].request();

    bool locationGranted = await Geolocator.isLocationServiceEnabled();
    if (locationGranted) {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _userPosition = LatLng(pos.latitude, pos.longitude);
        });
        _mapController.move(_userPosition, 15.0);
      }
    }

    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (event.heading != null) {
        final heading = (360.0 - event.heading!) % 360.0;
        _compassHeadingNotifier.value = heading;
        _navEngine.setCompassHeading(heading);
      }
    });
  }

  Future<void> _fetchRouteToDestination(LatLng dest) async {
    setState(() {
      _destinationPosition = dest;
      _isLoadingRoute = true;
    });

    final route = await _osrmService.fetchRoute(_userPosition, dest);

    if (!mounted) return;

    setState(() {
      _isLoadingRoute = false;
      _currentRoute = route;
    });

    if (route != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ruta obtenida: ${(route.totalDistanceMeters / 1000).toStringAsFixed(1)} km '
            '(${(route.totalDurationSeconds / 60).round()} min)',
          ),
          backgroundColor: const Color(0xFF00E676),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al obtener la ruta del servidor OSRM'),
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
            const SnackBar(content: Text('Selecciona primero un destino en el mapa')),
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

  Future<void> _toggleBleConnection() async {
    if (_connectedDevice != null || _isConnecting) {
      await _disconnectBle();
    } else {
      await _connectBle();
    }
  }

  Future<void> _connectBle() async {
    setState(() {
      _isConnecting = true;
      _statusText = 'Buscando ESP32C3_BLE...';
      _statusColor = const Color(0xFFFFB74D);
    });

    try {
      await FlutterBluePlus.stopScan();
      Completer<BluetoothDevice?> completer = Completer();

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName == targetServiceName ||
              r.advertisementData.advName == targetServiceName ||
              r.advertisementData.serviceUuids.contains(serviceUuid)) {
            if (!completer.isCompleted) completer.complete(r.device);
          }
        }
      });

      await FlutterBluePlus.startScan(withServices: [serviceUuid], timeout: const Duration(seconds: 8));

      BluetoothDevice? dev = await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => null,
      );

      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();

      if (dev == null) {
        setState(() {
          _isConnecting = false;
          _statusText = 'ESP32C3_BLE no encontrado';
          _statusColor = const Color(0xFFFF5252);
        });
        return;
      }

      setState(() {
        _statusText = 'Conectando a ESP32-C3...';
      });

      await dev.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = dev;

      _connectionStateSubscription = dev.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleBleDisconnected();
        }
      });

      List<BluetoothService> services = await dev.discoverServices();
      for (var s in services) {
        for (var c in s.characteristics) {
          if (c.uuid == characteristicUuid) {
            _bleCharacteristic = c;
            break;
          }
        }
      }

      if (_bleCharacteristic == null) {
        await dev.disconnect();
        setState(() {
          _isConnecting = false;
          _statusText = 'Característica no encontrada';
          _statusColor = const Color(0xFFFF5252);
        });
        return;
      }

      _packetsSentNotifier.value = 0;
      setState(() {
        _isConnecting = false;
        _statusText = '¡CONECTADO AL ESP32-C3!';
        _statusColor = const Color(0xFF00E676);
      });

      _startBleHeartbeatTimer();
    } catch (e) {
      await _disconnectBle();
      setState(() {
        _isConnecting = false;
        _statusText = 'Error BLE: $e';
        _statusColor = const Color(0xFFFF5252);
      });
    }
  }

  Timer? _bleHeartbeatTimer;

  void _startBleHeartbeatTimer() {
    _bleHeartbeatTimer?.cancel();
    _bleHeartbeatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_connectedDevice == null || _bleCharacteristic == null) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final lastPacket = _lastPacketNotifier.value;

      if (_navEngine.isNavigating && _currentRoute != null && _currentRoute!.steps.isNotEmpty) {
        int upcomingIndex = (_navEngine.currentStepIndex + 1 < _currentRoute!.steps.length)
            ? _navEngine.currentStepIndex + 1
            : _navEngine.currentStepIndex;

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
    if (_bleCharacteristic != null && _connectedDevice != null) {
      try {
        final bytes = packet.toBytes();
        bool withoutResponse = _bleCharacteristic!.properties.writeWithoutResponse;
        await _bleCharacteristic!.write(bytes, withoutResponse: withoutResponse);
        _packetsSentNotifier.value++;
      } catch (e) {
        debugPrint('Error enviando paquete BLE a ESP32: $e');
      }
    }
  }

  Future<void> _disconnectBle() async {
    _bleHeartbeatTimer?.cancel();
    _bleHeartbeatTimer = null;
    _bleCharacteristic = null;
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
      _connectedDevice = null;
    }
    _handleBleDisconnected();
  }

  void _handleBleDisconnected() {
    _bleHeartbeatTimer?.cancel();
    _bleHeartbeatTimer = null;
    if (mounted) {
      setState(() {
        _isConnecting = false;
        _connectedDevice = null;
        _bleCharacteristic = null;
        _statusText = 'Estado: Desconectado';
        _statusColor = const Color(0xFFFFB74D);
      });
    }
  }

  @override
  void dispose() {
    _bleHeartbeatTimer?.cancel();
    _compassSubscription?.cancel();
    _positionStreamSub?.cancel();
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _disconnectBle();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = _connectedDevice != null && _bleCharacteristic != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 Smart HUD Navigation', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: _statusColor,
            ),
            onPressed: _toggleBleConnection,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. MAPA INTERACTIVO OPENSTREETMAP
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _userPosition,
              initialZoom: 15.0,
              onTap: (tapPosition, point) {
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
                  // Marcador Usuario con ValueListenableBuilder para evitar rebuilds de la pantalla
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
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_on, color: Colors.redAccent, size: 40),
                    ),
                ],
              ),
            ],
          ),

          // 2. PANEL TOP BAR - DESTINO RÁPIDO & INDICACIONES
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              color: const Color(0xFF1E1E1E).withValues(alpha: 0.92),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'BLE: $_statusText',
                      style: TextStyle(color: _statusColor, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Toca cualquier punto del mapa para fijar destino OSRM',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoadingRoute
                                ? null
                                : () {
                                    // Preset Bogotá Centro - Chapinero
                                    _fetchRouteToDestination(const LatLng(4.64862, -74.06284));
                                  },
                            icon: const Icon(Icons.explore, size: 18),
                            label: const Text('Ruta Demo Chapinero'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2A2A2A),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _toggleBleConnection,
                          icon: Icon(_isConnecting ? Icons.hourglass_top : Icons.bluetooth, size: 18),
                          label: Text(isConnected ? 'Conectado' : 'BLE ESP32'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isConnected ? const Color(0xFF00E676) : const Color(0xFFFFB74D),
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. PANEL BOTTOM SHEET - CONTROL NAVEGACIÓN Y PREVIEW HUD
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Banner Preview HUD si hay navegación activa (reactivo sin setState)
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
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF00E676), width: 1.5),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.turn_right, size: 36, color: Color(0xFF00E676)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${lastPacket.distanceMeters} m - ${lastPacket.streetName}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      ValueListenableBuilder<int>(
                                        valueListenable: _packetsSentNotifier,
                                        builder: (context, count, _) {
                                          return Text(
                                            'Velocidad: ${lastPacket.speedKmh} km/h | Paquetes BLE enviados: $count',
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

                  // Botón Iniciar / Detener Navegación
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _toggleNavigation,
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
