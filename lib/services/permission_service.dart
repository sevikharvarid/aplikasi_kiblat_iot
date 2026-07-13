// lib/services/permission_service.dart
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class PermissionService {
  // Check if Location Service is enabled
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  // Check if Bluetooth is enabled
  static Future<bool> isBluetoothEnabled() async {
    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (e) {
      return false;
    }
  }

  // Request to turn on Location with dialog
  static Future<bool> requestLocationService(BuildContext context) async {
    bool isEnabled = await isLocationServiceEnabled();
    
    if (isEnabled) return true;

    bool? shouldEnable = await _showServiceDialog(
      context,
      'GPS Tidak Aktif',
      'Aplikasi membutuhkan GPS untuk menentukan lokasi Anda. Aktifkan GPS sekarang?',
      Icons.location_off,
    );

    if (shouldEnable == true) {
      bool opened = await Geolocator.openLocationSettings();
      if (opened) {
        // Wait a bit and check again
        await Future.delayed(Duration(seconds: 2));
        return await isLocationServiceEnabled();
      }
    }

    return false;
  }

  // Request to turn on Bluetooth with dialog
  static Future<bool> requestBluetoothService(BuildContext context) async {
    bool isEnabled = await isBluetoothEnabled();
    
    if (isEnabled) return true;

    bool? shouldEnable = await _showServiceDialog(
      context,
      'Bluetooth Tidak Aktif',
      'Aplikasi membutuhkan Bluetooth untuk terhubung ke ESP32. Aktifkan Bluetooth sekarang?',
      Icons.bluetooth_disabled,
    );

    if (shouldEnable == true) {
      try {
        if (await FlutterBluePlus.isSupported) {
          await FlutterBluePlus.turnOn();
        }
        // Wait a bit for Bluetooth to turn on
        await Future.delayed(Duration(seconds: 2));
        return await isBluetoothEnabled();
      } catch (e) {
        return false;
      }
    }

    return false;
  }

  // Request Location Permission
  static Future<bool> requestLocationPermission(BuildContext context) async {
    // First check if service is enabled
    bool serviceEnabled = await requestLocationService(context);
    if (!serviceEnabled) {
      return false;
    }

    PermissionStatus status = await Permission.location.status;

    if (status.isGranted) {
      return true;
    }

    if (status.isDenied) {
      bool? shouldRequest = await _showPermissionDialog(
        context,
        'Izin Lokasi Diperlukan',
        'Aplikasi membutuhkan akses lokasi untuk menghitung arah kiblat berdasarkan posisi Anda.',
        Icons.location_on,
      );

      if (shouldRequest == true) {
        status = await Permission.location.request();
        return status.isGranted;
      }
      return false;
    }

    if (status.isPermanentlyDenied) {
      bool? shouldOpenSettings = await _showPermissionDialog(
        context,
        'Izin Lokasi Ditolak',
        'Silakan aktifkan izin lokasi di Pengaturan untuk menggunakan aplikasi ini.',
        Icons.settings,
      );

      if (shouldOpenSettings == true) {
        await openAppSettings();
      }
      return false;
    }

    return false;
  }

  // Request Bluetooth Permissions
  static Future<bool> requestBluetoothPermissions(BuildContext context) async {
    // First check if Bluetooth service is enabled
    bool serviceEnabled = await requestBluetoothService(context);
    if (!serviceEnabled) {
      return false;
    }

    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);

    if (!allGranted) {
      bool hasPermDenied = statuses.values.any((status) => status.isPermanentlyDenied);
      
      if (hasPermDenied) {
        bool? shouldOpenSettings = await _showPermissionDialog(
          context,
          'Izin Bluetooth Diperlukan',
          'Silakan aktifkan izin Bluetooth dan Lokasi di Pengaturan untuk menghubungkan ke ESP32.',
          Icons.settings,
        );

        if (shouldOpenSettings == true) {
          await openAppSettings();
        }
      }
    }

    return allGranted;
  }

  // Check and request everything needed for Location
  static Future<bool> checkAndRequestLocation(BuildContext context) async {
    // Check service first
    bool serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      bool enabled = await requestLocationService(context);
      if (!enabled) return false;
    }

    // Then check permission
    return await requestLocationPermission(context);
  }

  // Check and request everything needed for Bluetooth
  static Future<bool> checkAndRequestBluetooth(BuildContext context) async {
    // Check service first
    bool serviceEnabled = await isBluetoothEnabled();
    if (!serviceEnabled) {
      bool enabled = await requestBluetoothService(context);
      if (!enabled) return false;
    }

    // Then check permissions
    return await requestBluetoothPermissions(context);
  }

  // Service Dialog (for GPS/Bluetooth toggle)
  static Future<bool?> _showServiceDialog(
    BuildContext context,
    String title,
    String message,
    IconData icon,
  ) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          icon: Icon(icon, size: 50, color: Colors.orange),
          title: Text(title, textAlign: TextAlign.center),
          content: Text(message, textAlign: TextAlign.center),
          actions: <Widget>[
            TextButton(
              child: Text('Nanti', style: TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Aktifkan', style: TextStyle(color: Colors.white)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
  }

  // Permission Dialog
  static Future<bool?> _showPermissionDialog(
    BuildContext context,
    String title,
    String message,
    IconData icon,
  ) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          icon: Icon(icon, size: 50, color: Colors.teal),
          title: Text(title, textAlign: TextAlign.center),
          content: Text(message, textAlign: TextAlign.center),
          actions: <Widget>[
            TextButton(
              child: Text('Batal', style: TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Izinkan', style: TextStyle(color: Colors.white)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
  }
}