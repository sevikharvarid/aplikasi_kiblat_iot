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

  // === SEND QIBLA ANGLE TO ESP32 ===
  static Future<void> sendQiblaAngle(double qiblaAngle) async {
    final simulator = await isSimulator;
    if (simulator) {
      await Future.delayed(Duration(milliseconds: 500));
      responseController.add("STATUS:Streaming BNO Data");
      await Future.delayed(Duration(milliseconds: 100));
      responseController.add("BNO:Ready");
      
      // Simulasi streaming BNO untuk simulator
      _simulateBNOStream();
      return;
    }

    if (device != null && device!.isConnected) {
      try {
        // Format: "xxx.xx\n" (contoh: "294.50\n")
        String data = "${qiblaAngle.toStringAsFixed(2)}\n";
        List<int> bytes = utf8.encode(data);
        
        if (writeChar != null) {
          await writeChar!.write(bytes, withoutResponse: false);
          print("✅ Qibla angle sent: $data");
        } else {
          print("⚠️ No write characteristic found");
          responseController.add("ERROR: No write characteristic");
        }
      } catch (e) {
        print("❌ Error sending qibla: $e");
        responseController.add("ERROR: $e");
      }
    } else {
      print("⚠️ Device not connected");
      responseController.add("ERROR: Device not connected");
    }
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

  static void _simulateBNOStream() {
    double simulatedHeading = 0.0;
    Timer.periodic(Duration(milliseconds: 100), (timer) {
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