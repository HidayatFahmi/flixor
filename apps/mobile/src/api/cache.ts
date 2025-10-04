import AsyncStorage from '@react-native-async-storage/async-storage';

/**
 * API Response Cache with TTL, LRU eviction, and AsyncStorage persistence
 *
 * Features:
 * - In-memory LRU cache for fast access
 * - Per-endpoint TTL configuration
 * - Request deduplication (prevent parallel duplicate requests)
 * - AsyncStorage persistence across app sessions
 * - Memory budget management
 */

type CacheEntry = {
  data: any;
  timestamp: number;
  ttl: number;
};

type InFlightRequest = Promise<any>;

const CACHE_PREFIX = 'api_cache:';
const CACHE_INDEX_KEY = 'api_cache_index';

// Cache TTL configuration (in milliseconds)
const CACHE_TTL: Record<string, number> = {
  // Static content - rarely changes
  '/api/tmdb/movie/': 24 * 60 * 60 * 1000,      // 24h
  '/api/tmdb/tv/': 24 * 60 * 60 * 1000,         // 24h

  // Semi-static - changes daily
  '/api/tmdb/trending': 60 * 60 * 1000,         // 1h
  '/api/tmdb/discover': 60 * 60 * 1000,         // 1h
  '/api/trakt/trending': 60 * 60 * 1000,        // 1h
  '/api/trakt/popular': 60 * 60 * 1000,         // 1h

  // Dynamic - changes frequently
  '/api/plex/continue': 5 * 60 * 1000,          // 5min
  '/api/plex/recent': 5 * 60 * 1000,            // 5min
  '/api/plex/library/items': 5 * 60 * 1000,     // 5min
  '/api/trakt/users/me/history': 5 * 60 * 1000, // 5min
  '/api/trakt/users/me/watchlist': 5 * 60 * 1000, // 5min
  '/api/trakt/recommendations': 10 * 60 * 1000,  // 10min

  // Moderate cache
  '/api/plex/metadata/': 10 * 60 * 1000,        // 10min
  '/api/plex/search': 2 * 60 * 1000,            // 2min

  // No cache (auth, session, settings)
  '/api/auth/': 0,
  '/api/settings': 0,
};

const CACHE_LIMITS = {
  maxMemoryEntries: 200,      // ~50MB with avg 250KB per response
  maxDiskEntries: 400,        // ~100MB on disk
  maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days absolute max
};

class ApiCache {
  private memoryCache = new Map<string, CacheEntry>();
  private inFlightRequests = new Map<string, InFlightRequest>();
  private accessOrder: string[] = []; // For LRU tracking

  /**
   * Get TTL for a given path
   */
  private getTTL(path: string): number {
    // Find matching cache policy
    for (const [pattern, ttl] of Object.entries(CACHE_TTL)) {
      if (path.startsWith(pattern)) {
        return ttl;
      }
    }
    // Default: 5 minutes for unspecified endpoints
    return 5 * 60 * 1000;
  }

  /**
   * Check if cache entry is still valid
   */
  private isValid(entry: CacheEntry): boolean {
    const age = Date.now() - entry.timestamp;
    return age < entry.ttl && age < CACHE_LIMITS.maxAge;
  }

  /**
   * Update LRU access order
   */
  private touchKey(key: string) {
    const idx = this.accessOrder.indexOf(key);
    if (idx > -1) {
      this.accessOrder.splice(idx, 1);
    }
    this.accessOrder.push(key);
  }

  /**
   * Evict least recently used entries if over limit
   */
  private evictIfNeeded() {
    while (this.memoryCache.size > CACHE_LIMITS.maxMemoryEntries) {
      const oldestKey = this.accessOrder.shift();
      if (oldestKey) {
        this.memoryCache.delete(oldestKey);
      }
    }
  }

  /**
   * Get from memory cache
   */
  private getFromMemory(key: string): any | null {
    const entry = this.memoryCache.get(key);
    if (!entry) return null;

    if (!this.isValid(entry)) {
      this.memoryCache.delete(key);
      return null;
    }

    this.touchKey(key);
    return entry.data;
  }

  /**
   * Get from disk cache (AsyncStorage)
   */
  private async getFromDisk(key: string): Promise<any | null> {
    try {
      const raw = await AsyncStorage.getItem(CACHE_PREFIX + key);
      if (!raw) return null;

      const entry: CacheEntry = JSON.parse(raw);
      if (!this.isValid(entry)) {
        await AsyncStorage.removeItem(CACHE_PREFIX + key);
        return null;
      }

      // Promote to memory cache
      this.memoryCache.set(key, entry);
      this.touchKey(key);
      this.evictIfNeeded();

      return entry.data;
    } catch (e) {
      console.error('[ApiCache] Failed to read from disk:', e);
      return null;
    }
  }

