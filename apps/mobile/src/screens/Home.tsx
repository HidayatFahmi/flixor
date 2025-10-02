import React, { useEffect, useState } from 'react';
import { View, Text, ActivityIndicator, Animated } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MobileApi } from '../api/client';
import Row from '../components/Row';
import { useNavigation, useIsFocused } from '@react-navigation/native';
import {
  fetchContinue,
  fetchRecent,
  fetchTrendingMovies,
  fetchTrendingShows,
  // fetchPlexPopular,
  fetchPlexGenreRow,
  fetchPlexWatchlist,
  fetchTraktTrendingMapped,
  fetchTraktPopularShowsMapped,
  fetchTraktWatchlistMapped,
  fetchTraktHistoryMapped,
  fetchTraktRecommendationsMapped,
  fetchTmdbTrendingTVWeek,
  RowItem,
} from '../api/data';
import HomeHeader from '../components/HomeHeader';
import TopAppBar from '../components/TopAppBar';
import Pills from '../components/Pills';
import HeroCard from '../components/HeroCard';

export default function Home({ api }: { api: MobileApi }) {
  const nav: any = useNavigation();
  const [loading, setLoading] = useState(true);
  const [welcome, setWelcome] = useState<string>('');
  const [continueItems, setContinueItems] = useState<any[]>([]);
  const [trendingMovies, setTrendingMovies] = useState<any[]>([]);
  const [trendingShows, setTrendingShows] = useState<any[]>([]);
  const [recent, setRecent] = useState<any[]>([]);
  // Web Home uses TMDB trending TV week as the source for the first two rows
  const [popularOnPlexTmdb, setPopularOnPlexTmdb] = useState<RowItem[]>([]);
  const [trendingNow, setTrendingNow] = useState<RowItem[]>([]);
  const [watchlist, setWatchlist] = useState<RowItem[]>([]);
  const [genres, setGenres] = useState<Record<string, RowItem[]>>({});
  const [traktTrendMovies, setTraktTrendMovies] = useState<RowItem[]>([]);
  const [traktTrendShows, setTraktTrendShows] = useState<RowItem[]>([]);
  const [traktPopularShows, setTraktPopularShows] = useState<RowItem[]>([]);
  const [traktMyWatchlist, setTraktMyWatchlist] = useState<RowItem[]>([]);
  const [traktHistory, setTraktHistory] = useState<RowItem[]>([]);
  const [traktRecommendations, setTraktRecommendations] = useState<RowItem[]>([]);
  const [tab, setTab] = useState<'all'|'movies'|'shows'>('all');
  const [showTopBar, setShowTopBar] = useState(false);
  const [showFilterBar, setShowFilterBar] = useState(false);
  const y = React.useRef(new Animated.Value(0)).current;
  const prevY = React.useRef(0);
  const isFocused = useIsFocused();

  useEffect(() => {
    (async () => {
      try {
        console.log('[Home] session fetch');
        const session = await api.session();
        const name = session?.user?.username || 'User';
        setWelcome(`Welcome, ${name}`);
        // Continue Watching
        console.log('[Home] continue fetch');
        const cont = await fetchContinue(api);
        setContinueItems(cont);
        // Trending Movies/Shows (raw for hero scoring only)
        console.log('[Home] trending movies (raw)');
        setTrendingMovies(await fetchTrendingMovies(api));
        console.log('[Home] trending shows (raw)');
        setTrendingShows(await fetchTrendingShows(api));
        // Recently Added
        console.log('[Home] recent');
        setRecent(await fetchRecent(api));

        // Popular on Plex + Trending Now (from TMDB trending TV week)
        console.log('[Home] tmdb trending tv (week)');
        const tmdbTv = await fetchTmdbTrendingTVWeek(api);
        setPopularOnPlexTmdb(tmdbTv.slice(0, 8));
        setTrendingNow(tmdbTv.slice(8, 16));

        // Plex.tv Watchlist
        console.log('[Home] plex.tv watchlist');
        setWatchlist(await fetchPlexWatchlist(api));

        // Genre rows
        const genreDefs: Array<{key:string; type:'movie'|'show'; label:string}> = [
          { key:'TV Shows - Children', type:'show', label:'Children' },
          { key:'Movie - Music', type:'movie', label:'Music' },
          { key:'Movies - Documentary', type:'movie', label:'Documentary' },
          { key:'Movies - History', type:'movie', label:'History' },
          { key:'TV Shows - Reality', type:'show', label:'Reality' },
          { key:'Movies - Drama', type:'movie', label:'Drama' },
          { key:'TV Shows - Suspense', type:'show', label:'Suspense' },
          { key:'Movies - Animation', type:'movie', label:'Animation' },
        ];
        const gEntries: [string, RowItem[]][] = [];
        for (const gd of genreDefs) {
          try { gEntries.push([gd.key, await fetchPlexGenreRow(api, gd.type, gd.label)]); } catch {}
        }
        setGenres(Object.fromEntries(gEntries));

        // Trakt mapped rows (with Plex mapping fallback)
        console.log('[Home] trakt trending mapped');
        setTraktTrendMovies(await fetchTraktTrendingMapped(api, 'movies'));
        setTraktTrendShows(await fetchTraktTrendingMapped(api, 'shows'));
        console.log('[Home] trakt popular shows');
        setTraktPopularShows(await fetchTraktPopularShowsMapped(api));
        console.log('[Home] trakt my watchlist');
        setTraktMyWatchlist(await fetchTraktWatchlistMapped(api));
        console.log('[Home] trakt history');
        setTraktHistory(await fetchTraktHistoryMapped(api));
        console.log('[Home] trakt recommendations');
        setTraktRecommendations(await fetchTraktRecommendationsMapped(api));
      } catch {
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  // Light refresh of Trakt-dependent rows on focus (after potential auth)
  useEffect(() => {
    (async () => {
      if (!isFocused || loading) return;
      try {
        setTraktTrendMovies(await fetchTraktTrendingMapped(api, 'movies'));
        setTraktTrendShows(await fetchTraktTrendingMapped(api, 'shows'));
        setTraktPopularShows(await fetchTraktPopularShowsMapped(api));
        setTraktMyWatchlist(await fetchTraktWatchlistMapped(api));
        setTraktHistory(await fetchTraktHistoryMapped(api));
        setTraktRecommendations(await fetchTraktRecommendationsMapped(api));
      } catch {}
    })();
  }, [isFocused]);

  if (loading) {
    return (
      <View style={{ flex: 1, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator color="#fff" />
      </View>
    );
  }

  const authHeaders = api.token ? { Authorization: `Bearer ${api.token}` } : undefined;
  const plexImage = (item: any) => {
    const path = item?.thumb || item?.art;
    if (!path) return undefined;
    // Use backend plex image proxy (accepts path and uses Authorization header)
    return `${api.baseUrl}/api/image/plex?path=${encodeURIComponent(String(path))}&w=300&f=webp`;
  };

  const getRowUri = (it: RowItem) => it.image;
  const getRowTitle = (it: RowItem) => it.title;
  const onRowPress = (it: RowItem) => {
    if (!it?.id) return;
    if (it.id.startsWith('plex:')) {
      const rk = it.id.split(':')[1];
      return nav.navigate('Details', { type:'plex', ratingKey: rk });
    }
    if (it.id.startsWith('tmdb:')) {
      const [, media, id] = it.id.split(':');
      return nav.navigate('Details', { type:'tmdb', mediaType: media === 'movie' ? 'movie' : 'tv', id });
    }
  };

  type HeroPick = { title: string; image?: string; subtitle?: string };
  const pickHero = (): HeroPick => {
    // Build candidates with a lightweight scoring similar to web (prefer Plex continue/onDeck; else trending with backdrops)
    const candidates: Array<{ title: string; image?: string; score: number; subtitle?: string }> = [];
    // Continue candidates (Plex)
    continueItems.slice(0, 4).forEach((it, i) => {
      candidates.push({
        title: it.title || it.name || 'Continue',
        image: plexImage(it),
        score: 50 - i * 2 + (it.viewOffset ? 1 : 0),
        subtitle: undefined,
      });
    });
    // Trending movies
    trendingMovies.slice(0, 6).forEach((it, i) => {
      const b = it?.movie?.backdrop_path ? `https://image.tmdb.org/t/p/w780${it.movie.backdrop_path}` : undefined;
      const t = it?.movie?.title;
      if (b && t) candidates.push({ title: t, image: b, score: 40 - i * 2 + (tab !== 'shows' ? 2 : 0), subtitle: `#${i+1} in Movies Today` });
    });
    // Trending shows
    trendingShows.slice(0, 6).forEach((it, i) => {
      const b = it?.show?.backdrop_path ? `https://image.tmdb.org/t/p/w780${it.show.backdrop_path}` : undefined;
      const t = it?.show?.title || it?.show?.name;
      if (b && t) candidates.push({ title: t, image: b, score: 38 - i * 2 + (tab !== 'movies' ? 2 : 0), subtitle: `#${i+1} in Shows Today` });
    });
    // Recently added (as a last resort)
    recent.slice(0, 4).forEach((it, i) => {
      candidates.push({ title: it.title || it.name || 'Featured', image: plexImage(it), score: 20 - i * 2 });
    });
    // Choose best by score
    const best = candidates.sort((a, b) => b.score - a.score)[0];
    return { title: best?.title || 'Featured', image: best?.image, subtitle: best?.subtitle };
  };

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: '#1b0a10' }}>
      {/* Sticky Top Bar that fades in on scroll */}
      <TopAppBar visible={showTopBar} username={welcome.replace('Welcome, ', '')} showFilters={showFilterBar} selected={tab} onChange={setTab} onOpenCategories={()=>{}} />
      {/* Themed background layers inspired by web bg-home-gradient */}
      {/* Base vertical dark gradient */}
      <LinearGradient
        colors={[ '#0a0a0a', '#0f0f10', '#0b0c0d' ]}
        start={{ x: 0.5, y: 0 }}
        end={{ x: 0.5, y: 1 }}
        style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 260 }}
      />
      {/* Diagonal warm tint from bottom-left akin to web's red radial */}
      <LinearGradient
        colors={[ 'rgba(122,22,18,0.28)', 'rgba(122,22,18,0.08)', 'rgba(122,22,18,0.0)' ]}
        start={{ x: 0.0, y: 1.0 }}
        end={{ x: 0.45, y: 0.35 }}
        style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 260 }}
      />
      {/* Diagonal cool tint from top-right akin to web's teal radial */}
      <LinearGradient
        colors={[ 'rgba(20,76,84,0.26)', 'rgba(20,76,84,0.08)', 'rgba(20,76,84,0.0)' ]}
        start={{ x: 1.0, y: 0.0 }}
        end={{ x: 0.55, y: 0.45 }}
        style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 260 }}
      />
      <Animated.ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingBottom: 24 }}
        scrollEventThrottle={16}
        onScroll={Animated.event([
          { nativeEvent: { contentOffset: { y } } }
        ], {
          useNativeDriver: false,
          listener: (e) => {
            const off = e.nativeEvent.contentOffset.y;
            const delta = off - prevY.current;
            prevY.current = off;
            if (!showTopBar && off > 120) setShowTopBar(true);
            else if (showTopBar && off <= 120) setShowTopBar(false);
            // Much more sensitive pill show/hide
            // Show when user scrolls up slightly past a small offset; hide on tiny downward scrolls
            if (!showFilterBar && off > 40 && delta < -1.5) setShowFilterBar(true);
            if (showFilterBar && delta > 2) setShowFilterBar(false);
          }
        })}
      >
      <HomeHeader username={welcome.replace('Welcome, ', '')} onSearch={()=>{}} />
      <Pills selected={tab} onChange={setTab} onOpenCategories={()=>{}} />
      {(() => { const h = pickHero(); return (
        <HeroCard hero={{ title: h.title, subtitle: h.subtitle, imageUri: h.image }} authHeaders={authHeaders} onPlay={()=>{}} onAdd={()=>{}} />
      ); })()}

      <View style={{ paddingHorizontal: 16, marginTop: 16 }}>
      {popularOnPlexTmdb.length > 0 && (
        <Row title="Popular on Plex" items={popularOnPlexTmdb}
          getImageUri={getRowUri}
          getTitle={getRowTitle}
          authHeaders={authHeaders}
          onItemPress={onRowPress}
        />
      )}

      {continueItems.length > 0 && (
        <Row title="Continue Watching" items={continueItems}
          getImageUri={plexImage}
          getTitle={(it) => it.title || it.name}
          authHeaders={authHeaders}
          onItemPress={(it)=> nav.navigate('Details', { type:'plex', ratingKey: String(it.ratingKey || it.guid || '') })}
        />
      )}

      {trendingNow.length > 0 && (
        <Row title="Trending Now" items={trendingNow}
          getImageUri={getRowUri}
          getTitle={getRowTitle}
          authHeaders={authHeaders}
          onItemPress={onRowPress}
        />
      )}

      {watchlist.length > 0 && (
        <Row title="Watchlist" items={watchlist}
          getImageUri={getRowUri}
          getTitle={getRowTitle}
          authHeaders={authHeaders}
          onItemPress={onRowPress}
        />
      )}

      {watchlist.length > 0 && (
        <Row title="Watchlist" items={watchlist}
          getImageUri={getRowUri}
          getTitle={getRowTitle}
          authHeaders={authHeaders}
          onItemPress={onRowPress}
        />
      )}

      {genres['TV Shows - Children']?.length ? (
        <Row title="TV Shows - Children" items={genres['TV Shows - Children']}
          getImageUri={getRowUri} getTitle={getRowTitle} authHeaders={authHeaders} onItemPress={onRowPress}
        />
      ) : null}
      {genres['Movie - Music']?.length ? (
        <Row title="Movie - Music" items={genres['Movie - Music']}
          getImageUri={getRowUri} getTitle={getRowTitle} authHeaders={authHeaders} onItemPress={onRowPress}
        />
      ) : null}
      {genres['Movies - Documentary']?.length ? (
        <Row title="Movies - Documentary" items={genres['Movies - Documentary']}
          getImageUri={getRowUri} getTitle={getRowTitle} authHeaders={authHeaders} onItemPress={onRowPress}
        />
      ) : null}
      {genres['Movies - History']?.length ? (
        <Row title="Movies - History" items={genres['Movies - History']}
          getImageUri={getRowUri} getTitle={getRowTitle} authHeaders={authHeaders} onItemPress={onRowPress}
        />
      ) : null}
      {genres['TV Shows - Reality']?.length ? (
        <Row title="TV Shows - Reality" items={genres['TV Shows - Reality']}
          getImageUri={getRowUri} getTitle={getRowTitle} authHeaders={authHeaders} onItemPress={onRowPress}
        />
      ) : null}
      {genres['Movies - Drama']?.length ? (
        <Row title="Movies - Drama" items={genres['Movies - Drama']}
          getImageUri={getRowUri} getTitle={getRowTitle} authHeaders={authHeaders} onItemPress={onRowPress}
        />
      ) : null}
      {genres['TV Shows - Suspense']?.length ? (
        <Row title="TV Shows - Suspense" items={genres['TV Shows - Suspense']}
          getImageUri={getRowUri} getTitle={getRowTitle} authHeaders={authHeaders} onItemPress={onRowPress}
        />
      ) : null}
      {genres['Movies - Animation']?.length ? (
        <Row title="Movies - Animation" items={genres['Movies - Animation']}
          getImageUri={getRowUri} getTitle={getRowTitle} authHeaders={authHeaders} onItemPress={onRowPress}
        />
      ) : null}

      {recent.length > 0 && (
        <Row title="Recently Added" items={recent}
          getImageUri={plexImage}
          getTitle={(it) => it.title || it.name}
          authHeaders={authHeaders}
          onItemPress={(it)=> nav.navigate('Details', { type:'plex', ratingKey: String(it.ratingKey || it.guid || '') })}
        />
      )}

      {(tab !== 'shows') && traktTrendMovies.length > 0 && (
        <Row title="Trending Movies on Trakt" items={traktTrendMovies}
          getImageUri={getRowUri}
          getTitle={getRowTitle}
          authHeaders={authHeaders}
          onItemPress={onRowPress}
        />
      )}

      {(tab !== 'movies') && traktTrendShows.length > 0 && (
        <Row title="Trending TV Shows on Trakt" items={traktTrendShows}
          getImageUri={getRowUri}
          getTitle={getRowTitle}
          authHeaders={authHeaders}
          onItemPress={onRowPress}
        />
      )}

      {traktMyWatchlist.length > 0 && (
        <Row title="Your Trakt Watchlist" items={traktMyWatchlist}
          getImageUri={getRowUri}
          getTitle={getRowTitle}
          authHeaders={authHeaders}
          onItemPress={onRowPress}
        />
      )}

      {traktHistory.length > 0 && (
        <Row title="Recently Watched" items={traktHistory}
          getImageUri={getRowUri}
          getTitle={getRowTitle}
          authHeaders={authHeaders}
          onItemPress={onRowPress}
        />
      )}

      {traktRecommendations.length > 0 && (
        <Row title="Recommended for You" items={traktRecommendations}
          getImageUri={getRowUri}
          getTitle={getRowTitle}
          authHeaders={authHeaders}
          onItemPress={onRowPress}
        />
      )}

      {traktPopularShows.length > 0 && (
        <Row title="Popular TV Shows on Trakt" items={traktPopularShows}
          getImageUri={getRowUri}
          getTitle={getRowTitle}
          authHeaders={authHeaders}
          onItemPress={onRowPress}
        />
      )}
      </View>
      </Animated.ScrollView>
    </SafeAreaView>
  );
}
