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
  roundabout(8),
  arrived(9);

  final int value;
  const TurnIcon(this.value);
}

class NavigationPacket {
  final int packetType;
  final int navState; // 0 = Idle (Sin Navegación), 1 = Active Navigation, 2 = Arrived
  final TurnIcon turnIcon;
  final int distanceMeters;
  final int totalRemainingMeters;
  final int speedKmh;
  final int headingDeg;
  final int currentHour;
  final int currentMinute;
  final String streetName;

  NavigationPacket({
    this.packetType = 1,
    required this.navState,
    required this.turnIcon,
    required this.distanceMeters,
    required this.totalRemainingMeters,
    required this.speedKmh,
    required this.headingDeg,
    required this.currentHour,
    required this.currentMinute,
    required this.streetName,
  });

  /// Serializa el paquete a un Uint8List de 28 bytes (coincidente con C++ packed struct)
  Uint8List toBytes() {
    final buffer = ByteData(28);

    buffer.setUint8(0, packetType & 0xFF);
    buffer.setUint8(1, navState & 0xFF);
    buffer.setUint8(2, turnIcon.value & 0xFF);
    buffer.setUint16(3, distanceMeters.clamp(0, 65535), Endian.little);
    buffer.setUint32(5, totalRemainingMeters.clamp(0, 4294967295), Endian.little);
    buffer.setUint8(9, speedKmh.clamp(0, 255));
    buffer.setUint16(10, headingDeg.clamp(0, 360), Endian.little);
    buffer.setUint8(12, currentHour.clamp(0, 23));
    buffer.setUint8(13, currentMinute.clamp(0, 59));

    List<int> encodedStreet = utf8.encode(streetName);
    for (int i = 0; i < 14; i++) {
      if (i < encodedStreet.length && i < 13) {
        buffer.setUint8(14 + i, encodedStreet[i]);
      } else {
        buffer.setUint8(14 + i, 0);
      }
    }

    return buffer.buffer.asUint8List();
  }
}
