// Run: NODE_PATH=<playwright node_modules> node --test test/verification/face_capture_browser_test.cjs
// Deterministic camera/landmark fixtures exercise the real capture page, not biometric accuracy.
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const {createServer} = require('node:http');
const {readFile} = require('node:fs/promises');
const path = require('node:path');
const {chromium} = require('playwright');
let server, browser, origin;
before(async () => {
  server = createServer(async (req, res) => {
    try {
      const name = new URL(req.url, 'http://localhost').pathname;
      if (!name.startsWith('/face/') || name.includes('..')) throw Error('Bad path');
      res.setHeader('Content-Type', name.endsWith('.mjs') ? 'text/javascript' : name.endsWith('.html') ? 'text/html' : 'application/octet-stream');
      res.end(await readFile(path.join(process.env.FACE_TEST_ROOT || path.join(__dirname, '../../web'), name)));
    } catch { res.writeHead(404); res.end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch({channel: 'chrome', headless: true,
    args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream']});
});
after(async () => { await browser?.close(); await new Promise(resolve => server?.close(resolve)); });
async function pageFor(t, options = {}) {
  const context = await browser.newContext({permissions:['camera'], viewport:{width:390,height:844}});
  t.after(() => context.close());
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  t.after(() => assert.deepEqual(errors, [], 'No unhandled page errors'));
  await page.addInitScript(options => {
    window.testOptions = options;
    window.messages = [];
    window.addEventListener('message', event => {try { window.messages.push(JSON.parse(event.data)); } catch {}});
    window.sample = {yaw:options.neutralYaw || 0, blink:0, count:1};
    if (options.delayPhoto) {
      const toBlob = HTMLCanvasElement.prototype.toBlob;
      HTMLCanvasElement.prototype.toBlob = function (...args) { window.releasePhoto = () => toBlob.apply(this,args); };
    }
    window.detectCalls = 0;
    window.detectorClosed = 0;
    const originalPlay = HTMLMediaElement.prototype.play;
    let plays = 0;
    HTMLMediaElement.prototype.play = function () {
      if (options.rejectAutoplay && plays++ === 0) return Promise.reject(new DOMException('Tap required', 'NotAllowedError'));
      return originalPlay.call(this);
    };
    if (options.rejectCodec) {
      const Recorder = window.MediaRecorder;
      window.MediaRecorder = class extends Recorder {
        constructor(stream, settings) {
          if (settings.mimeType.includes('vp8')) throw Error('Codec initialization failed');
          super(stream,settings);
        }
      };
    }
    if (options.denyCamera) {
      navigator.mediaDevices.getUserMedia = async () => {throw new DOMException('Denied','NotAllowedError');};
    }
    if (options.delayCamera) {
      const get = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
      navigator.mediaDevices.getUserMedia = async (...args) => {
        await new Promise(resolve => window.releaseCamera = resolve);
        return get(...args);
      };
    }
  }, options);
  if (!options.realModel) await page.route('**/vendor/vision_bundle.mjs', route => route.fulfill({contentType:'text/javascript',body:`
    export const FilesetResolver = {forVisionTasks: async () => ({})};
    export const FaceLandmarker = {createFromOptions: async () => ({
      close() {window.detectorClosed++;},
      detectForVideo() {
        window.detectCalls++;
        if (window.testOptions.throwDetector) throw Error('Inference failed');
        const s = window.sample;
        const points = Array.from({length:478}, () => ({x:.5,y:.5,z:0}));
        points[33]={x:.35,y:.4}; points[263]={x:.65,y:.4}; points[1]={x:.5+s.yaw*.3,y:.5};
        points[10]={x:.5,y:.18}; points[152]={x:.5,y:.82}; points[234]={x:.25,y:.5}; points[454]={x:.75,y:.5};
        return {faceLandmarks:Array.from({length:s.count}, () => points),faceBlendshapes:[{categories:[
          {categoryName:'eyeBlinkLeft',score:s.blink},{categoryName:'eyeBlinkRight',score:s.blink}]}]};
      }
    })};
  `}));
  const config = {nonce:'test',method:options.manual?'manual':'guided',actions:['left','right','blink']};
  await page.goto(`${origin}/face/index.html#${options.badConfig ? '%INVALID' : encodeURIComponent(JSON.stringify(config))}`);
  return page;
}
test('guided capture starts automatically once camera and model are ready', async t => {
  const page = await pageFor(t);
  await page.waitForFunction(() => window.detectCalls > 0, null, {timeout:3000});
});
test('autoplay rejection offers a tap that resumes the same camera', async t => {
  const page = await pageFor(t, {rejectAutoplay:true});
  await page.getByRole('button', {name:'Start camera',exact:true}).click({timeout:3000});
  await page.waitForFunction(() => window.detectCalls > 0, null, {timeout:3000});
});
test('manual capture never takes a photo automatically', async t => {
  const page = await pageFor(t, {manual:true});
  await page.getByRole('button', {name:'Take review photo',exact:true}).waitFor();
  assert.equal(await page.evaluate(() => window.messages.some(m => m.type === 'complete')), false);
  await page.getByRole('button', {name:'Take review photo',exact:true}).click();
  await page.waitForFunction(() => window.messages.some(m => m.type === 'complete'));
});
test('cancel during photo encoding cannot send a stale completed capture', async t => {
  const page = await pageFor(t, {manual:true,delayPhoto:true});
  await page.getByRole('button', {name:'Take review photo',exact:true}).click();
  await page.waitForFunction(() => !!window.releasePhoto);
  await page.evaluate(() => window.stopFaceCapture());
  await page.getByRole('button', {name:'Restart camera',exact:true}).click();
  await page.getByRole('button', {name:'Take review photo',exact:true}).waitFor();
  await page.evaluate(() => window.releasePhoto());
  await page.waitForTimeout(200);
  assert.equal(await page.evaluate(() => window.messages.some(m => m.type === 'complete')), false);
});
test('late camera permission after cancellation releases the stream', async t => {
  const page = await pageFor(t, {delayCamera:true});
  await page.waitForFunction(() => !!window.releaseCamera);
  await page.evaluate(() => {window.stopFaceCapture(); window.releaseCamera();});
  await page.waitForTimeout(300);
  assert.equal(await page.evaluate(() => document.querySelector('video').srcObject), null);
  assert.equal(await page.evaluate(() => window.detectCalls), 0);
});
test('inference failure releases model and camera, then retry starts cleanly', async t => {
  const page = await pageFor(t, {throwDetector:true});
  await page.getByRole('button', {name:'Restart camera',exact:true}).waitFor({timeout:3000});
  assert.equal(await page.evaluate(() => window.detectorClosed), 1);
  assert.equal(await page.evaluate(() => document.querySelector('video').srcObject), null);
  await page.evaluate(() => window.testOptions.throwDetector = false);
  await page.getByRole('button', {name:'Restart camera',exact:true}).click();
  await page.waitForFunction(() => window.detectCalls > 2);
});
test('guided left, right and blink capture produces one bounded video and selfie', async t => {
  const page = await pageFor(t, {neutralYaw:.1});
  const instruction = page.locator('#instruction');
  for (const [prompt,sample,returnPrompt] of [
    ['Slowly turn your head left',{yaw:.34},'Look straight ahead again'],
    ['Slowly turn your head right',{yaw:-.14},'Look straight ahead again'],
    ['Blink naturally',{blink:.9},'Open your eyes'],
  ]) {
    await page.waitForFunction(text => document.getElementById('instruction').textContent === text, prompt, {timeout:4000});
    await page.evaluate(sample => Object.assign(window.sample,sample),sample);
    await page.waitForFunction(text => document.getElementById('instruction').textContent === text, returnPrompt, {timeout:4000});
    await page.evaluate(() => Object.assign(window.sample,{yaw:.1,blink:0}));
  }
  await page.waitForFunction(() => window.messages.some(m => m.type === 'complete'));
  const messages = await page.evaluate(() => window.messages.filter(m => m.type === 'complete'));
  assert.equal(messages.length,1);
  const capture = messages[0];
  assert.equal(capture.method,'guided'); assert.equal(capture.nonce,'test');
  assert.ok(Buffer.from(capture.selfie,'base64').length >= 100);
  assert.ok(Buffer.from(capture.clip,'base64').length >= 100);
  assert.ok(Buffer.from(capture.clip,'base64').length <= 8388608);
  assert.equal(await page.evaluate(() => document.querySelector('video').srcObject), null);
  await page.evaluate(() => window.stopFaceCapture());
  assert.equal(await instruction.textContent(),'Capture ready');
});
test('real bundled model loads and a synthetic camera without a face never passes', async t => {
  const page = await pageFor(t, {realModel:true});
  await page.waitForFunction(() => document.getElementById('instruction').textContent === 'Look at the camera in even light', null, {timeout:45000});
  assert.equal(await page.evaluate(() => window.messages.some(m => m.type === 'complete')),false);
  await page.evaluate(() => window.stopFaceCapture());
  await page.getByRole('button',{name:'Restart camera',exact:true}).waitFor();
});
test('recorder falls back when an advertised codec fails to initialize',async t => {
  const page = await pageFor(t,{rejectCodec:true});
  await page.waitForFunction(() => window.detectCalls > 0,null,{timeout:3000});
});
test('denied camera and malformed session both display recoverable errors',async t => {
  for(const options of [{denyCamera:true},{badConfig:true}]) {
    const page = await pageFor(t,options);
    await page.getByRole('button',{name:'Restart camera',exact:true}).waitFor({timeout:3000});
    assert.equal(await page.locator('#error').isVisible(),true);
    assert.equal(await page.evaluate(() => window.messages.some(m => m.type === 'complete')),false);
  }
});
test('multiple faces and a wrong turn cannot complete an action',async t => {
  const page = await pageFor(t);
  await page.waitForFunction(() => document.getElementById('instruction').textContent === 'Slowly turn your head left');
  await page.evaluate(() => Object.assign(window.sample,{yaw:-.35}));
  await page.waitForTimeout(400);
  assert.equal(await page.locator('#progress').evaluate(element => element.value),0);
  await page.evaluate(() => Object.assign(window.sample,{count:2,yaw:.35}));
  await page.waitForFunction(() => document.getElementById('instruction').textContent === 'Keep only your face in view');
  assert.equal(await page.locator('#progress').evaluate(element => element.value),0);
  assert.equal(await page.evaluate(() => window.messages.some(m => m.type === 'complete')),false);
});
