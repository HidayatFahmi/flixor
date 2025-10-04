import React, { useEffect, useState, useRef } from 'react';
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
import { TopBarStore, useTopBarStore } from '../components/TopBarStore';
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
  const [heroLogo, setHeroLogo] = useState<string | undefined>(undefined);
  const [heroPick, setHeroPick] = useState<HeroPick | null>(null);
  const y = React.useRef(new Animated.Value(0)).current;
  const showPillsAnim = React.useRef(new Animated.Value(1)).current;
  const barHeight = useTopBarStore(s => s.height || 90);
  const isFocused = useIsFocused();
  const lastScrollY = useRef(0);
  const scrollDirection = useRef<'up'|'down'>('down');

  // Set scrollY and showPills immediately on mount and when regaining focus
  React.useLayoutEffect(() => {
    if (isFocused) {
      console.log('[Home] Setting scrollY and showPills for Home screen');
      TopBarStore.setScrollY(y);
      TopBarStore.setShowPills(showPillsAnim);
    }
  }, [isFocused, y]);

  // Reset tab to 'all' when returning to Home (on focus), but not on first mount
  const isFirstMount = useRef(true);
  useEffect(() => {
    if (isFocused) {
      if (isFirstMount.current) {
        isFirstMount.current = false;
      } else {
        // Only reset if we're returning (not first mount)
        console.log('[Home] Returning to Home, resetting tab to all');
        setTab('all');
      }
    }
  }, [isFocused]);

  // Push top bar updates via effects - include isFocused to re-establish handlers when screen regains focus
  useEffect(() => {
    if (!isFocused) return; // Only update when focused
    
    console.log('[Home] Updating TopBar handlers, tab:', tab);
    TopBarStore.setVisible(true);
    TopBarStore.setShowFilters(true);
    TopBarStore.setUsername(welcome.replace('Welcome, ', ''));
    TopBarStore.setSelected(tab);
    TopBarStore.setCompact(false); // Home uses full-size bar
    TopBarStore.setHandlers({ 
      onNavigateLibrary: (t)=> {
        console.log('[Home] Navigating to Library with tab:', t);
        nav.navigate('Library', { tab: t==='movies'?'movies':'tv' });
      }, 
      onClose: () => {
        console.log('[Home] Close button clicked, resetting to all');
        setTab('all');
      },
      onSearch: () => {
        console.log('[Home] Opening search');
        nav.navigate('Search');
      }
    });
  }, [welcome, tab, nav, isFocused]);

  // Helper function to pick hero - defined early so effects can use it
  const pickHero = (): HeroPick => {
    // Pick randomly from Popular on Plex
    if (popularOnPlexTmdb.length > 0) {
      const randomIndex = Math.floor(Math.random() * Math.min(popularOnPlexTmdb.length, 8));
      const pick = popularOnPlexTmdb[randomIndex];
      
      // Extract TMDB ID from pick.id (format: "tmdb:tv:12345" or "tmdb:movie:67890")
      let tmdbId: string | undefined;
      let mediaType: 'movie'|'tv' | undefined;
      if (pick.id && pick.id.startsWith('tmdb:')) {
        const parts = pick.id.split(':');
        mediaType = parts[1] as 'movie'|'tv';
        tmdbId = parts[2];
      }
      
      return {
        title: pick.title,
        image: pick.image,
        subtitle: 'Watch the Limited Series now',
        tmdbId,
        mediaType,
      };
    }
    
    // Fallback to trending if Popular on Plex is empty
    const fallback = [...trendingMovies, ...trendingShows];
    if (fallback.length > 0) {
      const randomIndex = Math.floor(Math.random() * Math.min(fallback.length, 6));
      const pick = fallback[randomIndex];
      const b = pick?.movie?.backdrop_path || pick?.show?.backdrop_path;
      const t = pick?.movie?.title || pick?.show?.title || pick?.show?.name;
      return {
        title: t || 'Featured',
        image: b ? `https://image.tmdb.org/t/p/w780${b}` : undefined,
        subtitle: 'Watch now',
      };
    }
    
    return { title: 'Featured', image: undefined, subtitle: undefined };
  };

  useEffect(() => {
    (async () => {
      try {
        console.log('[Home] session fetch');
        const session = await api.session();
        const name = session?.user?.username || 'User';
        setWelcome(`Welcome, ${name}`);

        // Kick off primary rows in parallel and handle failures gracefully
        const results = await Promise.allSettled([
          fetchContinue(api),                              // 0
          fetchTrendingMovies(api),                        // 1
          fetchTrendingShows(api),                         // 2
          fetchRecent(api),                                // 3
          fetchTmdbTrendingTVWeek(api),                    // 4
          fetchPlexWatchlist(api),                         // 5
        ]);
        const val = (i: number, def: any) => results[i].status === 'fulfilled' ? (results[i] as PromiseFulfilledResult<any>).value : def;
        try { setContinueItems(val(0, [])); } catch {}
        try { setTrendingMovies(val(1, [])); } catch {}
        try { setTrendingShows(val(2, [])); } catch {}
        try { setRecent(val(3, [])); } catch {}
        try {
          const tv = val(4, []);
          console.log('[Home] TMDB trending TV fetched:', tv.length, 'items');
          setPopularOnPlexTmdb(tv.slice(0, 8));
          setTrendingNow(tv.slice(8, 16));
        } catch {}
        try { setWatchlist(val(5, [])); } catch {}

        // Genre rows – best-effort per row
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
        await Promise.allSettled(genreDefs.map(async (gd) => {
          try { gEntries.push([gd.key, await fetchPlexGenreRow(api, gd.type, gd.label)]); } catch {}
        }));
        setGenres(Object.fromEntries(gEntries));

        // Trakt mapped rows in parallel (each call is resilient in data.ts)
        const traktRes = await Promise.allSettled([
          fetchTraktTrendingMapped(api, 'movies'),         // 0
          fetchTraktTrendingMapped(api, 'shows'),          // 1
          fetchTraktPopularShowsMapped(api),               // 2
          fetchTraktWatchlistMapped(api),                  // 3
          fetchTraktHistoryMapped(api),                    // 4
          fetchTraktRecommendationsMapped(api),            // 5
        ]);
        const tval = (i: number) => traktRes[i].status === 'fulfilled' ? (traktRes[i] as PromiseFulfilledResult<any>).value : [];
        setTraktTrendMovies(tval(0));
        setTraktTrendShows(tval(1));
        setTraktPopularShows(tval(2));
        setTraktMyWatchlist(tval(3));
        setTraktHistory(tval(4));
        setTraktRecommendations(tval(5));
      } catch {
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  // Fetch logo for hero once popularOnPlexTmdb is loaded
  useEffect(() => {
    console.log('[Home] Hero effect triggered, popularOnPlexTmdb length:', popularOnPlexTmdb.length);
    if (popularOnPlexTmdb.length === 0) {
      console.log('[Home] No popularOnPlexTmdb items yet, skipping hero');
      return;
    }
    
    console.log('[Home] Starting hero selection async...');
    (async () => {
      try {
        const hero = pickHero();
        console.log('[Home] Picked hero:', hero.title, 'tmdbId:', hero.tmdbId, 'has image:', !!hero.image);
        setHeroPick(hero);
        
        if (hero.tmdbId && hero.mediaType) {
          console.log('[Home] Fetching logo for:', hero.mediaType, hero.tmdbId);
          const imgs = await api.get(`/api/tmdb/${hero.mediaType}/${encodeURIComponent(hero.tmdbId)}/images?language=en,null`);
          const logos = (imgs?.logos || []) as any[];
          console.log('[Home] Logos found:', logos.length);
          const logo = logos.find((l:any)=> l.iso_639_1 === 'en') || logos[0];
          if (logo?.file_path) {
            console.log('[Home] Setting hero logo:', logo.file_path);
            setHeroLogo(`https://image.tmdb.org/t/p/w500${logo.file_path}`);
          } else {
            console.log('[Home] No logo found for hero');
          }
        } else {
          console.log('[Home] No TMDB ID for hero, logo unavailable');
        }
      } catch (e) {
        console.log('[Home] Error in hero selection:', e);
      }
    })();
  }, [popularOnPlexTmdb]);

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

  const plexContinueImage = (item: any) => {
    // For episodes, use the show's poster (grandparentThumb) instead of episode thumbnail
    const path = item?.type === 'episode' 
      ? (item?.grandparentThumb || item?.thumb || item?.art)
      : (item?.thumb || item?.art);
    if (!path) return undefined;
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

  type HeroPick = { title: string; image?: string; subtitle?: string; tmdbId?: string; mediaType?: 'movie'|'tv' };

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: '#1b0a10' }}>
      {/* Sticky Top Bar is global; update via store */}
      {/* Themed background layers inspired by web bg-home-gradient - full screen */}
      {/* Base vertical dark gradient */}
      <LinearGradient
        colors={[ '#0a0a0a', '#0f0f10', '#0b0c0d' ]}
        start={{ x: 0.5, y: 0 }}
        end={{ x: 0.5, y: 1 }}
        style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
      />
      {/* Diagonal warm tint from bottom-left akin to web's red radial */}
      <LinearGradient
        colors={[ 'rgba(122,22,18,0.28)', 'rgba(122,22,18,0.08)', 'rgba(122,22,18,0.0)' ]}
        start={{ x: 0.0, y: 1.0 }}
        end={{ x: 0.45, y: 0.35 }}
        style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
      />
      {/* Diagonal cool tint from top-right akin to web's teal radial */}
      <LinearGradient
        colors={[ 'rgba(20,76,84,0.26)', 'rgba(20,76,84,0.08)', 'rgba(20,76,84,0.0)' ]}
        start={{ x: 1.0, y: 0.0 }}
        end={{ x: 0.55, y: 0.45 }}
        style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
      />
      <Animated.ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingBottom: 24, paddingTop: barHeight }}
        scrollEventThrottle={16}
        onScroll={Animated.event([
          { nativeEvent: { contentOffset: { y } } }
        ], { 
          useNativeDriver: false,
          listener: (e: any) => {
            const currentY = e.nativeEvent.contentOffset.y;
            const delta = currentY - lastScrollY.current;
            
            // Determine scroll direction
            if (delta > 5) {
              // Scrolling down - hide pills with smooth spring
              if (scrollDirection.current !== 'down') {
                scrollDirection.current = 'down';
                Animated.spring(showPillsAnim, {
                  toValue: 0,
                  useNativeDriver: true,
                  tension: 60,
                  friction: 10,
                }).start();
              }
            } else if (delta < -5) {
              // Scrolling up - show pills with smooth spring
              if (scrollDirection.current !== 'up') {
                scrollDirection.current = 'up';
                Animated.spring(showPillsAnim, {
                  toValue: 1,
                  useNativeDriver: true,
                  tension: 60,
                  friction: 10,
                }).start();
              }
            }
            
            lastScrollY.current = currentY;
          }
        })}
      >
      {heroPick ? (
        <HeroCard hero={{ title: heroPick.title, subtitle: heroPick.subtitle, imageUri: heroPick.image, logoUri: heroLogo }} authHeaders={authHeaders} onPlay={()=>{}} onAdd={()=>{}} />
      ) : null}

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
          getImageUri={plexContinueImage}
          getTitle={(it) => it.type === 'episode' ? (it.grandparentTitle || it.title || it.name) : (it.title || it.name)}
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
