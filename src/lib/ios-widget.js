/**
 * ios-widget.js — feeds the iOS home/lock-screen widget (ios/App/NutriTraceWidget).
 *
 * iOS only; every export is a no-op on web and Android.
 *
 * Two paths keep the widget current:
 *  1. pushWidgetSnapshot(): the Diary sends today's calories/protein and the
 *     goals it shows (activity / dynamic / adaptive adjustments included). The
 *     native WidgetBridge plugin stores them in the App Group and redraws the
 *     widget right away.
 *  2. ensureWidgetToken(): creates a read-only (mcp:read) API token named
 *     "iPhone widget" and hands it to the widget (iOS Keychain), so the widget
 *     can fetch /api/v1/diary/<today>/totals itself every ~15 minutes and pick
 *     up entries made on the web or Android. Needs PUBLIC_API_ENABLED on the
 *     server and an admin account; if either is missing the widget still works
 *     from path 1.
 */
import { registerPlugin } from '@capacitor/core';
import { isIOS, getServerUrl, getAuthToken } from './platform.js';

const WidgetBridge = isIOS ? registerPlugin('WidgetBridge') : null;
const TOKEN_NAME = 'iPhone widget';

let _pending = null;
let _timer = null;

/** Debounced: the Diary's reactive statements fire several times per change. */
export function pushWidgetSnapshot(snap) {
  if (!WidgetBridge || !snap?.date) return;
  _pending = snap;
  clearTimeout(_timer);
  _timer = setTimeout(() => {
    const s = _pending;
    _pending = null;
    WidgetBridge.setSnapshot(s).catch(e => console.warn('[widget] snapshot failed:', e?.message));
  }, 600);
}

let _tokenAttempted = false;

export async function ensureWidgetToken() {
  if (!WidgetBridge || _tokenAttempted) return;
  const serverUrl = getServerUrl();
  if (!serverUrl || !getAuthToken()) return;
  _tokenAttempted = true; // once per app launch, success or not
  try {
    const status = await WidgetBridge.getStatus();
    if (status.hasToken && status.serverUrl === serverUrl) return;
    const { NtApi } = await import('./api.js');
    // A reinstall loses the Keychain copy only sometimes; revoke earlier widget
    // tokens so they don't pile up in Settings → API tokens.
    try {
      const { tokens } = await NtApi.get('/api/admin/api-tokens');
      for (const t of tokens || []) {
        if (t.name === TOKEN_NAME) await NtApi.del(`/api/admin/api-tokens/${t.id}`).catch(() => {});
      }
    } catch { /* listing failed: create anyway */ }
    const { raw } = await NtApi.post('/api/admin/api-tokens', { name: TOKEN_NAME, scopes: ['mcp:read'] });
    if (raw) await WidgetBridge.setServer({ serverUrl, token: raw });
  } catch (e) {
    // Non-admin account, older server, offline: the widget falls back to
    // the app's own snapshots.
    console.warn('[widget] API token setup skipped:', e?.message);
  }
}

/** Sign-out: revoke the widget's token on the server (call while the session
 *  still works), then drop the widget's numbers and token from this phone. */
export async function clearWidget() {
  if (!WidgetBridge) return;
  _tokenAttempted = false;
  try {
    const status = await WidgetBridge.getStatus();
    if (status.hasToken && getServerUrl()) {
      const { NtApi } = await import('./api.js');
      const { tokens } = await NtApi.get('/api/admin/api-tokens');
      for (const t of tokens || []) {
        if (t.name === TOKEN_NAME) await NtApi.del(`/api/admin/api-tokens/${t.id}`).catch(() => {});
      }
    }
  } catch { /* never block sign-out */ }
  try { await WidgetBridge.clear(); } catch {}
}
