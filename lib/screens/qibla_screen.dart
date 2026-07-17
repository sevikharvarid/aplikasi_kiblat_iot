// lib/screens/qibla_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:async';
import '../services/qibla_bluetooth.dart';
import '../services/qibla_calculator.dart';
import '../widgets/status_card.dart';
import '../widgets/qibla_compass.dart';
import '../utils/constants.dart';

class QiblaScreen extends StatefulWidget {
  final double lat, lng, qibla, declination;
  final String locationName;

  const QiblaScreen({
    required this.lat,
    required this.lng,
    required this.qibla,
    required this.declination,
    required this.locationName,
    super.key,
  });

  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
}

class _QiblaScreenState extends State<QiblaScreen> {
  String response = "Belum terhubung";
  bool isSending = false;

  // Heading dari sensor HP → hanya untuk ditampilkan di "Sudut Kompas Internal"
  double currentHeading = 0;
  StreamSubscription<CompassEvent>? compassSubscription;

  // Heading dari BNO055 di ESP32 → DIPAKAI OLEH COMPASS & ditampilkan
  double bnoHeading = 0.0;
  StreamSubscription<double>? bnoSubscription;

  // Adjusted Qibla angle (calculated based on current BNO heading)
  double adjustedQiblaAngle = 0.0;

  // Deklinasi magnetik, dihitung lokal di app (magnetic_declination package)
  late double declination = widget.declination;

  // Status kesejajaran shaf, dihitung dari selisih bnoHeading vs bearing kiblat
  ShafResult shaf = const ShafResult("Menghitung...", 0);

  @override
  void initState() {
    super.initState();

    // Respon umum dari ESP32
    QiblaBluetooth.responseController.stream.listen((msg) {
      if (mounted) {
        setState(() {
          response = msg;
          isSending = false;
        });
      }
    });

    // Kompas HP (hanya untuk ditampilkan di teks)
    compassSubscription = FlutterCompass.events?.listen((event) {
      if (mounted && event.heading != null) {
        setState(() {
          currentHeading = event.heading!;
        });
      }
    });

    // Data BNO dari ESP32 → DIGUNAKAN UNTUK COMPASS WIDGET & perhitungan adjusted angle
    bnoSubscription = QiblaBluetooth.bnoHeadingController.stream.listen((heading) {
      if (mounted) {
        setState(() {
          bnoHeading = heading;
          // Update adjusted qibla angle berdasarkan BNO heading terkini
          adjustedQiblaAngle = _calculateAdjustedQiblaAngle(heading);
          shaf = QiblaCalculator.calculateShaf(widget.qibla, heading);
        });
      }
    });

    // Initialize adjusted qibla angle & shaf
    adjustedQiblaAngle = _calculateAdjustedQiblaAngle(bnoHeading);
    shaf = QiblaCalculator.calculateShaf(widget.qibla, bnoHeading);
  }

  @override
  void dispose() {
    compassSubscription?.cancel();
    bnoSubscription?.cancel();
    super.dispose();
  }

  // Calculate adjusted qibla angle relative to current BNO heading
  double _calculateAdjustedQiblaAngle(double currentBnoHeading) {
    double angle = widget.qibla - currentBnoHeading;
    
    // Normalize angle to 0-360 range (selalu positif)
    angle = angle % 360;
    if (angle < 0) {
      angle += 360;
    }
    
    return angle;
  }

  // Tombol 1: kirim sudut kiblat saja — format *<bearing>K
  void _sendBearingOnly() async {
    setState(() {
      isSending = true;
      response = "Mengirim sudut kiblat...";
    });
    try {
      await QiblaBluetooth.sendQiblaBearing(widget.qibla);
    } catch (e) {
      setState(() {
        response = "Error: $e";
        isSending = false;
      });
    }
  }

  // Tombol 2: kirim deklinasi + lokasi saja — format *<decl>D <lat>L <lng>N
  void _sendDeclinationLocationOnly() async {
    setState(() {
      isSending = true;
      response = "Mengirim deklinasi & lokasi...";
    });
    try {
      await QiblaBluetooth.sendDeclinationLocation(declination, widget.lat, widget.lng);
    } catch (e) {
      setState(() {
        response = "Error: $e";
        isSending = false;
      });
    }
  }

