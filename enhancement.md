# Implementasi Deklinasi — v3 (spec client / Alternatif B, single-packet)

> **Repo:** `sevikharvarid/aplikasi_kiblat_iot` · **Sensor:** BNO055 (fusion onboard) · **Protokol:** plain-text
> **Prinsip:** App **cuma kirim data** (lat, lng, tanggal) + **menampilkan** balasan. **ESP32 yang menghitung deklinasi** (WMM_Tinier).

---

## 0. KOREKSI ARSITEKTUR (baca ini dulu)

Versi lama dokumen ini keliru: mengira **app** yang hitung deklinasi. Sesuai kata client, yang benar:

| | Alternatif A (versi lama, salah) | **Alternatif B (spec client, dipakai)** |
|---|---|---|
| Yang hitung deklinasi | App (package `magnetic_declination`) | **ESP32 (WMM_Tinier)** |
| Yang dikirim app → ESP32 | nilai deklinasi | **lat + lng + tanggal/jam** |
| Deklinasi buat ditampilkan | dihitung app | **diterima balik dari ESP32** |
| Alur | fire-once | **bertahap / handshake** |

Kutipan client yang jadi acuan:
- *"aplikasi langsung mengirim data lokasi (lintang, bujur) dan tanggal"* → app kirim **lat, lng, tanggal**.
- *"ESP32 memakai data ini untuk menghitung deklinasi lewat WMM_Tinier"* → **ESP32 yang hitung**.
- *"Alat mengirim sinyal balik... Android baru mengirim data kedua (bearing kiblat)"* → **handshake bertahap**.

**Efek ke app:** package `magnetic_declination` **tidak wajib** lagi. App tidak menghitung apa pun soal deklinasi — hanya kirim lat/lng/tanggal, lalu terima & tampilkan nilai deklinasi dari ESP32.

---

## 1. Peran App (final)

1. Ambil **lat, lng** dari GPS HP (`LocationService` — sudah ada).
2. Ambil **tanggal/jam** dari jam HP (`DateTime.now()`).
3. Kirim `lat + lng + tanggal` ke ESP32 → memicu **Tahap 1** (ESP32 hitung deklinasi + gerak ke utara sejati).
4. Terima balik dari ESP32: **nilai deklinasi** + sinyal **"utara sejati siap"**.
5. **Tampilkan** lat, lng, deklinasi.
6. Setelah dapat sinyal siap → kirim **bearing kiblat** (angka tetap `widget.qibla`) → **Tahap 2 & 3**.

> App **tidak** menghitung deklinasi dan **tidak** mengoreksi bearing kiblat. Itu semua di firmware.

---

## 2. Kontrak Protokol BLE (sepakati dengan tim firmware)

**App kirim SEMUA data dalam satu paket, ESP32 yang pisah pakai separator.** (Tidak perlu handshake bertahap dari sisi app.)

| Arah | Pesan | Arti | Status |
|---|---|---|---|
| App → ESP32 | `KIBLAT:<lat>|<lng>|<ISO8601>|<bearing>\n` | lat, lng, tanggal/jam, bearing kiblat — sekaligus | **BARU** |
| ESP32 → App | `DECL:<derajat>\n` | hasil hitung deklinasi (buat ditampilkan) | **BARU** |
| ESP32 → App | `STATUS:NORTH_LOCKED\n` | (opsional) info sudah di utara sejati | **BARU** |
| ESP32 → App | `BNO:<derajat>\n` | stream heading BNO055 | *existing* |
| ESP32 → App | `STATUS:...\n` | pesan status umum | *existing* |

Contoh paket: `KIBLAT:-6.234567|106.987654|2026-07-14T15:30:00.000|294.50\n`

> **Separator `|` (pipe)** dipilih karena tidak muncul di field mana pun (lat/lng/bearing = angka; tanggal ISO8601 = angka + `-` `:` `T` `.`). Koma juga aman kalau tim ESP lebih suka. Formatnya fleksibel — **tim ESP yang final memutuskan cara pisahnya**.

**Yang harus dikunci bareng hardware:**
1. Separator apa (`|` / `,` / lainnya) dan urutan field: **lat, lng, tanggal, bearing**.
2. Firmware pisah paket → ambil lat/lng/tanggal → hitung deklinasi (WMM_Tinier) → balas `DECL:` (buat app tampilkan).
3. Firmware simpan `bearing` (dari paket yang sama) → dipakai nanti di Tahap 2, tidak dikoreksi apa pun.
4. Bearing = **angka tetap absolut** (0–360), firmware yang hitung rute terpendek.

---

## 3. Ringkasan perubahan file

