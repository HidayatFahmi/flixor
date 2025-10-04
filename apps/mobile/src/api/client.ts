import AsyncStorage from '@react-native-async-storage/async-storage';
import { apiCache } from './cache';

export type SessionInfo = {
  authenticated: boolean;
  user?: {
    id: string;
    username: string;
    email?: string;
    thumb?: string;
  };
};

const KEY_BASE_URL = 'flixor.baseUrl';
const KEY_TOKEN = 'flixor.token';

export class MobileApi {
  baseUrl: string;
  token: string | null = null;

  constructor(baseUrl: string, token?: string | null) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
    this.token = token || null;
  }

  static async load(): Promise<MobileApi | null> {
    const base = await AsyncStorage.getItem(KEY_BASE_URL);
    if (!base) return null;
    const token = await AsyncStorage.getItem(KEY_TOKEN);
    return new MobileApi(base, token);
  }

  async save(): Promise<void> {
    await AsyncStorage.setItem(KEY_BASE_URL, this.baseUrl);
    if (this.token) await AsyncStorage.setItem(KEY_TOKEN, this.token);
  }

  setToken(token: string | null) {
    this.token = token;
    if (token) AsyncStorage.setItem(KEY_TOKEN, token); else AsyncStorage.removeItem(KEY_TOKEN);
  }

  headers(additional?: Record<string, string>) {
    const h: Record<string, string> = { 'Content-Type': 'application/json' };
    if (this.token) h['Authorization'] = `Bearer ${this.token}`;
    return { ...h, ...(additional || {}) };
  }

  async get(path: string, extraHeaders?: Record<string, string>, options?: { skipCache?: boolean }) {
    const url = `${this.baseUrl}${path}`;

    // Skip cache if requested or for real-time endpoints
    if (options?.skipCache) {
      const res = await fetch(url, { headers: this.headers(extraHeaders) });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return res.json();
    }

    // Use cache with automatic deduplication
    return apiCache.getOrFetch(path, async () => {
      const res = await fetch(url, { headers: this.headers(extraHeaders) });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return res.json();
    });
  }

  async post(path: string, body?: any, extraHeaders?: Record<string, string>) {
    const url = `${this.baseUrl}${path}`;
    const res = await fetch(url, {
      method: 'POST',
      headers: this.headers(extraHeaders),
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  }

  // Health check
  async health(): Promise<any> {
    const url = `${this.baseUrl.replace(/\/api\/?$/, '')}/health`;
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  }

  // PIN flow (mobile)
  async createPin(clientId?: string) {
    const r = await this.post('/api/auth/plex/pin', { clientId }, { 'X-Mobile': '1' });
    return r;
  }

  async checkPin(id: number, clientId: string) {
    // Ask backend to issue a JWT for mobile if authenticated
    const path = `/api/auth/plex/pin/${id}?clientId=${encodeURIComponent(clientId)}&mobile=1`;
    const r = await this.get(path, { 'X-Mobile': '1' });
    return r;
  }

  async session(): Promise<SessionInfo> {
    const r = await this.get('/api/auth/session');
    return r;
  }

  // --- Trakt auth (device code flow) ---
  async traktDeviceCode() {
    const r = await this.post('/api/trakt/oauth/device/code', {});
    return r;
  }

  async traktPollToken(deviceCode: string) {
    const r = await this.post('/api/trakt/oauth/device/token', { code: deviceCode });
    // Backend returns { ok:false, error } while pending; { ok:true, tokens } on success
    return r;
  }

  async traktProfile() {
    return this.get('/api/trakt/users/me');
  }

  // --- Library helpers (mobile) ---
  async libraryItems(opts: { type?: 'all'|'movie'|'show'; page?: number; pageSize?: number }) {
    const { type = 'all', page = 1, pageSize = 30 } = opts || {};
    const t = type === 'all' ? '' : `&type=${type}`;
    return this.get(`/api/plex/library/items?page=${page}&pageSize=${pageSize}${t}`);
  }

  async searchLibrary(opts: { q: string; type?: 'all'|'movie'|'show'; page?: number; pageSize?: number }) {
    const { q, type = 'all', page = 1, pageSize = 30 } = opts;
    const t = type === 'all' ? '' : `&type=${type}`;
    return this.get(`/api/plex/search?q=${encodeURIComponent(q)}&page=${page}&pageSize=${pageSize}${t}`);
  }

  // --- Cache management ---
  async invalidateCache(path: string) {
    return apiCache.invalidate(path);
  }

  async invalidateCachePattern(pattern: string) {
    return apiCache.invalidatePattern(pattern);
  }

  async clearCache() {
    return apiCache.clear();
  }

  // Prefetch data in background (fire and forget)
  prefetch(path: string, extraHeaders?: Record<string, string>) {
    apiCache.prefetch(path, async () => {
      const res = await fetch(`${this.baseUrl}${path}`, { headers: this.headers(extraHeaders) });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return res.json();
    });
  }
}

// Convenience helpers used by screens
export async function saveBaseUrl(baseUrl: string) {
  await AsyncStorage.setItem(KEY_BASE_URL, baseUrl.replace(/\/$/, ''));
}

export async function loadBaseUrl(): Promise<string | null> {
  return AsyncStorage.getItem(KEY_BASE_URL);
}

// Optional: store Trakt tokens locally to gate UI without a server call
const KEY_TRAKT = 'flixor.trakt.tokens';
export async function saveTraktTokens(tokens: any | null) {
  if (tokens) await AsyncStorage.setItem(KEY_TRAKT, JSON.stringify(tokens));
  else await AsyncStorage.removeItem(KEY_TRAKT);
}

export async function getTraktTokens(): Promise<any | null> {
  const s = await AsyncStorage.getItem(KEY_TRAKT);
  if (!s) return null;
  try { return JSON.parse(s); } catch { return null; }
}
