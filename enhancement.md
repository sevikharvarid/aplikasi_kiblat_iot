# Enhancement Spec — Kompas Digital Penunjuk Kiblat dengan Koreksi Utara Sejati

**Status:** Draft eksekusi + dasar penulisan metodologi tesis
**Platform:** Flutter (Android) ⇄ BLE ⇄ ESP32 + motor + sensor kompas (magnetometer)
**Ringkasan 1 kalimat:** App menghitung deklinasi magnetik dari GPS + tanggal, menampilkannya, lalu mengirim koreksi ke ESP32 supaya alat mengarah ke **utara sejati** dulu, baru ke **kiblat**.

---

## 0. Perubahan dari Kondisi Existing

| Existing | Enhancement (target) |
|---|---|
| Sensor kompas kirim heading ke app | Tetap, tapi heading mentah (0–360, **0 = utara magnetik**, bukan utara sejati) |
| App hitung arah kiblat | Tetap |
| Tombol "Kirim ke ESP32" via Bluetooth | Tetap |
| — | **+ Ambil lat/lng dari GPS HP** (otomatis) |
| — | **+ Ambil tanggal-bulan-tahun-jam** (otomatis dari device) |
| — | **+ Hitung nilai deklinasi** (koreksi utara sejati) |
| — | **+ Tombol "Deklinasi"** (opsional; bisa otomatis) |
| — | **+ Tampilkan Latitude, Longitude, Deklinasi di layar app** |

**Inti masalah:** sensor kompas kasih `0°` di utara **magnetik**. Utara **sejati** (geografis) berbeda sebesar **deklinasi (D)**. Untuk kiblat yang benar, arah harus dihitung dari utara sejati, jadi:

```
heading_sejati = (heading_sensor + D) mod 360
```

---

## 1. Nilai Deklinasi dari Mana? (Jawaban Library)

Deklinasi dihitung dari **World Magnetic Model (WMM)** — model resmi NOAA/BGS yang dirilis tiap 5 tahun. Inputnya: **lintang, bujur, (tinggi ≈ 0), dan tanggal**.

### Opsi Flutter (dipakai)

| Library | Cara kerja | Kelebihan | Kekurangan |
|---|---|---|---|
| **`magnetic_declination`** ✅ | Wrapper native: Android pakai `GeomagneticField`, iOS pakai CoreLocation | Paling simpel, tanpa file koefisien | Butuh device asli (native), bukan pure-Dart |
| `geomag` | Pure Dart, port geomagJS, pakai koefisien WMM | Offline, lintas platform, akurasi ±0.2° | Data bawaan lama (WMM-2015v2) → ganti .COF ke WMM2025 |

### Opsi ESP32 (kalau tetap mau hitung di alat)
- `WMM_Tinier` (yang kamu sebut) atau `bolderflight/wmm` (Arduino/CMake). Butuh koefisien di firmware.

### ⚠️ Catatan penting untuk lokasi kamu
Deklinasi di **Jakarta/Bekasi ≈ +0.64°** (sangat kecil, ke timur). Jadi angka contoh **+12° → target sensor 348°** itu **ilustratif** saja; nilai real di lokasimu mendekati nol. Untuk tesis, deklinasi tetap **wajib dibahas** sebagai koreksi metodologis walau praktisnya kecil.

---

## 2. Keputusan Arsitektur — 2 Alternatif

### 🅰️ Alternatif A — Deklinasi dihitung di APP **(REKOMENDASI)**
- App: ambil GPS + tanggal → hitung `D` pakai `magnetic_declination` → **tampilkan lat/lng/D** → kirim `D` (satu angka) ke ESP32.
- ESP32: cukup terima `D` dan `bearing_kiblat`. Tidak perlu WMM_Tinier, tidak proses lat/lng/tanggal. Firmware simpel.
- **Cocok karena** requirement "tampilkan deklinasi di app" langsung terpenuhi tanpa hitung dobel.

### 🅱️ Alternatif B — Deklinasi dihitung di ESP32
- App kirim lat/lng/tanggal → ESP32 hitung `D` via WMM_Tinier → **kirim `D` balik ke app** untuk ditampilkan.
- Lebih rumit (WMM di mikrokontroler + roundtrip data), tapi alat "self-sufficient".

> **Tentang "kalau pakai GPS aplikasi ga perlu revisi":** benar untuk **sumber lokasi** — lat/lng datang dari GPS HP otomatis, jadi tidak ada input manual. Yang tetap perlu ditambahkan hanyalah logika hitung + tampil deklinasi (bukan revisi besar). Sediakan fallback **input manual lat/lng** kalau GPS mati/indoor.

**Dokumen ini memakai Alternatif A sebagai basis.**

---

## 3. Protokol Komunikasi BLE

Format pesan sederhana (JSON per baris atau CSV). Contoh JSON:

**App → ESP32 (Tahap 1, kirim koreksi utara sejati):**
```json
{ "cmd": "SET_NORTH", "declination": 0.64 }
```

