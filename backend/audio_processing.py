"""
Audio preprocessing and feature extraction pipeline.
Mirrors the exact training-time pipeline to ensure consistent predictions.
"""

import numpy as np
import librosa
import noisereduce as nr

# ── Feature extraction config (must match training exactly) ──────────────
TARGET_SR = 22050
N_MFCC = 20
HOP_LENGTH = 512
TARGET_DURATION = 3.0
MAX_FRAMES = int(np.ceil(TARGET_SR * TARGET_DURATION / HOP_LENGTH))


def preprocess_audio(y: np.ndarray, sr: int) -> np.ndarray:
    """Silence removal, peak normalisation, and noise reduction."""

    # Remove silence
    intervals = librosa.effects.split(y, top_db=20)
    if len(intervals) > 0:
        y = np.concatenate([y[start:end] for start, end in intervals])

    # Peak normalisation
    peak = np.max(np.abs(y))
    if peak > 0:
        y = y / peak

    # Noise reduction
    try:
        y = nr.reduce_noise(y=y, sr=sr, prop_decrease=0.8)
    except Exception:
        pass

    return y


def extract_and_scale_features(file_path: str, scaler) -> np.ndarray:
    """
    Extract MFCC + delta + delta-delta + spectral contrast features,
    pad/truncate to MAX_FRAMES, and scale using the saved training scaler.

    Returns a float32 array of shape (MAX_FRAMES, 80).
    """

    y, sr = librosa.load(file_path, sr=TARGET_SR, mono=True)
    y = preprocess_audio(y, sr)

    # MFCCs + derivatives
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=N_MFCC, hop_length=HOP_LENGTH)
    delta1 = librosa.feature.delta(mfcc)
    delta2 = librosa.feature.delta(mfcc, order=2)

    # Spectral contrast (7 bands → pad/trim to N_MFCC rows)
    spec_contrast = librosa.feature.spectral_contrast(
        y=y, sr=sr, hop_length=HOP_LENGTH
    )
    if spec_contrast.shape[0] < N_MFCC:
        spec_contrast = np.pad(
            spec_contrast,
            ((0, N_MFCC - spec_contrast.shape[0]), (0, 0)),
            mode="edge",
        )
    else:
        spec_contrast = spec_contrast[:N_MFCC, :]

    # Stack → (time, features)
    features = np.vstack([mfcc, delta1, delta2, spec_contrast]).T

    # Pad or truncate to fixed length
    if features.shape[0] < MAX_FRAMES:
        pad_width = MAX_FRAMES - features.shape[0]
        features = np.pad(
            features, ((0, pad_width), (0, 0)), mode="constant", constant_values=0
        )
    else:
        features = features[:MAX_FRAMES, :]

    # Scale using the saved training scaler
    n_features = features.shape[1]
    features_scaled = scaler.transform(features.reshape(-1, n_features))
    features_scaled = features_scaled.reshape(features.shape)

    return features_scaled.astype("float32")
