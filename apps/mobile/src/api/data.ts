import { MobileApi } from './client';

// Types are kept minimal; expand as needed
export type MediaItem = {
  ratingKey?: string | number;
  key?: string;
  title?: string;
  name?: string;
  type?: string;
  thumb?: string;
  art?: string;
  year?: number;
  viewOffset?: number;
  duration?: number;
};

export type RowItem = {
  id: string; // "plex:<rk>" or "tmdb:<movie|tv>:<id>"
  title: string;
  image?: string;
  mediaType?: 'movie'|'tv';
};

export async function fetchContinue(api: MobileApi): Promise<MediaItem[]> {
  const items = await api.get('/api/plex/continue');
  return items || [];
}

export async function fetchRecent(api: MobileApi, libraryKey?: string): Promise<MediaItem[]> {
  const path = libraryKey ? `/api/plex/recent?library=${encodeURIComponent(libraryKey)}` : '/api/plex/recent';
  const items = await api.get(path);
  return items || [];
}

async function withLimit<T, R>(items: T[], limit: number, fn: (t: T) => Promise<R>): Promise<R[]> {
  const ret: R[] = [];
  let idx = 0;
  async function worker() {
    while (idx < items.length) {
      const i = idx++;
      ret[i] = await fn(items[i]);
    }
  }
  const workers = Array.from({ length: Math.min(limit, items.length) }).map(worker);
  await Promise.all(workers);
  return ret;
}

export async function fetchTrendingMovies(api: MobileApi): Promise<any[]> {
  const data = await api.get('/api/trakt/trending/movies?limit=20');
  const arr = Array.isArray(data) ? data : [];
  // Enrich with TMDB poster/backdrop to render images
  return withLimit(arr, 5, async (item) => {
    const tmdbId = item?.movie?.ids?.tmdb;
    if (!tmdbId) return item;
    try {
      const details = await api.get(`/api/tmdb/movie/${tmdbId}`);
      return { ...item, movie: { ...item.movie, poster_path: details?.poster_path, backdrop_path: details?.backdrop_path } };
    } catch {
      return item;
    }
  });
}

export async function fetchTrendingShows(api: MobileApi): Promise<any[]> {
  const data = await api.get('/api/trakt/trending/shows?limit=20');
  const arr = Array.isArray(data) ? data : [];
  return withLimit(arr, 5, async (item) => {
    const tmdbId = item?.show?.ids?.tmdb;
    if (!tmdbId) return item;
    try {
      const details = await api.get(`/api/tmdb/tv/${tmdbId}`);
      return { ...item, show: { ...item.show, poster_path: details?.poster_path, backdrop_path: details?.backdrop_path } };
    } catch {
      return item;
    }
  });
}

// Plex details
export async function fetchPlexMetadata(api: MobileApi, ratingKey: string): Promise<any> {
  const data = await api.get(`/api/plex/metadata/${encodeURIComponent(ratingKey)}`);
  return data?.MediaContainer?.Metadata?.[0] || data?.MediaContainer || data || null;
}

export async function fetchPlexEpisodes(api: MobileApi, showRatingKey: string): Promise<any[]> {
  const mc = await api.get(`/api/plex/dir/library/metadata/${encodeURIComponent(showRatingKey)}/children`);
  // Backend returns MediaContainer directly (not wrapped)
  return (mc?.Metadata || []) as any[];
}