**ESP32 → App (selesai Tahap 1, sudah di utara sejati):**
```json
{ "status": "NORTH_LOCKED" }
```

**App → ESP32 (Tahap 2, kirim arah kiblat):**
```json
{ "cmd": "SET_QIBLA", "bearing": 295.15 }
```

**ESP32 → App (selesai Tahap 3):**
```json
{ "status": "QIBLA_LOCKED", "heading": 295.15 }
```

> `bearing` kiblat = angka tetap hasil geometri lokasi→Ka'bah, **tidak pernah dikoreksi apa pun** (deklinasi hanya untuk mencari utara sejati, bukan untuk bearing kiblat).

---

## 4. Mekanisme Kerja 3 Tahap (untuk Metodologi Tesis)

### TAHAP 1 — Menuju Utara Sejati
Setelah Android terhubung ke ESP32 via BLE, app mengambil **lokasi (lat, lng)** dari GPS HP dan **tanggal** dari device, lalu menghitung **deklinasi magnetik (D)** menggunakan World Magnetic Model (library `magnetic_declination`). Nilai lat, lng, dan D **ditampilkan di layar app**, kemudian D dikirim ke ESP32.

ESP32 masuk **loop koreksi**: membaca sensor kompas berulang, menghitung `heading_sejati = (heading_sensor + D) mod 360`, dan menggerakkan motor sedikit demi sedikit sampai `heading_sejati ≈ 0°`. Target sensor mentah = `(360 − D) mod 360` (contoh ilustratif: D = +12° → target 348°). Motor berhenti saat tercapai — **titik berhenti pertama: perangkat menghadap utara sejati.**

