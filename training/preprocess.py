"""
Preprocessing pipeline: raw CSV (Gonzalez 2017) → finestre normalizzate NumPy.

Struttura dataset attesa:
    data/raw/data/
        potholes/       *.csv  (colonna: acc_z)
        regular_road/   *.csv
        asphalt_bumps/  *.csv
        metal_bumps/    *.csv
        worn_out_road/  *.csv

Lo split train/val/test viene fatto sulle SERIE ORIGINALI (file) prima del
windowing, in modo da garantire che finestre overlappate della stessa serie
non compaiano in split diversi (no data leakage).

Uso:
    python -m training.preprocess

Output in data/processed/:
    X_train.npy, y_train.npy
    X_val.npy,   y_val.npy
    X_test.npy,  y_test.npy

Output in models/:
    scaler.json  (mean + std, stimati solo su train)
"""

import json
import sys
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

from training.config import (
    RAW_DIR, PROCESSED_DIR, MODELS_DIR,
    WINDOW_SIZE, STEP, GRAVITY_ROLLING,
    CLASS_TO_IDX, IDX_TO_CLASS, TEST_SIZE, VAL_SIZE, RANDOM_STATE,
    FOLDER_TO_CLASS, ACC_COLUMN,
)


def load_raw_files(raw_dir):
    """
    Carica tutti i CSV dalle sottocartelle di raw_dir.
    Restituisce lista di (signal_array, class_label).
    """
    if not raw_dir.exists():
        sys.exit(
            f"Cartella dataset non trovata: {raw_dir}\n"
            "Assicurati di aver estratto il dataset in data/raw/."
        )

    found_folders = [d for d in raw_dir.iterdir() if d.is_dir() and d.name in FOLDER_TO_CLASS]
    if not found_folders:
        sys.exit(
            f"Nessuna cartella riconosciuta in {raw_dir}.\n"
            f"Cartelle attese: {list(FOLDER_TO_CLASS.keys())}\n"
            f"Cartelle trovate: {[d.name for d in raw_dir.iterdir() if d.is_dir()]}"
        )

    records = []   # list of (signal: np.ndarray, class_name: str)
    for folder in sorted(found_folders):
        class_name = FOLDER_TO_CLASS[folder.name]
        csv_files = sorted(folder.glob('*.csv'))
        print(f"  {folder.name:20s} → {class_name:15s}  ({len(csv_files)} file)")
        for f in csv_files:
            try:
                df = pd.read_csv(f)
                df.columns = [c.lower().strip() for c in df.columns]
                col = ACC_COLUMN if ACC_COLUMN in df.columns else df.columns[0]
                signal = df[col].dropna().values.astype(float)
                records.append((signal, class_name))
            except Exception as e:
                print(f"    [WARNING] Errore lettura {f.name}: {e} — saltato")

    print(f"\n  Totale serie caricate: {len(records)}")
    return records


def split_series(records):
    """
    Split stratificato sulle SERIE originali (non sulle finestre).
    Restituisce tre liste di (signal, class_name): train, val, test.
    """
    signals = [r[0] for r in records]
    labels  = [r[1] for r in records]

    idx = list(range(len(records)))
    idx_train, idx_tmp = train_test_split(
        idx,
        test_size=TEST_SIZE + VAL_SIZE,
        stratify=labels,
        random_state=RANDOM_STATE,
    )
    labels_tmp = [labels[i] for i in idx_tmp]
    idx_val, idx_test = train_test_split(
        idx_tmp,
        test_size=0.5,
        stratify=labels_tmp,
        random_state=RANDOM_STATE,
    )

    def subset(indices):
        return [records[i] for i in indices]

    return subset(idx_train), subset(idx_val), subset(idx_test)


def detrend(signal: np.ndarray) -> np.ndarray:
    """Rimuove la gravità statica con rolling mean."""
    series = pd.Series(signal)
    win = min(GRAVITY_ROLLING, len(signal))
    return (series - series.rolling(win, min_periods=1).mean()).values