export async function fetchPlexSeasons(api: MobileApi, showRatingKey: string): Promise<Array<{ ratingKey: string; title: string; index?: number; type?: string }>> {
  const url = `/api/plex/dir/library/metadata/${encodeURIComponent(showRatingKey)}/children`;
  console.log('[fetchPlexSeasons] Fetching:', url);
  const mc = await api.get(url);
  // Backend returns MediaContainer directly (not wrapped)
  const items = (mc?.Metadata || []) as any[];
  console.log('[fetchPlexSeasons] Response:', { count: items.length, items: items.slice(0, 2), fullResponse: mc });
  if (!items || !items.length) {
    console.warn('[fetchPlexSeasons] No items found');
    return [];
  }
  // Many PMS return season entries without explicit type; accept both
  let seasons = items.filter((x:any)=> String(x.type||'').toLowerCase()==='season');
  if (!seasons.length) {
    // Fallback: treat children as seasons (they should have ratingKey and title like 'Season 1')
    console.log('[fetchPlexSeasons] No typed seasons, using all items as fallback');
    seasons = items;
  }

  // Normalize to consistent format with required fields
  const normalized = seasons
    .filter((s: any) => s.ratingKey) // Only include items with ratingKey
    .map((s: any) => ({
      ratingKey: String(s.ratingKey),
      title: s.title || `Season ${s.index || ''}`,
      index: s.index,
      type: s.type
    }));

  console.log('[fetchPlexSeasons] Normalized seasons:', { count: normalized.length, first: normalized[0] });
  return normalized;
}

export async function fetchPlexSeasonEpisodes(api: MobileApi, seasonKey: string): Promise<any[]> {
  const url = `/api/plex/dir/library/metadata/${encodeURIComponent(seasonKey)}/children`;
  console.log('[fetchPlexSeasonEpisodes] Fetching:', url);
  const mc = await api.get(url);
  // Backend returns MediaContainer directly (not wrapped)
  const episodes = (mc?.Metadata || []) as any[];
  console.log('[fetchPlexSeasonEpisodes] Response:', { count: episodes.length, first: episodes[0] });
  return episodes;
}

export async function fetchTmdbRecommendations(api: MobileApi, mediaType: 'movie'|'tv', id: string): Promise<any[]> {
  const data = await api.get(`/api/tmdb/${mediaType}/${encodeURIComponent(id)}/recommendations`);
  const results = Array.isArray(data?.results) ? data.results : [];
  return results;
}

export async function fetchTmdbRecommendationsMapped(api: MobileApi, mediaType: 'movie'|'tv', id: string): Promise<RowItem[]> {
  try {
    const data = await api.get(`/api/tmdb/${mediaType}/${encodeURIComponent(id)}/recommendations`);
    const results: any[] = Array.isArray(data?.results) ? data.results : [];
    const out: RowItem[] = [];
    let idx = 0;
    const limit = Math.min(5, results.length || 0);
    async function worker() {
      while (idx < results.length) {
        const i = idx++;
        const r = results[i];
        const tmdbId = r?.id;
        const title = r?.title || r?.name || '';
        if (!tmdbId) continue;
        const mapped = await mapByTmdb(api, Number(tmdbId), mediaType);
        if (mapped) { out[i] = mapped; continue; }
        const img = r?.poster_path ? `https://image.tmdb.org/t/p/w342${r.poster_path}` : (r?.backdrop_path ? `https://image.tmdb.org/t/p/w780${r.backdrop_path}` : undefined);
        out[i] = { id: `tmdb:${mediaType}:${tmdbId}`, title, image: img, mediaType };
      }
    }
    await Promise.all(Array.from({ length: limit }).map(worker));
    return out.filter(Boolean).slice(0, 12);
  } catch { return []; }
}

export async function fetchTmdbSimilarMapped(api: MobileApi, mediaType: 'movie'|'tv', id: string): Promise<RowItem[]> {
  try {
    const data = await api.get(`/api/tmdb/${mediaType}/${encodeURIComponent(id)}/similar`);
    const results: any[] = Array.isArray(data?.results) ? data.results : [];
    const out: RowItem[] = [];
    let idx = 0;
    const limit = Math.min(5, results.length || 0);
    async function worker() {
      while (idx < results.length) {
        const i = idx++;
        const r = results[i];
        const tmdbId = r?.id;
        const title = r?.title || r?.name || '';
        if (!tmdbId) continue;
        const mapped = await mapByTmdb(api, Number(tmdbId), mediaType);
        if (mapped) { out[i] = mapped; continue; }
        const img = r?.poster_path ? `https://image.tmdb.org/t/p/w342${r.poster_path}` : (r?.backdrop_path ? `https://image.tmdb.org/t/p/w780${r.backdrop_path}` : undefined);
        out[i] = { id: `tmdb:${mediaType}:${tmdbId}`, title, image: img, mediaType };
      }
    }
    await Promise.all(Array.from({ length: limit }).map(worker));
    return out.filter(Boolean).slice(0, 12);
  } catch { return []; }
}

