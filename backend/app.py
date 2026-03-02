import streamlit as st
import numpy as np
import tensorflow as tf
import tensorflow.keras.backend as K
from tensorflow.keras.layers import Layer
import librosa
import noisereduce as nr
import soundfile as sf
import joblib
import os
import matplotlib.pyplot as plt
import sounddevice as sd
import base64
import plotly.express as px
import time
import pandas as pd
from datetime import datetime
# -------------------------------------------------
# PAGE CONFIG
# -------------------------------------------------
st.set_page_config(
    page_title="Urdu Emotion AI",
    page_icon="🎙️",
    layout="centered"
)

# -------------------------------------------------
# CUSTOM ATTENTION LAYER (must exist before model load)
# -------------------------------------------------
class AttentionLayer(Layer):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def build(self, input_shape):
        self.W = self.add_weight(
            name='att_weight', shape=(input_shape[-1], input_shape[-1]),
            initializer='glorot_uniform', trainable=True
        )
        self.b = self.add_weight(
            name='att_bias', shape=(input_shape[-1],),
            initializer='zeros', trainable=True
        )
        super().build(input_shape)

    def call(self, x):
        e = K.tanh(K.dot(x, self.W) + self.b)
        a = K.softmax(e, axis=1)
        return K.sum(x * a, axis=1)

    def compute_output_shape(self, input_shape):
        return (input_shape[0], input_shape[-1])

    def get_config(self):
        return super().get_config()

# -------------------------------------------------
# FEATURE EXTRACTION CONFIG (must match training exactly)
# -------------------------------------------------
TARGET_SR = 22050
N_MFCC = 20
HOP_LENGTH = 512
TARGET_DURATION = 3.0
MAX_FRAMES = int(np.ceil(TARGET_SR * TARGET_DURATION / HOP_LENGTH))

# -------------------------------------------------
# SESSION STATE
# -------------------------------------------------
for key, default in {
    "logged_in": False,
    "username": "",
    "role": None
}.items():
    if key not in st.session_state:
        st.session_state[key] = default

# -------------------------------------------------
# SIDEBAR (ADMIN ONLY)
# -------------------------------------------------
if st.session_state.logged_in:
    with st.sidebar:
        st.success(f"Logged in as {st.session_state.username}")
        st.caption(f"Role: {st.session_state.role}")

        if st.session_state.role == "admin":
            st.markdown("### Admin")
            st.page_link("pages/Dashboard.py", label="📊 Dashboard")

        if st.button("Logout"):
            st.session_state.logged_in = False
            st.session_state.role = None
            st.rerun()

# -------------------------------------------------
# LOGO
# -------------------------------------------------
def display_logo(logo_filename="nobg_logo.png", width=180):
    if os.path.exists(logo_filename):
        with open(logo_filename, "rb") as f:
            encoded = base64.b64encode(f.read()).decode()
        st.markdown(
            f"<div style='text-align:center; margin-bottom:20px;'>"
            f"<img src='data:image/png;base64,{encoded}' style='width:{width}px;'/>"
            "</div>",
            unsafe_allow_html=True
        )

# -------------------------------------------------
# LOGIN PAGE
# -------------------------------------------------
def login_page():
    display_logo()

    st.markdown("""
    <style>
    .login-card input {
        background:#2a2a38;color:white;border-radius:10px;
        border:1px solid #555;padding:0.5rem;width:100%;
    }
    .login-card button {
        background:#00adb5;color:white;border:none;
        border-radius:10px;padding:0.6rem;width:100%;
        font-weight:600;
    }
    </style>
    """, unsafe_allow_html=True)

    st.markdown("<div class='login-card'>", unsafe_allow_html=True)
    st.markdown("<h2 style='text-align:center;'>Login</h2>", unsafe_allow_html=True)

    role = st.radio("Login as", ["User", "Admin"], horizontal=True)
    username = st.text_input("Username")
    password = st.text_input("Password", type="password")

    if st.button("Login"):
        if role == "Admin" and username == "admin" and password == "admin":
            st.session_state.logged_in = True
            st.session_state.username = username
            st.session_state.role = "admin"
            st.rerun()

        elif role == "User" and username == "user" and password == "user":
            st.session_state.logged_in = True
            st.session_state.username = username
            st.session_state.role = "user"
            st.rerun()
        else:
            st.error("❌ Invalid credentials")

    st.markdown("</div>", unsafe_allow_html=True)

# -------------------------------------------------
# LOAD MODEL
# -------------------------------------------------
@st.cache_resource
def load_model_and_artifacts():
    model = tf.keras.models.load_model(
        "waleed_final_lstm.keras",
        custom_objects={"AttentionLayer": AttentionLayer}
    )
    le = joblib.load("label_encoder.joblib")
    scaler = joblib.load("waleed_mfcc_scaler.joblib")
    return model, le, scaler

# -------------------------------------------------
# AUDIO PREPROCESSING (same as training pipeline)
# -------------------------------------------------
def preprocess_audio(y, sr):
    """Exact same preprocessing used during training."""
    # Remove silence
    intervals = librosa.effects.split(y, top_db=20)
    if len(intervals) > 0:
        y = np.concatenate([y[start:end] for start, end in intervals])

    # Normalize
    peak = np.max(np.abs(y))
    if peak > 0:
        y = y / peak

    # Noise reduction
    try:
        y = nr.reduce_noise(y=y, sr=sr, prop_decrease=0.8)
    except:
        pass

    return y

