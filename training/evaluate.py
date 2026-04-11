"""
Valutazione sul test set.

Uso:
    python -m training.evaluate

Prerequisiti: aver eseguito train.py

Output in models/:
    confusion_matrix.png
"""

import sys
import numpy as np
import matplotlib.pyplot as plt
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix, ConfusionMatrixDisplay

from training.config import PROCESSED_DIR, MODELS_DIR, CLASSES


def main():
    model_path = MODELS_DIR / 'model.h5'
    if not model_path.exists():
        sys.exit(f"Modello non trovato in {model_path}. Esegui prima: python -m training.train")

    X_test_path = PROCESSED_DIR / 'X_test.npy'
    y_test_path = PROCESSED_DIR / 'y_test.npy'
    if not X_test_path.exists():
        sys.exit("Test set mancante. Esegui prima: python -m training.preprocess")

    X_test = np.load(X_test_path)
    y_test = np.load(y_test_path)

    model = tf.keras.models.load_model(str(model_path))
    print(f"Modello caricato da {model_path}\n")

    y_pred_probs = model.predict(X_test, verbose=0)
    y_pred = np.argmax(y_pred_probs, axis=1)

    accuracy = (y_pred == y_test).mean()
    print(f"Accuracy sul test set: {accuracy:.4f}\n")
    print("Report per classe:")
    print(classification_report(y_test, y_pred, target_names=CLASSES))

    cm = confusion_matrix(y_test, y_pred)
    disp = ConfusionMatrixDisplay(confusion_matrix=cm, display_labels=CLASSES)
    fig, ax = plt.subplots(figsize=(8, 6))
    disp.plot(ax=ax, xticks_rotation=45, colorbar=False)
    ax.set_title('Confusion Matrix — Road Quality Monitor')
    plt.tight_layout()

    cm_path = MODELS_DIR / 'confusion_matrix.png'
    plt.savefig(cm_path, dpi=150)
    print(f"Confusion matrix salvata in {cm_path}")


if __name__ == '__main__':
    main()
