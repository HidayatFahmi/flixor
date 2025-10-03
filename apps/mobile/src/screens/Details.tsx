import React, { useEffect, useState, useRef } from 'react';
import { View, Text, ActivityIndicator, ScrollView, Pressable, Animated, PanResponder, Dimensions, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MobileApi } from '../api/client';
import { fetchPlexMetadata, fetchPlexEpisodes, fetchPlexSeasons, fetchPlexSeasonEpisodes, fetchTmdbRecommendations, fetchTmdbRecommendationsMapped, fetchTmdbSimilarMapped, fetchTmdbTvSeasonsList, fetchTmdbSeasonEpisodes, mapTmdbToPlex, mapTmdbToPlexDebug, RowItem } from '../api/data';
import Row from '../components/Row';
import { Ionicons } from '@expo/vector-icons';
import Feather from '@expo/vector-icons/Feather';
import { LinearGradient } from 'expo-linear-gradient';
import { BlurView } from 'expo-blur';
import BadgePill from '../components/BadgePill';
import { useNavigation } from '@react-navigation/native';

let ExpoImage: any = null;
try { ExpoImage = require('expo-image').Image; } catch {}

type RouteParams = {
  route?: { params?: { type: 'plex'|'tmdb'; ratingKey?: string; mediaType?: 'movie'|'tv'; id?: string } };
};