### TAHAP 2 — Terima Data Kiblat
ESP32 mengirim sinyal `NORTH_LOCKED` ke Android. Android baru mengirim data kedua: **bearing kiblat** (angka tetap dari geometri lokasi ke Ka'bah). Angka ini **tidak dikoreksi** apa pun.

### TAHAP 3 — Menuju Kiblat
ESP32 menghitung selisih antara bearing kiblat dan posisi sekarang (yang sudah 0° = utara sejati), lalu **normalisasi** agar motor mengambil rute terpendek. Motor berputar **langsung sekali gerak** menuju kiblat, berhenti di **titik berhenti kedua**, lalu **terus memantau**: jika ada pergeseran kecil, posisi dikoreksi otomatis tanpa mengulang Tahap 1.

**Alur ringkas:**
```
BLE connect
  → App: GPS + tanggal → hitung D → tampilkan → kirim D
    → ESP32: loop (sensor + D) sampai heading_sejati ≈ 0°   [STOP 1: utara sejati]
      → ESP32: kirim NORTH_LOCKED
        → App: kirim bearing_kiblat
          → ESP32: putar rute terpendek ke bearing_kiblat   [STOP 2: kiblat]
            → ESP32: loop pemantauan drift (koreksi kecil otomatis)
```

---

## 5. Implementasi Flutter (snippet)

### 5.1 Dependencies (`pubspec.yaml`)
```yaml
dependencies:
  magnetic_declination: ^latest   # cek versi terbaru di pub.dev
  geolocator: ^latest             # GPS lat/lng
  flutter_blue_plus: ^latest       # BLE (atau flutter_reactive_ble)
```

### 5.2 Ambil lokasi + hitung deklinasi + tampilkan
```dart
import 'package:geolocator/geolocator.dart';
import 'package:magnetic_declination/magnetic_declination.dart';

Future<Map<String, double>> getLocationAndDeclination() async {
  // 1. GPS dari HP (pastikan izin & service aktif)
  final pos = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );

  final lat = pos.latitude;
  final lng = pos.longitude;
  final date = DateTime.now();

  // 2. Hitung deklinasi (altitude 0 → efeknya diabaikan)
  final declination = await MagneticDeclination.calculateDeclination(
    lat, lng, 0.0, date,
  );

  // 3. Nilai untuk ditampilkan di UI: lat, lng, declination
  return {'lat': lat, 'lng': lng, 'declination': declination};
}
```

### 5.3 Hitung bearing kiblat (great-circle ke Ka'bah)
```dart
import 'dart:math';

// Koordinat Ka'bah
const double kaabaLat = 21.4225;
const double kaabaLng = 39.8262;

double qiblaBearing(double lat, double lng) {
  final phi1 = lat * pi / 180;
  final phi2 = kaabaLat * pi / 180;
  final dLng = (kaabaLng - lng) * pi / 180;

  final y = sin(dLng);
  final x = cos(phi1) * tan(phi2) - sin(phi1) * cos(dLng);
  var brng = atan2(y, x) * 180 / pi;
  return (brng + 360) % 360; // normalisasi 0–360
}
```

### 5.4 Kirim via BLE (pseudocode)
```dart
// Tahap 1
await bleWrite('{"cmd":"SET_NORTH","declination":$declination}');

// Tunggu status NORTH_LOCKED dari ESP32 (listen notify) ...

// Tahap 2
final bearing = qiblaBearing(lat, lng);
await bleWrite('{"cmd":"SET_QIBLA","bearing":$bearing}');
```

---

## 6. Implementasi ESP32 (pseudocode — Alternatif A)

```cpp
float declination = 0;        // diterima dari app (SET_NORTH)
float qiblaBearing = 0;       // diterima dari app (SET_QIBLA)
enum State { WAIT_NORTH, SEEK_NORTH, WAIT_QIBLA, SEEK_QIBLA, TRACK };
State state = WAIT_NORTH;

float readCompass();          // heading magnetik 0–360 dari magnetometer
float normalize(float a){ a = fmod(a,360); return a<0? a+360 : a; }

void loop() {
  float sensor = readCompass();
  float trueHeading = normalize(sensor + declination);

  switch (state) {
    case SEEK_NORTH:
      // gerak pelan sampai trueHeading ≈ 0
      if (fabs(trueHeading) <= TOL || fabs(trueHeading-360) <= TOL) {
        motorStop();
        bleNotify("{\"status\":\"NORTH_LOCKED\"}");
        state = WAIT_QIBLA;
      } else {
        stepTowardZero(trueHeading);   // rute terpendek ke 0
      }
      break;

    case SEEK_QIBLA: {
      // sekarang trueHeading acuan; putar ke qiblaBearing rute terpendek
      float diff = normalize(qiblaBearing - trueHeading);
      if (diff > 180) diff -= 360;     // -180..180
      if (fabs(diff) <= TOL) {
        motorStop();
        bleNotify("{\"status\":\"QIBLA_LOCKED\"}");
        state = TRACK;
      } else {
        motorMove(diff);               // sekali gerak
      }
      break;
    }

    case TRACK: {
      // pantau drift, koreksi kecil tanpa ulang Tahap 1
      float diff = normalize(qiblaBearing - trueHeading);
      if (diff > 180) diff -= 360;
      if (fabs(diff) > TOL) motorMove(diff);
      break;
    }
  }
}

// onReceive SET_NORTH → declination = ...; state = SEEK_NORTH;
// onReceive SET_QIBLA → qiblaBearing = ...; state = SEEK_QIBLA;
```

> `TOL` = toleransi (mis. 1–2°). Untuk Alternatif B, ganti input `SET_NORTH` jadi lat/lng/tanggal lalu hitung `declination` pakai WMM_Tinier di sini, dan kirim balik ke app untuk ditampilkan.

---

## 7. Requirement Tampilan App

Tampilkan minimal 3 nilai (real-time / setelah tombol ditekan):

| Label | Sumber | Contoh |
|---|---|---|
| Latitude | GPS | -6.2xxx |
| Longitude | GPS | 106.9xxx |
| Deklinasi | WMM (`magnetic_declination`) | +0.64° |
| *(opsional)* Bearing Kiblat | hitung geometri | ±295° |
| *(opsional)* Heading sekarang | notify ESP32 | 0–360° |

Tombol: **[Ambil Lokasi & Deklinasi]** → **[Kirim ke ESP32 (Utara Sejati)]** → (auto) **[Kirim Kiblat]**.

---

## 8. Checklist Revisi (yang harus dikerjakan)

- [ ] Tambah permission + ambil GPS (`geolocator`) + fallback input manual lat/lng.
- [ ] Ambil `DateTime.now()` untuk input WMM.
- [ ] Integrasi `magnetic_declination`, hitung D.
- [ ] UI: tampilkan Latitude, Longitude, Deklinasi.
- [ ] Fungsi `qiblaBearing()` (rumus great-circle ke Ka'bah).
- [ ] Definisikan format pesan BLE (SET_NORTH / SET_QIBLA / status).
- [ ] Handler notify: tunggu `NORTH_LOCKED` sebelum kirim kiblat.
- [ ] Firmware ESP32: state machine 3 tahap + normalisasi rute terpendek + mode TRACK.
- [ ] Uji lapangan: bandingkan hasil alat vs aplikasi kiblat referensi.

---

## 9. Rumus Pendukung (ringkas)

**Utara sejati dari sensor:**
```
heading_sejati = (heading_sensor + D) mod 360
target_sensor_utara = (360 − D) mod 360
```

**Bearing kiblat (great-circle):**
```
θ = atan2( sin(Δλ),  cos(φ1)·tan(φ2) − sin(φ1)·cos(Δλ) )
Δλ = λ_kabah − λ_user ;  φ1 = lat_user ;  φ2 = lat_kabah = 21.4225°
bearing_kiblat = (θ_deg + 360) mod 360
```

**Rute terpendek (motor):**
```
diff = ((target − sekarang + 540) mod 360) − 180   // hasil −180..+180
```

---

*Catatan sumber: nilai deklinasi Jakarta ≈ +0.64° dan model WMM2025 (epoch 2025–2030) untuk perhitungan 2026. Selalu verifikasi nilai real lokasi via NOAA Magnetic Field Calculator saat menulis tesis.*