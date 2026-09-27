import {FaceChallenge} from './challenge.mjs';
import {faceMetrics} from './metrics.mjs';
const $ = id => document.getElementById(id);
let config = {};
try { config = JSON.parse(decodeURIComponent(location.hash.slice(1)) || '{}'); } catch { /* Report below, with a usable error screen. */ }
const manual = config?.method === 'manual';
if (/^#[0-9a-f]{6}$/i.test(config?.brand)) document.documentElement.style.setProperty('--brand', config.brand);
let stream, detector, recorder, frame, timeout, loadTimeout;
let running = false, stopping = false, preparing = false, completed = false;
let challenge, lastFrame = -1, lastAnalysis = 0, lastVideoTime = 0, generation = 0;
const video = $('camera');
const send = payload => {
  const message = JSON.stringify({...payload, nonce: config.nonce});
  if (window.FaceCapture) window.FaceCapture.postMessage(message);
  else parent.postMessage(message, location.origin);
};
function clean() {
  generation++; preparing = false; running = false; stopping = false;
  clearTimeout(loadTimeout); clearTimeout(timeout); cancelAnimationFrame(frame);
  if (recorder) {
    recorder.ondataavailable = null; recorder.onerror = null; recorder.onstop = null;
    try { if (recorder.state !== 'inactive') recorder.stop(); } catch { /* Already disconnected. */ }
    recorder = null;
  }
  stream?.getTracks().forEach(track => { track.onended = null; track.stop(); });
  stream = null; video.srcObject = null;
  try { detector?.close(); } catch { /* A failed WASM instance may already be closed. */ }
  detector = null;
}
function fail(message) {
  clean(); $('error').textContent = message; $('error').hidden = false;
  $('instruction').textContent = 'Let’s try again';
  $('oval').classList.remove('ready'); $('progress').value = 0;
  $('start').disabled = false; $('start').textContent = 'Restart camera';
  $('start').onclick = prepare;
}
const encode = blob => new Promise((resolve, reject) => {
  const reader = new FileReader(); reader.onload = () => resolve(reader.result.split(',')[1]);
  reader.onerror = () => reject(Error('Could not read capture')); reader.readAsDataURL(blob);
});
async function selfie() {
  if (!video.videoWidth || !video.videoHeight || video.readyState < 2) throw Error('Camera not ready');
  const canvas = document.createElement('canvas');
  const scale = Math.min(480/video.videoWidth, 640/video.videoHeight);
  canvas.width = Math.round(video.videoWidth*scale); canvas.height = Math.round(video.videoHeight*scale);
  canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
  return new Promise((resolve, reject) => canvas.toBlob(b => b ? resolve(b) : reject(Error('Photo unavailable')), 'image/jpeg', .8));
}
let chunks = [], recordedBytes = 0;
async function finish() {
  if (stopping || completed) return;
  const current = generation;
  stopping = true; running = false; clearTimeout(timeout); cancelAnimationFrame(frame);
  $('start').disabled = true; $('instruction').textContent = 'Preparing your capture';
  try {
    // Snapshot before stopping tracks; stop recording before waiting for photo encoding.
    const photoPromise = selfie();
    const clipPromise = manual ? Promise.resolve(null) : new Promise((resolve, reject) => {
      const active = recorder;
      const guard = setTimeout(() => reject(Error('Recording did not finish')), 5000);
      active.onstop = () => {
        clearTimeout(guard);
        if (current !== generation) { reject(Error('Capture cancelled')); return; }
        resolve(new Blob(chunks, {type:active.mimeType.split(';')[0]}));
      };
      try { active.stop(); } catch (error) { clearTimeout(guard); reject(error); }
    });
    const [photo, clip] = await Promise.all([photoPromise,clipPromise]);
    if (current !== generation) return;
    if (clip && (clip.size > 8388608 || clip.size < 100)) throw Error('Recording size invalid');
    if (photo.size > 524288 || photo.size < 100) throw Error('Photo size invalid');
    const [photoData, clipData] = await Promise.all([encode(photo),clip ? encode(clip) : null]);
    if (current !== generation) return;
    clean(); chunks = []; completed = true;
    send({type:'complete', selfie:photoData, clip:clipData,
      extension:clip?.type.includes('mp4') ? 'mp4' : 'webm', method:config.method});
    $('instruction').textContent = 'Capture ready'; $('hint').textContent = 'Return to Musafir to submit for admin review.';
  } catch { if (current === generation) fail('Could not finish the capture. Restart and try again.'); }
  finally { if (current === generation) stopping = false; }
}
function analyze(time) {
  if (!running) return;
  frame = requestAnimationFrame(analyze);
  if (time - lastAnalysis < 60) return;
  if (video.readyState < 2 || video.currentTime === lastFrame) {
    if (time - lastVideoTime > 5000) fail('Camera preview froze. Restart the camera.');
    return;
  }
  lastFrame = video.currentTime; lastAnalysis = time; lastVideoTime = time;
  try {
    const sample = faceMetrics(detector.detectForVideo(video, time), video.videoWidth/video.videoHeight);
    challenge.update(sample,time);
    const prompt = sample.count === 0 ? 'Look at the camera in even light' : sample.count > 1 ? 'Keep only your face in view' :
      !sample.centered ? 'Fit your whole face in the frame' : challenge.instruction;
    if ($('instruction').textContent !== prompt) $('instruction').textContent = prompt;
    $('progress').value = challenge.index;
    $('step').textContent = `Action ${Math.min(challenge.index+1,3)} of 3`;
    $('hint').textContent = challenge.phase === 'action' && challenge.actions[challenge.index] !== 'blink'
      ? 'Turn your head gently, keep your eyes open, then face the camera again.'
      : 'Keep your phone still. Follow the instruction above.';
    $('oval').classList.toggle('ready',sample.count === 1 && sample.centered);
    if (challenge.complete) void finish();
  } catch { fail('Face guidance stopped. Restart the camera or use manual review.'); }
}
function start() {
  if (running || stopping || completed || !stream) return;
  $('start').disabled = true; $('error').hidden = true;
  if (manual) { void finish(); return; }
  challenge.reset(); chunks = []; recordedBytes = 0; lastFrame = -1; lastAnalysis = 0;
  lastVideoTime = performance.now();
  const current = generation;
  try {
    // A declared codec can still fail to initialize on a particular device.
    for (const type of ['video/webm;codecs=vp8','video/mp4','video/webm']) {
      if (!MediaRecorder.isTypeSupported(type)) continue;
      try {
        recorder = new MediaRecorder(stream, {mimeType:type,videoBitsPerSecond:700000});
        recorder.ondataavailable = event => {
          if (current !== generation) return;
          if (event.data.size) { chunks.push(event.data); recordedBytes += event.data.size; }
          if (recordedBytes > 8388608) fail('Recording is too large. Please try again.');
        };
        recorder.onerror = () => { if (current === generation) fail('Recording stopped. Please try again.'); };
        recorder.start(500);
        break;
      } catch {
        if (recorder) { recorder.ondataavailable = null; recorder.onerror = null; }
        recorder = null; chunks = []; recordedBytes = 0;
      }
    }
    if (!recorder) throw Error('No supported recorder');
    running = true;
    $('start').textContent = 'Face check in progress';
    timeout = setTimeout(() => { if (current === generation) fail('Capture timed out. Try again in brighter light, or use manual review.'); },35000);
    frame = requestAnimationFrame(analyze);
  } catch { fail('Could not record. Try another browser or use manual review.'); }
}
async function playCamera(current) {
  try {
    await video.play();
    if (current !== generation) return;
    // play() resolves once playback starts; frame dimensions are now available.
    clearTimeout(loadTimeout); preparing = false;
    $('progress').hidden = manual; $('progress').value = 0;
    $('step').textContent = manual ? 'Manual review photo' : 'Blink and turn';
    $('instruction').textContent = manual ? 'Look straight at the camera' : 'Look straight ahead';
    $('hint').textContent = manual ? 'This photo needs a separate manual review. No gesture check is recorded.' : 'Follow three short actions. Stay within the frame.';
    send({type:'ready'});
    if (manual) {
      $('start').disabled = false; $('start').textContent = 'Take review photo'; $('start').onclick = start;
    } else start();
  } catch (error) {
    if (current !== generation) return;
    if (error.name === 'NotAllowedError') {
      // Some browsers require a fresh gesture after permission or model loading.
      clearTimeout(loadTimeout); preparing = false;
      $('instruction').textContent = 'Tap to start your camera';
      $('start').disabled = false; $('start').textContent = 'Start camera';
      $('start').onclick = () => { $('start').disabled = true; void playCamera(current); };
    } else fail('Camera preview could not start. Restart and try again.');
  }
}
async function prepare() {
  clean(); completed = false; chunks = [];
  const current = generation; preparing = true;
  loadTimeout = setTimeout(() => { if (current === generation) fail('Camera setup timed out. Retry on a stable connection or use manual review.'); },45000);
  $('error').hidden = true; $('start').disabled = true; $('start').textContent = 'Preparing…';
  $('instruction').textContent = 'Preparing your camera';
  try {
    if (!config?.nonce || !['guided','manual'].includes(config.method)) throw Error('Invalid session');
    if (!navigator.mediaDevices?.getUserMedia || (!manual && !window.MediaRecorder)) throw Error('Unsupported camera');
    if (!manual) challenge = new FaceChallenge(config.actions);
    // Ask for camera access promptly, before the model download/initialization.
    const constraints = {width:{ideal:640},height:{ideal:480},frameRate:{ideal:20,max:24}};
    let opened;
    try {
      opened = await navigator.mediaDevices.getUserMedia({video:{...constraints,facingMode:{exact:'user'}},audio:false});
    } catch (error) {
      if (current !== generation) return;
      if (!['OverconstrainedError','NotFoundError'].includes(error.name)) throw error;
      opened = await navigator.mediaDevices.getUserMedia({video:{...constraints,facingMode:'user'},audio:false});
      if (opened.getVideoTracks()[0]?.getSettings().facingMode === 'environment') {
        opened.getTracks().forEach(track => track.stop()); throw Error('Front camera unavailable');
      }
    }
    if (current !== generation) { opened.getTracks().forEach(t => t.stop()); return; }
    stream = opened; video.srcObject = stream;
    for (const track of stream.getTracks()) track.onended = () => {
      if (current === generation && !stopping) fail('Camera disconnected. Please try again.');
    };
    if (!manual) {
      $('instruction').textContent = 'Preparing face guidance';
      const {FaceLandmarker,FilesetResolver} = await import('./vendor/vision_bundle.mjs');
      if (current !== generation) return;
      const files = await FilesetResolver.forVisionTasks('./vendor/wasm');
      if (current !== generation) return;
      const loaded = await FaceLandmarker.createFromOptions(files, {baseOptions:{modelAssetPath:'./models/face_landmarker.task'},
        runningMode:'VIDEO',numFaces:2,outputFaceBlendshapes:true,minFaceDetectionConfidence:.6,minFacePresenceConfidence:.6});
      if (current !== generation) { loaded.close(); return; }
      detector = loaded;
    }
    if (current !== generation) return;
    await playCamera(current);
  } catch (error) {
    if (current !== generation) return;
    fail(error.name === 'NotAllowedError'
      ? 'Camera access was denied. Allow camera access in your browser or app settings, then retry.'
      : 'Camera or face guidance is unavailable. Retry, or choose manual review.');
  }
}
document.addEventListener('visibilitychange', () => { if (document.hidden && (stream || preparing)) fail('Capture paused. Restart when you return.'); });
window.addEventListener('pagehide', clean);
window.addEventListener('message', event => { if(event.origin===location.origin && event.source===parent && event.data==='stop-face-capture') clean(); });
window.stopFaceCapture = () => { if (!completed) fail('Capture paused. Restart when you return.'); };
void prepare();