// ---------- TMDB: TV Seasons/Episodes (best-effort based on backend support) ----------
export async function fetchTmdbTvDetails(api: MobileApi, tvId: string): Promise<any> {
  try { return await api.get(`/api/tmdb/tv/${encodeURIComponent(tvId)}`); } catch { return null; }
}

export async function fetchTmdbTvSeasonsList(api: MobileApi, tvId: string): Promise<Array<{ key: string; title: string; season_number: number }>> {
  const d = await fetchTmdbTvDetails(api, tvId);
  const ss: any[] = Array.isArray(d?.seasons) ? d.seasons : [];
  return ss.filter(s => (s?.season_number ?? 0) > 0).map((s:any) => ({ key: String(s.season_number), title: `Season ${s.season_number}`, season_number: s.season_number }));
}

export async function fetchTmdbSeasonEpisodes(api: MobileApi, tvId: string, seasonNumber: number): Promise<any[]> {
  // Try to append season details for episodes
  try {
    const d = await api.get(`/api/tmdb/tv/${encodeURIComponent(tvId)}?append_to_response=season/${seasonNumber}`);
    const key = `season/${seasonNumber}`;
    const block = d && d[key];
    const eps: any[] = Array.isArray(block?.episodes) ? block.episodes : [];
    if (eps.length) return eps;
  } catch {}
  // Fallback to basic tv details object (if backend injects episodes there)
  try {
    const d = await fetchTmdbTvDetails(api, tvId);
    const season = (d?.seasons || []).find((s:any)=> s.season_number === seasonNumber);
    const eps: any[] = Array.isArray((season as any)?.episodes) ? (season as any).episodes : [];
    return eps;
  } catch { return []; }
}

// ---------- TMDB: Trending TV (week) for Home rows ----------
export async function fetchTmdbTrendingTVWeek(api: MobileApi): Promise<RowItem[]> {
  try {
    const data = await api.get('/api/tmdb/trending/tv/week');
    const results: any[] = Array.isArray(data?.results) ? data.results : [];
    return results.map((r:any) => ({
      id: `tmdb:tv:${String(r.id)}`,
      title: r.name || r.title || 'Title',
      // Prefer poster for mobile poster cards; fallback to backdrop if no poster
      image: r.poster_path ? `https://image.tmdb.org/t/p/w342${r.poster_path}`
        : (r.backdrop_path ? `https://image.tmdb.org/t/p/w780${r.backdrop_path}` : undefined),
      mediaType: 'tv',
    }));
  } catch { return []; }
}

