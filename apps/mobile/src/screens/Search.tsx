import React, { useState, useEffect, useRef, useCallback } from 'react';
import { View, Text, TextInput, Pressable, ActivityIndicator, ScrollView, StyleSheet, Animated, Keyboard } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { Image as ExpoImage } from 'expo-image';
import { MobileApi } from '../api/client';
import Row from '../components/Row';
import { useNavigation } from '@react-navigation/native';
import { RowItem } from '../api/data';

type SearchResult = {
  id: string;
  title: string;
  type: 'movie' | 'show';
  image?: string;
  year?: string;
  source: 'plex' | 'tmdb';
  genreIds?: number[];
};

type GenreRow = {
  title: string;
  items: SearchResult[];
};

// TMDB Genre mapping
const GENRE_MAP: { [key: number]: string } = {
  28: 'Action', 12: 'Adventure', 16: 'Animation', 35: 'Comedy', 80: 'Crime',
  99: 'Documentary', 18: 'Drama', 10751: 'Family', 14: 'Fantasy', 36: 'History',
  27: 'Horror', 10402: 'Music', 9648: 'Mystery', 10749: 'Romance', 878: 'Sci-Fi',
  10770: 'TV Movie', 53: 'Thriller', 10752: 'War', 37: 'Western',
  10759: 'Action & Adventure', 10762: 'Kids', 10763: 'News', 10764: 'Reality',
  10765: 'Sci-Fi & Fantasy', 10766: 'Soap', 10767: 'Talk', 10768: 'War & Politics'
};

