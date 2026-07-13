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
}