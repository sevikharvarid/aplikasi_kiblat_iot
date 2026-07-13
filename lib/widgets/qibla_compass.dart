// lib/widgets/qibla_compass.dart
import 'package:flutter/material.dart';
import 'dart:math' as math;

class QiblaCompass extends StatelessWidget {
  final double qiblaDirection;
  final double currentHeading;

  const QiblaCompass({
    required this.qiblaDirection,
    this.currentHeading = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate the angle difference
    double angle = qiblaDirection - currentHeading;
    
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Compass circle with degrees
          CustomPaint(
            size: Size(280, 280),
            painter: CompassPainter(),
          ),
          
          // Rotating Qibla indicator
          Transform.rotate(
            angle: angle * (math.pi / 180),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.navigation,
                  size: 80,
                  color: Color(0xFF00A896),
                ),
                SizedBox(height: 10),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Color(0xFF00A896),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${qiblaDirection.toStringAsFixed(1)}°',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Center dot
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF1A5D57),
            ),
          ),
        ],
      ),
    );
  }
}

class CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;
    
    final paint = Paint()
      ..color = Colors.grey[300]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    // Draw outer circle
    canvas.drawCircle(center, radius, paint);
    
    // Draw cardinal directions
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    
    final directions = ['N', 'E', 'S', 'W'];
    final angles = [0, 90, 180, 270];
    
    for (int i = 0; i < 4; i++) {
      final angle = angles[i] * math.pi / 180;
      final x = center.dx + (radius - 30) * math.sin(angle);
      final y = center.dy - (radius - 30) * math.cos(angle);
      
      textPainter.text = TextSpan(
        text: directions[i],
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1A5D57),
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }
    
    // Draw degree marks
    for (int i = 0; i < 360; i += 10) {
      final angle = i * math.pi / 180;
      final isMainMark = i % 30 == 0;
      
      final startRadius = isMainMark ? radius - 15 : radius - 8;
      final endRadius = radius;
      
      final start = Offset(
        center.dx + startRadius * math.sin(angle),
        center.dy - startRadius * math.cos(angle),
      );
      
      final end = Offset(
        center.dx + endRadius * math.sin(angle),
        center.dy - endRadius * math.cos(angle),
      );
      
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = isMainMark ? Color(0xFF1A5D57) : Colors.grey[400]!
          ..strokeWidth = isMainMark ? 2 : 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}