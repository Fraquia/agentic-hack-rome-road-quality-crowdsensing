"""
Export del modello in TFLite (Android) e CoreML (iOS).

Uso:
    python -m training.export

Prerequisiti: aver eseguito train.py e preprocess.py (per scaler.json)

Output in models/:
    model.tflite   (quantizzato int8, per Android)
    model.mlmodel  (CoreML, solo macOS con coremltools)
    scaler.json    (parametri normalizzazione — ridondante rispetto a preprocess, ma garantisce coerenza)
"""

import json
import sys
from pathlib import Path

import numpy as np
import tensorflow as tf

from training.config import MODELS_DIR, PROCESSED_DIR, WINDOW_SIZE


def load_model_and_scaler():
    model_path = MODELS_DIR / 'model.h5'
    scaler_path = MODELS_DIR / 'scaler.json'

    if not model_path.exists():
        sys.exit(f"Modello non trovato: {model_path}. Esegui prima: python -m training.train")
    if not scaler_path.exists():
        sys.exit(f"scaler.json non trovato: {scaler_path}. Esegui prima: python -m training.preprocess")

    model = tf.keras.models.load_model(str(model_path))

    with open(scaler_path) as f:
        scaler_params = json.load(f)

    return model, scaler_params


def export_tflite(model: tf.keras.Model, path: Path = MODELS_DIR / 'model.tflite'):
    """Converte in TFLite con quantizzazione int8."""
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]

    # Representative dataset per la calibrazione int8
    x_train_path = PROCESSED_DIR / 'X_train.npy'
    if x_train_path.exists():
        X_cal = np.load(x_train_path).astype(np.float32)[:200]

        def representative_dataset():
            for sample in X_cal:
                yield [sample[np.newaxis, :, :]]

        converter.representative_dataset = representative_dataset
        converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
        converter.inference_input_type  = tf.float32
        converter.inference_output_type = tf.float32

    tflite_model = converter.convert()
    path.write_bytes(tflite_model)
    print(f"TFLite salvato in {path}  ({len(tflite_model) / 1024:.1f} KB)")


def export_coreml(model: tf.keras.Model, path: Path = MODELS_DIR / 'model.mlmodel'):
    """Converte in CoreML per iOS (richiede macOS + coremltools).

    Usa il formato SavedModel su disco per aggirare l'incompatibilità di
    coremltools con TF > 2.12 quando si passa direttamente l'oggetto Keras.
    """
    try:
        import coremltools as ct
    except ImportError:
        print("[SKIP] coremltools non installato — skip export CoreML.")
        print("       Su macOS: pip install coremltools")
        return

    import tempfile, shutil
    tmp_dir = Path(tempfile.mkdtemp(suffix='_saved_model'))
    try:
        # Salva come SavedModel e converti dal percorso
        model.export(str(tmp_dir))
        input_shape = ct.Shape(shape=(1, WINDOW_SIZE, 1))
        mlmodel = ct.convert(
            str(tmp_dir),
            inputs=[ct.TensorType(shape=input_shape, name='input_layer')],
            source='tensorflow',
            minimum_deployment_target=ct.target.iOS15,
        )
        mlmodel.short_description = 'Road Quality Monitor — CNN-1D 5-class classifier'
        mlmodel.save(str(path))
        print(f"CoreML salvato in {path}")
    except Exception as e:
        print(f"[WARN] Export CoreML fallito: {e}")
        print("       Il modello TFLite per Android è già disponibile.")
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def export_scaler(scaler_params: dict, path: Path = MODELS_DIR / 'scaler.json'):
    """Risalva scaler.json (utile se export.py è lanciato standalone dopo training)."""
    with open(path, 'w') as f:
        json.dump(scaler_params, f, indent=2)
    print(f"scaler.json salvato in {path}")


def main():
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    model, scaler_params = load_model_and_scaler()

    print("Esporto TFLite ...")
    export_tflite(model)

    print("Risalvo scaler.json ...")
    export_scaler(scaler_params)

    print("\nExport completato.")
    print("Copia i file nell'app Flutter:")
    print(f"  cp {MODELS_DIR}/model.tflite  app/assets/")
    print(f"  cp {MODELS_DIR}/scaler.json   app/assets/")


if __name__ == '__main__':
    main()