export default function Details({ route }: RouteParams) {
  const params = route?.params || {};
  const [api, setApi] = useState<MobileApi | null>(null);
  const [loading, setLoading] = useState(true);
  const [meta, setMeta] = useState<any>(null);
  const [episodes, setEpisodes] = useState<any[]>([]);
  const [seasons, setSeasons] = useState<any[]>([]);
  const [seasonKey, setSeasonKey] = useState<string | null>(null);
  const [seasonSource, setSeasonSource] = useState<'plex'|'tmdb'|null>(null);
  const [tab, setTab] = useState<'episodes'|'suggested'|'details'>('suggested');
  const [tmdbCast, setTmdbCast] = useState<Array<{ name: string; profile_path?: string }>>([]);
  const [tmdbCrew, setTmdbCrew] = useState<Array<{ name: string; job?: string }>>([]);
  const [matchedPlex, setMatchedPlex] = useState<boolean>(false);
  const [mappedRk, setMappedRk] = useState<string | null>(null);
  const [noLocalSource, setNoLocalSource] = useState<boolean>(false);
  const [tmdbVote, setTmdbVote] = useState<number | null>(null);
  const [plexImdb, setPlexImdb] = useState<number | null>(null);
  const [plexRtCritic, setPlexRtCritic] = useState<number | null>(null);
  const [plexRtAudience, setPlexRtAudience] = useState<number | null>(null);
  const [episodesLoading, setEpisodesLoading] = useState<boolean>(false);
  const [onDeck, setOnDeck] = useState<any | null>(null);
  const [closing, setClosing] = useState(false);
  const [dragging, setDragging] = useState(false);
  const y = useRef(new Animated.Value(0)).current;
  const panY = useRef(new Animated.Value(0)).current;
  const appear = useRef(new Animated.Value(0)).current;
  const overlayOpacity = useRef(new Animated.Value(1)).current;
  const scrollRef = useRef<ScrollView | null>(null);
  const nav: any = useNavigation();
  const screenH = Dimensions.get('window').height;
  const scrollYRef = useRef(0);
  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => false,
      onStartShouldSetPanResponderCapture: () => false,
      onMoveShouldSetPanResponder: (_, g) => (!closing && scrollYRef.current <= 0 && Math.abs(g.dy) > 6),
      onMoveShouldSetPanResponderCapture: () => false,
      onPanResponderGrant: () => {
        setDragging(true);
      },
      onPanResponderMove: (_, g) => {
        if (closing) return;
        if (g.dy > 0) panY.setValue(g.dy);
      },
      onPanResponderRelease: (_, g) => {
        if (closing) return;
        const shouldClose = g.dy > 120 || g.vy > 1.0;
        if (shouldClose) {
          setClosing(true);
          // Fade overlay while sliding down the sheet together
          Animated.parallel([
            Animated.timing(panY, { toValue: screenH, duration: 180, useNativeDriver: true }),
            Animated.timing(overlayOpacity, { toValue: 0, duration: 180, useNativeDriver: true })
          ]).start(() => nav.goBack());
        } else {
          Animated.parallel([
            Animated.spring(panY, { toValue: 0, useNativeDriver: true, stiffness: 220, damping: 24, mass: 1 }),
            Animated.timing(overlayOpacity, { toValue: 1, duration: 120, useNativeDriver: true })
          ]).start(() => { setDragging(false); });
        }
      },
      onPanResponderTerminationRequest: () => false,
      onPanResponderTerminate: () => {
        setDragging(false);
        Animated.parallel([
          Animated.spring(panY, { toValue: 0, useNativeDriver: true, stiffness: 220, damping: 24, mass: 1 }),
          Animated.timing(overlayOpacity, { toValue: 1, duration: 120, useNativeDriver: true })
        ]).start();
      },
    })
  ).current;

  useEffect(() => {
    Animated.timing(appear, { toValue: 1, duration: 200, useNativeDriver: true }).start();
  }, []);

  // Lazy load episodes when Episodes tab is selected
  useEffect(() => {
    if (tab === 'episodes' && seasonKey && !episodes.length && !episodesLoading && api) {
      (async () => {
        setEpisodesLoading(true);
        console.log('[Details] Lazy loading episodes for season:', seasonKey);
        try {
          const eps = await fetchPlexSeasonEpisodes(api, seasonKey);
          console.log('[Details] Episodes loaded:', { count: eps.length, first: eps[0] });
          setEpisodes(eps);
        } catch (e) {
          console.error('[Details] Failed to load episodes:', e);
        } finally {
          setEpisodesLoading(false);
        }
      })();
    }
  }, [tab, seasonKey, episodes.length, episodesLoading, api]);

  useEffect(() => {
    (async () => {
      const a = await MobileApi.load();
      setApi(a);
      if (a && params.type === 'plex' && params.ratingKey) {
        try {
          // STEP 1: Load basic metadata and unblock UI immediately
          const m = await fetchPlexMetadata(a, params.ratingKey);
          const next: any = { ...m };
          setMeta(next);
          setMatchedPlex(true);
          setMappedRk(String(params.ratingKey));
          setTab(next?.type === 'show' ? 'episodes' : 'suggested');
          setLoading(false); // ✅ Unblock UI immediately with basic data

          // STEP 2: Load non-critical data in parallel (background)
          const promises = [];

          // TMDB logo (non-blocking)
          promises.push((async () => {
            try {
              const guids: string[] = Array.isArray(m?.Guid) ? m.Guid.map((g:any)=> String(g.id||'')) : [];
              const tmdbGuid = guids.find(g=> g.includes('tmdb://') || g.includes('themoviedb://'));
              if (tmdbGuid && a) {
                const tid = tmdbGuid.split('://')[1];
                const mediaType = (m?.type === 'movie') ? 'movie' : 'tv';
                const imgs = await a.get(`/api/tmdb/${mediaType}/${encodeURIComponent(tid)}/images?language=en,null`);
                const logos = (imgs?.logos || []) as any[];
                const logo = logos.find(l=> l.iso_639_1 === 'en') || logos[0];
                if (logo?.file_path) {
                  setMeta(prev => ({ ...prev, logoUrl: `https://image.tmdb.org/t/p/w500${logo.file_path}` }));
                }
              }
            } catch {}
          })());

          // Ratings (non-blocking)
          promises.push((async () => {
            try {
              const rr = await a.get(`/api/plex/ratings/${encodeURIComponent(String(params.ratingKey))}`);
              if (rr?.imdb?.rating != null) setPlexImdb(Number(rr.imdb.rating));
              if (rr?.rottenTomatoes?.critic != null) setPlexRtCritic(Number(rr.rottenTomatoes.critic));
              if (rr?.rottenTomatoes?.audience != null) setPlexRtAudience(Number(rr.rottenTomatoes.audience));
            } catch {}
          })());

          // For TV shows: Load seasons list + onDeck in parallel
          if (next?.type === 'show') {
            // Load seasons list (non-blocking)
            promises.push((async () => {
              try {
                const seas = await fetchPlexSeasons(a, params.ratingKey);
                console.log('[Details] Plex show seasons:', { showRK: params.ratingKey, count: seas.length, firstSeason: seas[0] });
                setSeasons(seas);
                setSeasonSource('plex');
                if (seas[0]?.ratingKey) {
                  setSeasonKey(String(seas[0].ratingKey));
                  // Don't load episodes here - wait for user to view Episodes tab
                }
              } catch (e) {
                console.error('[Details] Failed to load seasons:', e);
              }
            })());

            // Load onDeck (non-blocking)
            promises.push((async () => {
              try {
                const od: any = await a.get(`/api/plex/dir/library/metadata/${encodeURIComponent(String(params.ratingKey))}/onDeck?nocache=${Date.now()}`);
                const ep = od?.MediaContainer?.Metadata?.[0];
                if (ep) {
                  const durMin = Math.round((ep.duration||0)/60000);
                  const progress = (() => {
                    const dur = (ep.duration||0)/1000; const vo = (ep.viewOffset||0)/1000; const vc = ep.viewCount||0;
                    if (vc > 0) return 100;
                    if (dur > 0 && vo/dur >= 0.95) return 100;
                    if (dur > 0) return Math.round((vo/dur)*100);
                    return 0;
                  })();
                  setOnDeck({
                    id: `plex:${ep.ratingKey}`,
                    title: ep.title,
                    overview: ep.summary,
                    image: `${a.baseUrl}/api/image/plex?path=${encodeURIComponent(String(ep.thumb || ep.parentThumb || ''))}&w=640&f=webp`,
                    duration: durMin,
                    progress,
                  });
                } else setOnDeck(null);
              } catch { setOnDeck(null); }
            })());
          }

          // Wait for all background tasks
          await Promise.allSettled(promises);
        } catch (e) {
          console.error('[Details] Failed to load metadata:', e);
          setLoading(false);
        }
      }
      // TMDB path with Plex mapping fallback
      if (a && params.type === 'tmdb' && params.id && params.mediaType) {
        try {
          // Try robust TMDB → Plex mapping (guid + title/year fallback)
          let detForMap: any = null;
          try { detForMap = await a.get(`/api/tmdb/${params.mediaType}/${encodeURIComponent(params.id)}?append_to_response=external_ids`); } catch {}
          const mapped = await mapTmdbToPlex(a, params.mediaType, String(params.id), detForMap?.title || detForMap?.name, (detForMap?.release_date || detForMap?.first_air_date || '').slice(0,4));
          if (mapped?.ratingKey) {
            // Use full Plex metadata so UI/features work (play, badges)
            const m = await fetchPlexMetadata(a, String(mapped.ratingKey));
            const next: any = { ...m };
            // Optional TMDB logo
            try {
              const guids: string[] = Array.isArray(m?.Guid) ? m.Guid.map((g:any)=> String(g.id||'')) : [];
              const tmdbGuid = guids.find(g=> g.includes('tmdb://') || g.includes('themoviedb://'));
              if (tmdbGuid && a) {
                const tid = tmdbGuid.split('://')[1];
                const mediaType = (m?.type === 'movie') ? 'movie' : 'tv';
                const imgs = await a.get(`/api/tmdb/${mediaType}/${encodeURIComponent(tid)}/images?language=en,null`);
                const logos = (imgs?.logos || []) as any[];
                const logo = logos.find(l=> l.iso_639_1 === 'en') || logos[0];
                if (logo?.file_path) next.logoUrl = `https://image.tmdb.org/t/p/w500${logo.file_path}`;
              }
            } catch {}
            setMeta(next);
            setMatchedPlex(true);
            setMappedRk(String(mapped.ratingKey));
            setTab(next?.type === 'show' ? 'episodes' : 'suggested');
            if (next?.type === 'show') {
              const seas = await fetchPlexSeasons(a, String(mapped.ratingKey));
              console.log('[Details] TMDB→Plex mapped show seasons:', { showRK: mapped.ratingKey, count: seas.length, firstSeason: seas[0] });
              setSeasons(seas);
              setSeasonSource('plex');
              if (seas[0]?.ratingKey) {
                const firstSeasonKey = String(seas[0].ratingKey);
                setSeasonKey(firstSeasonKey);
                setEpisodesLoading(true);
                console.log('[Details] Fetching episodes for mapped season:', firstSeasonKey);
                try {
                  const eps = await fetchPlexSeasonEpisodes(a, firstSeasonKey);
                  console.log('[Details] Episodes loaded for mapped show:', { count: eps.length, first: eps[0] });
                  setEpisodes(eps);
                } finally { setEpisodesLoading(false); }
              } else {
                console.warn('[Details] No valid season ratingKey found in mapped show:', seas[0]);
              }
              try {
                const od: any = await a.get(`/api/plex/dir/library/metadata/${encodeURIComponent(String(mapped.ratingKey))}/onDeck?nocache=${Date.now()}`);
                const ep = od?.MediaContainer?.Metadata?.[0];
                if (ep) {
                  const durMin = Math.round((ep.duration||0)/60000);
                  const progress = (() => {
                    const dur = (ep.duration||0)/1000; const vo = (ep.viewOffset||0)/1000; const vc = ep.viewCount||0;
                    if (vc > 0) return 100;
                    if (dur > 0 && vo/dur >= 0.95) return 100;
                    if (dur > 0) return Math.round((vo/dur)*100);
                    return 0;
                  })();
                  setOnDeck({
                    id: `plex:${ep.ratingKey}`,
                    title: ep.title,
                    overview: ep.summary,
                    image: `${a.baseUrl}/api/image/plex?path=${encodeURIComponent(String(ep.thumb || ep.parentThumb || ''))}&w=640&f=webp`,
                    duration: durMin,
                    progress,
                  });
                } else setOnDeck(null);
              } catch { setOnDeck(null); }
            }
            // Fetch normalized ratings from backend
            try {
              const rr = await a.get(`/api/plex/ratings/${encodeURIComponent(String(mapped.ratingKey))}`);
              if (rr?.imdb?.rating != null) setPlexImdb(Number(rr.imdb.rating));
              if (rr?.rottenTomatoes?.critic != null) setPlexRtCritic(Number(rr.rottenTomatoes.critic));
              if (rr?.rottenTomatoes?.audience != null) setPlexRtAudience(Number(rr.rottenTomatoes.audience));
            } catch {}
          } else {
            // Fallback: show TMDB details minimal UI
            const det = detForMap || await a.get(`/api/tmdb/${params.mediaType}/${encodeURIComponent(params.id)}?append_to_response=external_ids`);
            const back = det?.backdrop_path ? `https://image.tmdb.org/t/p/w1280${det.backdrop_path}` : (det?.poster_path ? `https://image.tmdb.org/t/p/w780${det.poster_path}` : undefined);
            const genres = Array.isArray(det?.genres) ? det.genres.map((g:any)=> ({ tag: g.name })) : [];
            setMeta({
              title: det?.title || det?.name || 'Title',
              summary: det?.overview,
              year: (det?.release_date || det?.first_air_date || '').slice(0,4),
              type: params.mediaType === 'movie' ? 'movie' : 'show',
              backdropUrl: back,
              Genre: genres,
              tmdbCollectionName: det?.belongs_to_collection?.name,
            });
            setTmdbVote(typeof det?.vote_average === 'number' ? det.vote_average : null);
            setNoLocalSource(true);
            // For TV, we’ll show TMDB seasons/episodes below if unmatched
            // Fetch TMDB credits for cast/crew
            try {
              const cr = await a.get(`/api/tmdb/${params.mediaType}/${encodeURIComponent(params.id)}/credits`);
              setTmdbCast((cr?.cast||[]).slice(0,16).map((c:any)=> ({ name: c.name, profile_path: c.profile_path })));
              setTmdbCrew((cr?.crew||[]).slice(0,16).map((c:any)=> ({ name: c.name, job: c.job })));
            } catch {}
            // For TV shows, populate seasons + episodes (best effort)
            if (params.mediaType === 'tv') {
              try {
                const ss = await fetchTmdbTvSeasonsList(a, String(params.id));
                if (ss.length) {
                  setSeasons(ss.map(s=> ({ key: s.key, title: s.title })) as any);
                  setSeasonKey(ss[0].key);
                  setEpisodesLoading(true);
                  try { const eps = await fetchTmdbSeasonEpisodes(a, String(params.id), Number(ss[0].key)); setEpisodes(eps); } finally { setEpisodesLoading(false); }
                  setSeasonSource('tmdb');
                }
              } catch {}
            }
            setTab('suggested');
          }
        } catch {}
      }
      setLoading(false);
    })();
  }, []);

  if (loading || !api) {
    return (
      <View style={{ flex:1, backgroundColor:'#0b0b0b', alignItems:'center', justifyContent:'center' }}>
        <ActivityIndicator color="#fff" />
      </View>
    );
  }

  const authHeaders = api.token ? { Authorization: `Bearer ${api.token}` } : undefined;
  const backdrop = () => {
    if (meta?.backdropUrl) return String(meta.backdropUrl);
    const path = meta?.art || meta?.thumb;
    return path ? `${api.baseUrl}/api/image/plex?path=${encodeURIComponent(String(path))}&w=1080&f=webp` : undefined;
  };
  const title = meta?.title || meta?.grandparentTitle || 'Title';
  const contentRating = meta?.contentRating || 'PG';
  // Badges parsing from Plex streams
  const media = (meta?.Media || [])[0] || {};
  const videoRes = media?.videoResolution;
  const isHD = videoRes && Number(videoRes) >= 720;
  const audioChannels = media?.audioChannels || 2;
  const streams = ((media?.Part || [])[0]?.Stream || []) as any[];
  const subtitleStreams = streams.filter(s => s.streamType === 3);
  const audioStreams = streams.filter(s => s.streamType === 2);
  const hasCC = subtitleStreams.some(s => String(s?.displayTitle || '').toLowerCase().includes('cc'));
  const hasAD = audioStreams.some(s => String(s?.displayTitle || '').toLowerCase().includes('description'));
  const hasDV = streams.some(s =>
    /dolby.?vision|dovi/i.test(String(s?.displayTitle || '')) ||
    /smpte2084|pq|hdr10/i.test(String(s?.colorTrc || ''))
  );

  // Keep overlay fully visible until the sheet is mostly offscreen, then fade.
  const backdropOpacity = panY.interpolate({ inputRange: [0, screenH * 0.8, screenH], outputRange: [1, 1, 0], extrapolate: 'clamp' });

  return (
    <SafeAreaView style={{ flex:1, backgroundColor:'transparent' }}>
      <Animated.View style={{ flex:1, transform:[{ translateY: panY }] }} {...panResponder.panHandlers}>
        {/* Dim + blur backdrop under the modal so swiping reveals content behind, not black */}
        <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFillObject, { opacity: backdropOpacity }]}>
          <BlurOverlay />
        </Animated.View>

        {/* Shadow under the sheet so any reveal looks natural, not a black jump */}
        <View style={{ position:'absolute', top:0, left:0, right:0, height:16, backgroundColor:'transparent', shadowColor:'#000', shadowOpacity:0.35, shadowRadius:14, shadowOffset:{ width:0, height:6 }, zIndex:1 }} />
        <View style={{ flex:1, backgroundColor:'#0d0d0f', borderTopLeftRadius: 20, borderTopRightRadius: 20, overflow: 'hidden' }}>
      <ScrollView ref={ref => (scrollRef.current = ref)}
        scrollEventThrottle={16}
        onScroll={(e:any) => { scrollYRef.current = e.nativeEvent.contentOffset.y; }}
        scrollEnabled={!closing}
        bounces={false}
        contentContainerStyle={{ paddingBottom: 32 }}
      >
        {/* Hero backdrop with rounded bottom corners */}
        <View style={{
          marginBottom: 12,
          borderBottomLeftRadius: 28,
          borderBottomRightRadius: 28,
          overflow: 'hidden',
        }}>
          <View style={{ width:'100%', aspectRatio: 16/9, backgroundColor:'#111' }}>
            {backdrop() && ExpoImage ? (
              <ExpoImage source={{ uri: backdrop(), headers: authHeaders }} style={{ width:'100%', height:'100%' }} contentFit="cover" />
            ) : null}
            {/* Top-right actions over image */}
            <View style={{ position:'absolute', right: 12, top: 12, flexDirection:'row' }}>
              <Feather name="cast" size={20} color="#fff" style={{ marginHorizontal: 8 }} />
              <Ionicons name="share-outline" size={20} color="#fff" style={{ marginHorizontal: 8 }} />
              <Pressable onPress={()=> nav.goBack()}>
                <Ionicons name="close" size={22} color="#fff" style={{ marginHorizontal: 8 }} />
              </Pressable>
            </View>
            {/* Gradient from image into content */}
            <LinearGradient
              colors={[ 'rgba(0,0,0,0.0)', 'rgba(13,13,15,0.85)', '#0d0d0f' ]}
              start={{ x: 0.5, y: 0.4 }} end={{ x: 0.5, y: 1.0 }}
              style={{ position:'absolute', left:0, right:0, bottom:0, height:'55%' }}
            />
            {/* TMDB logo overlay (center) if available */}
            {meta?.logoUrl && ExpoImage ? (
              <ExpoImage source={{ uri: meta.logoUrl }} style={{ position:'absolute', bottom: 24, left:'10%', right:'10%', height: 48 }} contentFit="contain" />
            ) : null}
            {/* No diagnostics UI in production */}
          </View>
        </View>

        {/* Title */}
        <Text style={{ color:'#fff', fontSize:28, fontWeight:'800', marginHorizontal:16 }}>{title}</Text>

        {/* Badges */}
        <View style={{ flexDirection:'row', flexWrap:'wrap', gap:8, marginTop:12, marginHorizontal:16 }}>
          <BadgePill label={contentRating} />
          {isHD ? <BadgePill icon="hd" /> : null}
          <BadgePill icon="5.1" />
          {hasDV ? <BadgePill icon="dolby" /> : null}
          {hasCC ? <BadgePill icon="cc" /> : null}
          {hasAD ? <BadgePill icon="ad" /> : null}
          {matchedPlex ? <BadgePill label="Plex" /> : null}
          {!matchedPlex && params.type === 'tmdb' ? <BadgePill label="No local source" /> : null}
        </View>

        {/* Meta line */}
        <Text style={{ color:'#bbb', marginHorizontal:16, marginTop:8 }}>
          {meta?.year ? `${meta.year} • ` : ''}
          {meta?.type === 'show' ? `${meta?.leafCount || 0} Episodes` : (meta?.duration ? `${Math.round(meta.duration/60000)}m` : '')}
          {meta?.Genre?.length ? ` • ${meta.Genre.map((g:any)=>g.tag).slice(0,3).join(', ')}` : ''}
        </Text>

        {/* Play */}
        <Pressable
          onPress={() => {
            if (matchedPlex || params.type === 'plex') {
              const rk = mappedRk || params.ratingKey;
              if (rk) nav.navigate('Player', { type: 'plex', ratingKey: rk });
            }
          }}
          style={{ marginHorizontal:16, marginTop:12, backgroundColor:'#fff', paddingVertical:12, borderRadius:12, alignItems:'center' }}
        >
          <Text style={{ color:'#000', fontWeight:'900', letterSpacing:2 }}>▶  PLAY</Text>
        </Pressable>

        {/* Actions */}
        <View style={{ flexDirection:'row', justifyContent:'space-around', marginTop:14 }}>
          <ActionIcon icon="play-circle-outline" label="TRAILER" />
          <ActionIcon icon="add" label="WATCHLIST" />
          <ActionIcon icon="download-outline" label="DOWNLOAD" />
        </View>

        {/* Synopsis */}
        {meta?.summary ? (
          <Text style={{ color:'#ddd', marginHorizontal:16, marginTop:16, lineHeight:20 }}>{meta.summary}</Text>
        ) : null}

        {/* Tabs (TV shows include Episodes; Movies omit Episodes) */}
        <Tabs tab={tab} setTab={setTab} showEpisodes={meta?.type === 'show'} />

        {/* Content area */}
        <View style={{ marginTop:8 }}>
          {meta?.type === 'show' && tab === 'episodes' ? (
            <>
              {onDeck ? (
                <View style={{ marginHorizontal:16, marginTop:8, marginBottom:8, backgroundColor:'#1a1a1a', borderRadius:12, borderWidth:1, borderColor:'#2a2b30' }}>
                  <Text style={{ color:'#fff', fontWeight:'700', paddingHorizontal:12, paddingTop:10, paddingBottom:6 }}>Continue watching</Text>
                  <View style={{ paddingHorizontal:12, paddingBottom:12 }}>
                    <EpisodeCard ep={onDeck} />
                  </View>
                </View>
              ) : null}
              <SeasonSelector seasons={seasons} seasonKey={seasonKey} onChange={async (key)=> {
                // Clear episodes and set new season - lazy loading effect will fetch
                setEpisodes([]);
                setSeasonKey(key);
                setEpisodesLoading(true);
                try {
                  if (seasonSource === 'plex') {
                    setEpisodes(await fetchPlexSeasonEpisodes(api, key));
                  } else if (seasonSource === 'tmdb') {
                    const tvId = route?.params?.id ? String(route?.params?.id) : undefined;
                    if (tvId) setEpisodes(await fetchTmdbSeasonEpisodes(api, tvId, Number(key)));
                  }
                } finally { setEpisodesLoading(false); }
              }} />
              {episodesLoading ? (
                <View style={{ alignItems:'center', justifyContent:'center', paddingVertical:16 }}>
                  <ActivityIndicator color="#fff" />
                </View>
              ) : (
                episodes && episodes.length > 0 ? (
                  <EpisodeList
                    seasonTitle={seasons.find(s => String(s.ratingKey || s.key) === seasonKey)?.title || `Season ${seasonKey}`}
                    episodes={episodes}
                    api={api}
                    tmdbMode={seasonSource==='tmdb'}
                    tmdbId={route?.params?.id ? String(route?.params?.id) : undefined}
                  />
                ) : (
                  <Text style={{ color:'#888', textAlign:'center', paddingVertical:24 }}>{noLocalSource ? 'No source found' : 'No episodes found'}</Text>
                )
              )}
            </>
          ) : null}
          {tab === 'suggested' ? (
            <SuggestedRows api={api} meta={meta} routeParams={route?.params} />
          ) : null}
          {tab === 'details' ? (
            <DetailsTab meta={meta} api={api} tmdbCast={tmdbCast} tmdbCrew={tmdbCrew} tmdbVote={tmdbVote} plexRatings={{ imdb: plexImdb, rtCritic: plexRtCritic, rtAudience: plexRtAudience }} />
          ) : null}
        </View>
      </ScrollView>
        </View>
      </Animated.View>
    </SafeAreaView>
  );
}

