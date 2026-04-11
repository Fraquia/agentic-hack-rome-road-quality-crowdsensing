# Road Quality Monitor

App mobile + pipeline ML per il monitoraggio del manto stradale via sensori IMU.
Gli utenti guidano normalmente; l'app rileva anomalie (buche, dossi, asfalto consumato)
in background, le geolocalizza e le invia a un server per costruire una mappa
della qualità stradale.

## Struttura del repository

```
road-quality/
├── requirements.txt        # dipendenze Python
├── data/
│   ├── raw/                # dataset scaricato da accelerometer.xyz
│   ├── processed/          # finestre NumPy pronte per il training
│   └── labels.csv          # schema mapping file → classe
├── training/
│   ├── config.py           # costanti condivise (WINDOW_SIZE, STEP, CLASSES…)
│   ├── preprocess.py       # windowing, normalizzazione, split
│   ├── model.py            # architettura CNN-1D
│   ├── train.py            # training loop
│   ├── evaluate.py         # metriche e confusion matrix
│   ├── export.py           # conversione → TFLite e CoreML
│   └── download_dataset.py # verifica presenza dataset
├── models/                 # output del training (gitignored)
└── app/                    # Flutter
    ├── pubspec.yaml
    ├── README.md           # setup Flutter + snippet permessi
    └── lib/
        ├── main.dart
        ├── sensor_collector.dart
        ├── inference.dart
        ├── windowing.dart
        └── gps_tagger.dart
```

## Quickstart

### 1. Setup Python

```bash
python -m venv .venv
source .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### 2. Dataset

Scarica i dati da [accelerometer.xyz](https://www.accelerometer.xyz/datasets/)
e posiziona i file CSV/HDF5 in `data/raw/`.

```bash
python -m training.download_dataset   # verifica presenza file
```

Ogni file deve contenere le colonne `z` (asse verticale, m/s²) e `label`
(oppure il nome del file deve contenere la classe: es. `smooth_001.csv`).

**Classi:** `smooth`, `pothole`, `asphalt_bump`, `metal_bump`, `worn_road`

### 3. Pipeline di training

```bash
# Windowing, normalizzazione, split 70/15/15
python -m training.preprocess

# Training CNN-1D (EarlyStopping patience=10)
python -m training.train

# Accuracy, F1 per classe, confusion matrix
python -m training.evaluate

# Export TFLite (+ CoreML su macOS)
python -m training.export
```

Output in `models/`:
- `model.h5` — pesi Keras
- `model.tflite` — per Android
- `model.mlmodel` — per iOS (solo macOS)
- `scaler.json` — parametri normalizzazione

### 4. App Flutter

```bash
cp models/model.tflite  app/assets/
cp models/scaler.json   app/assets/

cd app
flutter create . --project-name road_quality --org com.hackathon.roadquality
# Aggiungi i permessi Android/iOS (vedi app/README.md)
flutter pub get
flutter run
```

Vedi `app/README.md` per i dettagli sul setup Flutter e i permessi nativi.

## Architettura ML

| Parametro | Valore |
|---|---|
| Frequenza campionamento | 50 Hz |
| Finestra | 100 campioni (2 s) |
| Overlap | 50% (step = 50 campioni) |
| Input model | (1, 100, 1) |
| Output | 5 probabilità softmax |
| Post-processing | Majority vote su 3 finestre |

## Note

- Il **server backend** non è incluso. Imposta `_serverUrl` in
  `app/lib/gps_tagger.dart` prima del demo.
- L'export CoreML richiede macOS e `coremltools` (installato automaticamente
  su macOS da `requirements.txt`).
- La calibrazione dell'asse Z assume il telefono fisso nel veicolo.
  Il riorientamento dinamico via magnetometro è una seconda iterazione.
