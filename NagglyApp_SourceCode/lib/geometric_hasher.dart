import 'dart:math';
import 'afis_engine.dart';
import 'delaunay.dart';

/// Geometric Hashing : Transforme les bifurcations en signatures topologiques
/// invariantes à la rotation et à la translation.
/// C'est l'équivalent exact de FastAFISIndex du code Python Colab.

class GeometricHasher {
  /// Quantification des longueurs (arrondi à 5 pixels près)
  /// Identique au Python : permet de tolérer de légères variations
  static const int _quantizationStep = 5;

  /// Extrait les signatures "L1_L2_L3" à partir d'une liste de bifurcations.
  /// Chaque triangle de Delaunay génère une clé unique basée sur ses 3 côtés triés.
  static List<String> extractSignatures(List<Point> bifurcations) {
    if (bifurcations.length < 3) return [];

    // 1. Triangulation de Delaunay (Bowyer-Watson en Dart pur)
    final List<Triangle> triangles = Delaunay.triangulate(bifurcations);

    // 2. Pour chaque triangle, calculer les longueurs des 3 côtés
    final Set<String> signatures = {};

    for (final tri in triangles) {
      double l1 = _distance(tri.a, tri.b);
      double l2 = _distance(tri.b, tri.c);
      double l3 = _distance(tri.c, tri.a);

      // 3. Quantifier (arrondir) les longueurs
      int q1 = (l1 / _quantizationStep).round();
      int q2 = (l2 / _quantizationStep).round();
      int q3 = (l3 / _quantizationStep).round();

      // 4. Trier les longueurs pour garantir l'invariance à la rotation
      // Triangle ABC = Triangle BCA = Triangle CAB → même signature
      List<int> sorted = [q1, q2, q3]..sort();

      // 5. Générer la clé unique "L1_L2_L3"
      String sig = '${sorted[0]}_${sorted[1]}_${sorted[2]}';
      signatures.add(sig); // Le Set élimine les doublons automatiquement
    }

    return signatures.toList();
  }

  /// Distance euclidienne entre deux points
  static double _distance(Point a, Point b) {
    final dx = (a.x - b.x).toDouble();
    final dy = (a.y - b.y).toDouble();
    return sqrt(dx * dx + dy * dy);
  }
}
