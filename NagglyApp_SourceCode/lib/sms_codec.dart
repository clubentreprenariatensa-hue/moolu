import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'afis_engine.dart'; // Pour la classe Point

class SMSCodec {
  /// Encodage Lossless (Delta + Zlib + Base64Url)
  static String encode(List<Point> bifurcations) {
    if (bifurcations.isEmpty) return "";

    // 1. Tri spatial pour maximiser la compression Delta
    bifurcations.sort((a, b) =>
        a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));

    List<int> deltaEncoded = [];
    int prevX = 0, prevY = 0;

    for (var pt in bifurcations) {
      deltaEncoded.add(pt.x - prevX);
      deltaEncoded.add(pt.y - prevY);
      prevX = pt.x;
      prevY = pt.y;
    }

    // 2. Conversion en bytes (entiers signés sur 16 bits)
    final bytes = ByteData(deltaEncoded.length * 2);
    for (int i = 0; i < deltaEncoded.length; i++) {
      bytes.setInt16(i * 2, deltaEncoded[i], Endian.little);
    }

    // 3. Compression Zlib (sans perte)
    final compressed = ZLibEncoder().encode(bytes.buffer.asUint8List());

    // 4. Encodage URL-safe Base64 (SANS padding '=' pour SMS)
    return base64Url.encode(compressed).replaceAll('=', '');
  }

  /// Décodage instantané du SMS
  static List<Point> decode(String smsString) {
    // 1. Ré-ajout du padding si nécessaire avant décodage Base64
    final padded = smsString + '=' * ((4 - smsString.length % 4) % 4);
    final compressed = base64Url.decode(padded);

    // 2. Décompression Zlib
    final decompressed = ZLibDecoder().decodeBytes(compressed);

    // 3. Lecture des Deltas (chaque point = 2 x int16 = 4 octets)
    final bytes = ByteData.sublistView(Uint8List.fromList(decompressed));
    final List<Point> bifurcations = [];
    int prevX = 0, prevY = 0;

    // Chaque point occupe 4 octets (dx sur 2 + dy sur 2)
    final pointCount = bytes.lengthInBytes ~/ 4;
    for (int i = 0; i < pointCount; i++) {
      final dx = bytes.getInt16(i * 4,     Endian.little);
      final dy = bytes.getInt16(i * 4 + 2, Endian.little);
      final x = prevX + dx;
      final y = prevY + dy;
      bifurcations.add(Point(x, y));
      prevX = x;
      prevY = y;
    }

    return bifurcations;
  }
}