# -------------------------------------------------
# FEATURE EXTRACTION (same as training pipeline)
# -------------------------------------------------
def extract_and_scale_features(file_path, scaler):
    """Extract features using the EXACT same method as training."""
    y, sr = librosa.load(file_path, sr=TARGET_SR, mono=True)

    # Preprocess (critical for real-world audio)
    y = preprocess_audio(y, sr)

    # MFCCs + derivatives
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=N_MFCC, hop_length=HOP_LENGTH)
    delta1 = librosa.feature.delta(mfcc)
    delta2 = librosa.feature.delta(mfcc, order=2)

    # Spectral contrast
    spec_contrast = librosa.feature.spectral_contrast(y=y, sr=sr, hop_length=HOP_LENGTH)
    if spec_contrast.shape[0] < N_MFCC:
        spec_contrast = np.pad(spec_contrast,
                               ((0, N_MFCC - spec_contrast.shape[0]), (0, 0)),
                               mode='edge')
    else:
        spec_contrast = spec_contrast[:N_MFCC, :]

    # Stack and transpose to (time, features)
    features = np.vstack([mfcc, delta1, delta2, spec_contrast]).T

    # Pad or truncate to fixed length
    if features.shape[0] < MAX_FRAMES:
        pad_width = MAX_FRAMES - features.shape[0]
        features = np.pad(features, ((0, pad_width), (0, 0)),
                         mode='constant', constant_values=0)
    else:
        features = features[:MAX_FRAMES, :]

    # Scale using training scaler
    n_features = features.shape[1]
    features_scaled = scaler.transform(features.reshape(-1, n_features))
    features_scaled = features_scaled.reshape(features.shape)

    return features_scaled.astype("float32")

# -------------------------------------------------
# SAVE AUDIO + METADATA
# -------------------------------------------------
def save_prediction(audio_path, emotion, confidence, input_type):
    os.makedirs("logs", exist_ok=True)
    os.makedirs(f"recordings/{emotion}", exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{emotion}_{timestamp}.wav"
    save_path = os.path.join("recordings", emotion, filename)

    y, sr = librosa.load(audio_path, sr=TARGET_SR)
    sf.write(save_path, y, sr)

    log_path = "logs/predictions.csv"
    row = {
        "timestamp": timestamp,
        "emotion": emotion,
        "confidence": round(confidence, 2),
        "input_type": input_type,
        "audio_file": save_path
    }

    if os.path.exists(log_path):
        df = pd.read_csv(log_path)
        df = pd.concat([df, pd.DataFrame([row])], ignore_index=True)
    else:
        df = pd.DataFrame([row])

    df.to_csv(log_path, index=False)

# -------------------------------------------------
# MAIN APP
# -------------------------------------------------
def main_app():
    display_logo()

    st.markdown("<h1 style='text-align:center;'>Urdu Emotion Recognition</h1>", unsafe_allow_html=True)
    st.markdown("<p style='text-align:center;'>Upload or record an Urdu audio clip</p>", unsafe_allow_html=True)

    temp_path = "temp_audio.wav"
    audio_ready = False
    input_type = None

    mode = st.radio("Input Method", ["Upload Audio", "Record Live"], horizontal=True)

    # UPLOAD
    if mode == "Upload Audio":
        uploaded = st.file_uploader("Upload audio", type=["wav", "mp3", ".ogg", ".opus"])
        if uploaded:
            with open(temp_path, "wb") as f:
                f.write(uploaded.getbuffer())

            st.audio(uploaded)

            audio, _ = librosa.load(temp_path, sr=TARGET_SR)
            fig, ax = plt.subplots(figsize=(8, 2))
            ax.plot(audio)
            ax.axis("off")
            st.pyplot(fig)
            plt.close(fig)

            audio_ready = True
            input_type = "Upload"

    # RECORD
    else:
        duration = st.slider("Duration (seconds)", 2, 15, 5)
        sr = TARGET_SR
        chunk_len = int(sr * 0.12)

        if st.button("Start Recording"):
            frames = []
            progress = st.progress(0)
            waveform = st.empty()

            with sd.InputStream(samplerate=sr, channels=1, dtype="float32") as stream:
                total_chunks = int(duration / 0.12)
                for i in range(total_chunks):
                    data, _ = stream.read(chunk_len)
                    frames.append(data.copy())

                    audio_so_far = np.concatenate(frames, axis=0)
                    fig, ax = plt.subplots(figsize=(7, 2))
                    ax.plot(audio_so_far)
                    ax.axis("off")
                    waveform.pyplot(fig)
                    plt.close(fig)

                    progress.progress((i + 1) / total_chunks)
                    time.sleep(0.01)

            audio = np.concatenate(frames).flatten()
            sf.write(temp_path, audio, sr)
            st.audio(temp_path)

            audio_ready = True
            input_type = "Record"

    # PREDICTION
    if audio_ready:
        model, le, scaler = load_model_and_artifacts()

        features = extract_and_scale_features(temp_path, scaler)
        features = np.expand_dims(features, axis=0)

        preds = model.predict(features, verbose=0)
        idx = int(np.argmax(preds))
        emotion = le.classes_[idx]
        confidence = preds[0][idx] * 100

        st.success(f"Emotion: {emotion}")
        st.write(f"Confidence: {confidence:.2f}%")

        fig = px.bar(x=le.classes_, y=preds[0])
        st.plotly_chart(fig, use_container_width=True)

        # ✅ SAVE EVERYTHING
        save_prediction(temp_path, emotion, confidence, input_type)

# -------------------------------------------------
# ENTRY POINT
# -------------------------------------------------
if not st.session_state.logged_in:
    login_page()
else:
    main_app()