import 'dart:math';

class QiblaCalculator {
  static const double kaabaLat = 21.4225;
  static const double kaabaLng = 39.8262;

  static double calculate(double lat, double lng) {
    final double lat1 = lat * pi / 180;
    final double lng1 = lng * pi / 180;
    final double lat2 = kaabaLat * pi / 180;
    final double lng2 = kaabaLng * pi / 180;

    final double dLng = lng2 - lng1;

    final double y = sin(dLng);
    final double x = cos(lat1) * tan(lat2) - sin(lat1) * cos(dLng);

    double bearing = atan2(y, x) * 180 / pi;
    bearing = (bearing + 360) % 360;

    return bearing;
  }

  // Status kesejajaran (shaf) terhadap arah kiblat, dari selisih heading
  // kompas saat ini terhadap bearing kiblat. Toleransi default 3° dianggap lurus.
  static ShafResult calculateShaf(
    double qiblaBearing,
    double currentHeading, {
    double tolerance = 3,
  }) {
    double diff = (qiblaBearing - currentHeading) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    if (diff.abs() <= tolerance) {
      return ShafResult("Shaf Lurus", diff);
    } else if (diff > 0) {
      return ShafResult("Geser Kanan ${diff.toStringAsFixed(1)}°", diff);
    } else {
      return ShafResult("Geser Kiri ${(-diff).toStringAsFixed(1)}°", diff);
    }
  }
}

class ShafResult {
  final String label;
  final double offsetDeg;
  const ShafResult(this.label, this.offsetDeg);
}