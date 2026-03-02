"""
FastAPI backend for Urdu Speech Emotion Recognition.

Run with:
    uvicorn main:app --host 0.0.0.0 --port 8000
"""

import json
import os
import tempfile
from contextlib import asynccontextmanager

import firebase_admin
import numpy as np
import joblib
import tensorflow as tf
from fastapi import FastAPI, File, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from firebase_admin import credentials, firestore, messaging
from pydantic import BaseModel

from attention_layer import AttentionLayer
from audio_processing import extract_and_scale_features

# ── Global references (populated at startup) ─────────────────────────────
model = None
label_encoder = None
scaler = None

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


# ── Firebase Admin init (runs once at import time) ───────────────────────
_sa_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "")
if _sa_json and not firebase_admin._apps:
    firebase_admin.initialize_app(credentials.Certificate(json.loads(_sa_json)))


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load model and artifacts once at startup."""
    global model, label_encoder, scaler

    model = tf.keras.models.load_model(
        os.path.join(BASE_DIR, "waleed_final_lstm.keras"),
        custom_objects={"AttentionLayer": AttentionLayer},
    )
    label_encoder = joblib.load(os.path.join(BASE_DIR, "label_encoder.joblib"))
    scaler = joblib.load(os.path.join(BASE_DIR, "waleed_mfcc_scaler.joblib"))

    print("✅ Model, label encoder, and scaler loaded successfully.")
    yield  # application runs here
    print("🛑 Shutting down.")


# ── FastAPI app ──────────────────────────────────────────────────────────
app = FastAPI(
    title="Urdu Emotion Recognition API",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Routes ───────────────────────────────────────────────────────────────
@app.get("/health")
async def health():
    """Liveness check."""
    return {"status": "ok"}


@app.post("/predict")
async def predict(file: UploadFile = File(...)):
    """
    Accept an audio file, extract features, and return the predicted emotion.

    Returns:
        {"emotion": str, "confidence": float, "all_scores": {label: float}}
    """
    if model is None or scaler is None or label_encoder is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet.")

    # Save uploaded file to a temporary location
    suffix = os.path.splitext(file.filename or "audio.wav")[1] or ".wav"
    tmp_fd, tmp_path = tempfile.mkstemp(suffix=suffix)
    try:
        contents = await file.read()
        with os.fdopen(tmp_fd, "wb") as tmp_file:
            tmp_file.write(contents)

        # Feature extraction (identical to training pipeline)
        features = extract_and_scale_features(tmp_path, scaler)
        features = np.expand_dims(features, axis=0)  # (1, frames, features)

        # Prediction
        preds = model.predict(features, verbose=0)
        idx = int(np.argmax(preds))
        emotion = label_encoder.classes_[idx]
        confidence = round(float(preds[0][idx]) * 100, 2)

        all_scores = {
            str(label_encoder.classes_[i]): round(float(preds[0][i]) * 100, 2)
            for i in range(len(label_encoder.classes_))
        }
        return {"emotion": emotion, "confidence": confidence, "all_scores": all_scores}

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Prediction failed: {e}")
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


# ── Push notifications ───────────────────────────────────────────────────

class NotificationRequest(BaseModel):
    title: str
    body: str
    target: str  # "All Users" or "Active Users"


@app.post("/send-notification")
async def send_notification(
    req: NotificationRequest,
    x_admin_secret: str = Header(...),
):
    """Send a push notification to all (non-blocked) users via FCM."""
    if x_admin_secret != os.environ.get("ADMIN_NOTIFICATION_SECRET", ""):
        raise HTTPException(status_code=403, detail="Unauthorized")

    if not firebase_admin._apps:
        raise HTTPException(status_code=503, detail="Firebase not initialized. Set FIREBASE_SERVICE_ACCOUNT secret.")

    db = firestore.client()
    tokens = []
    for doc in db.collection("users").stream():
        u = doc.to_dict()
        if u.get("role") == "admin":
            continue
        if u.get("isBlocked"):
            continue
        token = u.get("fcmToken")
        if token:
            tokens.append(token)

    if not tokens:
        return {"sent": 0, "total": 0}

    sent = 0
    for i in range(0, len(tokens), 500):
        batch = tokens[i : i + 500]
        msg = messaging.MulticastMessage(
            tokens=batch,
            notification=messaging.Notification(title=req.title, body=req.body),
            android=messaging.AndroidConfig(priority="high"),
        )
        result = messaging.send_each_for_multicast(msg)
        sent += result.success_count

    return {"sent": sent, "total": len(tokens)}
