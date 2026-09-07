import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.locationAlways,
      Permission.notification,
    ].request();

    return statuses[Permission.locationWhenInUse]?.isGranted ?? false;
  }

  Future<LatLng?> getCurrentUserPosition() async {
    bool locationGranted = await Geolocator.isLocationServiceEnabled();
    if (!locationGranted) return null;

    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }
}
