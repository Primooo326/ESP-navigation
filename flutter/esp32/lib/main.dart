import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ImuBleApp());
}

class ImuBleApp extends StatelessWidget {
  const ImuBleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Android IMU BLE Streamer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const ImuBleScreen(),
    );
  }
}

class ImuBleScreen extends StatefulWidget {
  const ImuBleScreen({super.key});

  @override
  State<ImuBleScreen> createState() => _ImuBleScreenState();
}

class _ImuBleScreenState extends State<ImuBleScreen> {
  static const String targetServiceName = 'ESP32C3_BLE';
  static final Guid serviceUuid = Guid('4fa1c201-1fb5-459e-8fcc-c5c9c331914b');
  static final Guid characteristicUuid = Guid('beb5483e-36e1-4688-b7f5-ea07361b26a8');

  // Sensor data
  double _accX = 0.0;
  double _accY = 0.0;
  double _accZ = 0.0;

  double _gyroX = 0.0;
  double _gyroY = 0.0;
  double _gyroZ = 0.0;

  double _heading = 0.0;

  // BLE State
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _bleCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;

  // Sensor Subscriptions
  StreamSubscription<AccelerometerEvent>? _accSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;

  // Stream timer & stats
  Timer? _sendTimer;
  int _streamIntervalMs = 500; // Default: 500ms (slower transmission)
  int _packetsSent = 0;
  String _statusText = 'Estado: Desconectado';
  Color _statusColor = const Color(0xFFFFB74D);
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _startSensorListeners();
  }

  void _startSensorListeners() {
    // Accelerometer listener (including gravity)
    _accSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      if (mounted) {
        setState(() {
          _accX = event.x;
          _accY = event.y;
          _accZ = event.z;
        });
      }
    });

    // Gyroscope listener
    _gyroSubscription = gyroscopeEventStream().listen((GyroscopeEvent event) {
      if (mounted) {
        setState(() {
          _gyroX = event.x;
          _gyroY = event.y;
          _gyroZ = event.z;
        });
      }
    });

    // Compass listener
    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (mounted && event.heading != null) {
        setState(() {
          double rawHeading = event.heading!;
          _heading = (360.0 - rawHeading) % 360.0;
          if (_heading < 0) _heading += 360.0;
        });
      }
    });
  }

  Future<bool> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (status.isDenied || status.isPermanentlyDenied) {
        allGranted = false;
      }
    });

    return allGranted;
  }

  Future<void> _toggleConnection() async {
    if (_connectedDevice != null || _isConnecting) {
      await _disconnectBLE();
    } else {
      await _connectBLE();
    }
  }

  Future<void> _connectBLE() async {
    setState(() {
      _isConnecting = true;
      _statusText = 'Verificando permisos...';
      _statusColor = const Color(0xFFFFB74D);
    });

    bool hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      setState(() {
        _isConnecting = false;
        _statusText = 'Error: Permisos no concedidos';
        _statusColor = const Color(0xFFFF5252);
      });
      return;
    }

    // Check adapter state
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      setState(() {
        _isConnecting = false;
        _statusText = 'Error: Activa el Bluetooth';
        _statusColor = const Color(0xFFFF5252);
      });
      return;
    }

    setState(() {
      _statusText = 'Buscando ESP32C3_BLE...';
      _statusColor = const Color(0xFFFFB74D);
    });

    try {
      await FlutterBluePlus.stopScan();

      Completer<BluetoothDevice?> deviceCompleter = Completer();

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          bool nameMatch = r.device.platformName == targetServiceName ||
              r.advertisementData.advName == targetServiceName;
          bool serviceMatch = r.advertisementData.serviceUuids.contains(serviceUuid);

          if ((nameMatch || serviceMatch) && !deviceCompleter.isCompleted) {
            deviceCompleter.complete(r.device);
            break;
          }
        }
      });

      await FlutterBluePlus.startScan(
        withServices: [serviceUuid],
        timeout: const Duration(seconds: 12),
      );

      BluetoothDevice? targetDevice = await deviceCompleter.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => null,
      );

      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;

      if (targetDevice == null) {
        // Fallback: scan without filter in case device advertisement metadata differs
        setState(() {
          _statusText = 'Escaneo detallado ESP32C3...';
        });

        Completer<BluetoothDevice?> fallbackCompleter = Completer();
        _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
          for (ScanResult r in results) {
            if ((r.device.platformName.contains('ESP32') ||
                    r.advertisementData.advName.contains('ESP32')) &&
                !fallbackCompleter.isCompleted) {
              fallbackCompleter.complete(r.device);
              break;
            }
          }
        });

        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

        targetDevice = await fallbackCompleter.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );

        await FlutterBluePlus.stopScan();
        await _scanSubscription?.cancel();
        _scanSubscription = null;
      }

      if (targetDevice == null) {
        setState(() {
          _isConnecting = false;
          _statusText = 'ESP32C3_BLE no encontrado';
          _statusColor = const Color(0xFFFF5252);
        });
        return;
      }

      setState(() {
        _statusText = 'Conectando a ${targetDevice!.platformName}...';
      });

      await targetDevice.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = targetDevice;

      _connectionStateSubscription = targetDevice.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnected();
        }
      });

      setState(() {
        _statusText = 'Descubriendo servicios...';
      });

      List<BluetoothService> services = await targetDevice.discoverServices();
      BluetoothCharacteristic? targetChar;

      for (BluetoothService service in services) {
        if (service.uuid == serviceUuid) {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid == characteristicUuid) {
              targetChar = characteristic;
              break;
            }
          }
        }
      }

      if (targetChar == null) {
        // Search across all characteristics if exact UUID service wrapping differs
        for (BluetoothService service in services) {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid == characteristicUuid) {
              targetChar = characteristic;
              break;
            }
          }
        }
      }

      if (targetChar == null) {
        await targetDevice.disconnect();
        setState(() {
          _isConnecting = false;
          _statusText = 'Característica BLE no encontrada';
          _statusColor = const Color(0xFFFF5252);
        });
        return;
      }

      _bleCharacteristic = targetChar;

      setState(() {
        _isConnecting = false;
        _statusText = '¡CONECTADO AL ESP32-C3!';
        _statusColor = const Color(0xFF00E676);
        _packetsSent = 0;
      });

      _startDataStream();
    } catch (e) {
      await FlutterBluePlus.stopScan();
      await _disconnectBLE();
      setState(() {
        _isConnecting = false;
        _statusText = 'Error: ${e.toString()}';
        _statusColor = const Color(0xFFFF5252);
      });
    }
  }

  void _setStreamInterval(int intervalMs) {
    setState(() {
      _streamIntervalMs = intervalMs;
    });
    if (_connectedDevice != null && _bleCharacteristic != null) {
      _startDataStream();
    }
  }

  void _startDataStream() {
    _sendTimer?.cancel();
    _sendTimer = Timer.periodic(Duration(milliseconds: _streamIntervalMs), (timer) async {
      if (_bleCharacteristic != null && _connectedDevice != null) {
        // Formato: "accX,accY,accZ,gyroX,gyroY,gyroZ,heading"
        String payload =
            '${_accX.toStringAsFixed(2)},${_accY.toStringAsFixed(2)},${_accZ.toStringAsFixed(2)},'
            '${_gyroX.toStringAsFixed(2)},${_gyroY.toStringAsFixed(2)},${_gyroZ.toStringAsFixed(2)},'
            '${_heading.toStringAsFixed(1)}';

        try {
          bool useWithoutResponse = _bleCharacteristic!.properties.writeWithoutResponse;
          await _bleCharacteristic!.write(
            utf8.encode(payload),
            withoutResponse: useWithoutResponse,
          );
          if (mounted) {
            setState(() {
              _packetsSent++;
            });
          }
        } catch (e) {
          // Fallback retry with opposite mode if characteristic properties differ
          try {
            await _bleCharacteristic!.write(
              utf8.encode(payload),
              withoutResponse: !_bleCharacteristic!.properties.writeWithoutResponse,
            );
            if (mounted) {
              setState(() {
                _packetsSent++;
              });
            }
          } catch (err) {
            debugPrint('Error enviando paquete BLE: $err');
          }
        }
      }
    });
  }

  Future<void> _disconnectBLE() async {
    _sendTimer?.cancel();
    _sendTimer = null;
    _bleCharacteristic = null;

    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
      _connectedDevice = null;
    }

    _handleDisconnected();
  }

  void _handleDisconnected() {
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
    _sendTimer?.cancel();
    _accSubscription?.cancel();
    _gyroSubscription?.cancel();
    _compassSubscription?.cancel();
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _disconnectBLE();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = _connectedDevice != null && _bleCharacteristic != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Android IMU BLE Streamer',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Transmite Acelerómetro, Giroscopio y Brújula a tu ESP32-C3',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 16),

            // Connection Status Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _statusColor.withValues(alpha: 0.4), width: 1.5),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                        color: _statusColor,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _statusText,
                          style: TextStyle(
                            color: _statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  if (isConnected) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Paquetes transmitidos: $_packetsSent',
                      style: const TextStyle(color: Color(0xFF00E676), fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Connect Button
            ElevatedButton.icon(
              onPressed: _isConnecting ? null : _toggleConnection,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : Icon(
                      isConnected ? Icons.power_settings_new : Icons.bluetooth_searching,
                      color: Colors.black,
                    ),
              label: Text(
                _isConnecting
                    ? 'Conectando...'
                    : (isConnected ? 'Desconectar de ESP32-C3' : 'Conectar con ESP32C3_BLE'),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isConnected ? const Color(0xFFFF5252) : const Color(0xFF00E676),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Transmission Interval Control Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.speed, color: Color(0xFF00E676), size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Frecuencia de Envío:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                      ),
                      const Spacer(),
                      Text(
                        '$_streamIntervalMs ms',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFF00E676),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Slider(
                    value: _streamIntervalMs.toDouble(),
                    min: 100,
                    max: 3000,
                    divisions: 29,
                    activeColor: const Color(0xFF00E676),
                    inactiveColor: Colors.white12,
                    label: '$_streamIntervalMs ms',
                    onChanged: (val) => _setStreamInterval(val.round()),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildPresetChip('150 ms', 150),
                      _buildPresetChip('500 ms', 500),
                      _buildPresetChip('1.0 s', 1000),
                      _buildPresetChip('2.0 s', 2000),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Telemetry Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.sensors, color: Color(0xFF00E676)),
                      SizedBox(width: 8),
                      Text(
                        'Lectura de Sensores:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 24),

                  // Heading / Compass
                  _buildSensorRow(
                    label: 'Brújula (Heading):',
                    value: '${_heading.toStringAsFixed(1)}°',
                    icon: Icons.explore,
                    color: Colors.cyanAccent,
                  ),
                  const SizedBox(height: 16),

                  // Accelerometer
                  const Text(
                    'Acelerómetro (m/s²):',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildAxisValue('X', _accX.toStringAsFixed(2)),
                      _buildAxisValue('Y', _accY.toStringAsFixed(2)),
                      _buildAxisValue('Z', _accZ.toStringAsFixed(2)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Gyroscope
                  const Text(
                    'Giroscopio (rad/s):',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildAxisValue('X', _gyroX.toStringAsFixed(2)),
                      _buildAxisValue('Y', _gyroY.toStringAsFixed(2)),
                      _buildAxisValue('Z', _gyroZ.toStringAsFixed(2)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorRow({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 15, color: Colors.white70),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildAxisValue(String axis, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$axis: ',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white54),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: Color(0xFF00E676),
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, int valueMs) {
    bool isSelected = _streamIntervalMs == valueMs;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.black : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF00E676),
      backgroundColor: const Color(0xFF2A2A2A),
      onSelected: (_) => _setStreamInterval(valueMs),
    );
  }
}