| File | Perubahan |
|---|---|
| `pubspec.yaml` | **Tidak perlu** `magnetic_declination` (deklinasi di ESP32). |
| `services/qibla_bluetooth.dart` | + `sendLocationDate()`, + stream `declinationController`, + parse `DECL:` di notify, + helper `runQiblaSequence()` (handshake). |
| `screens/home_screen.dart` | Kirim `LOC` saat konek, listen `declinationController`, simpan `declination`, oper ke QiblaScreen. |
| `screens/qibla_screen.dart` | Terima `declination`, tampilkan (StatusCard + `icon`), tombol kirim pakai `runQiblaSequence()`. |

**File `declination_service.dart` dari versi lama: HAPUS / tidak dipakai.**

---

## 4. EDIT — `lib/services/qibla_bluetooth.dart`

### 4a. Tambah stream deklinasi
Di dekat deklarasi controller yang sudah ada:
```dart
static StreamController<double> declinationController = StreamController.broadcast();
```

### 4b. Kirim SEMUA data sekaligus (lat + lng + tanggal + bearing)
```dart
  static const String kSep = "|"; // separator — samakan dgn tim ESP

  // === KIRIM SEMUA DATA SEKALIGUS: lat|lng|tanggal|bearing ===
  static Future<void> sendAllData(
      double lat, double lng, double bearing, {DateTime? date}) async {
    final simulator = await isSimulator;
    final iso = (date ?? DateTime.now()).toIso8601String();

    final payload =
        "KIBLAT:${lat.toStringAsFixed(6)}$kSep${lng.toStringAsFixed(6)}$kSep$iso$kSep${bearing.toStringAsFixed(2)}\n";

    if (simulator) {
      responseController.add("STATUS:Data diterima");
      await Future.delayed(const Duration(milliseconds: 300));
      declinationController.add(0.64);                 // dummy deklinasi
      responseController.add("STATUS:NORTH_LOCKED");   // dummy info
      return;
    }

    if (device != null && device!.isConnected && writeChar != null) {
      try {
        await writeChar!.write(utf8.encode(payload), withoutResponse: false);
        print("✅ Data sent: $payload");
      } catch (e) {
        responseController.add("ERROR: $e");
      }
    } else {
      responseController.add("ERROR: Device not connected");
    }
  }
```

### 4c. Parse `DECL:` di notify handler
Di `discoverServices()`, di dalam `char.lastValueStream.listen(...)` yang sekarang mem-parse `BNO:`, tambahkan cabang `DECL:`. Ubah blok:
```dart
if (msg.startsWith("BNO:")) {
  // ... existing parsing BNO ...
} else {
  responseController.add(msg.trim());
}
```
jadi:
```dart
if (msg.startsWith("BNO:")) {
  // ... existing parsing BNO (biarkan) ...
} else if (msg.startsWith("DECL:")) {
  final v = double.tryParse(msg.substring(5).trim());
  if (v != null) {
    declinationController.add(v);
    print("🧭 Declination diterima: $v°");
  }
} else {
  responseController.add(msg.trim());
}
```

### 4d. (Tidak perlu handshake lagi)
Karena semua data dikirim dalam satu paket, **tidak ada** `runQiblaSequence`/tunggu `NORTH_LOCKED`. App cukup panggil `sendAllData(...)` sekali. ESP32 yang atur tahapannya internal (pakai bearing yang sudah ada di paket).

---

## 5. EDIT — `lib/screens/home_screen.dart`

### 5a. State deklinasi
```dart
double? lat, lng, qibla, declination;
```

### 5b. Listen deklinasi dari ESP32 (di `initState`)
```dart
QiblaBluetooth.declinationController.stream.listen((d) {
  if (mounted) setState(() => declination = d);
});
```

### 5c. Kirim LOC saat sudah konek
Kirim data cukup dilakukan dari tombol di QiblaScreen (§6c). Kalau mau kirim otomatis begitu konek, di `_connectAndProceed()` setelah lokasi + `angle` didapat bisa panggil:
```dart
await QiblaBluetooth.sendAllData(pos.latitude, pos.longitude, angle);
```
(Deklinasi akan masuk lewat listener 5b lalu tampil otomatis.)

### 5d. Tampilkan deklinasi (lat & lng SUDAH tampil di `:361`)
Setelah baris koordinat:
```dart
Text(
  "${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}",
  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
),
```
sisipkan:
```dart
SizedBox(height: 4),
Text(
  "Deklinasi: ${declination?.toStringAsFixed(2) ?? 'menunggu ESP32...'}°",
  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
),
```

### 5e. Oper deklinasi ke QiblaScreen (2 tempat `Navigator.push`)
```dart
builder: (_) => QiblaScreen(
  lat: lat!,
  lng: lng!,
  qibla: qibla!,
  declination: declination ?? 0,
  locationName: locationName ?? "Unknown",
),
```