  // Kirim semua data lengkap (gabungan tombol 1 + tombol 2)
  void _sendAll() async {
    setState(() {
      isSending = true;
      response = "Mengirim semua data...";
    });
    try {
      await QiblaBluetooth.sendAllData(widget.qibla, declination, widget.lat, widget.lng);
    } catch (e) {
      setState(() {
        response = "Error: $e";
        isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text("Arah Kiblat", style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),

      // KONTEN UTAMA (bisa discroll)
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100), // kasih space bawah buat tombol
        child: Column(
          children: [
            // Location Header
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.location_city, color: AppColors.primary, size: 30),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.locationName,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            "${widget.lat.toStringAsFixed(6)}, ${widget.lng.toStringAsFixed(6)}",
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 12),

            // Tombol 2: kirim deklinasi + lokasi saja
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isSending ? null : _sendDeclinationLocationOnly,
                icon: Icon(Icons.location_on, color: AppColors.primary),
                label: Text(
                  "Kirim Deklinasi + Lokasi",
                  style: TextStyle(color: AppColors.primary, fontSize: 14),
                ),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: AppColors.primary, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            SizedBox(height: 20),

            // WIDGET COMPASS → MENGGUNAKAN bnoHeading (dari ESP32 BNO055)
            QiblaCompass(
              qiblaDirection: adjustedQiblaAngle,
              currentHeading: bnoHeading,
            ),

            SizedBox(height: 12),

            // Tombol 1: kirim sudut kiblat saja
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isSending ? null : _sendBearingOnly,
                icon: Icon(Icons.explore, color: AppColors.accent),
                label: Text(
                  "Kirim Sudut Kiblat",
                  style: TextStyle(color: AppColors.accent, fontSize: 14),
                ),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: AppColors.accent, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            SizedBox(height: 20),

            // Direction Info
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, spreadRadius: 2),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildDirectionInfo(
                    "Sudut BNO",
                    "${bnoHeading.toStringAsFixed(1)}°",
                    Icons.navigation,
                    AppColors.accent,
                  ),
                  Container(height: 50, width: 1, color: Colors.grey[300]),
                  _buildDirectionInfo(
                    "Sudut Kompas Internal",
                    "${currentHeading.toStringAsFixed(1)}°",
                    Icons.navigation,
                    AppColors.primary,
                  ),
                ],
              ),
            ),

            SizedBox(height: 20),

            // Status Cards
            StatusCard(
              title: "Status Shaf",
              value: shaf.label,
              icon: shaf.label == "Shaf Lurus" ? Icons.check_circle : Icons.swap_horiz,
            ),

            SizedBox(height: 20),

            StatusCard(
              title: "Deklinasi Magnetik",
              value: "${declination.toStringAsFixed(2)}°",
              icon: Icons.explore,
            ),

            SizedBox(height: 20),

            StatusCard(
              title: "Respon ESP32",
              value: response,
              icon: Icons.device_hub,
            ),

            SizedBox(height: 20),

            // Info Text
            Text(
              "Kompas menggunakan sensor BNO055 dari ESP32. Arahkan perangkat ke arah panah hijau untuk menemukan kiblat.",
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: 80), // space ekstra biar tombol tidak tertutup
          ],
        ),
      ),

      // TOMBOL FLOATING & FIXED DI BAWAH (selalu terlihat!)
      floatingActionButton: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        width: double.infinity,
        height: 56,
        child: FloatingActionButton.extended(
          onPressed: isSending ? null : _sendAll,
          backgroundColor: isSending ? Colors.grey[400] : AppColors.accent,
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSending)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              if (isSending) const SizedBox(width: 12),
              Text(
                isSending ? "Mengirim..." : "Kirim Semua Data Lengkap",
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (!isSending) ...[
                const SizedBox(width: 12),
                const Icon(Icons.send, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildDirectionInfo(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 30),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}