export default function Search() {
  const nav: any = useNavigation();
  const [api, setApi] = useState<MobileApi | null>(null);
  const [query, setQuery] = useState('');
  const [plexResults, setPlexResults] = useState<SearchResult[]>([]);
  const [tmdbMovies, setTmdbMovies] = useState<SearchResult[]>([]);
  const [tmdbShows, setTmdbShows] = useState<SearchResult[]>([]);
  const [trending, setTrending] = useState<RowItem[]>([]);
  const [genreRows, setGenreRows] = useState<GenreRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [searchMode, setSearchMode] = useState<'idle' | 'results'>('idle');
  const searchTimeout = useRef<NodeJS.Timeout>();
  const inputRef = useRef<TextInput>(null);
  const fadeAnim = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    (async () => {
      const a = await MobileApi.load();
      setApi(a);
      // Load recommended/trending for empty state as vertical list
      if (a) {
        try {
          // Fetch both movies and shows for initial recommendations
          const [moviesRes, showsRes] = await Promise.all([
            a.get('/api/tmdb/trending/movie/week'),
            a.get('/api/tmdb/trending/tv/week'),
          ]);
          
          const movies = (moviesRes?.results || []).slice(0, 6).map((item: any) => ({
            id: `tmdb:movie:${item.id}`,
            title: item.title,
            image: item.backdrop_path ? `https://image.tmdb.org/t/p/w780${item.backdrop_path}` : undefined,
            year: item.release_date?.slice(0, 4),
          }));

          const shows = (showsRes?.results || []).slice(0, 6).map((item: any) => ({
            id: `tmdb:tv:${item.id}`,
            title: item.name,
            image: item.backdrop_path ? `https://image.tmdb.org/t/p/w780${item.backdrop_path}` : undefined,
            year: item.first_air_date?.slice(0, 4),
          }));
          
          // Interleave movies and shows for variety
          const combined: RowItem[] = [];
          for (let i = 0; i < Math.max(movies.length, shows.length); i++) {
            if (shows[i]) combined.push(shows[i]);
            if (movies[i]) combined.push(movies[i]);
          }
          
          setTrending(combined);
        } catch {}
      }
    })();
    
    // Fade in animation
    Animated.timing(fadeAnim, { toValue: 1, duration: 200, useNativeDriver: true }).start();
    
    // Auto-focus input
    setTimeout(() => inputRef.current?.focus(), 100);
  }, []);

  const performSearch = useCallback(async (q: string) => {
    if (!api || !q.trim()) return;
    
    setLoading(true);
    setSearchMode('results');
    
    try {
      const plexRes: SearchResult[] = [];
      const tmdbMovieRes: SearchResult[] = [];
      const tmdbShowRes: SearchResult[] = [];

      // Search Plex
      try {
        const res = await api.get(`/api/plex/search?query=${encodeURIComponent(q)}`);
        const items = Array.isArray(res) ? res : (res?.MediaContainer?.Metadata || []);
        items.slice(0, 20).forEach((item: any) => {
          const thumb = item.thumb || item.parentThumb || item.grandparentThumb;
          plexRes.push({
            id: `plex:${item.ratingKey}`,
            title: item.title || item.grandparentTitle || 'Untitled',
            type: item.type === 'movie' ? 'movie' : 'show',
            image: thumb ? `${api.baseUrl}/api/image/plex?path=${encodeURIComponent(thumb)}&w=300&f=webp` : undefined,
            year: item.year ? String(item.year) : undefined,
            source: 'plex',
          });
        });
      } catch (e) {
        console.log('[Search] Plex search failed:', e);
      }

      // Search TMDB
      const allGenreIds = new Set<number>();
      try {
        const res = await api.get(`/api/tmdb/search/multi?query=${encodeURIComponent(q)}&page=1`);
        const items = res?.results || [];
        items.slice(0, 20).forEach((item: any) => {
          if (item.media_type === 'movie') {
            tmdbMovieRes.push({
              id: `tmdb:movie:${item.id}`,
              title: item.title,
              type: 'movie',
              image: item.poster_path ? `https://image.tmdb.org/t/p/w500${item.poster_path}` : undefined,
              year: item.release_date?.slice(0, 4),
              source: 'tmdb',
              genreIds: item.genre_ids || [],
            });
            (item.genre_ids || []).forEach((gid: number) => allGenreIds.add(gid));
          } else if (item.media_type === 'tv') {
            tmdbShowRes.push({
              id: `tmdb:tv:${item.id}`,
              title: item.name,
              type: 'show',
              image: item.poster_path ? `https://image.tmdb.org/t/p/w500${item.poster_path}` : undefined,
              year: item.first_air_date?.slice(0, 4),
              source: 'tmdb',
              genreIds: item.genre_ids || [],
            });
            (item.genre_ids || []).forEach((gid: number) => allGenreIds.add(gid));
          }
        });
      } catch (e) {
        console.log('[Search] TMDB search failed:', e);
      }

      setPlexResults(plexRes);
      setTmdbMovies(tmdbMovieRes);
      setTmdbShows(tmdbShowRes);

      // Fetch genre-based recommendations
      const genreRowsData: GenreRow[] = [];
      const topGenres = Array.from(allGenreIds).slice(0, 3); // Top 3 genres from search results

      for (const genreId of topGenres) {
        const genreName = GENRE_MAP[genreId];
        if (!genreName) continue;

        try {
          // Fetch movies for this genre
          const movieRes = await api.get(`/api/tmdb/discover/movie?with_genres=${genreId}&sort_by=popularity.desc&page=1`);
          const movies = (movieRes?.results || []).slice(0, 10).map((item: any) => ({
            id: `tmdb:movie:${item.id}`,
            title: item.title,
            type: 'movie' as const,
            image: item.poster_path ? `https://image.tmdb.org/t/p/w500${item.poster_path}` : undefined,
            year: item.release_date?.slice(0, 4),
            source: 'tmdb' as const,
          }));

          // Fetch TV shows for this genre
          const tvRes = await api.get(`/api/tmdb/discover/tv?with_genres=${genreId}&sort_by=popularity.desc&page=1`);
          const shows = (tvRes?.results || []).slice(0, 10).map((item: any) => ({
            id: `tmdb:tv:${item.id}`,
            title: item.name,
            type: 'show' as const,
            image: item.poster_path ? `https://image.tmdb.org/t/p/w500${item.poster_path}` : undefined,
            year: item.first_air_date?.slice(0, 4),
            source: 'tmdb' as const,
          }));

          // Combine movies and shows
          const combined = [...movies, ...shows].slice(0, 15);

          if (combined.length > 0) {
            genreRowsData.push({
              title: genreName,
              items: combined,
            });
          }
        } catch (e) {
          console.log(`[Search] Failed to fetch genre ${genreName}:`, e);
        }
      }

      setGenreRows(genreRowsData);
    } finally {
      setLoading(false);
    }
  }, [api]);

  const handleQueryChange = (text: string) => {
    setQuery(text);
    
    if (searchTimeout.current) clearTimeout(searchTimeout.current);
    
    if (text.trim()) {
      searchTimeout.current = setTimeout(() => performSearch(text), 300);
    } else {
      setSearchMode('idle');
      setPlexResults([]);
      setTmdbMovies([]);
      setTmdbShows([]);
      setGenreRows([]);
    }
  };

  const handleResultPress = (result: SearchResult | RowItem) => {
    const id = result.id;
    if (id.startsWith('plex:')) {
      const rk = id.split(':')[1];
      nav.navigate('Details', { type: 'plex', ratingKey: rk });
    } else if (id.startsWith('tmdb:')) {
      const [, media, tmdbId] = id.split(':');
      nav.navigate('Details', { type: 'tmdb', mediaType: media, id: tmdbId });
    }
  };

  const authHeaders = api?.token ? { Authorization: `Bearer ${api.token}` } : undefined;

  return (
    <View style={{ flex: 1, backgroundColor: '#0a0a0a' }}>
      {/* Full screen gradients */}
      <LinearGradient
        colors={[ '#0a0a0a', '#0f0f10', '#0b0c0d' ]}
        start={{ x: 0.5, y: 0 }} end={{ x: 0.5, y: 1 }}
        style={StyleSheet.absoluteFillObject}
      />
      <LinearGradient
        colors={[ 'rgba(122,22,18,0.20)', 'rgba(122,22,18,0.08)', 'rgba(122,22,18,0.0)' ]}
        start={{ x: 0.0, y: 1.0 }} end={{ x: 0.45, y: 0.35 }}
        style={StyleSheet.absoluteFillObject}
      />
      <LinearGradient
        colors={[ 'rgba(20,76,84,0.18)', 'rgba(20,76,84,0.08)', 'rgba(20,76,84,0.0)' ]}
        start={{ x: 1.0, y: 0.0 }} end={{ x: 0.55, y: 0.45 }}
        style={StyleSheet.absoluteFillObject}
      />

      <SafeAreaView style={{ flex: 1 }} edges={['top']}>
        <Animated.View style={{ flex: 1, opacity: fadeAnim }}>
          {/* Search Bar */}
          <View style={styles.searchBar}>
            <Ionicons name="search" size={20} color="#888" style={{ marginRight: 12 }} />
            <TextInput
              ref={inputRef}
              value={query}
              onChangeText={handleQueryChange}
              placeholder="Search for movies, shows..."
              placeholderTextColor="#666"
              style={styles.input}
              returnKeyType="search"
              autoCapitalize="none"
              autoCorrect={false}
            />
            {query ? (
              <Pressable onPress={() => handleQueryChange('')} style={{ padding: 4 }}>
                <Ionicons name="close-circle" size={20} color="#888" />
              </Pressable>
            ) : null}
            <Pressable onPress={() => nav.goBack()} style={{ marginLeft: 12 }}>
              <Text style={{ color: '#fff', fontWeight: '600' }}>Cancel</Text>
            </Pressable>
          </View>

          {/* Results/Empty State */}
          <ScrollView
            style={{ flex: 1 }}
            contentContainerStyle={{ paddingBottom: 80 }}
            keyboardShouldPersistTaps="handled"
            onScrollBeginDrag={() => Keyboard.dismiss()}
          >
            {searchMode === 'idle' ? (
              <View style={{ paddingTop: 24 }}>
                <Text style={{ color: '#fff', fontSize: 20, fontWeight: '800', marginHorizontal: 16, marginBottom: 16 }}>Recommended TV Shows & Movies</Text>
                {/* Vertical list of recommended items */}
                {trending.map((item, i) => (
                  <Pressable key={i} onPress={() => handleResultPress(item)} style={styles.recommendCard}>
                    <View style={styles.recommendImage}>
                      {item.image ? (
                        <ExpoImage source={{ uri: item.image }} style={{ width: '100%', height: '100%' }} contentFit="cover" />
                      ) : null}
                      {/* "Recently added" badge for some items */}
                      {i < 3 ? (
                        <View style={{ position: 'absolute', bottom: 8, left: 8, backgroundColor: '#E50914', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 4 }}>
                          <Text style={{ color: '#fff', fontSize: 11, fontWeight: '700' }}>Recently added</Text>
                        </View>
                      ) : null}
                      {/* TOP 10 badge for top items */}
                      {i < 2 ? (
                        <View style={{ position: 'absolute', top: 8, right: 8, backgroundColor: '#E50914', width: 36, height: 36, borderRadius: 4, alignItems: 'center', justifyContent: 'center' }}>
                          <Text style={{ color: '#fff', fontSize: 10, fontWeight: '700' }}>TOP</Text>
                          <Text style={{ color: '#fff', fontSize: 16, fontWeight: '900' }}>10</Text>
                        </View>
                      ) : null}
                    </View>
                    <View style={{ flex: 1, marginLeft: 16, justifyContent: 'center' }}>
                      <Text style={{ color: '#fff', fontWeight: '700', fontSize: 16 }}>{item.title}</Text>
                      {item.year ? <Text style={{ color: '#aaa', fontSize: 13, marginTop: 4 }}>{item.year}</Text> : null}
                    </View>
                    {/* Play button */}
                    <View style={{ width: 44, height: 44, borderRadius: 22, borderWidth: 2, borderColor: '#fff', alignItems: 'center', justifyContent: 'center' }}>
                      <Ionicons name="play" size={20} color="#fff" style={{ marginLeft: 2 }} />
                    </View>
                  </Pressable>
                ))}
              </View>
            ) : null}

            {searchMode === 'results' ? (
              loading ? (
                <View style={{ alignItems: 'center', paddingTop: 40 }}>
                  <ActivityIndicator color="#fff" size="large" />
                </View>
              ) : (
                <View style={{ paddingTop: 8 }}>
                  {/* Plex Results - Grid (Prominent) */}
                  {plexResults.length > 0 ? (
                    <>
                      <Text style={{ color: '#fff', fontSize: 22, fontWeight: '700', marginHorizontal: 16, marginBottom: 16, marginTop: 8 }}>Results from Your Plex</Text>

                      {/* Plex results grid - show first 4 results */}
                      <View style={styles.topResultsGrid}>
                        {plexResults
                          .slice(0, 4)
                          .map((result, i) => (
                            <Pressable key={i} onPress={() => handleResultPress(result)} style={styles.topResultCard}>
                              <View style={styles.topResultImage}>
                                {result.image ? (
                                  <ExpoImage source={{ uri: result.image, headers: authHeaders }} style={{ width: '100%', height: '100%' }} contentFit="cover" />
                                ) : (
                                  <View style={{ width: '100%', height: '100%', backgroundColor: '#1a1a1a' }} />
                                )}
                              </View>
                            </Pressable>
                          ))}
                      </View>

                      {/* Additional Plex results as horizontal row */}
                      {plexResults.length > 4 ? (
                        <View style={{ marginTop: 8, marginHorizontal: 16}}>
                          <Row
                            title="More from Your Plex"
                            items={plexResults.slice(4).map(r => ({ id: r.id, title: r.title, image: r.image }))}
                            getImageUri={(it) => it.image}
                            getTitle={(it) => it.title}
                            authHeaders={authHeaders}
                            onItemPress={handleResultPress}
                          />
                        </View>
                      ) : null}
                    </>
                  ) : null}

                  {/* Top Results Section - Horizontal Rows */}
                  {tmdbMovies.length > 0 ? (
                    <View style={{ marginTop: plexResults.length > 0 ? 16 : 8 }}>
                      <Row
                        title="Top Results"
                        items={tmdbMovies.slice(0, 10).map(r => ({ id: r.id, title: r.title, image: r.image }))}
                        getImageUri={(it) => it.image}
                        getTitle={(it) => it.title}
                        authHeaders={authHeaders}
                        onItemPress={handleResultPress}
                      />
                    </View>
                  ) : null}

                  {tmdbShows.length > 0 ? (
                    <Row
                      title="TV Shows"
                      items={tmdbShows.slice(0, 10).map(r => ({ id: r.id, title: r.title, image: r.image }))}
                      getImageUri={(it) => it.image}
                      getTitle={(it) => it.title}
                      authHeaders={authHeaders}
                      onItemPress={handleResultPress}
                    />
                  ) : null}

                  {/* Dynamic Genre Rows */}
                  {genreRows.map((genreRow, idx) => (
                    <Row
                      key={idx}
                      title={genreRow.title}
                      items={genreRow.items.map(r => ({ id: r.id, title: r.title, image: r.image }))}
                      getImageUri={(it) => it.image}
                      getTitle={(it) => it.title}
                      authHeaders={authHeaders}
                      onItemPress={handleResultPress}
                    />
                  ))}

                  {!loading && plexResults.length === 0 && tmdbMovies.length === 0 && tmdbShows.length === 0 ? (
                    <Text style={{ color: '#888', textAlign: 'center', marginTop: 40 }}>No results found for "{query}"</Text>
                  ) : null}
                </View>
              )
            ) : null}
          </ScrollView>
        </Animated.View>
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(48,48,50,0.98)',
    marginHorizontal: 16,
    marginTop: 12,
    marginBottom: 8,
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 10,
  },
  input: {
    flex: 1,
    color: '#fff',
    fontSize: 17,
    padding: 0,
  },
  recommendCard: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: 16,
    marginBottom: 8,
    paddingVertical: 8,
  },
  recommendImage: {
    width: 200,
    height: 112,
    borderRadius: 8,
    backgroundColor: '#1a1a1a',
    overflow: 'hidden',
  },
  topResultsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingHorizontal: 12,
    gap: 8,
  },
  topResultCard: {
    width: '48.5%',
    marginBottom: 8,
  },
  topResultImage: {
    width: '100%',
    aspectRatio: 2/3,
    borderRadius: 6,
    backgroundColor: '#1a1a1a',
    overflow: 'hidden',
  },
});