---

## 6. EDIT — `lib/screens/qibla_screen.dart`

### 6a. Terima parameter + listen update deklinasi
```dart
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
```
Di `_QiblaScreenState`, tambah field + listener supaya nilai deklinasi tetap update kalau ESP32 kirim ulang:
```dart
double declination = 0;

@override
void initState() {
  super.initState();
  declination = widget.declination;
  QiblaBluetooth.declinationController.stream.listen((d) {
    if (mounted) setState(() => declination = d);
  });
  // ... listener existing lainnya ...
}
```

### 6b. Tampilkan deklinasi (WAJIB `icon`)
Dekat kartu "Respon ESP32" (~baris 209):
```dart
StatusCard(
  title: "Deklinasi Magnetik",
  value: "${declination.toStringAsFixed(2)}°",
  icon: Icons.explore,   // WAJIB — StatusCard butuh icon
),
SizedBox(height: 20),
```

### 6c. Tombol kirim → pakai handshake + bearing TETAP
Ubah `_sendQiblaAngle()`. Ganti:
```dart
double normalizedAngle = adjustedQiblaAngle % 360;
if (normalizedAngle < 0) normalizedAngle += 360;
await QiblaBluetooth.sendQiblaAngle(normalizedAngle);
```
jadi:
```dart
// Kirim SEMUA data sekaligus: lat, lng, tanggal, bearing kiblat TETAP
await QiblaBluetooth.sendAllData(widget.lat, widget.lng, widget.qibla);
```
> Catatan: yang dikirim adalah **bearing kiblat tetap** (`widget.qibla`), bukan `adjustedQiblaAngle`. Panah on-screen (`adjustedQiblaAngle`) tetap dipakai hanya untuk tampilan visual.

---

## 7. Checklist eksekusi

- [ ] Hapus `declination_service.dart` (tidak dipakai lagi)
- [ ] `qibla_bluetooth.dart`: `declinationController`, `sendAllData()`, parse `DECL:`
- [ ] `home_screen.dart`: state `declination`, listener, kirim `LOC` saat konek, tampilkan deklinasi, oper ke QiblaScreen
- [ ] `qibla_screen.dart`: terima `declination`, listener, tampilkan (`StatusCard`+`icon`), tombol → `sendAllData()`
- [ ] Sepakati separator + urutan field `KIBLAT:...` dan `DECL:` dengan tim firmware
- [ ] Uji simulator dulu (dummy DECL 0.64 + NORTH_LOCKED), lalu device asli

### ✅ Cek requirement "lat, lng, deklinasi tampil di app"
| Nilai | Sumber | Tampil di | Aksi |
|---|---|---|---|
| Latitude | GPS HP | Home `:361`, Qibla `:155` | ✅ sudah |
| Longitude | GPS HP | Home `:361`, Qibla `:155` | ✅ sudah |
| Deklinasi | **dihitung ESP32**, dikirim balik | Home §5d, Qibla §6b | tambah (wajib) |

---

## 8. Untuk metodologi tesis (versi benar)

1. App ambil **lat, lng** (GPS HP) + **tanggal/jam** (jam HP) + hitung **bearing kiblat** (geometri ke Ka'bah).
2. App kirim **semua sekaligus** ke ESP32 via BLE dalam satu paket ber-separator (`KIBLAT:lat|lng|tanggal|bearing`). ESP32 yang memisah datanya.
3. **ESP32** hitung **deklinasi** dengan **WMM_Tinier** (kalkulator murni), kirim nilainya balik ke app untuk ditampilkan.
4. ESP32 (BNO055): `heading_sejati = heading_BNO + deklinasi` → motor gerak sampai utara sejati (Tahap 1), lalu kirim `NORTH_LOCKED`.
5. ESP32 memakai **bearing kiblat** (yang sudah dikirim di paket awal) untuk Tahap 2–3: putar rute terpendek ke kiblat, lalu pantau drift.

Peran app = **penyedia data lokasi/waktu + antarmuka tampilan**. Peran ESP32 = **komputasi deklinasi + kontrol motor**. Contoh 12°/348° ilustratif; deklinasi real Bekasi ≈ +0.64°.

---

### (Opsional) kalau mau app menampilkan deklinasi TANPA menunggu ESP32
Bisa tambahkan `magnetic_declination` hanya untuk *preview* di app (hitung lokal buat ditampilkan lebih cepat), sementara ESP32 tetap hitung sendiri untuk motor. Tapi ini menyalahi "satu sumber hitung" dan bisa beda tipis antar-model WMM — **tidak disarankan** kecuali diperlukan untuk UX.