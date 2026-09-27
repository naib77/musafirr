# Locally hosted face guidance assets

- MediaPipe Tasks Vision 0.10.32: https://www.npmjs.com/package/@mediapipe/tasks-vision/v/0.10.32
- Source: https://github.com/google-ai-edge/mediapipe/tree/v0.10.32
- License: Apache 2.0, included in `vendor/LICENSE`.
- Face Landmarker float16 model bundle, version 1: https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task
- Model cards: https://ai.google.dev/edge/mediapipe/solutions/vision/face_landmarker#models
- Face Mesh V2 license: https://storage.googleapis.com/mediapipe-assets/Model%20Card%20MediaPipe%20Face%20Mesh%20V2.pdf
- Short-range face detector license: https://storage.googleapis.com/mediapipe-assets/MediaPipe%20BlazeFace%20Model%20Card%20(Short%20Range).pdf

The runtime/model are unmodified upstream files. The capture page and challenge state machine are Musafir code. Assets are served from the app origin; face inference does not call Google or a paid service. The browser downloads one WASM variant plus the model on first use. This still uses bandwidth. No biometric accuracy or spoof-resistance certification is claimed.

Recheck licensing, model behavior, hashes, and supported devices before changing versions. The model card describes landmarks and expressions, not identity recognition or presentation-attack detection.