// ---------- Plex: Popular across libraries ----------
export async function fetchPlexPopular(api: MobileApi, limitPerLib: number = 50): Promise<RowItem[]> {
  try {
    const libraries = await api.get('/api/plex/libraries');
    const dirs: any[] = Array.isArray(libraries) ? libraries : [];
    const hits: any[] = [];
    for (const d of dirs) {
      if (d.type !== 'movie' && d.type !== 'show') continue;
      const typeNum = d.type === 'movie' ? 1 : 2;
      let res: any = null;
      try {
        res = await api.get(`/api/plex/library/${encodeURIComponent(d.key)}/all?type=${typeNum}&sort=lastViewedAt:desc&offset=0&limit=${limitPerLib}`);
      } catch {}
      if (!res) {
        try {
          res = await api.get(`/api/plex/library/${encodeURIComponent(d.key)}/all?type=${typeNum}&sort=viewCount:desc&offset=0&limit=${limitPerLib}`);
        } catch {}
      }
      const meta: any[] = (res?.MediaContainer?.Metadata || res?.Metadata || res || []);
      hits.push(...meta);
    }
    const score = (m:any) => (m.lastViewedAt||0) * 10 + (m.viewCount||0);
    hits.sort((a,b)=> score(b)-score(a));
    return hits.slice(0, 100).map((m:any) => ({
      id: `plex:${m.ratingKey}`,
      title: m.title || m.grandparentTitle || 'Title',
      image: plexImgFromMeta(m, api),
      mediaType: m.type === 'movie' ? 'movie' : 'tv',
    }));
  } catch {
    return [];
  }
}

// ---------- Plex: Genre row from first matching library ----------
export async function fetchPlexGenreRow(api: MobileApi, type: 'movie'|'show', genre: string): Promise<RowItem[]> {
  try {
    const libraries = await api.get('/api/plex/libraries');
    const dirs: any[] = Array.isArray(libraries) ? libraries : [];
    const lib = dirs.find((d:any)=> d.type === (type==='movie'?'movie':'show'));
    if (!lib) return [];
    const gens = await api.get(`/api/plex/library/${encodeURIComponent(lib.key)}/genre`);
    const gx = (gens?.MediaContainer?.Directory || gens?.Directory || []).find((g:any)=> String(g.title).toLowerCase() === genre.toLowerCase());
    if (!gx) return [];
    const path = `/api/plex/dir/library/sections/${encodeURIComponent(lib.key)}/genre/${encodeURIComponent(gx.key)}`;
    const data = await api.get(path);
    const meta: any[] = data?.MediaContainer?.Metadata || data?.Metadata || [];
    return meta.slice(0, 12).map((m:any) => ({ id: `plex:${m.ratingKey}`, title: m.title || m.grandparentTitle || 'Title', image: plexImgFromMeta(m, api), mediaType: m.type==='movie'?'movie':'tv' }));
  } catch { return []; }
}

// ---------- Plex.tv Watchlist (mapped to Plex/TMDB) ----------
export async function fetchPlexWatchlist(api: MobileApi): Promise<RowItem[]> {
  try {
    const wl = await api.get('/api/plextv/watchlist');
    const meta: any[] = wl?.MediaContainer?.Metadata || [];
    const out: RowItem[] = [];
    for (const m of meta) {
      const g = String(m.guid || '');
      const tmdbId = /tmdb:\/\/(\d+)/.exec(g)?.[1] || /themoviedb:\/\/(\d+)/.exec(g)?.[1];
      const mediaType: 'movie'|'tv' = (m.type === 'movie') ? 'movie' : 'tv';
      if (tmdbId) {
        const mapped = await mapByTmdb(api, Number(tmdbId), mediaType);
        if (mapped) { out.push(mapped); continue; }
        out.push({ id: `tmdb:${mediaType}:${tmdbId}`, title: m.title || m.grandparentTitle || 'Title', image: m.thumb || m.parentThumb || m.grandparentThumb, mediaType });
        continue;
      }
      // If GUID lacks TMDB, try IMDb/TVDB
      const imdb = /imdb:\/\/([a-z0-9]+)/i.exec(g)?.[1];
      const tvdb = /tvdb:\/\/(\d+)/.exec(g)?.[1];
      if (imdb) {
        const mapped = await mapByGuid(api, `imdb://${imdb}`, mediaType);
        if (mapped) { out.push(mapped); continue; }
      }
      if (tvdb) {
        const mapped = await mapByGuid(api, `tvdb://${tvdb}` as any, mediaType);
        if (mapped) { out.push(mapped); continue; }
      }
    }
    return out.slice(0, 12);
  } catch { return []; }
}