  /**
   * Set in both memory and disk cache
   */
  private async setCache(key: string, data: any, ttl: number) {
    const entry: CacheEntry = {
      data,
      timestamp: Date.now(),
      ttl,
    };

    // Memory cache
    this.memoryCache.set(key, entry);
    this.touchKey(key);
    this.evictIfNeeded();

    // Disk cache (async, don't await)
    try {
      await AsyncStorage.setItem(CACHE_PREFIX + key, JSON.stringify(entry));
      await this.updateCacheIndex(key);
    } catch (e) {
      console.error('[ApiCache] Failed to write to disk:', e);
    }
  }

  /**
   * Maintain index of cache keys for cleanup
   */
  private async updateCacheIndex(key: string) {
    try {
      const indexRaw = await AsyncStorage.getItem(CACHE_INDEX_KEY);
      const index: string[] = indexRaw ? JSON.parse(indexRaw) : [];

      if (!index.includes(key)) {
        index.push(key);
      }

      // Limit disk cache entries
      while (index.length > CACHE_LIMITS.maxDiskEntries) {
        const oldKey = index.shift();
        if (oldKey) {
          await AsyncStorage.removeItem(CACHE_PREFIX + oldKey);
        }
      }

      await AsyncStorage.setItem(CACHE_INDEX_KEY, JSON.stringify(index));
    } catch (e) {
      console.error('[ApiCache] Failed to update index:', e);
    }
  }

  /**
   * Get cached data or execute fetch function
   * Includes request deduplication
   */
  async getOrFetch(path: string, fetchFn: () => Promise<any>): Promise<any> {
    const ttl = this.getTTL(path);

    // No cache for this endpoint
    if (ttl === 0) {
      return fetchFn();
    }

    const cacheKey = path;

    // 1. Check memory cache
    const memoryData = this.getFromMemory(cacheKey);
    if (memoryData !== null) {
      // console.log('[ApiCache] Memory hit:', path);
      return memoryData;
    }

    // 2. Check if request is already in flight (deduplication)
    const inFlight = this.inFlightRequests.get(cacheKey);
    if (inFlight) {
      // console.log('[ApiCache] Deduped request:', path);
      return inFlight;
    }

    // 3. Check disk cache
    const diskData = await this.getFromDisk(cacheKey);
    if (diskData !== null) {
      // console.log('[ApiCache] Disk hit:', path);
      return diskData;
    }

    // 4. Execute fetch and cache result
    // console.log('[ApiCache] Cache miss, fetching:', path);
    const promise = fetchFn()
      .then(async (data) => {
        await this.setCache(cacheKey, data, ttl);
        this.inFlightRequests.delete(cacheKey);
        return data;
      })
      .catch((error) => {
        this.inFlightRequests.delete(cacheKey);
        throw error;
      });

    this.inFlightRequests.set(cacheKey, promise);
    return promise;
  }

  /**
   * Invalidate specific cache entry
   */
  async invalidate(path: string) {
    this.memoryCache.delete(path);
    await AsyncStorage.removeItem(CACHE_PREFIX + path);
  }

  /**
   * Invalidate all cache entries matching a pattern
   */
  async invalidatePattern(pattern: string) {
    // Memory
    const keysToDelete: string[] = [];
    this.memoryCache.forEach((_, key) => {
      if (key.includes(pattern)) {
        keysToDelete.push(key);
      }
    });
    keysToDelete.forEach(key => this.memoryCache.delete(key));

    // Disk
    try {
      const indexRaw = await AsyncStorage.getItem(CACHE_INDEX_KEY);
      const index: string[] = indexRaw ? JSON.parse(indexRaw) : [];

      for (const key of index) {
        if (key.includes(pattern)) {
          await AsyncStorage.removeItem(CACHE_PREFIX + key);
        }
      }
    } catch (e) {
      console.error('[ApiCache] Failed to invalidate pattern:', e);
    }
  }

  /**
   * Clear all cache
   */
  async clear() {
    this.memoryCache.clear();
    this.accessOrder = [];
    this.inFlightRequests.clear();

    try {
      const indexRaw = await AsyncStorage.getItem(CACHE_INDEX_KEY);
      const index: string[] = indexRaw ? JSON.parse(indexRaw) : [];

      for (const key of index) {
        await AsyncStorage.removeItem(CACHE_PREFIX + key);
      }
      await AsyncStorage.removeItem(CACHE_INDEX_KEY);
    } catch (e) {
      console.error('[ApiCache] Failed to clear cache:', e);
    }
  }

  /**
   * Prefetch data in background (fire and forget)
   */
  prefetch(path: string, fetchFn: () => Promise<any>) {
    this.getOrFetch(path, fetchFn).catch((e) => {
      console.warn('[ApiCache] Prefetch failed:', path, e);
    });
  }
}

export const apiCache = new ApiCache();
