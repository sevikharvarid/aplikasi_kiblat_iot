// lib/services/qibla_bluetooth.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'dart:async';

class QiblaBluetooth {
  static BluetoothDevice? device;
  static BluetoothCharacteristic? writeChar;
  static BluetoothCharacteristic? notifyChar;

  static StreamController<String> responseController = StreamController.broadcast();
  static StreamController<double> bnoHeadingController = StreamController.broadcast();

  // DETEKSI SIMULATOR
  static Future<bool> get isSimulator async {
    if (kIsWeb) return true;
    try {
      final isAvailable = await FlutterBluePlus.isAvailable;
      return !isAvailable;
    } catch (e) {
      return true;
    }
  }

  static Future<void> _writeRaw(String payload) async {
    if (device != null && device!.isConnected && writeChar != null) {
      try {
        await writeChar!.write(utf8.encode(payload), withoutResponse: false);
        print("✅ Data sent: $payload");
      } catch (e) {
        print("❌ Error sending data: $e");
        responseController.add("ERROR: $e");
      }
    } else {
      print("⚠️ Device not connected");
      responseController.add("ERROR: Device not connected");
    }
  }

  // === TOMBOL 1: Kirim sudut kiblat === format: *<bearing>K
  static Future<void> sendQiblaBearing(double bearing) async {
    final simulator = await isSimulator;
    final payload = "*${bearing.toStringAsFixed(1)}K\n";

    if (simulator) {
      responseController.add("STATUS:Sudut kiblat terkirim (simulasi)");
      _simulateBNOStream(); // biar compass tetap bergerak di simulator
      return;
    }
    await _writeRaw(payload);
  }

  // === TOMBOL 2: Kirim deklinasi + lokasi === format: *<decl>D <lat>L <lng>N
  static Future<void> sendDeclinationLocation(
      double declination, double lat, double lng) async {
    final simulator = await isSimulator;
    final payload =
        "*${declination.toStringAsFixed(1)}D ${lat.toStringAsFixed(6)}L ${lng.toStringAsFixed(6)}N\n";

    if (simulator) {
      responseController.add("STATUS:Deklinasi & lokasi terkirim (simulasi)");
      return;
    }
    await _writeRaw(payload);
  }

  // === Kirim semua data lengkap (gabungan tombol 1 + tombol 2) ===
  static Future<void> sendAllData(
      double bearing, double declination, double lat, double lng) async {
    await sendQiblaBearing(bearing);
    await Future.delayed(const Duration(milliseconds: 150));
    await sendDeclinationLocation(declination, lat, lng);
  }

  static Future<void> startScan() async {
    final simulator = await isSimulator;
    if (simulator) {
      responseController.add("Simulator: Bluetooth tidak tersedia");
      return;
    }
    
    try {
      await FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: 10),
        androidUsesFineLocation: true,
      );
      print("🔍 Scanning started...");
    } catch (e) {
      print("❌ Error starting scan: $e");
      responseController.add("Error: $e");
    }
  }

  static Stream<List<ScanResult>> get scanResults {
    return FlutterBluePlus.scanResults;
  }

  static Future<void> connectToDevice(BluetoothDevice d) async {
    final simulator = await isSimulator;
    if (simulator) {
      responseController.add("Simulator: Koneksi dummy berhasil");
      return;
    }

    try {
      device = d;
      
      print("📱 Connecting to ${d.platformName}...");
      
      if (await d.isConnected) {
        await d.disconnect();
        await Future.delayed(Duration(seconds: 1));
      }
      
      await d.connect(timeout: Duration(seconds: 15));
      
      print("✅ Connected to ${d.platformName}");
      
      await discoverServices();
      
      responseController.add("Connected to ${d.platformName}");
    } catch (e) {
      print("❌ Connection error: $e");
      device = null;
      responseController.add("Connection failed: $e");
      rethrow;
    }
  }

  static Future<void> discoverServices() async {
    final simulator = await isSimulator;
    if (simulator || device == null) return;

    try {
      print("🔍 Discovering services...");
      
      List<BluetoothService> services = await device!.discoverServices();
      
      print("📋 Found ${services.length} services");
      
      bool foundCharacteristics = false;
      
      for (var service in services) {
        print("📦 Service UUID: ${service.uuid}");
        
        for (var char in service.characteristics) {
          print("   🔌 Characteristic UUID: ${char.uuid}");
          print("      Properties - Write: ${char.properties.write}, "
                "WriteNoResponse: ${char.properties.writeWithoutResponse}, "
                "Notify: ${char.properties.notify}, "
                "Read: ${char.properties.read}");
          
          if (char.properties.write || char.properties.writeWithoutResponse) {
            writeChar = char;
            print("   ✅ Using as WRITE characteristic");
            foundCharacteristics = true;
          }
          
          if (char.properties.notify) {
            notifyChar = char;
            print("   ✅ Using as NOTIFY characteristic");
            foundCharacteristics = true;
            
            try {
              await char.setNotifyValue(true);
              char.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  String msg = utf8.decode(value);
                  print("📥 Received: $msg");
                  
                  // Parse BNO heading data (format: BNO:xxx.xx)
                  if (msg.startsWith("BNO:")) {
                    try {
                      String headingStr = msg.substring(4).trim();
                      double heading = double.parse(headingStr);
                      bnoHeadingController.add(heading);
                      print("🧭 BNO Heading: $heading°");
                    } catch (e) {
                      print("⚠️ Error parsing BNO data: $e");
                    }
                  } else {
                    // Response messages lainnya
                    responseController.add(msg.trim());
                  }
                }
              });
              print("   ✅ Notification enabled");
            } catch (e) {
              print("   ⚠️ Could not enable notifications: $e");
            }
          }
        }
      }
      
      if (!foundCharacteristics) {
        print("⚠️ No suitable characteristics found!");
      }
      
    } catch (e) {
      print("❌ Error discovering services: $e");
      responseController.add("Service discovery failed: $e");
    }
  }

  static Timer? _bnoSimTimer;

  static void _simulateBNOStream() {
    _bnoSimTimer?.cancel(); // jangan biarkan timer lama masih jalan bareng yang baru
    double simulatedHeading = 0.0;
    _bnoSimTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      simulatedHeading += 1.5;
      if (simulatedHeading >= 360.0) {
        simulatedHeading = 0.0;
      }
      bnoHeadingController.add(simulatedHeading);
    });
  }

  static Future<void> disconnect() async {
    if (device != null) {
      try {
        await device!.disconnect();
        print("🔌 Disconnected");
      } catch (e) {
        print("⚠️ Disconnect error: $e");
      }
      device = null;
      writeChar = null;
      notifyChar = null;
    }
  }

  static Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      print("⚠️ Error stopping scan: $e");
    }
  }
}