def make_windows(signal: np.ndarray, label_idx: int):
    """
    Sliding window su un singolo segnale.
    File più corti di WINDOW_SIZE vengono paddati con il valor medio.
    """
    X, y = [], []
    if len(signal) < WINDOW_SIZE:
        pad = np.full(WINDOW_SIZE - len(signal), signal.mean() if len(signal) > 0 else 0.0)
        X.append(np.concatenate([signal, pad]))
        y.append(label_idx)
    else:
        for start in range(0, len(signal) - WINDOW_SIZE + 1, STEP):
            X.append(signal[start: start + WINDOW_SIZE])
            y.append(label_idx)
    return X, y


def records_to_arrays(records):
    """Detrend + windowing su una lista di serie. Restituisce X (n,W), y (n,)."""
    all_X, all_y = [], []
    for signal, class_name in records:
        label_idx = CLASS_TO_IDX[class_name]
        sig_dt = detrend(signal)
        X_s, y_s = make_windows(sig_dt, label_idx)
        all_X.extend(X_s)
        all_y.extend(y_s)
    return (
        np.array(all_X, dtype=np.float32),
        np.array(all_y, dtype=np.int32),
    )


def main():
    print(f"Carico file da {RAW_DIR} ...")
    records = load_raw_files(RAW_DIR)

    # --- Split sulle serie originali (no leakage) ---
    print("\nSplit train/val/test sulle serie originali ...")
    train_recs, val_recs, test_recs = split_series(records)
    print(f"  Serie — train: {len(train_recs)}  val: {len(val_recs)}  test: {len(test_recs)}")

    # --- Windowing per split ---
    print("\nWindowing ...")
    X_train, y_train = records_to_arrays(train_recs)
    X_val,   y_val   = records_to_arrays(val_recs)
    X_test,  y_test  = records_to_arrays(test_recs)
    print(f"  Finestre — train: {len(X_train)}  val: {len(X_val)}  test: {len(X_test)}")

    # --- Normalizzazione z-score: fit SOLO su train ---
    print("\nNormalizzazione z-score (fit su train) ...")
    scaler = StandardScaler()
    X_train_norm = scaler.fit_transform(X_train.reshape(-1, 1)).reshape(X_train.shape)
    X_val_norm   = scaler.transform(X_val.reshape(-1, 1)).reshape(X_val.shape)
    X_test_norm  = scaler.transform(X_test.reshape(-1, 1)).reshape(X_test.shape)

    # Reshape finale: (n, WINDOW_SIZE, 1)
    X_train_norm = X_train_norm.reshape(-1, WINDOW_SIZE, 1)
    X_val_norm   = X_val_norm.reshape(-1, WINDOW_SIZE, 1)
    X_test_norm  = X_test_norm.reshape(-1, WINDOW_SIZE, 1)

    # --- Distribuzione classi ---
    print("\nDistribuzione classi (train):")
    unique, counts = np.unique(y_train, return_counts=True)
    for idx, count in zip(unique, counts):
        print(f"  {IDX_TO_CLASS[idx]:15s}: {count}")

    # --- Salvataggio ---
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    np.save(PROCESSED_DIR / 'X_train.npy', X_train_norm)
    np.save(PROCESSED_DIR / 'y_train.npy', y_train)
    np.save(PROCESSED_DIR / 'X_val.npy',   X_val_norm)
    np.save(PROCESSED_DIR / 'y_val.npy',   y_val)
    np.save(PROCESSED_DIR / 'X_test.npy',  X_test_norm)
    np.save(PROCESSED_DIR / 'y_test.npy',  y_test)

    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    scaler_path = MODELS_DIR / 'scaler.json'
    with open(scaler_path, 'w') as f:
        json.dump({'mean': scaler.mean_.tolist(), 'std': scaler.scale_.tolist()}, f, indent=2)

    print(f"\nPreprocessing completato. scaler.json → {scaler_path}")


if __name__ == '__main__':
    main()