function BlurOverlay() {
  return (
    <View style={StyleSheet.absoluteFillObject}>
      <BlurView intensity={60} tint="dark" style={StyleSheet.absoluteFillObject} />
      <LinearGradient
        colors={[ 'rgba(10,10,10,0.22)', 'rgba(10,10,10,0.10)' ]}
        start={{ x: 0.5, y: 0 }} end={{ x: 0.5, y: 1 }}
        style={StyleSheet.absoluteFillObject}
      />
    </View>
  );
}

function Badge({ label }: { label: string }) {
  return (
    <View style={{ backgroundColor:'#262626', paddingHorizontal:10, paddingVertical:6, borderRadius:8 }}>
      <Text style={{ color:'#fff', fontWeight:'700' }}>{label}</Text>
    </View>
  );
}

function ActionIcon({ icon, label }: { icon: any; label: string }) {
  return (
    <View style={{ alignItems:'center' }}>
      <Ionicons name={icon} size={22} color="#fff" />
      <Text style={{ color:'#fff', marginTop:4, fontWeight:'600' }}>{label}</Text>
    </View>
  );
}

function EpisodeList({ seasonTitle, episodes, api, tmdbMode, tmdbId }: { seasonTitle: string; episodes: any[]; api: MobileApi; tmdbMode?: boolean; tmdbId?: string }) {
  const authHeaders = api.token ? { Authorization: `Bearer ${api.token}` } : undefined;
  const nav: any = useNavigation();

  return (
    <View style={{ marginTop: 12 }}>
      <Text style={{ color:'#fff', fontSize:18, fontWeight:'800', marginHorizontal:16, marginBottom:8 }}>{seasonTitle}</Text>
      {episodes.map((ep:any, idx:number) => {
        const path = tmdbMode ? undefined : (ep.thumb || ep.art);
        const img = tmdbMode
          ? (ep.still_path ? `https://image.tmdb.org/t/p/w780${ep.still_path}` : undefined)
          : (path ? `${api.baseUrl}/api/image/plex?path=${encodeURIComponent(String(path))}&w=640&f=webp` : undefined);
        // Compute progress (Plex episodes only)
        let progress: number | undefined = undefined;
        if (!tmdbMode) {
          try {
            const dur = (ep.duration||0)/1000; const vo = (ep.viewOffset||0)/1000; const vc = ep.viewCount||0;
            if (vc > 0) progress = 100;
            else if (dur > 0 && vo/dur >= 0.95) progress = 100;
            else if (dur > 0) progress = Math.round((vo/dur)*100);
          } catch {}
        }
        return (
          <Pressable
            key={idx}
            onPress={() => {
              // Only play Plex episodes (not TMDB-only)
              if (!tmdbMode && ep.ratingKey) {
                nav.navigate('Player', { type: 'plex', ratingKey: String(ep.ratingKey) });
              }
            }}
            style={{ flexDirection:'row', marginHorizontal:16, marginBottom:12 }}
          >
            <View style={{ width:140, height:78, borderRadius:10, overflow:'hidden', backgroundColor:'#222' }}>
              {img && ExpoImage ? (
                <ExpoImage source={{ uri: img, headers: authHeaders }} style={{ width:'100%', height:'100%' }} contentFit="cover" />
              ) : null}
              {typeof progress === 'number' && progress > 0 ? (
                <View style={{ position:'absolute', left:0, right:0, bottom:0, height:4, backgroundColor:'#ffffff33' }}>
                  <View style={{ width: `${Math.min(100, Math.max(0, progress))}%`, height:'100%', backgroundColor:'#fff' }} />
                </View>
              ) : null}
            </View>
            <View style={{ flex:1, marginLeft:12, justifyContent:'center' }}>
              <Text style={{ color:'#fff', fontWeight:'800' }}>{idx+1}. {ep.title || ep.name || 'Episode'}</Text>
              <Text style={{ color:'#bbb', marginTop:2 }}>
                {tmdbMode ? (ep.runtime ? `${ep.runtime}m` : '') : (ep.duration ? `${Math.round(ep.duration/60000)}m` : '')}
              </Text>
            </View>
            <Ionicons name="download-outline" size={18} color="#fff" style={{ alignSelf:'center' }} />
          </Pressable>
        );
      })}
    </View>
  );
}

