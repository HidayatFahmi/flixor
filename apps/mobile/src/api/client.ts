import AsyncStorage from '@react-native-async-storage/async-storage';

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

  private log(msg: string, extra?: any) {
    try {
      // Keep logs concise; avoid printing tokens
      const safe = extra && typeof extra === 'object' ? JSON.parse(JSON.stringify(extra)) : extra;
      console.log(`[MobileApi] ${msg}`, safe ?? '');
    } catch {
      console.log(`[MobileApi] ${msg}`);
    }
  }

  headers(additional?: Record<string, string>) {
    const h: Record<string, string> = { 'Content-Type': 'application/json' };
    if (this.token) h['Authorization'] = `Bearer ${this.token}`;
    return { ...h, ...(additional || {}) };
  }

  async get(path: string, extraHeaders?: Record<string, string>) {
    const url = `${this.baseUrl}${path}`;
    this.log(`GET ${url}`);
    const res = await fetch(url, { headers: this.headers(extraHeaders) });
    this.log(`GET ${url} -> ${res.status}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  }

  async post(path: string, body?: any, extraHeaders?: Record<string, string>) {
    const url = `${this.baseUrl}${path}`;
    this.log(`POST ${url}`, { hasBody: !!body });
    const res = await fetch(url, {
      method: 'POST',
      headers: this.headers(extraHeaders),
      body: body ? JSON.stringify(body) : undefined,
    });
    this.log(`POST ${url} -> ${res.status}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  }

  // Health check
  async health(): Promise<any> {
    const url = `${this.baseUrl.replace(/\/api\/?$/, '')}/health`;
    this.log(`GET ${url}`);
    const res = await fetch(url);
    this.log(`GET ${url} -> ${res.status}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  }

  // PIN flow (mobile)
  async createPin(clientId?: string) {
    this.log('Create PIN');
    const r = await this.post('/api/auth/plex/pin', { clientId }, { 'X-Mobile': '1' });
    this.log('PIN created', { id: r?.id, code: r?.code });
    return r;
  }

  async checkPin(id: number, clientId: string) {
    // Ask backend to issue a JWT for mobile if authenticated
    const path = `/api/auth/plex/pin/${id}?clientId=${encodeURIComponent(clientId)}&mobile=1`;
    this.log('Check PIN', { id, clientId });
    const r = await this.get(path, { 'X-Mobile': '1' });
    this.log('PIN status', { authenticated: r?.authenticated, hasToken: !!r?.token });
    return r;
  }

  async session(): Promise<SessionInfo> {
    this.log('Get session');
    const r = await this.get('/api/auth/session');
    this.log('Session', { authenticated: r?.authenticated, user: r?.user?.username });
    return r;
  }

  // --- Trakt auth (device code flow) ---
  async traktDeviceCode() {
    this.log('Trakt device code');
    const r = await this.post('/api/trakt/oauth/device/code', {});
    return r;
  }

  async traktPollToken(deviceCode: string) {
    this.log('Trakt poll token');
    const r = await this.post('/api/trakt/oauth/device/token', { code: deviceCode });
    // Backend returns { ok:false, error } while pending; { ok:true, tokens } on success
    return r;
  }

  async traktProfile() {
    this.log('Trakt profile');
    return this.get('/api/trakt/users/me');
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
