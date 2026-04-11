from pathlib import Path

# --- Segnale ---
WINDOW_SIZE = 200        # campioni per finestra (4 s a 50 Hz)
OVERLAP     = 0.5
STEP        = int(WINDOW_SIZE * (1 - OVERLAP))   # 50 campioni = 1 s
SAMPLE_RATE = 50         # Hz
GRAVITY_ROLLING = 500    # campioni usati per stimare la gravità statica

# --- Dataset ---
CLASSES = ['smooth', 'pothole', 'asphalt_bump', 'metal_bump', 'worn_road']
N_CLASSES = len(CLASSES)
CLASS_TO_IDX = {c: i for i, c in enumerate(CLASSES)}
IDX_TO_CLASS = {i: c for i, c in enumerate(CLASSES)}

# --- Split ---
TEST_SIZE  = 0.15
VAL_SIZE   = 0.15
RANDOM_STATE = 42

# --- Training ---
EPOCHS     = 50
BATCH_SIZE = 32
PATIENCE   = 10   # EarlyStopping

# --- Mapping cartelle dataset → classi interne ---
# Struttura reale: data/raw/data/FOLDER_NAME/*.csv
FOLDER_TO_CLASS = {
    'potholes':      'pothole',
    'regular_road':  'smooth',
    'asphalt_bumps': 'asphalt_bump',
    'metal_bumps':   'metal_bump',
    'worn_out_road': 'worn_road',
}
# Nome colonna accelerometro nei CSV del dataset Gonzalez 2017
ACC_COLUMN = 'acc_z'

# --- Paths ---
BASE_DIR      = Path(__file__).resolve().parent.parent
RAW_DIR       = BASE_DIR / 'data' / 'raw' / 'data'   # sottocartella del dataset
PROCESSED_DIR = BASE_DIR / 'data' / 'processed'
MODELS_DIR    = BASE_DIR / 'models'