function EpisodeCard({ ep }: { ep: { id: string; title: string; overview?: string; image?: string; duration?: number; progress?: number } }) {
  const nav: any = useNavigation();

  return (
    <Pressable
      onPress={() => {
        // Extract ratingKey from id (format: plex:12345)
        const rk = ep.id.replace(/^plex:/, '');
        if (rk) nav.navigate('Player', { type: 'plex', ratingKey: rk });
      }}
      style={{ flexDirection:'row', alignItems:'center' }}
    >
      <View style={{ width:160, height:90, borderRadius:10, overflow:'hidden', backgroundColor:'#222', marginRight:12 }}>
        {ep.image && ExpoImage ? (
          <ExpoImage source={{ uri: ep.image }} style={{ width:'100%', height:'100%' }} contentFit="cover" />
        ) : null}
        {typeof ep.progress === 'number' && ep.progress > 0 ? (
          <View style={{ position:'absolute', left:0, right:0, bottom:0, height:4, backgroundColor:'#ffffff33' }}>
            <View style={{ width: `${Math.min(100, Math.max(0, ep.progress))}%`, height:'100%', backgroundColor:'#fff' }} />
          </View>
        ) : null}
      </View>
      <View style={{ flex:1 }}>
        <Text style={{ color:'#fff', fontWeight:'800' }}>{ep.title}</Text>
        {ep.duration ? <Text style={{ color:'#bbb', marginTop:2 }}>{ep.duration}m</Text> : null}
        {ep.overview ? <Text style={{ color:'#888', marginTop:4 }} numberOfLines={2}>{ep.overview}</Text> : null}
      </View>
    </Pressable>
  );
}

