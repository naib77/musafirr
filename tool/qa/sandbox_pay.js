// Drive one SSLCommerz SANDBOX payment against the LOCAL stack, headless.
//
//   supabase start && supabase functions serve --env-file supabase/functions/.env.local --no-verify-jwt
//   node tool/qa/sandbox_pay.js <gateway_url> success       # OUTCOME=Success|"Success with risk"|Failed
//   node tool/qa/sandbox_pay.js <gateway_url> cancel
//
// Needs: `npm i playwright` somewhere on NODE_PATH, and PW_BIN pointing at a
// Chromium binary (a cached ~/Library/Caches/ms-playwright/chromium-*/… works).
//
// Two things here are not obvious. The functions run inside Docker, so the
// success/fail/cancel URLs sslcommerz-init hands the gateway are
// http://kong:8000/…; the browser cannot resolve that host, so page.route()
// rewrites those requests to http://127.0.0.1:54321 — that is the ONLY way the
// redirect settlement reaches the local database. And Chrome interposes an
// "insecure form submission" interstitial when the HTTPS bank page posts to
// that plain-HTTP URL, so the launch args disable it for this headless run.
// Server-to-server IPN never reaches localhost; the redirect path settles alone.
//
// Sandbox test card: 4111 1111 1111 1111, any future expiry, any CVC. The bank
// page then offers Success / Success with risk / Failed buttons; the checkout's
// only cancel affordance is the X icon (coordinates below are for 1200x900).
const { chromium } = require('playwright');
const LOCAL = 'http://127.0.0.1:54321';
const dump = async (page, tag) => {
  await page.screenshot({ path: `${tag}.png`, fullPage: true }).catch(() => {});
  const info = await page.evaluate(() => ({
    url: location.href,
    text: document.body.innerText.replace(/\s+/g, ' ').slice(0, 400),
    buttons: Array.from(document.querySelectorAll('button, input[type=submit], a.btn, .btn')).map(b => (b.innerText || b.value || '').trim()).filter(Boolean).slice(0, 20),
    inputs: Array.from(document.querySelectorAll('input:not([type=hidden])')).map(i => `${i.type}:${i.name || i.id}:${i.placeholder || ''}`).slice(0, 20),
  })).catch(e => ({ err: e.message }));
  console.log(`--- ${tag}`, JSON.stringify(info));
  return info;
};
(async () => {
  const [url, mode] = process.argv.slice(2); // mode: success | cancel
  const browser = await chromium.launch({ executablePath: process.env.PW_BIN, args: ['--disable-features=InsecureFormSubmissionInterstitial,MixedFormsWarning,InsecureFormSubmissionWarning', '--allow-running-insecure-content', '--unsafely-treat-insecure-origin-as-secure=http://kong:8000,http://127.0.0.1:54321'] });
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });
  // The redirect targets are http://kong:8000/... (the functions' in-container URL).
  // Rewrite them to the host-visible local gateway so the settlement lands.
  await page.route(/^http:\/\/kong:8000\//, async route => {
    const req = route.request();
    const newUrl = req.url().replace('http://kong:8000', LOCAL);
    console.log('REWRITE', req.method(), newUrl.slice(0, 120));
    const resp = await route.fetch({ url: newUrl });
    await route.fulfill({ response: resp });
  });
  page.on('response', r => { if (r.url().includes('sslcommerz-ipn') || r.url().includes('kong:8000')) console.log('RESP', r.status(), r.url().slice(0, 120)); });
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 90000 });
  await page.waitForTimeout(6000);
  await dump(page, 's1_checkout');
  if (mode === 'cancel') {
    // The checkout's only cancel affordance is the X icon at the card's top-right.
    await page.mouse.click(746, 82);
    await page.waitForTimeout(3000);
    const confirm = page.locator('button, a').filter({ hasText: /yes|ok|confirm|cancel/i }).first();
    if (await confirm.count()) { console.log('confirm dialog:', (await confirm.innerText()).trim()); await confirm.click({ force: true }).catch(() => {}); }
    await page.waitForTimeout(6000);
    await dump(page, 's2_after_cancel');
    await browser.close(); return;
  }
  // The form uses input masks; type key by key so its validation enables PAY.
  await page.locator('input[name=number]').pressSequentially('4111111111111111', { delay: 40 });
  await page.locator('input[name=expiry]').pressSequentially('1229', { delay: 40 });
  await page.locator('input[name=cvc]').pressSequentially('123', { delay: 40 });
  await page.locator('input[name=name]').pressSequentially('QA Guest Verified', { delay: 20 });
  await page.waitForTimeout(1000);
  await dump(page, 's1b_filled');
  const pay = page.locator('button, a, div, span').filter({ hasText: /PAY\s*10\s*BDT/i }).last();
  console.log('pay control count', await pay.count());
  await pay.click({ force: true, timeout: 10000 });
  await page.waitForTimeout(7000);
  let info = await dump(page, 's2_after_pay');
  // Sandbox bank page: OTP field plus explicit outcome buttons.
  const outcome = process.env.OUTCOME || 'Success';   // Success | Success with risk | Fail
  const otp = page.locator('input[type=text], input[type=tel], input[type=password]').first();
  if (await otp.count()) { await otp.fill('111111'); console.log('filled OTP'); }
  const btn = page.locator('button, input[type=submit], input[type=button], a').filter({ hasText: new RegExp('^\\s*' + outcome + '\\s*$', 'i') }).first();
  console.log('outcome button count', await btn.count(), 'for', outcome);
  await btn.click({ force: true, timeout: 10000 }).catch(e => console.log('outcome click failed', e.message));
  await page.waitForTimeout(8000);
  info = await dump(page, 's3_after_outcome');
  if (/Send anyway/.test(info.text || '')) {
    await page.getByText('Send anyway').click({ force: true }).catch(e => console.log('send anyway failed', e.message));
    await page.waitForTimeout(8000);
    info = await dump(page, 's4_after_send_anyway');
  }
  await browser.close();
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