// ---------- Trakt mapped rows ----------
export async function fetchTraktTrendingMapped(api: MobileApi, media: 'movies'|'shows'): Promise<RowItem[]> {
  const data = await api.get(`/api/trakt/trending/${media}?limit=20`).catch(()=>[]);
  const arr: any[] = Array.isArray(data) ? data : [];
  return mapExternalToRowItems(api, media === 'movies' ? 'movie' : 'tv', arr.map(x => x.movie || x.show || x));
}

export async function fetchTraktPopularShowsMapped(api: MobileApi): Promise<RowItem[]> {
  const data = await api.get(`/api/trakt/popular/shows?limit=20`).catch(()=>[]);
  const arr: any[] = Array.isArray(data) ? data : [];
  return mapExternalToRowItems(api, 'tv', arr);
}

export async function fetchTraktWatchlistMapped(api: MobileApi): Promise<RowItem[]> {
  try {
    const [m, s] = await Promise.all([
      api.get('/api/trakt/users/me/watchlist/movies').catch(()=>[]),
      api.get('/api/trakt/users/me/watchlist/shows').catch(()=>[])
    ]);
    const items = ([] as any[]).concat(m||[]).concat(s||[]).map((it:any)=> it.movie || it.show || it);
    return mapExternalToRowItems(api, undefined, items).then(x=>x.slice(0,12));
  } catch (e:any) {
    // Hide row when unauthorized
    if (String(e?.message||'').includes('HTTP 401')) return [];
    return [];
  }
}

export async function fetchTraktHistoryMapped(api: MobileApi): Promise<RowItem[]> {
  try {
    const [m, s] = await Promise.all([
      api.get('/api/trakt/users/me/history/movies?limit=20').catch(()=>[]),
      api.get('/api/trakt/users/me/history/shows?limit=20').catch(()=>[])
    ]);
    const items = ([] as any[]).concat(m||[]).concat(s||[]).map((it:any)=> it.movie || it.show || it);
    return mapExternalToRowItems(api, undefined, items).then(x=>x.slice(0,12));
  } catch (e:any) {
    if (String(e?.message||'').includes('HTTP 401')) return [];
    return [];
  }
}

export async function fetchTraktRecommendationsMapped(api: MobileApi): Promise<RowItem[]> {
  try {
    const [m, s] = await Promise.all([
      api.get('/api/trakt/recommendations/movies?limit=20').catch(()=>[]),
      api.get('/api/trakt/recommendations/shows?limit=20').catch(()=>[])
    ]);
    const items = ([] as any[]).concat(m||[]).concat(s||[]).map((it:any)=> it.movie || it.show || it);
    return mapExternalToRowItems(api, undefined, items).then(x=>x.slice(0,12));
  } catch (e:any) {
    if (String(e?.message||'').includes('HTTP 401')) return [];
    return [];
  }
}

// ---------- Mapping helpers ----------
function plexImgFromMeta(m: any, api: MobileApi): string | undefined {
  const p = m.thumb || m.parentThumb || m.grandparentThumb || m.art;
  return p ? `${api.baseUrl}/api/image/plex?path=${encodeURIComponent(String(p))}&w=480&f=webp` : undefined;
}

async function mapByGuid(api: MobileApi, guid: string, mediaType: 'movie'|'tv'): Promise<RowItem | undefined> {
  const typeNum = mediaType === 'movie' ? 1 : 2;
  try {
    const res = await api.get(`/api/plex/findByGuid?guid=${encodeURIComponent(guid)}&type=${typeNum}`);
    const meta: any[] = res?.MediaContainer?.Metadata || res?.Metadata || [];
    const hit = meta[0];
    if (!hit) return undefined;
    return { id: `plex:${hit.ratingKey}`, title: hit.title || hit.grandparentTitle || 'Title', image: plexImgFromMeta(hit, api), mediaType };
  } catch { return undefined; }
}

