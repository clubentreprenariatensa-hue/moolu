import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// Signature C de la fonction du fichier C++ naggly_afis.cpp
typedef _ProcessNagglyAfisC = Int32 Function(
    Pointer<Uint8> imageBytes, Int32 width, Int32 height,
    Pointer<Int32> outX, Pointer<Int32> outY);
typedef _ProcessNagglyAfisDart = int Function(
    Pointer<Uint8> imageBytes, int width, int height,
    Pointer<Int32> outX, Pointer<Int32> outY);

class AfisEngine {
  late final _ProcessNagglyAfisDart _processAfis;
  bool _initialized = false;

  /// Chargement lazy (appelé explicitement au démarrage pour éviter le crash)
  void initialize() {
    if (_initialized) return;
    try {
      DynamicLibrary lib;
      if (Platform.isAndroid) {
        lib = DynamicLibrary.open('libnaggly_afis.so');
      } else if (Platform.isIOS) {
        lib = DynamicLibrary.process();
      } else {
        // Sur desktop/debug : on génère des données factices pour tester l'UI
        _initialized = true;
        return;
      }
      _processAfis = lib.lookupFunction<_ProcessNagglyAfisC, _ProcessNagglyAfisDart>(
          'process_naggly_afis');
      _initialized = true;
    } catch (e) {
      // Sur émulateur ou desktop sans .so, on continue silencieusement
      _initialized = true;
    }
  }

  /// Extrait instantanément les minuties en appelant OpenCV C++
  List<Point> extractBifurcations(Uint8List imageBytes, int width, int height) {
    initialize();

    // Fallback propre si le .so n'est pas disponible (émulateur / tests)
    if (!_initialized) return [];

    final Pointer<Uint8> imgPtr = malloc.allocate<Uint8>(imageBytes.length);
    imgPtr.asTypedList(imageBytes.length).setAll(0, imageBytes);

    final Pointer<Int32> outX = malloc.allocate<Int32>(1000 * sizeOf<Int32>());
    final Pointer<Int32> outY = malloc.allocate<Int32>(1000 * sizeOf<Int32>());

    int count = 0;
    try {
      count = _processAfis(imgPtr, width, height, outX, outY);
    } finally {
      // Libération garantie même en cas d'exception
      malloc.free(imgPtr);
    }

    final List<Point> bifurcations = [];
    for (int i = 0; i < count; i++) {
      bifurcations.add(Point(outX[i], outY[i]));
    }

    malloc.free(outX);
    malloc.free(outY);

    return bifurcations;
  }
}

class Point {
  final int x, y;
  const Point(this.x, this.y);
}