function Tabs({ tab, setTab, showEpisodes }: { tab: 'episodes'|'suggested'|'details'; setTab: (t:any)=>void; showEpisodes: boolean }) {
  const tabs: Array<{ key: any; label: string }> = showEpisodes
    ? [ { key:'episodes', label:'EPISODES' }, { key:'suggested', label:'SUGGESTED' }, { key:'details', label:'DETAILS' } ]
    : [ { key:'suggested', label:'SUGGESTED' }, { key:'details', label:'DETAILS' } ];
  return (
    <View style={{ marginTop:18 }}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal:16 }}>
        {tabs.map(t => (
          <Pressable key={t.key} onPress={()=> setTab(t.key)} style={{ marginRight:28 }}>
            <Text style={{ color:'#fff', fontWeight:'900', letterSpacing:1.2, fontSize:14 }}>{t.label}</Text>
            {tab===t.key ? <View style={{ height:4, backgroundColor:'#fff', marginTop:6, borderRadius:2 }} /> : <View style={{ height:4, backgroundColor:'transparent', marginTop:6 }} />}
          </Pressable>
        ))}
      </ScrollView>
    </View>
  );
}

function SuggestedRows({ api, meta, routeParams }: { api: MobileApi; meta: any; routeParams?: any }) {
  const [recs, setRecs] = React.useState<RowItem[]>([]);
  const [similar, setSimilar] = React.useState<RowItem[]>([]);
  const [loading, setLoading] = React.useState(true);
  const tmdbId = React.useMemo(() => {
    try {
      // Prefer Plex GUID (meta) if available
      const guids: string[] = Array.isArray(meta?.Guid) ? meta.Guid.map((g:any)=> String(g.id||'')) : [];
      const tmdbGuid = guids.find(g=> g.includes('tmdb://') || g.includes('themoviedb://'));
      if (tmdbGuid) return tmdbGuid.split('://')[1];
      // Fallback to route param for TMDB-only details
      const pid = routeParams?.id; return pid ? String(pid) : null;
    } catch { return null; }
  }, [meta, routeParams]);
  const mediaType: 'movie'|'tv' = React.useMemo(() => {
    if (meta?.type === 'movie' || meta?.type === 'show') return (meta.type === 'movie') ? 'movie' : 'tv';
    const rt = routeParams?.mediaType; return rt === 'movie' ? 'movie' : 'tv';
  }, [meta, routeParams]);

  React.useEffect(() => {
    (async () => {
      try {
        if (!tmdbId) return setLoading(false);
        const [r, s] = await Promise.all([
          fetchTmdbRecommendationsMapped(api, mediaType, tmdbId),
          fetchTmdbSimilarMapped(api, mediaType, tmdbId)
        ]);
        setRecs(r);
        setSimilar(s);
      } finally {
        setLoading(false);
      }
    })();
  }, [tmdbId, mediaType]);

  const authHeaders = api.token ? { Authorization: `Bearer ${api.token}` } : undefined;
  const getUri = (it: RowItem) => it.image;
  const getTitle = (it: RowItem) => it.title;
  const nav: any = useNavigation();
  const onPress = (it: RowItem) => {
    if (!it?.id) return;
    if (it.id.startsWith('plex:')) {
      const rk = it.id.split(':')[1];
      nav.navigate('Details', { type:'plex', ratingKey: rk });
    } else if (it.id.startsWith('tmdb:')) {
      const [, media, id] = it.id.split(':');
      nav.navigate('Details', { type:'tmdb', mediaType: media === 'movie' ? 'movie' : 'tv', id });
    }
  };

  if (loading) return <Text style={{ color:'#888', marginHorizontal:16 }}>Loading…</Text>;
  if (!recs.length && !similar.length) return <Text style={{ color:'#888', marginHorizontal:16 }}>No suggestions</Text>;
  return (
    <View style={{ marginLeft: 12 }}>
      {recs.length > 0 && (
        <Row title="Recommended" items={recs}
          getImageUri={getUri} getTitle={getTitle} authHeaders={authHeaders} onItemPress={onPress}
        />
      )}
      {similar.length > 0 && (
        <Row title="More Like This" items={similar}
          getImageUri={getUri} getTitle={getTitle} authHeaders={authHeaders} onItemPress={onPress}
        />
      )}
    </View>
  );
}

