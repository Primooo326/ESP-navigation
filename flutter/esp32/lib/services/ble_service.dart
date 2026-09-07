import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static const String targetDeviceName = 'ESP32C3_BLE';
  static final Guid serviceUuid = Guid('4fa1c201-1fb5-459e-8fcc-c5c9c331914b');
  static final Guid characteristicUuid = Guid('beb5483e-36e1-4688-b7f5-ea07361b26a8');

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _bleCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;

  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isConnectingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> statusTextNotifier = ValueNotifier<String>('Desconectado');
  final ValueNotifier<int> packetsSentNotifier = ValueNotifier<int>(0);

  BluetoothDevice? get connectedDevice => _connectedDevice;
  BluetoothCharacteristic? get bleCharacteristic => _bleCharacteristic;

  Future<void> checkAndAutoConnect() async {
    try {
      // 1. Verificar si el ESP32 ya está emparejado/conectado a nivel del sistema Android
      List<BluetoothDevice> connected = FlutterBluePlus.connectedDevices;
      for (BluetoothDevice dev in connected) {
        if (dev.platformName == targetDeviceName || dev.remoteId.str.contains('ESP32')) {
          _connectedDevice = dev;
          await _setupConnectedDevice(dev);
          return;
        }
      }
      // 2. Si no está conectado, iniciar escaneo y auto-conexión en segundo plano
      if (!isConnectedNotifier.value && !isConnectingNotifier.value) {
        connect();
      }
    } catch (e) {
      debugPrint('Auto-connect BLE error: $e');
    }
  }

  Future<void> toggleConnection() async {
    if (_connectedDevice != null || isConnectingNotifier.value) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<void> connect() async {
    isConnectingNotifier.value = true;
    statusTextNotifier.value = 'Buscando ESP32C3_BLE...';

    try {
      await FlutterBluePlus.stopScan();
      Completer<BluetoothDevice?> completer = Completer();

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName == targetDeviceName ||
              r.advertisementData.advName == targetDeviceName ||
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
        isConnectingNotifier.value = false;
        statusTextNotifier.value = 'ESP32C3_BLE no encontrado';
        return;
      }

      statusTextNotifier.value = 'Conectando a ESP32...';
      await dev.connect(timeout: const Duration(seconds: 10));
      await _setupConnectedDevice(dev);
    } catch (e) {
      await disconnect();
      isConnectingNotifier.value = false;
      statusTextNotifier.value = 'Error BLE: $e';
    }
  }

  Future<void> _setupConnectedDevice(BluetoothDevice dev) async {
    _connectedDevice = dev;
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = dev.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _handleDisconnected();
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
      isConnectingNotifier.value = false;
      statusTextNotifier.value = 'Característica no encontrada';
      return;
    }

    packetsSentNotifier.value = 0;
    isConnectingNotifier.value = false;
    isConnectedNotifier.value = true;
    statusTextNotifier.value = '¡CONECTADO AL ESP32!';
  }

  Future<void> sendPacketBytes(Uint8List bytes) async {
    if (_bleCharacteristic != null && _connectedDevice != null) {
      try {
        bool withoutResponse = _bleCharacteristic!.properties.writeWithoutResponse;
        await _bleCharacteristic!.write(bytes, withoutResponse: withoutResponse);
        packetsSentNotifier.value++;
      } catch (e) {
        debugPrint('Error enviando paquete BLE: $e');
      }
    }
  }

  Future<void> disconnect() async {
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
    isConnectingNotifier.value = false;
    isConnectedNotifier.value = false;
    _connectedDevice = null;
    _bleCharacteristic = null;
    statusTextNotifier.value = 'Desconectado';
  }

  void dispose() {
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    disconnect();
  }
}