async function mapByTmdb(api: MobileApi, id: number, mediaType: 'movie'|'tv'): Promise<RowItem | undefined> {
  const guid1 = `tmdb://${id}`;
  const guid2 = `themoviedb://${id}`;
  return (await mapByGuid(api, guid1, mediaType)) || (await mapByGuid(api, guid2, mediaType));
}

export async function mapExternalToRowItems(api: MobileApi, mediaType: 'movie'|'tv'|undefined, list: any[]): Promise<RowItem[]> {
  const out: RowItem[] = [];
  let idx = 0;
  const limit = Math.min(5, list.length || 0);
  async function worker() {
    while (idx < list.length) {
      const i = idx++;
      const it = list[i];
      const mt: 'movie'|'tv' = mediaType || (it?.title && it?.runtime ? 'movie' : (it?.name ? 'tv' : 'movie'));
      const ids = it?.ids || {};
      const tmdbId: number | undefined = ids?.tmdb || it?.id;
      const title = it?.title || it?.name || '';
      if (tmdbId) {
        const mapped = await mapByTmdb(api, Number(tmdbId), mt);
        if (mapped) { out[i] = mapped; continue; }
        // Fallback to TMDB image if available
        let img: string | undefined;
        try {
          const details = await api.get(`/api/tmdb/${mt === 'movie' ? 'movie' : 'tv'}/${tmdbId}`);
          if (details?.poster_path) img = `https://image.tmdb.org/t/p/w342${details.poster_path}`;
          else if (details?.backdrop_path) img = `https://image.tmdb.org/t/p/w780${details.backdrop_path}`;
        } catch {}
        out[i] = { id: `tmdb:${mt}:${tmdbId}`, title, image: img, mediaType: mt };
        continue;
      }
      // No TMDB id -> skip to keep interactions consistent
    }
  }
  await Promise.all(Array.from({ length: limit }).map(worker));
  return out.filter(Boolean).slice(0, 12);
}

// ---------- TMDB → Plex mapping (parity with web) ----------
type PlexMatch = { ratingKey: string; meta: any };

function normalizeTitle(s: string): string {
  const base = (s || '').toLowerCase();
  const noArticles = base.replace(/^(the|a|an)\s+/i, '');
  const noDiacritics = noArticles.normalize('NFD').replace(/\p{Diacritic}+/gu, '');
  return noDiacritics.replace(/[^a-z0-9]+/g, '');
}

