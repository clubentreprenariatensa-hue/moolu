import 'dart:math';
import 'afis_engine.dart'; // Pour la classe Point

/// Implémentation de la Triangulation de Delaunay (Algorithme Bowyer-Watson)
/// Transforme une liste de bifurcations (x,y) en triangles optimaux.
/// Complexité : O(n log n) — instantané pour 200 points.

class Triangle {
  final Point a, b, c;
  const Triangle(this.a, this.b, this.c);

  /// Vérifie si un point P est à l'intérieur du cercle circonscrit du triangle
  bool circumcircleContains(Point p) {
    final double ax = a.x.toDouble(), ay = a.y.toDouble();
    final double bx = b.x.toDouble(), by = b.y.toDouble();
    final double cx = c.x.toDouble(), cy = c.y.toDouble();
    final double px = p.x.toDouble(), py = p.y.toDouble();

    final double d = 2.0 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by));
    if (d.abs() < 1e-10) return false;

    final double ux = ((ax * ax + ay * ay) * (by - cy) +
                        (bx * bx + by * by) * (cy - ay) +
                        (cx * cx + cy * cy) * (ay - by)) / d;
    final double uy = ((ax * ax + ay * ay) * (cx - bx) +
                        (bx * bx + by * by) * (ax - cx) +
                        (cx * cx + cy * cy) * (bx - ax)) / d;

    final double r2 = (ax - ux) * (ax - ux) + (ay - uy) * (ay - uy);
    final double dist2 = (px - ux) * (px - ux) + (py - uy) * (py - uy);

    return dist2 <= r2;
  }

  /// Vérifie si le triangle contient un sommet d'un super-triangle
  bool containsVertex(Point p) {
    return (a.x == p.x && a.y == p.y) ||
           (b.x == p.x && b.y == p.y) ||
           (c.x == p.x && c.y == p.y);
  }

  List<Edge> get edges => [
    Edge(a, b),
    Edge(b, c),
    Edge(c, a),
  ];
}

class Edge {
  final Point p1, p2;
  const Edge(this.p1, this.p2);

  @override
  bool operator ==(Object other) {
    if (other is! Edge) return false;
    return (p1.x == other.p1.x && p1.y == other.p1.y &&
            p2.x == other.p2.x && p2.y == other.p2.y) ||
           (p1.x == other.p2.x && p1.y == other.p2.y &&
            p2.x == other.p1.x && p2.y == other.p1.y);
  }

  @override
  int get hashCode {
    // Hash symétrique : Edge(A,B) == Edge(B,A)
    final int h1 = p1.x * 31 + p1.y;
    final int h2 = p2.x * 31 + p2.y;
    return h1 < h2 ? h1 * 37 + h2 : h2 * 37 + h1;
  }
}

class Delaunay {
  /// Algorithme Bowyer-Watson : génère les triangles de Delaunay
  static List<Triangle> triangulate(List<Point> points) {
    if (points.length < 3) return [];

    // 1. Calcul du super-triangle (englobe tous les points)
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final p in points) {
      if (p.x < minX) minX = p.x.toDouble();
      if (p.y < minY) minY = p.y.toDouble();
      if (p.x > maxX) maxX = p.x.toDouble();
      if (p.y > maxY) maxY = p.y.toDouble();
    }

    final double dx = maxX - minX;
    final double dy = maxY - minY;
    final double deltaMax = max(dx, dy);
    final double midX = (minX + maxX) / 2;
    final double midY = (minY + maxY) / 2;

    final Point superA = Point((midX - 2 * deltaMax).toInt(), (midY - deltaMax).toInt());
    final Point superB = Point((midX + 2 * deltaMax).toInt(), (midY - deltaMax).toInt());
    final Point superC = Point((midX).toInt(), (midY + 2 * deltaMax).toInt());
    final Triangle superTriangle = Triangle(superA, superB, superC);

    List<Triangle> triangles = [superTriangle];

    // 2. Insertion incrémentale de chaque point
    for (final point in points) {
      List<Triangle> badTriangles = [];

      // Trouver tous les triangles dont le cercle circonscrit contient le point
      for (final tri in triangles) {
        if (tri.circumcircleContains(point)) {
          badTriangles.add(tri);
        }
      }

      // Trouver les arêtes du polygone (arêtes non partagées)
      List<Edge> polygon = [];
      for (final tri in badTriangles) {
        for (final edge in tri.edges) {
          bool shared = false;
          for (final other in badTriangles) {
            if (identical(tri, other)) continue;
            for (final otherEdge in other.edges) {
              if (edge == otherEdge) {
                shared = true;
                break;
              }
            }
            if (shared) break;
          }
          if (!shared) polygon.add(edge);
        }
      }

      // Retirer les mauvais triangles
      triangles.removeWhere((t) => badTriangles.contains(t));

      // Créer de nouveaux triangles avec le point et chaque arête du polygone
      for (final edge in polygon) {
        triangles.add(Triangle(edge.p1, edge.p2, point));
      }
    }

    // 3. Retirer tous les triangles connectés au super-triangle
    triangles.removeWhere((t) =>
      t.containsVertex(superA) ||
      t.containsVertex(superB) ||
      t.containsVertex(superC));

    return triangles;
  }
}
