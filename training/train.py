"""
Training loop.

Uso:
    python -m training.train

Prerequisiti: aver eseguito python -m training.preprocess

Output in models/:
    model.h5       (pesi migliori su val_loss)
    history.json   (loss/accuracy per epoch)
"""

import json
import numpy as np
import tensorflow as tf
from pathlib import Path
from sklearn.utils.class_weight import compute_class_weight

from training.config import (
    PROCESSED_DIR, MODELS_DIR,
    EPOCHS, BATCH_SIZE, PATIENCE,
)
from training.model import build_model


def load_processed():
    def _load(split):
        X = np.load(PROCESSED_DIR / f'X_{split}.npy')
        y = np.load(PROCESSED_DIR / f'y_{split}.npy')
        return X, y

    missing = [
        p for p in ['X_train', 'y_train', 'X_val', 'y_val']
        if not (PROCESSED_DIR / f'{p}.npy').exists()
    ]
    if missing:
        import sys
        sys.exit(
            f"File mancanti in {PROCESSED_DIR}: {missing}\n"
            "Esegui prima: python -m training.preprocess"
        )

    return _load('train'), _load('val')


def main():
    MODELS_DIR.mkdir(parents=True, exist_ok=True)

    (X_train, y_train), (X_val, y_val) = load_processed()
    print(f"Train: {len(X_train)}  Val: {len(X_val)}")

    weights = compute_class_weight('balanced', classes=np.unique(y_train), y=y_train)
    class_weight = dict(enumerate(weights))
    print(f"Class weights: { {k: f'{v:.2f}' for k, v in class_weight.items()} }")

    model = build_model()
    model.summary()

    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor='val_loss',
            patience=PATIENCE,
            restore_best_weights=True,
            verbose=1,
        ),
        tf.keras.callbacks.ModelCheckpoint(
            filepath=str(MODELS_DIR / 'model.h5'),
            monitor='val_loss',
            save_best_only=True,
            verbose=1,
        ),
    ]

    history = model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        class_weight=class_weight,
        callbacks=callbacks,
        verbose=1,
    )

    history_path = MODELS_DIR / 'history.json'
    with open(history_path, 'w') as f:
        json.dump(
            {k: [float(v) for v in vals] for k, vals in history.history.items()},
            f,
            indent=2,
        )
    print(f"\nTraining completato. Modello in {MODELS_DIR / 'model.h5'}")
    print(f"History in {history_path}")


if __name__ == '__main__':
    main()
