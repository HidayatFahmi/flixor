import React, { useEffect, useMemo, useRef, useState } from 'react';
import { View, Text, ActivityIndicator, Pressable, StyleSheet, Dimensions, Animated } from 'react-native';
import { Image as ExpoImage } from 'expo-image';
import { FlashList } from '@shopify/flash-list';
import { MobileApi } from '../api/client';
import { TopBarStore, useTopBarStore } from '../components/TopBarStore';
import { LinearGradient } from 'expo-linear-gradient';
import { useRoute, useNavigation } from '@react-navigation/native';

type Item = {
  ratingKey: string;
  title: string;
  type: 'movie'|'show'|'episode';
  thumb?: string;
  year?: number;
};

export default function Library() {
  const route = useRoute();
  const nav: any = useNavigation();
  const [api, setApi] = useState<MobileApi | null>(null);
  const [items, setItems] = useState<Item[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<'all'|'movies'|'shows'>('all');
  const [username, setUsername] = useState<string>('You');
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const loadingMoreRef = useRef(false);
  const [sectionKeys, setSectionKeys] = useState<{ show?: string; movie?: string }>({});
  const y = useRef(new Animated.Value(0)).current;
  const showPillsAnim = useRef(new Animated.Value(1)).current;
  const barHeight = useTopBarStore(s => s.height || 90);
  const lastScrollY = useRef(0);
  const scrollDirection = useRef<'up'|'down'>('down');

  const mType = useMemo(() => selected === 'movies' ? 'movie' : selected === 'shows' ? 'show' : 'all', [selected]);

  // Read route params to set initial selection
  useEffect(() => {
    const params = route.params as any;
    if (params?.tab === 'movies') {
      setSelected('movies');
    } else if (params?.tab === 'tv') {
      setSelected('shows');
    }
    console.log('[Library] route params:', params);
  }, [route.params]);

  // Set scrollY and showPills immediately on mount
  React.useLayoutEffect(() => {
    console.log('[Library] Setting scrollY and showPills for Library screen');
    TopBarStore.setScrollY(y);
    TopBarStore.setShowPills(showPillsAnim);
  }, [y]);

  // Push top bar updates via effects (avoid setState in render)
  useEffect(() => {
    TopBarStore.setVisible(true);
    TopBarStore.setShowFilters(true);
    TopBarStore.setUsername(username);
    TopBarStore.setSelected(selected);
    TopBarStore.setHandlers({ 
      onNavigateLibrary: undefined, 
      onClose: () => {
        console.log('[Library] Close button clicked, navigating back');
        if (nav.canGoBack()) {
          nav.goBack();
        }
      },
      onSearch: () => {
        console.log('[Library] Opening search');
        nav.navigate('Search');
      }
    });
  }, [username, selected, nav]);


  useEffect(() => {
    (async () => {
      const a = await MobileApi.load();
      setApi(a);
      try {
        if (a) {
          try { const s = await a.session(); if (s?.user?.username) setUsername(s.user.username); } catch {}
          const libs = await a.get('/api/plex/libraries');
          const dirs = Array.isArray(libs) ? libs : (libs?.MediaContainer?.Directory || []);
          const show = dirs.find((d:any)=> d.type==='show');
          const movie = dirs.find((d:any)=> d.type==='movie');
          setSectionKeys({ show: show?.key ? String(show.key) : undefined, movie: movie?.key ? String(movie.key) : undefined });
          console.log('[Library] sections resolved', { show: show?.key, movie: movie?.key });
        }
      } catch {}
    })();
  }, []);

  useEffect(() => {
    if (!api) return;
    setLoading(true);
    setError(null);
    setPage(1);
    (async () => {
      try {
        // Resolve a concrete section key based on pill, or fall back to first available section
        const useSection = (mType === 'show' ? sectionKeys.show : mType === 'movie' ? sectionKeys.movie : (sectionKeys.show || sectionKeys.movie));
        console.log('[Library] load items', { selected, mType, useSection });
        if (useSection) {
          const typeParam = mType === 'movie' ? '&type=1' : (mType === 'show' ? '&type=2' : '');
          const res = await api.get(`/api/plex/library/${encodeURIComponent(String(useSection))}/all?sort=addedAt:desc&offset=0&limit=40${typeParam}`);
          const container = (res && (res.MediaContainer || res)) || {} as any;
          let md = Array.isArray(container.Metadata) ? container.Metadata : [];
          if (!md.length) {
            // Fallback without type filter just in case
            const res2 = await api.get(`/api/plex/library/${encodeURIComponent(String(useSection))}/all?sort=addedAt:desc&offset=0&limit=40`);
            const c2 = (res2 && (res2.MediaContainer || res2)) || {} as any;
            md = Array.isArray(c2.Metadata) ? c2.Metadata : [];
            console.log('[Library] fallback query items', md.length);
          }
          const mapped: Item[] = md.map((m:any)=> ({ ratingKey:String(m.ratingKey), title: m.title || m.grandparentTitle || 'Untitled', type: m.type, thumb: m.thumb || m.parentThumb || m.grandparentThumb, year: m.year }));
          console.log('[Library] mapped first page', mapped.length);
          setItems(mapped);
          console.log('[Library] setItems length', mapped.length);
          const totalSize = typeof container.totalSize === 'number' ? container.totalSize : mapped.length;
          setHasMore(mapped.length < totalSize);
        } else {
          console.log('[Library] no section found; showing empty');
          setItems([]);
          setHasMore(false);
        }
      } catch (e: any) {
        setError(e?.message || 'Failed to load library');
      } finally {
        setLoading(false);
      }
    })();
  }, [api, mType, sectionKeys]);

  const loadMore = async () => {
    if (!api || !hasMore || loadingMoreRef.current) return;
    loadingMoreRef.current = true;
    try {
      const nextPage = page + 1;
      const useSection = (mType === 'show' ? sectionKeys.show : mType === 'movie' ? sectionKeys.movie : (sectionKeys.show || sectionKeys.movie));
      let newItems: Item[] = [];
      if (useSection) {
        const offset = (nextPage-1) * 40;
        const typeParam = mType === 'movie' ? '&type=1' : (mType === 'show' ? '&type=2' : '');
        const res = await api.get(`/api/plex/library/${encodeURIComponent(String(useSection))}/all?sort=addedAt:desc&offset=${offset}&limit=40${typeParam}`);
        const container = (res && (res.MediaContainer || res)) || {} as any;
        let md = Array.isArray(container.Metadata) ? container.Metadata : [];
        newItems = md.map((m:any)=> ({ ratingKey:String(m.ratingKey), title: m.title || m.grandparentTitle || 'Untitled', type: m.type, thumb: m.thumb || m.parentThumb || m.grandparentThumb, year: m.year }));
        console.log('[Library] loadMore page', nextPage, 'count', newItems.length);
      } else { newItems = []; }
      setItems(prev => [...prev, ...newItems]);
      console.log('[Library] after loadMore items length', (items.length + newItems.length));
      setPage(nextPage);
      const estTotal = (items.length + newItems.length) + (newItems.length > 0 ? 40 : 0);
      setHasMore(newItems.length === 40);
    } catch {}
    loadingMoreRef.current = false;
  };

  if (!api || loading) {
    return (
      <View style={styles.center}><ActivityIndicator color="#fff" /></View>
    );
  }

  if (error) {
    return (
      <View style={styles.center}>
        <Text style={{ color:'#fff', marginBottom:12 }}>{error}</Text>
        <Pressable onPress={()=> setSelected(s=> s)} style={styles.retry}><Text style={{ color:'#000', fontWeight:'800' }}>Retry</Text></Pressable>
      </View>
    );
  }

  const numColumns = Dimensions.get('window').width >= 800 ? 5 : 3;
  const itemSize = Math.floor((Dimensions.get('window').width - 16 - (numColumns-1)*8)/numColumns);

  return (
    <View style={{ flex:1, backgroundColor:'#0a0a0a' }}>
      {/* Themed background layers similar to Home */}
      <LinearGradient
        colors={[ '#0a0a0a', '#0f0f10', '#0b0c0d' ]}
        start={{ x: 0.5, y: 0 }} end={{ x: 0.5, y: 1 }}
        style={StyleSheet.absoluteFillObject}
      />
      <LinearGradient
        colors={[ 'rgba(122,22,18,0.24)', 'rgba(122,22,18,0.10)', 'rgba(122,22,18,0.0)' ]}
        start={{ x: 0.0, y: 1.0 }} end={{ x: 0.45, y: 0.35 }}
        style={StyleSheet.absoluteFillObject}
      />
      <LinearGradient
        colors={[ 'rgba(20,76,84,0.22)', 'rgba(20,76,84,0.10)', 'rgba(20,76,84,0.0)' ]}
        start={{ x: 1.0, y: 0.0 }} end={{ x: 0.55, y: 0.45 }}
        style={StyleSheet.absoluteFillObject}
      />

      {/* Global Top Bar updates via effects */}

      <FlashList
        data={items}
        keyExtractor={(it)=> String(it.ratingKey)}
        renderItem={({ item }) => <Card item={item} api={api} size={itemSize} onPress={()=> nav.navigate('Details', { type:'plex', ratingKey: item.ratingKey })} />}
        estimatedItemSize={itemSize+28}
        numColumns={numColumns}
        contentContainerStyle={{ padding:8, paddingTop: barHeight }}
        onEndReached={loadMore}
        onEndReachedThreshold={0.5}
        onScroll={Animated.event([
          { nativeEvent: { contentOffset: { y } } }
        ], { 
          useNativeDriver: false,
          listener: (e: any) => {
            const currentY = e.nativeEvent.contentOffset.y;
            const delta = currentY - lastScrollY.current;
            
            // Determine scroll direction
            if (delta > 5) {
              // Scrolling down - hide pills
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
              // Scrolling up - show pills
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
        ListEmptyComponent={<Text style={{ color:'#888', textAlign:'center', marginTop:40 }}>No items</Text>}
      />
    </View>
  );
}

function Card({ item, api, size, onPress }: { item: Item; api: MobileApi; size: number; onPress?: () => void }) {
  const authHeaders = api.token ? { Authorization: `Bearer ${api.token}` } : undefined;
  const img = item.thumb ? `${api.baseUrl}/api/image/plex?path=${encodeURIComponent(item.thumb)}&w=${size*2}&f=webp` : undefined;
  return (
    <Pressable onPress={onPress} style={{ width: size, margin:4 }}>
      <View style={{ width:size, height: Math.round(size*1.5), backgroundColor:'#111', borderRadius:10, overflow:'hidden' }}>
        {img ? <ExpoImage source={{ uri: img, headers: authHeaders }} style={{ width:'100%', height:'100%' }} contentFit="cover" /> : null}
      </View>
      <Text numberOfLines={1} style={{ color:'#fff', marginTop:6, fontWeight:'700' }}>{item.title}</Text>
      {item.year ? <Text style={{ color:'#aaa', fontSize:12 }}>{item.year}</Text> : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  center: { flex:1, backgroundColor:'#000', alignItems:'center', justifyContent:'center' },
  retry: { backgroundColor:'#fff', paddingHorizontal:16, paddingVertical:10, borderRadius:8 }
});
