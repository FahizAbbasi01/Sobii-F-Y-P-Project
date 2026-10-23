const BASE = `${import.meta.env.VITE_API_URL || 'http://localhost:4000'}/api/v1`;

// Access token in memory; refresh token in sessionStorage (cleared when the tab closes).
let accessToken = null;
const REFRESH_KEY = 'dt_admin_refresh';
let onExpired = () => {};

export function setOnExpired(fn) { onExpired = fn; }
export function hasSession() { return !!sessionStorage.getItem(REFRESH_KEY); }

function saveSession(data) {
  accessToken = data.accessToken;
  sessionStorage.setItem(REFRESH_KEY, data.refreshToken);
}

export function clearSession() {
  accessToken = null;
  sessionStorage.removeItem(REFRESH_KEY);
}

export class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

let refreshing = null;
async function refresh() {
  const token = sessionStorage.getItem(REFRESH_KEY);
  if (!token) return false;
  if (!refreshing) {
    refreshing = fetch(`${BASE}/auth/refresh`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ refreshToken: token }),
    }).then(async (r) => {
      if (!r.ok) { clearSession(); return false; }
      const data = await r.json();
      if (data.user.role !== 'admin') { clearSession(); return false; }
      saveSession(data);
      return true;
    }).catch(() => false).finally(() => { refreshing = null; });
  }
  return refreshing;
}

export async function request(method, path, body, retried = false) {
  if (!accessToken && !retried && hasSession()) await refresh();
  let res;
  try {
    res = await fetch(`${BASE}${path}`, {
      method,
      headers: { 'Content-Type': 'application/json', ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(0, 'Cannot reach the API server. Is the backend running?');
  }
  if (res.status === 401 && !retried) {
    if (await refresh()) return request(method, path, body, true);
    onExpired();
  }
  if (res.status === 204) return null;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError(res.status, data?.error?.message || `Request failed (${res.status})`);
  return data;
}

export const api = {
  get: (p, query) => {
    const qs = query ? `?${new URLSearchParams(Object.entries(query).filter(([, v]) => v !== undefined && v !== '' && v !== null))}` : '';
    return request('GET', p + qs);
  },
  post: (p, b) => request('POST', p, b ?? {}),
};

export async function login(email, password) {
  const data = await request('POST', '/auth/login', { email, password }, true);
  if (data.user.role !== 'admin') {
    // Don't keep a non-admin session around in the dashboard.
    await fetch(`${BASE}/auth/logout`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ refreshToken: data.refreshToken }) }).catch(() => {});
    throw new ApiError(403, 'This account does not have admin access.');
  }
  saveSession(data);
  return data.user;
}

export async function logout() {
  const token = sessionStorage.getItem(REFRESH_KEY);
  clearSession();
  if (token) await fetch(`${BASE}/auth/logout`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ refreshToken: token }) }).catch(() => {});
}

export async function me() {
  const data = await api.get('/auth/me');
  if (data.user.role !== 'admin') throw new ApiError(403, 'Not an admin');
  return data.user;
}