function SectionHeader({ title }: { title: string }) {
  return (
    <Text style={{ color:'#fff', fontSize:18, fontWeight:'800', marginHorizontal:16, marginTop:18 }}>{title}</Text>
  );
}

function KeyValue({ k, v }: { k: string; v?: string }) {
  if (!v) return null;
  return (
    <View style={{ flexDirection:'row', justifyContent:'space-between', paddingHorizontal:16, paddingVertical:8 }}>
      <Text style={{ color:'#aaa' }}>{k}</Text>
      <Text style={{ color:'#eee', marginLeft:12, flexShrink:1, textAlign:'right' }}>{v}</Text>
    </View>
  );
}

function RatingsRow({ meta, tmdbVote, plex }: { meta: any; tmdbVote?: number | null; plex?: { imdb?: number|null; rtCritic?: number|null; rtAudience?: number|null } }) {
  // Parse ratings from Plex metadata if available (or override from backend)
  const ratings: any[] = Array.isArray(meta?.Rating) ? meta.Rating : [];
  let imdb: number | undefined;
  let rtCritic: number | undefined;
  let rtAudience: number | undefined;
  if (plex) {
    if (plex.imdb != null) imdb = Number(plex.imdb);
    if (plex.rtCritic != null) rtCritic = Number(plex.rtCritic);
    if (plex.rtAudience != null) rtAudience = Number(plex.rtAudience);
  }
  try {
    ratings.forEach((r:any) => {
      const img = String(r?.image || '').toLowerCase();
      const val = typeof r?.value === 'number' ? r.value : Number(r?.value);
      if (img.includes('imdb://image.rating')) imdb = val;
      if (img.includes('rottentomatoes://image.rating.ripe') || img.includes('rottentomatoes://image.rating.rotten')) rtCritic = val ? Math.round(val * 10) : undefined;
      if (img.includes('rottentomatoes://image.rating.upright')) rtAudience = val ? Math.round(val * 10) : undefined;
    });
  } catch {}

  // Fallbacks from top-level fields if present
  if (!imdb && typeof meta?.rating === 'number') imdb = meta.rating;
  if (!rtAudience && typeof meta?.audienceRating === 'number') rtAudience = Math.round(meta.audienceRating * 10);

  if (!imdb && !rtCritic && !rtAudience && (tmdbVote == null)) return null;
  return (
    <View style={{ flexDirection:'row', alignItems:'center', marginTop:8, marginHorizontal:16 }}>
      {typeof imdb === 'number' ? (
        <View style={{ flexDirection:'row', alignItems:'center', marginRight:16 }}>
          <Ionicons name="star" size={16} color="#f5c518" />
          <Text style={{ color:'#fff', fontWeight:'700', marginLeft:6 }}>IMDb {imdb.toFixed(1)}</Text>
        </View>
      ) : null}
      {typeof rtCritic === 'number' ? (
        <View style={{ flexDirection:'row', alignItems:'center', marginRight:16 }}>
          <Ionicons name="leaf-outline" size={16} color="#66bb6a" />
          <Text style={{ color:'#fff', fontWeight:'700', marginLeft:6 }}>Tomatometer {rtCritic}%</Text>
        </View>
      ) : null}
      {typeof rtAudience === 'number' ? (
        <View style={{ flexDirection:'row', alignItems:'center' }}>
          <Ionicons name="people-outline" size={16} color="#90caf9" />
          <Text style={{ color:'#fff', fontWeight:'700', marginLeft:6 }}>Audience {rtAudience}%</Text>
        </View>
      ) : null}
      {!imdb && !rtCritic && !rtAudience && (tmdbVote != null) ? (
        <View style={{ flexDirection:'row', alignItems:'center', marginRight:16 }}>
          <Ionicons name="film-outline" size={16} color="#9aa6b2" />
          <Text style={{ color:'#fff', fontWeight:'700', marginLeft:6 }}>TMDB {tmdbVote.toFixed(1)}</Text>
        </View>
      ) : null}
    </View>
  );
}

