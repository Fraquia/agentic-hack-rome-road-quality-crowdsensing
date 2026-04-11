# Road Quality Monitor — App Flutter

App mobile che legge l'IMU dello smartphone a 50 Hz, classifica le condizioni del manto stradale con una CNN-1D on-device (TFLite) e geolocalizza le anomalie rilevate.

## Setup iniziale (da fare una volta)

### 1. Prerequisiti
- Flutter SDK ≥ 3.10 (`flutter --version`)
- Android SDK o Xcode (per iOS)
- Modello e scaler generati dalla pipeline Python:
  ```bash
  cd ..   # nella root di road-quality/
  python -m training.export
  cp models/model.tflite  app/assets/
  cp models/scaler.json   app/assets/
  ```

### 2. Inizializza il progetto Flutter
Dalla cartella `app/`:
```bash
flutter create . --project-name road_quality --org com.hackathon.roadquality
```
> Questo genera i file nativi (android/, ios/, ecc.) senza sovrascrivere i file
> Dart già presenti in `lib/`.

### 3. Aggiungi i permessi

#### Android — `android/app/src/main/AndroidManifest.xml`
Inserisci prima di `<application>`:
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.HIGH_SAMPLING_RATE_SENSORS" />
```

> **Android 12+**: `HIGH_SAMPLING_RATE_SENSORS` è obbligatorio per campionare
> l'accelerometro a ≥200 Hz con `SENSOR_DELAY_GAME`.

#### iOS — `ios/Runner/Info.plist`
Aggiungi nel dizionario radice:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Per geolocalizzare le anomalie stradali rilevate</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Per rilevare anomalie anche a schermo spento</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
</array>
```

### 4. Installa le dipendenze e lancia
```bash
flutter pub get
flutter run
```

## Struttura dell'app

| File | Responsabilità |
|---|---|
| `lib/sensor_collector.dart` | Buffer circolare + throttle 50 Hz sull'accelerometro |
| `lib/inference.dart` | Caricamento modello TFLite + predizione z-score normalizzata |
| `lib/windowing.dart` | Majority vote su 3 finestre consecutive |
| `lib/gps_tagger.dart` | GPS 1 Hz + buffer locale + flush batch HTTP |
| `lib/main.dart` | UI + wiring di tutti i componenti |

## Architettura del flusso dati

```
Accelerometro a 50 Hz
        │
        ▼
SensorCollector (buffer circolare 100 camp.)
        │  ogni 50 campioni
        ▼
RoadInference.predict() → (label, confidence)
        │
        ▼
WindowingVoter.confirm() → label confermata (o null)
        │  solo se ≥ 2/3 concordano su classe non-smooth
        ▼
GpsTagger.tag(label, confidence)
        │
        ▼
buffer locale → flush HTTP POST ogni 5 minuti
```

## Note operative

- **Server**: imposta `_serverUrl` in `lib/gps_tagger.dart` con l'endpoint reale.
- **Android background**: usa `SENSOR_DELAY_GAME` (già impostato via `sensors_plus`).
  Per sensing continuativo in background con schermo spento, considera un
  `ForegroundService` — richiede plugin aggiuntivo (es. `flutter_foreground_task`).
- **iOS**: `CMMotionManager` viene gestito internamente da `sensors_plus`.
  Il filtro di Kalman di Apple fonde accelerometro e giroscopio automaticamente.
- **Calibrazione asse Z**: la spec assume il telefono fisso con Z verticale.
  Se il telefono è ruotato, i valori potrebbero essere proiettati su assi diversi.
