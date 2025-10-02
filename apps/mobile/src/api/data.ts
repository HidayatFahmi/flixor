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
  return (mc?.MediaContainer?.Metadata || []) as any[];
}

export async function fetchPlexSeasons(api: MobileApi, showRatingKey: string): Promise<any[]> {
  const mc = await api.get(`/api/plex/dir/library/metadata/${encodeURIComponent(showRatingKey)}/children`);
  const items = (mc?.MediaContainer?.Metadata || []) as any[];
  if (!items || !items.length) return [];
  // Many PMS return season entries without explicit type; accept both
  const seasons = items.filter((x:any)=> String(x.type||'').toLowerCase()==='season');
  if (seasons.length) return seasons;
  // Fallback: treat children as seasons (they should have ratingKey and title like 'Season 1')
  return items;
}

export async function fetchPlexSeasonEpisodes(api: MobileApi, seasonKey: string): Promise<any[]> {
  const mc = await api.get(`/api/plex/dir/library/metadata/${encodeURIComponent(seasonKey)}/children`);
  return (mc?.MediaContainer?.Metadata || []) as any[];
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