function CastScroller({ meta, api, tmdbCast }: { meta:any; api: MobileApi; tmdbCast?: Array<{ name: string; profile_path?: string }> }) {
  const roles: any[] = Array.isArray(meta?.Role) ? meta.Role.slice(0, 16) : [];
  const useTmdb = !roles.length && Array.isArray(tmdbCast) && tmdbCast.length > 0;
  if (!roles.length && !useTmdb) return null;
  const headers = api.token ? { Authorization: `Bearer ${api.token}` } : undefined;
  return (
    <View style={{ marginTop:8 }}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal:12 }}>
        {(useTmdb ? tmdbCast! : roles).map((r:any, idx:number) => {
          const src = useTmdb
            ? (r.profile_path ? `https://image.tmdb.org/t/p/w185${r.profile_path}` : undefined)
            : (r.thumb ? `${api.baseUrl}/api/image/plex?path=${encodeURIComponent(String(r.thumb))}&w=200&h=200&f=webp` : undefined);
          const name = useTmdb ? r.name : (r.tag || r.title);
          return (
            <View key={idx} style={{ width:96, marginHorizontal:4, alignItems:'center' }}>
              <View style={{ width:72, height:72, borderRadius:36, overflow:'hidden', backgroundColor:'#1a1a1a' }}>
                {src && ExpoImage ? <ExpoImage source={{ uri: src, headers }} style={{ width:'100%', height:'100%' }} contentFit="cover" /> : null}
              </View>
              <Text style={{ color:'#eee', marginTop:6 }} numberOfLines={1}>{name}</Text>
            </View>
          );
        })}
      </ScrollView>
    </View>
  );
}

function CrewList({ meta, tmdbCrew }: { meta:any; tmdbCrew?: Array<{ name: string; job?: string }> }) {
  const directors: any[] = Array.isArray(meta?.Director) ? meta.Director : [];
  const writers: any[] = Array.isArray(meta?.Writer) ? meta.Writer : [];
  let dirNames: string[] = directors.map((d:any)=> d.tag || d.title);
  let writerNames: string[] = writers.map((w:any)=> w.tag || w.title);
  if (!dirNames.length && Array.isArray(tmdbCrew)) dirNames = tmdbCrew.filter(c=> /director/i.test(String(c.job||''))).map(c=> c.name);
  if (!writerNames.length && Array.isArray(tmdbCrew)) writerNames = tmdbCrew.filter(c=> /(writer|screenplay)/i.test(String(c.job||''))).map(c=> c.name);
  if (!dirNames.length && !writerNames.length) return null;
  return (
    <View style={{ marginTop:4, paddingHorizontal:16 }}>
      {dirNames.length ? (
        <View style={{ marginBottom:8 }}>
          <Text style={{ color:'#aaa', marginBottom:6 }}>Directors</Text>
          <Text style={{ color:'#eee' }}>{dirNames.join(', ')}</Text>
        </View>
      ) : null}
      {writerNames.length ? (
        <View style={{ marginBottom:8 }}>
          <Text style={{ color:'#aaa', marginBottom:6 }}>Writers</Text>
          <Text style={{ color:'#eee' }}>{writerNames.join(', ')}</Text>
        </View>
      ) : null}
    </View>
  );
}

