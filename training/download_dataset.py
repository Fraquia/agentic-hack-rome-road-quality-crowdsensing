"""
Helper per la verifica e il download del dataset.

Uso:
    python -m training.download_dataset

Verifica che i file CSV/HDF5 siano presenti in data/raw/.
Se assenti, stampa le istruzioni manuali.
"""

import sys
from training.config import RAW_DIR


DATASET_URL = 'https://www.accelerometer.xyz/datasets/'


def main():
    csv_files = list(RAW_DIR.glob('*.csv'))
    hdf_files = list(RAW_DIR.glob('*.h5')) + list(RAW_DIR.glob('*.hdf5'))
    found = csv_files + hdf_files

    if found:
        print(f"Dataset trovato: {len(found)} file in {RAW_DIR}")
        for f in sorted(found):
            print(f"  {f.name}")
        print("\nPuoi procedere con: python -m training.preprocess")
    else:
        print("Dataset non trovato.\n")
        print("Istruzioni per il download manuale:")
        print(f"  1. Visita {DATASET_URL}")
        print( "  2. Scarica il dataset di accelerometri stradali (500 time series, 5 classi).")
        print(f"  3. Estrai i file CSV/HDF5 nella cartella: {RAW_DIR.resolve()}")
        print( "  4. Assicurati che ogni file contenga le colonne: z, label")
        print( "     (oppure che il nome del file contenga il nome della classe,")
        print( "      es. smooth_001.csv, pothole_042.csv).")
        print( "  5. Rilancia questo script per verificare: python -m training.download_dataset")
        sys.exit(1)


if __name__ == '__main__':
    main()
