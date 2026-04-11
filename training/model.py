"""
Definizione dell'architettura CNN-1D.

Uso:
    from training.model import build_model
    model = build_model()
    model.summary()
"""

import tensorflow as tf
from training.config import WINDOW_SIZE, N_CLASSES


def build_model(window_size: int = WINDOW_SIZE, n_classes: int = N_CLASSES) -> tf.keras.Model:
    """
    CNN-1D leggera compatibile con TFLite e CoreML.

    Input shape: (batch, window_size, 1)
    Output:      (batch, n_classes) — probabilità softmax
    """
    model = tf.keras.Sequential([
        tf.keras.layers.Conv1D(32, kernel_size=5, activation='relu',
                               input_shape=(window_size, 1)),
        tf.keras.layers.MaxPooling1D(pool_size=2),
        tf.keras.layers.Conv1D(64, kernel_size=3, activation='relu'),
        tf.keras.layers.MaxPooling1D(pool_size=2),
        tf.keras.layers.Flatten(),
        tf.keras.layers.Dense(64, activation='relu'),
        tf.keras.layers.Dropout(0.3),
        tf.keras.layers.Dense(n_classes, activation='softmax'),
    ])

    model.compile(
        optimizer='adam',
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy'],
    )
    return model


if __name__ == '__main__':
    m = build_model()
    m.summary()