export async function mapTmdbToPlex(api: MobileApi, media: 'movie'|'tv', tmdbId: string, title?: string, year?: string): Promise<PlexMatch | null> {
  const typeNum = media === 'movie' ? 1 : 2;
  const hits: any[] = [];
  const triedGuids: string[] = [];

  async function tryGuid(guid: string) {
    triedGuids.push(guid);
    try {
      const r = await api.get(`/api/plex/findByGuid?guid=${encodeURIComponent(guid)}&type=${typeNum}`);
      const arr: any[] = (r?.MediaContainer?.Metadata || r?.Metadata || []);
      if (arr?.length) hits.push(...arr);
    } catch {}
    // Fallback: try without type filter
    try {
      const r = await api.get(`/api/plex/findByGuid?guid=${encodeURIComponent(guid)}`);
      const arr: any[] = (r?.MediaContainer?.Metadata || r?.Metadata || []);
      if (arr?.length) hits.push(...arr);
    } catch {}
  }

  // 1) Try direct TMDB GUIDs
  await tryGuid(`tmdb://${tmdbId}`);
  await tryGuid(`themoviedb://${tmdbId}`);

  // 2) Try external ids from TMDB
  try {
    const ex: any = await api.get(`/api/tmdb/${media}/${encodeURIComponent(tmdbId)}?append_to_response=external_ids`);
    const imdb: string | undefined = ex?.external_ids?.imdb_id;
    const tvdb: number | undefined = ex?.external_ids?.tvdb_id;
    if (imdb) await tryGuid(`imdb://${imdb}`);
    if (tvdb && media === 'tv') await tryGuid(`tvdb://${tvdb}`);
    if (!title) title = ex?.title || ex?.name;
    if (!year) year = (ex?.release_date || ex?.first_air_date || '').slice(0, 4);
  } catch {}

  // 3) Title search fallback
  if (!hits.length && title) {
    try {
      const sr = await api.get(`/api/plex/search?query=${encodeURIComponent(title)}&type=${typeNum}`);
      const arr: any[] = Array.isArray(sr) ? sr : (sr?.MediaContainer?.Metadata || sr?.Metadata || []);
      if (arr?.length) hits.push(...arr);
    } catch {}
    // Untyped search as last resort
    if (!hits.length) {
      try {
        const sr2 = await api.get(`/api/plex/search?query=${encodeURIComponent(title)}`);
        const arr2: any[] = Array.isArray(sr2) ? sr2 : (sr2?.MediaContainer?.Metadata || sr2?.Metadata || []);
        if (arr2?.length) hits.push(...arr2);
      } catch {}
    }
  }

  if (!hits.length) return null;
  // Deduplicate by ratingKey
  const unique = Array.from(new Map(hits.map((h:any)=> [String(h.ratingKey), h])).values());

  // 4) Selection policy
  // a) exact TMDB GUID match
  for (const h of unique) {
    const guids = Array.isArray(h.Guid) ? h.Guid.map((g:any)=> String(g.id||'')) : [];
    if (guids.includes(`tmdb://${tmdbId}`) || guids.includes(`themoviedb://${tmdbId}`)) {
      return { ratingKey: String(h.ratingKey), meta: h };
    }
  }
  // b) normalized title + same/near year (±1)
  if (title) {
    const nTitle = normalizeTitle(title);
    for (const h of unique) {
      const t = normalizeTitle(h.title || h.grandparentTitle || '');
      const y = Number(h.year || 0);
      const yy = Number(year || 0);
      const yearOk = !yy || (y === yy) || (y === yy - 1) || (y === yy + 1);
      if (t === nTitle && yearOk) {
        return { ratingKey: String(h.ratingKey), meta: h };
      }
    }
  }
  // c) fallback first item
  const h = unique[0];
  return h ? { ratingKey: String(h.ratingKey), meta: h } : null;
}

// ---------- Mapping diagnostics for mobile (dev aid) ----------
export type MappingStep = { kind: 'guid'|'search'|'select'; detail: string; count?: number };
export type MappingDiagnostics = { steps: MappingStep[]; hits: any[]; unique: any[]; selected?: PlexMatch | null };

