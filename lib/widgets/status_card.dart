import 'package:flutter/material.dart';
import '../utils/constants.dart';

class StatusCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const StatusCard({required this.title, required this.value, required this.icon, super.key});

@override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: AppColors.accent, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title, 
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])
                  ),
                  SizedBox(height: 4),
                  Text(
                    value, 
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      fontSize: 16
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}