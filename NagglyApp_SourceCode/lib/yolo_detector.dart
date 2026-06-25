import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class YoloDetector {
  Interpreter? _interpreter;

  /// Charge le modèle TensorFlow Lite depuis les assets
  Future<void> loadModel() async {
    try {
      // Lit le modèle exporté depuis Colab
      _interpreter = await Interpreter.fromAsset('assets/models/best_float16.tflite');
      print('✅ Modèle YOLO TFLite chargé avec succès !');
    } catch (e) {
      print('❌ Erreur de chargement du modèle : $e');
    }
  }

  /// Exécute l'inférence YOLOv8 et recadre (crop) la Zone T
  Future<Uint8List?> detectAndCrop(Uint8List imageBytes) async {
    if (_interpreter == null) return null;

    // 1. Décodage de l'image source (ex: photo JPEG de la caméra)
    img.Image? originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) return null;

    // 2. Redimensionnement obligatoire pour YOLOv8 (640x640)
    img.Image resizedImage = img.copyResize(originalImage, width: 640, height: 640);

    // 3. Préparation du tenseur d'entrée [1, 640, 640, 3] avec normalisation [0..1]
    var input = List.generate(1, (i) => List.generate(640, (j) => List.generate(640, (k) => List.filled(3, 0.0))));
    for (int y = 0; y < 640; y++) {
      for (int x = 0; x < 640; x++) {
        var pixel = resizedImage.getPixel(x, y);
        // Normalisation entre 0.0 et 1.0 (RGB)
        input[0][y][x][0] = pixel.r / 255.0; // Red
        input[0][y][x][1] = pixel.g / 255.0; // Green
        input[0][y][x][2] = pixel.b / 255.0; // Blue
      }
    }

    // 4. Préparation du tenseur de sortie YOLOv8 [1, 6, 8400]
    // 6 = [cx, cy, w, h, confidence_classe_0, confidence_classe_1]
    // 8400 = nombre de bounding boxes générées par YOLOv8
    var output = List.generate(1, (i) => List.generate(6, (j) => List.filled(8400, 0.0)));

    // 5. INFÉRENCE ! (Exécution de l'IA sur le processeur du téléphone)
    _interpreter!.run(input, output);

    // 6. Analyse des prédictions (Parsing)
    double maxConfidence = 0;
    int bestBoxIndex = -1;
    
    for (int i = 0; i < 8400; i++) {
      double confidence = output[0][4][i]; // Classe 0 (museau)
      if (confidence > maxConfidence) {
        maxConfidence = confidence;
        bestBoxIndex = i;
      }
    }

    // Si la confiance est trop basse (ex: vache de dos), on ignore
    if (maxConfidence < 0.5 || bestBoxIndex == -1) {
      return null; 
    }

    // 7. Extraction des coordonnées YOLO de la meilleure boîte
    double cx = output[0][0][bestBoxIndex];
    double cy = output[0][1][bestBoxIndex];
    double w = output[0][2][bestBoxIndex];
    double h = output[0][3][bestBoxIndex];

    // 8. Projection sur l'image d'origine pour calculer le crop de la Zone T
    double ratioX = originalImage.width / 640.0;
    double ratioY = originalImage.height / 640.0;
    
    int left = ((cx - w / 2) * ratioX).toInt();
    int top = ((cy - h / 2) * ratioY).toInt();
    int right = ((cx + w / 2) * ratioX).toInt();
    int bottom = ((cy + h / 2) * ratioY).toInt();

    // Sécurisation des limites pour éviter un crash si YOLO dépasse de l'image
    left = left < 0 ? 0 : left;
    top = top < 0 ? 0 : top;
    right = right > originalImage.width ? originalImage.width : right;
    bottom = bottom > originalImage.height ? originalImage.height : bottom;

    // 9. Découpage (Crop) physique de la photo originale
    img.Image croppedImage = img.copyCrop(
      originalImage,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );

    // 10. Retourner l'image recadrée (Zone T prête pour le C++ OpenCV)
    return Uint8List.fromList(img.encodeJpg(croppedImage));
  }
}
