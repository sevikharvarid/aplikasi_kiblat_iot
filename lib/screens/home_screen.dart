import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'package:geocoding/geocoding.dart';
import 'package:geomag/geomag.dart';
import '../services/location_service.dart';
import '../services/qibla_calculator.dart';
import '../services/qibla_bluetooth.dart';
import '../services/permission_service.dart';
import '../widgets/status_card.dart';
import 'qibla_screen.dart';
import '../utils/constants.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool isScanning = false;
  List<ScanResult> devices = [];
  String status = "Tekan tombol untuk scan Bluetooth";
  double? lat, lng, qibla, declination;
  String? locationName;

  final GeoMag _geoMag = GeoMag();

  bool isLocationEnabled = false;
  bool isBluetoothEnabled = false;
  
  Timer? _statusCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    QiblaBluetooth.responseController.stream.listen((msg) {
      if (mounted) {
        setState(() => status = msg);
      }
    });

    _checkInitialStatus();
    _startStatusMonitoring();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusCheckTimer?.cancel();
    QiblaBluetooth.stopScan();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check when app comes to foreground
      _checkServicesStatus();
    }
  }

  // Check initial status
  Future<void> _checkInitialStatus() async {
    await _checkServicesStatus();
  }

  // Start continuous monitoring
  void _startStatusMonitoring() {
    _statusCheckTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      _checkServicesStatus();
    });
  }

  // Check services status (GPS & Bluetooth)
  Future<void> _checkServicesStatus() async {
    final locationEnabled = await PermissionService.isLocationServiceEnabled();
    final bluetoothEnabled = await PermissionService.isBluetoothEnabled();
    
    if (mounted) {
      setState(() {
        isLocationEnabled = locationEnabled;
        isBluetoothEnabled = bluetoothEnabled;
      });
    }
  }

  // Get real location name from coordinates using geocoding
  Future<String> _getLocationName(double latitude, double longitude) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
      
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        List<String> locationParts = [];
        
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          locationParts.add(place.subLocality!);
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          locationParts.add(place.locality!);
        }
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
          locationParts.add(place.administrativeArea!);
        }
        if (place.country != null && place.country!.isNotEmpty) {
          locationParts.add(place.country!);
        }
        
        return locationParts.isNotEmpty ? locationParts.join(", ") : "Unknown Location";
      }
      
      return "Unknown Location";
    } catch (e) {
      print("Error getting location name: $e");
      return "Lat: ${latitude.toStringAsFixed(4)}, Lng: ${longitude.toStringAsFixed(4)}";
    }
  }

  // Hitung deklinasi magnetik lokal (WMM, murni Dart) — gak perlu nunggu ESP32.
  double _getDeclination(double latitude, double longitude, double altitudeMeters) {
    try {
      final heightFeet = altitudeMeters / 0.3048; // geomag pakai satuan feet
      final result = _geoMag.calculate(latitude, longitude, heightFeet, DateTime.now());
      // Hindari "-0.0" (negative zero) saat dibulatkan 1 desimal — cuma artefak
      // floating-point, bukan nilai beda; snap ke 0.0 murni kalau rounding-nya nol.
      final rounded = double.parse(result.dec.toStringAsFixed(1));
      return rounded == 0 ? 0.0 : result.dec;
    } catch (e) {
      print("Error calculating declination: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal hitung deklinasi: $e")),
        );
      }
      return 0;
    }
  }

  // Get Location with full checks
  Future<void> _getLocationOnly() async {
    try {
      // Check and request Location service & permission
      bool hasLocationAccess = await PermissionService.checkAndRequestLocation(context);
      if (!hasLocationAccess) {
        setState(() => status = "GPS atau izin lokasi tidak aktif");
        return;
      }

      setState(() => status = "Mengambil lokasi...");
      
      final pos = await LocationService.getCurrentLocation();
      final angle = QiblaCalculator.calculate(pos.latitude, pos.longitude);

      // Get real location name from coordinates
      String realLocationName = await _getLocationName(pos.latitude, pos.longitude);
      double decl = _getDeclination(pos.latitude, pos.longitude, pos.altitude);

      setState(() {
        lat = pos.latitude;
        lng = pos.longitude;
        qibla = angle;
        declination = decl;
        locationName = realLocationName;
        status = "Lokasi berhasil diambil";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Arah Kiblat: ${angle.toStringAsFixed(1)}°"),
          backgroundColor: Colors.green,
        )
      );
    } catch (e) {
      setState(() => status = "Error: ${e.toString()}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${e.toString()}"))
      );
    }
  }

  // Scan Bluetooth with full checks
  void _startScan() async {
    // Check and request Bluetooth service & permissions
    bool hasBluetoothAccess = await PermissionService.checkAndRequestBluetooth(context);
    if (!hasBluetoothAccess) {
      setState(() => status = "Bluetooth atau izin tidak aktif");
      return;
    }

    setState(() {
      isScanning = true;
      devices.clear();
      status = "Scanning...";
    });

    await QiblaBluetooth.startScan();
    
    QiblaBluetooth.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          devices = results.where((r) => r.device.platformName.isNotEmpty).toList();
        });
      }
    });

    await Future.delayed(Duration(seconds: 4));
    if (mounted) {
      setState(() {
        isScanning = false;
        status = devices.isEmpty ? "Tidak ada perangkat" : "Pilih perangkat";
      });
    }
  }

  // Connect to device
  void _connectAndProceed(BluetoothDevice device) async {
    try {
      setState(() => status = "Menghubungkan...");
      
      await QiblaBluetooth.connectToDevice(device);
      
      // Check Location again before proceeding
      bool hasLocationAccess = await PermissionService.checkAndRequestLocation(context);
      if (!hasLocationAccess) {
        setState(() => status = "GPS diperlukan untuk melanjutkan");
        return;
      }

      setState(() => status = "Mengambil lokasi...");
      final pos = await LocationService.getCurrentLocation();
      final angle = QiblaCalculator.calculate(pos.latitude, pos.longitude);

      // Get real location name from coordinates
      String realLocationName = await _getLocationName(pos.latitude, pos.longitude);
      double decl = _getDeclination(pos.latitude, pos.longitude, pos.altitude);

      setState(() {
        lat = pos.latitude;
        lng = pos.longitude;
        qibla = angle;
        declination = decl;
        locationName = realLocationName;
        status = "Berhasil terhubung";
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QiblaScreen(
            lat: lat!,
            lng: lng!,
            qibla: qibla!,
            declination: declination ?? 0,
            locationName: locationName!,
          ),
        ),
      );
    } catch (e) {
      setState(() => status = "Error: ${e.toString()}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${e.toString()}"))
      );
    }
  }

  void _navigateToQiblaScreen() {
    if (lat != null && lng != null && qibla != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QiblaScreen(
            lat: lat!,
            lng: lng!,
            qibla: qibla!,
            declination: declination ?? 0,
            locationName: locationName ?? "Unknown",
          ),
        ),
      );
    }
  }

  // Manual enable Location
  Future<void> _enableLocation() async {
    await PermissionService.requestLocationService(context);
    await _checkServicesStatus();
  }

  // Manual enable Bluetooth
  Future<void> _enableBluetooth() async {
    await PermissionService.requestBluetoothService(context);
    await _checkServicesStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text("Qibla Finder", style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          // Refresh button
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _checkServicesStatus,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Service Status Card
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      "Status Layanan",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildServiceStatus(
                          "GPS",
                          isLocationEnabled,
                          Icons.location_on,
                          _enableLocation,
                        ),
                        Container(
                          height: 50,
                          width: 1,
                          color: Colors.grey[300],
                        ),
                        _buildServiceStatus(
                          "Bluetooth",
                          isBluetoothEnabled,
                          Icons.bluetooth,
                          _enableBluetooth,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 20),
            
            // Location Info Card
            if (lat != null && lng != null)
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.location_on, size: 40, color: AppColors.primary),
                      SizedBox(height: 10),
                      Text(
                        locationName ?? "Location",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 5),
                      Text(
                        "${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}",
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Deklinasi: ${declination?.toStringAsFixed(2) ?? '-'}°",
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      SizedBox(height: 10),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.explore, color: AppColors.accent),
                            SizedBox(width: 8),
                            Text(
                              "Kiblat: ${qibla!.toStringAsFixed(1)}°",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            SizedBox(height: 20),
            
            StatusCard(title: "Status BT", value: status, icon: Icons.bluetooth),
            
            SizedBox(height: 20),
            
            // Get Location Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _getLocationOnly,
                icon: Icon(Icons.my_location, color: Colors.white),
                label: Text(
                  "Ambil Lokasi GPS",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            
            SizedBox(height: 10),
            
            // Scan Bluetooth Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isScanning ? null : _startScan,
                icon: Icon(Icons.search, color: Colors.white),
                label: Text(
                  isScanning ? "Scanning..." : "Scan ESP32",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            // Show Qibla Direction Button
            if (lat != null && lng != null && qibla != null) ...[
              SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _navigateToQiblaScreen,
                  icon: Icon(Icons.explore, color: AppColors.primary),
                  label: Text(
                    "Lihat Arah Kiblat",
                    style: TextStyle(color: AppColors.primary, fontSize: 16),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 15),
                    side: BorderSide(color: AppColors.primary, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
            
            SizedBox(height: 20),
            
            // Device List
            if (devices.isNotEmpty) ...[
              Text(
                "Perangkat Ditemukan",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(height: 10),
            ],
            
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: devices.length,
              itemBuilder: (ctx, i) {
                final r = devices[i];
                return Card(
                  elevation: 2,
                  margin: EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Icon(Icons.developer_board, color: AppColors.primary),
                    title: Text(
                      r.device.platformName,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      r.device.remoteId.toString(),
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: Icon(Icons.arrow_forward, color: AppColors.accent),
                    onTap: () => _connectAndProceed(r.device),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceStatus(String label, bool isEnabled, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: isEnabled ? null : onTap,
      child: Column(
        children: [
          Stack(
            children: [
              Icon(
                icon,
                size: 40,
                color: isEnabled ? Colors.green : Colors.grey,
              ),
              if (!isEnabled)
                Positioned(
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isEnabled ? Colors.green : Colors.grey,
            ),
          ),
          SizedBox(height: 4),
          Text(
            isEnabled ? "Aktif" : "Nonaktif",
            style: TextStyle(
              fontSize: 11,
              color: isEnabled ? Colors.green : Colors.red,
            ),
          ),
          if (!isEnabled)
            Text(
              "Tap untuk aktifkan",
              style: TextStyle(
                fontSize: 10,
                color: Colors.blue,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}