function TechSpecs({ meta }: { meta:any }) {
  const m = (meta?.Media || [])[0] || {};
  if (!m) return null;
  const container = m?.container;
  const vCodec = m?.videoCodec || (m as any)?.videoCodecTag;
  const aCodec = m?.audioCodec;
  const res = m?.width && m?.height ? `${m.width}x${m.height}` : (m?.videoResolution ? `${m.videoResolution}p` : undefined);
  const bitrate = m?.bitrate ? `${m.bitrate} kbps` : undefined;
  const hdr = (() => {
    if (!Array.isArray(m?.Part)) return undefined;
    const streams = (m.Part[0]?.Stream || []) as any[];
    const s = streams.find(s => /dolby.?vision|dovi/i.test(String(s?.displayTitle||'')) || /smpte2084|pq|hdr10/i.test(String(s?.colorTrc||'')));
    if (!s) return undefined;
    if (/dolby.?vision|dovi/i.test(String(s?.displayTitle||''))) return 'Dolby Vision';
    return 'HDR10';
  })();

  return (
    <View style={{ marginTop:8 }}>
      <KeyValue k="Resolution" v={res} />
      <KeyValue k="Video" v={vCodec} />
      <KeyValue k="Audio" v={aCodec} />
      <KeyValue k="Container" v={container} />
      <KeyValue k="Bitrate" v={bitrate} />
      <KeyValue k="HDR" v={hdr} />
    </View>
  );
}

function Collections({ meta }: { meta:any }) {
  const cols: any[] = Array.isArray(meta?.Collection) ? meta.Collection : [];
  const tmdbCol = meta?.tmdbCollectionName;
  if (!cols.length && !tmdbCol) return null;
  return (
    <View style={{ flexDirection:'row', flexWrap:'wrap', paddingHorizontal:12, marginTop:8 }}>
      {cols.map((c:any, idx:number) => (
        <View key={`plexcol-${idx}`} style={{ margin:4, paddingHorizontal:10, paddingVertical:6, borderRadius:999, backgroundColor:'#1a1b20', borderWidth:1, borderColor:'#2a2b30' }}>
          <Text style={{ color:'#fff', fontWeight:'700' }}>{c.tag || c.title}</Text>
        </View>
      ))}
      {!cols.length && tmdbCol ? (
        <View key={`tmdbcol`} style={{ margin:4, paddingHorizontal:10, paddingVertical:6, borderRadius:999, backgroundColor:'#1a1b20', borderWidth:1, borderColor:'#2a2b30' }}>
          <Text style={{ color:'#fff', fontWeight:'700' }}>{tmdbCol}</Text>
        </View>
      ) : null}
    </View>
  );
}

function DetailsTab({ meta, api, tmdbCast, tmdbCrew, tmdbVote, plexRatings }: { meta:any; api: MobileApi; tmdbCast?: Array<{ name: string; profile_path?: string }>; tmdbCrew?: Array<{ name: string; job?: string }>; tmdbVote?: number | null; plexRatings?: { imdb?: number|null; rtCritic?: number|null; rtAudience?: number|null } }) {
  const guids: string[] = Array.isArray(meta?.Guid) ? meta.Guid.map((g:any)=> String(g.id||'')) : [];
  const imdbId = guids.find(x=> x.startsWith('imdb://'))?.split('://')[1];
  const tmdbId = guids.find(x=> x.includes('tmdb://') || x.includes('themoviedb://'))?.split('://')[1];

  return (
    <View>
      <SectionHeader title="Ratings" />
      <RatingsRow meta={meta} tmdbVote={tmdbVote} plex={plexRatings} />

      <SectionHeader title="Cast" />
      <CastScroller meta={meta} api={api} tmdbCast={tmdbCast} />

      <SectionHeader title="Crew" />
      <CrewList meta={meta} tmdbCrew={tmdbCrew} />

      <SectionHeader title="Technical" />
      <TechSpecs meta={meta} />

      <SectionHeader title="Collections" />
      <Collections meta={meta} />

      <SectionHeader title="Info" />
      <KeyValue k="Studio" v={meta?.studio} />
      <KeyValue k="Year" v={meta?.year ? String(meta.year) : undefined} />
      <KeyValue k="Content Rating" v={meta?.contentRating} />
      <KeyValue k="IMDb" v={imdbId ? `https://www.imdb.com/title/${imdbId}` : undefined} />
      <KeyValue k="TMDB" v={tmdbId ? `https://www.themoviedb.org/${meta?.type==='movie'?'movie':'tv'}/${tmdbId}` : undefined} />
      <View style={{ height:12 }} />
    </View>
  );
}

function SeasonSelector({ seasons, seasonKey, onChange }: { seasons:any[]; seasonKey:string|null; onChange:(key:string)=>void }) {
  if (!seasons?.length) return null;
  return (
    <View style={{ flexDirection:'row', alignItems:'center', justifyContent:'space-between', paddingHorizontal:16, marginBottom:8 }}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false}>
        {seasons.map((s:any, idx:number) => {
          const key = String(s.ratingKey || s.key || idx);
          const active = key === seasonKey;
          const label = s.title || `Season ${s.index || (idx+1)}`;
          console.log('[SeasonSelector] Season button:', { key, label, active, seasonKey });
          return (
            <Pressable key={key} onPress={()=> onChange(key)} style={{ marginRight:10, paddingHorizontal:12, paddingVertical:8, borderRadius:999, backgroundColor: active? '#ffffff22' : '#1a1b20', borderWidth:1, borderColor: active? '#ffffff' : '#2a2b30' }}>
              <Text style={{ color:'#fff', fontWeight:'700' }}>{label}</Text>
            </Pressable>
          );
        })}
      </ScrollView>
    </View>
  );
}