export async function mapTmdbToPlexDebug(api: MobileApi, media: 'movie'|'tv', tmdbId: string, title?: string, year?: string): Promise<MappingDiagnostics> {
  const steps: MappingStep[] = [];
  const typeNum = media === 'movie' ? 1 : 2;
  const hits: any[] = [];

  async function tryGuid(guid: string, withType: boolean) {
    const label = `${guid}${withType ? `&type=${typeNum}` : ''}`;
    steps.push({ kind: 'guid', detail: `try ${label}` });
    try {
      const url = withType ? `/api/plex/findByGuid?guid=${encodeURIComponent(guid)}&type=${typeNum}` : `/api/plex/findByGuid?guid=${encodeURIComponent(guid)}`;
      const r = await api.get(url);
      const arr: any[] = (r?.MediaContainer?.Metadata || r?.Metadata || []);
      steps.push({ kind: 'guid', detail: `resp ${label}`, count: arr?.length || 0 });
      if (arr?.length) hits.push(...arr);
    } catch (e: any) {
      steps.push({ kind: 'guid', detail: `error ${label}: ${String(e?.message||e)}` });
    }
  }

  // 1) Try TMDB GUIDs with and without type
  await tryGuid(`tmdb://${tmdbId}`, true);
  await tryGuid(`tmdb://${tmdbId}`, false);
  await tryGuid(`themoviedb://${tmdbId}`, true);
  await tryGuid(`themoviedb://${tmdbId}`, false);

  // 2) External IDs
  try {
    const ex: any = await api.get(`/api/tmdb/${media}/${encodeURIComponent(tmdbId)}?append_to_response=external_ids`);
    const imdb: string | undefined = ex?.external_ids?.imdb_id;
    const tvdb: number | undefined = ex?.external_ids?.tvdb_id;
    if (imdb) {
      await tryGuid(`imdb://${imdb}`, true);
      await tryGuid(`imdb://${imdb}`, false);
    }
    if (tvdb && media === 'tv') {
      await tryGuid(`tvdb://${tvdb}`, true);
      await tryGuid(`tvdb://${tvdb}`, false);
    }
    if (!title) title = ex?.title || ex?.name;
    if (!year) year = (ex?.release_date || ex?.first_air_date || '').slice(0, 4);
  } catch (e: any) {
    steps.push({ kind: 'guid', detail: `external_ids error: ${String(e?.message||e)}` });
  }

  // 3) Search fallback
  if (title) {
    try {
      const sr = await api.get(`/api/plex/search?query=${encodeURIComponent(title)}&type=${typeNum}`);
      const arr: any[] = Array.isArray(sr) ? sr : (sr?.MediaContainer?.Metadata || sr?.Metadata || []);
      steps.push({ kind: 'search', detail: `typed search '${title}' type=${typeNum}`, count: (arr?.length || 0) });
      if (arr?.length) hits.push(...arr);
    } catch (e: any) {
      steps.push({ kind: 'search', detail: `typed search error: ${String(e?.message||e)}` });
    }
    if (!hits.length) {
      try {
        const sr2 = await api.get(`/api/plex/search?query=${encodeURIComponent(title)}`);
        const arr2: any[] = Array.isArray(sr2) ? sr2 : (sr2?.MediaContainer?.Metadata || sr2?.Metadata || []);
        steps.push({ kind: 'search', detail: `untyped search '${title}'`, count: (arr2?.length || 0) });
        if (arr2?.length) hits.push(...arr2);
      } catch (e: any) {
        steps.push({ kind: 'search', detail: `untyped search error: ${String(e?.message||e)}` });
      }
    }
  }

  // Deduplicate
  const unique = Array.from(new Map(hits.map((h:any)=> [String(h.ratingKey), h])).values());

  // Selection
  let selected: PlexMatch | null = null;
  // a) exact GUID match
  for (const h of unique) {
    const guids = Array.isArray(h.Guid) ? h.Guid.map((g:any)=> String(g.id||'')) : [];
    if (guids.includes(`tmdb://${tmdbId}`) || guids.includes(`themoviedb://${tmdbId}`)) {
      steps.push({ kind: 'select', detail: `guid-exact ${h.ratingKey}` });
      selected = { ratingKey: String(h.ratingKey), meta: h };
      break;
    }
  }
  // b) title+year
  if (!selected && title) {
    const nTitle = normalizeTitle(title);
    for (const h of unique) {
      const t = normalizeTitle(h.title || h.grandparentTitle || '');
      const y = Number(h.year || 0);
      const yy = Number(year || 0);
      const yearOk = !yy || (y === yy) || (y === yy - 1) || (y === yy + 1);
      if (t === nTitle && yearOk) {
        steps.push({ kind: 'select', detail: `title-year ${h.ratingKey} (${h.title} ${h.year})` });
        selected = { ratingKey: String(h.ratingKey), meta: h };
        break;
      }
    }
  }
  if (!selected && unique[0]) {
    steps.push({ kind: 'select', detail: `fallback-first ${unique[0].ratingKey}` });
    selected = { ratingKey: String(unique[0].ratingKey), meta: unique[0] };
  }

  return { steps, hits, unique, selected };
}
