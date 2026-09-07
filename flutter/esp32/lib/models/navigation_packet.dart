import 'dart:convert';
import 'dart:typed_data';

enum TurnIcon {
  none(0),
  straight(1),
  turnRight(2),
  turnLeft(3),
  slightRight(4),
  slightLeft(5),
  sharpRight(6),
  sharpLeft(7),
  roundaboutExit1(8),
  arrived(9),
  roundaboutExit2(10),
  roundaboutExit3(11),
  roundaboutExit4(12),
  uTurn(13),
  forkRight(14),
  forkLeft(15),
  onRamp(16),
  offRamp(17);

  final int value;
  const TurnIcon(this.value);
}

class NavigationPacket {
  final int packetType;
  final int navState; // 0 = Idle, 1 = Active Navigation, 2 = Arrived
  final TurnIcon turnIcon;
  final int distanceMeters;
  final int totalRemainingMeters;
  final int speedKmh;
  final int headingDeg;        // Ángulo relativo hacia próxima maniobra
  final int vehicleHeadingDeg; // Rumbo real de brújula del vehículo (0-360)
  final int currentHour;
  final int currentMinute;
  final int temperatureC;
  final int weatherCode;
  final int finalHeadingDeg; // Ángulo relativo hacia el destino final (0-360)
  final String streetName;

  NavigationPacket({
    this.packetType = 1,
    required this.navState,
    required this.turnIcon,
    required this.distanceMeters,
    required this.totalRemainingMeters,
    required this.speedKmh,
    required this.headingDeg,
    required this.vehicleHeadingDeg,
    required this.currentHour,
    required this.currentMinute,
    this.temperatureC = 20,
    this.weatherCode = 0,
    this.finalHeadingDeg = 0,
    required this.streetName,
  });

  /// Serializa el paquete a un Uint8List de 32 bytes (coincidente con C++ packed struct)
  Uint8List toBytes() {
    final buffer = ByteData(32);

    buffer.setUint8(0, packetType & 0xFF);
    buffer.setUint8(1, navState & 0xFF);
    buffer.setUint8(2, turnIcon.value & 0xFF);
    buffer.setUint16(3, distanceMeters.clamp(0, 65535), Endian.little);
    buffer.setUint32(5, totalRemainingMeters.clamp(0, 4294967295), Endian.little);
    buffer.setUint8(9, speedKmh.clamp(0, 255));
    buffer.setUint16(10, headingDeg.clamp(0, 360), Endian.little);
    buffer.setUint16(12, vehicleHeadingDeg.clamp(0, 360), Endian.little);
    buffer.setUint8(14, currentHour.clamp(0, 23));
    buffer.setUint8(15, currentMinute.clamp(0, 59));
    buffer.setInt8(16, temperatureC.clamp(-50, 50));
    buffer.setUint8(17, weatherCode.clamp(0, 255));
    buffer.setUint16(18, finalHeadingDeg.clamp(0, 360), Endian.little);

    List<int> encodedStreet = utf8.encode(streetName);
    for (int i = 0; i < 12; i++) {
      if (i < encodedStreet.length && i < 11) {
        buffer.setUint8(20 + i, encodedStreet[i]);
      } else {
        buffer.setUint8(20 + i, 0);
      }
    }

    return buffer.buffer.asUint8List();
  }
}
