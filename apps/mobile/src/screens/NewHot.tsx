import React, { useState, useEffect, useRef } from 'react';
import { View, Text, ScrollView, Pressable, ActivityIndicator, StyleSheet, Animated } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { LinearGradient } from 'expo-linear-gradient';
import { Image as ExpoImage } from 'expo-image';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation, useIsFocused } from '@react-navigation/native';
import { MobileApi } from '../api/client';
import { TopBarStore, useTopBarStore } from '../components/TopBarStore';
import * as Haptics from 'expo-haptics';

type TabType = 'coming-soon' | 'everyones-watching' | 'top10-shows' | 'top10-movies';

type ContentItem = {
  id: string;
  title: string;
  image?: string;
  backdropImage?: string;
  subtitle?: string;
  description?: string;
  releaseDate?: string;
  badge?: string;
  rank?: number;
};

export default function NewHot() {
  const nav: any = useNavigation();
  const [api, setApi] = useState<MobileApi | null>(null);
  const [activeTab, setActiveTab] = useState<TabType>('coming-soon');
  const [loading, setLoading] = useState(false);
  const [content, setContent] = useState<ContentItem[]>([]);
  const y = useRef(new Animated.Value(0)).current;
  const barHeight = useTopBarStore(s => s.height || 60);
  const isFocused = useIsFocused();

  // Set scrollY and configure TopBar when screen is focused
  React.useLayoutEffect(() => {
    if (isFocused) {
      TopBarStore.setScrollY(y);

      // Prefetch all tab content in background
      if (api) {
        console.log('[NewHot] Prefetching tab content');
        api.prefetch('/api/tmdb/movie/upcoming?region=US');
        api.prefetch('/api/tmdb/trending/all/week');
        api.prefetch('/api/tmdb/trending/tv/week');
        api.prefetch('/api/tmdb/trending/movie/week');
      }
    }
  }, [isFocused, y, api]);

  useEffect(() => {
    if (!isFocused) return;
    
    // Render tab pills inside TopAppBar
    const tabPills = (
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={{ paddingHorizontal: 16, alignItems: 'center'}}
        style={{ flexGrow: 0 }}
      >
        {tabs.map((tab) => (
          <TabPill
            key={tab.id}
            active={activeTab === tab.id}
            label={tab.label}
            onPress={() => setActiveTab(tab.id)}
          />
        ))}
      </ScrollView>
    );
    
    TopBarStore.setVisible(true);
    TopBarStore.setShowFilters(false); // No default pills
    TopBarStore.setUsername('New & Hot');
    TopBarStore.setSelected('all');
    TopBarStore.setCompact(false); // Use compact mode for NewHot
    TopBarStore.setCustomFilters(tabPills); // Pass custom tab pills
    TopBarStore.setHandlers({ 
      onNavigateLibrary: undefined,
      onClose: undefined,
      onSearch: () => {
        // Navigate to HomeTab first, then to Search
        nav.navigate('HomeTab', { screen: 'Search' });
      }
    });
    
    // Cleanup when leaving screen
    return () => {
      TopBarStore.setCustomFilters(undefined);
      TopBarStore.setCompact(false);
    };
  }, [isFocused, nav, activeTab]);

  useEffect(() => {
    (async () => {
      const a = await MobileApi.load();
      setApi(a);
    })();
  }, []);

  useEffect(() => {
    if (api) {
      loadContent();
    }
  }, [api, activeTab]);

  const loadContent = async () => {
    if (!api) return;

    setLoading(true);
    try {
      switch (activeTab) {
        case 'coming-soon':
          await loadComingSoon();
          break;
        case 'everyones-watching':
          await loadEveryonesWatching();
          break;
        case 'top10-shows':
          await loadTop10Shows();
          break;
        case 'top10-movies':
          await loadTop10Movies();
          break;
      }
    } catch (error) {
      console.error('[NewHot] Failed to load content:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadComingSoon = async () => {
    if (!api) return;
    const res = await api.get('/api/tmdb/movie/upcoming?region=US');
    const items = (res?.results || []).slice(0, 20).map((item: any) => ({
      id: `tmdb:movie:${item.id}`,
      title: item.title,
      image: item.poster_path ? `https://image.tmdb.org/t/p/w500${item.poster_path}` : undefined,
      backdropImage: item.backdrop_path ? `https://image.tmdb.org/t/p/w780${item.backdrop_path}` : undefined,
      description: item.overview,
      releaseDate: item.release_date ? new Date(item.release_date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : undefined,
      badge: 'Coming Soon',
    }));
    setContent(items);
  };

  const loadEveryonesWatching = async () => {
    if (!api) return;
    const res = await api.get('/api/tmdb/trending/all/week');
    const items = (res?.results || []).slice(0, 20).map((item: any) => ({
      id: item.media_type === 'movie' ? `tmdb:movie:${item.id}` : `tmdb:tv:${item.id}`,
      title: item.title || item.name,
      image: item.poster_path ? `https://image.tmdb.org/t/p/w500${item.poster_path}` : undefined,
      backdropImage: item.backdrop_path ? `https://image.tmdb.org/t/p/w780${item.backdrop_path}` : undefined,
      description: item.overview,
      subtitle: (item.release_date || item.first_air_date)?.split('-')[0],
      badge: item.vote_average ? `⭐ ${item.vote_average.toFixed(1)}` : undefined,
    }));
    setContent(items);
  };

  const loadTop10Shows = async () => {
    if (!api) return;
    const res = await api.get('/api/tmdb/trending/tv/week');
    const items = (res?.results || []).slice(0, 10).map((item: any, index: number) => ({
      id: `tmdb:tv:${item.id}`,
      title: item.name,
      image: item.poster_path ? `https://image.tmdb.org/t/p/w500${item.poster_path}` : undefined,
      backdropImage: item.backdrop_path ? `https://image.tmdb.org/t/p/w780${item.backdrop_path}` : undefined,
      description: item.overview,
      subtitle: item.first_air_date?.split('-')[0],
      rank: index + 1,
    }));
    setContent(items);
  };

  const loadTop10Movies = async () => {
    if (!api) return;
    const res = await api.get('/api/tmdb/trending/movie/week');
    const items = (res?.results || []).slice(0, 10).map((item: any, index: number) => ({
      id: `tmdb:movie:${item.id}`,
      title: item.title,
      image: item.poster_path ? `https://image.tmdb.org/t/p/w500${item.poster_path}` : undefined,
      backdropImage: item.backdrop_path ? `https://image.tmdb.org/t/p/w780${item.backdrop_path}` : undefined,
      description: item.overview,
      subtitle: item.release_date?.split('-')[0],
      rank: index + 1,
    }));
    setContent(items);
  };

  const handleItemPress = (id: string) => {
    if (id.startsWith('plex:')) {
      const rk = id.split(':')[1];
      nav.navigate('Details', { type: 'plex', ratingKey: rk });
    } else if (id.startsWith('tmdb:')) {
      const [, media, tmdbId] = id.split(':');
      nav.navigate('Details', { type: 'tmdb', mediaType: media, id: tmdbId });
    }
  };

  const TabPill = ({ active, label, onPress }: { active?: boolean; label: string; onPress?: () => void }) => {
    const handlePress = () => {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      onPress?.();
    };

    return (
      <Pressable onPress={handlePress} style={[styles.tabPill, active && styles.tabPillActive]}>
        <Text style={[styles.tabPillText, { color: active ? '#000' : '#fff' }]}>{label}</Text>
      </Pressable>
    );
  };

  const tabs = [
    { id: 'coming-soon' as const, label: '🎁 Coming Soon' },
    { id: 'everyones-watching' as const, label: "🔥 Everyone's Watching" },
    { id: 'top10-shows' as const, label: '🔝 Top 10 Shows' },
    { id: 'top10-movies' as const, label: '🔝 Top 10 Movies' },
  ];

  return (
    <View style={{ flex: 1, backgroundColor: '#0a0a0a' }}>
      {/* Gradients */}
      <LinearGradient
        colors={['#0a0a0a', '#0f0f10', '#0b0c0d']}
        start={{ x: 0.5, y: 0 }} end={{ x: 0.5, y: 1 }}
        style={StyleSheet.absoluteFillObject}
      />

      <View style={{ flex: 1 }}>
        {/* TopAppBar is rendered globally above this content */}

        {/* Scrollable content - tab pills are now in TopAppBar */}
        <Animated.ScrollView 
          style={{ flex: 1 }} 
          contentContainerStyle={{ paddingTop: barHeight, paddingBottom: 80 }}
          scrollEventThrottle={16}
          onScroll={Animated.event([
            { nativeEvent: { contentOffset: { y } } }
          ], { useNativeDriver: false })}
        >
          {/* Content */}
          {loading ? (
            <View style={{ alignItems: 'center', paddingTop: 40 }}>
              <ActivityIndicator color="#fff" size="large" />
            </View>
          ) : (
            <View style={{ paddingTop: 16 }}>
              {content.map((item, index) => (
                <Pressable
                  key={index}
                  onPress={() => handleItemPress(item.id)}
                  style={styles.contentCard}
                >
                  {/* Backdrop Image */}
                  <View style={styles.backdropContainer}>
                    {item.backdropImage ? (
                      <ExpoImage
                        source={{ uri: item.backdropImage }}
                        style={{ width: '100%', height: '100%' }}
                        contentFit="cover"
                      />
                    ) : (
                      <View style={{ width: '100%', height: '100%', backgroundColor: '#1a1a1a' }} />
                    )}

                    {/* Rank badge for Top 10 */}
                    {item.rank && (
                      <View style={styles.rankBadge}>
                        <Text style={styles.rankNumber}>{item.rank}</Text>
                      </View>
                    )}

                    {/* Mute icon */}
                    <View style={styles.muteIcon}>
                      <Ionicons name="volume-mute" size={20} color="#fff" />
                    </View>
                  </View>

                  {/* Title and Info */}
                  <View style={styles.contentInfo}>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.contentTitle}>{item.title}</Text>
                      {item.releaseDate && (
                        <Text style={styles.releaseDate}>Coming on {item.releaseDate}</Text>
                      )}
                      {item.description && (
                        <Text style={styles.description} numberOfLines={3}>
                          {item.description}
                        </Text>
                      )}
                    </View>
                  </View>
                </Pressable>
              ))}
            </View>
          )}
        </Animated.ScrollView>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  tabPill: {
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#4a4a4a',
    backgroundColor: 'transparent',
    marginRight: 8,
  },
  tabPillActive: {
    backgroundColor: '#fff',
    borderColor: '#fff',
  },
  tabPillText: {
    fontWeight: '600',
    fontSize: 14,
  },
  contentCard: {
    marginBottom: 24,
    paddingHorizontal: 16,
  },
  backdropContainer: {
    width: '100%',
    aspectRatio: 16 / 9,
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: '#1a1a1a',
    marginBottom: 12,
  },
  rankBadge: {
    position: 'absolute',
    bottom: 8,
    left: 8,
    width: 40,
    height: 40,
    borderRadius: 4,
    backgroundColor: '#E50914',
    alignItems: 'center',
    justifyContent: 'center',
  },
  rankNumber: {
    color: '#fff',
    fontSize: 20,
    fontWeight: '900',
  },
  muteIcon: {
    position: 'absolute',
    bottom: 8,
    right: 8,
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: 'rgba(0,0,0,0.6)',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: '#fff',
  },
  contentInfo: {
    gap: 12,
  },
  contentTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 4,
  },
  releaseDate: {
    color: '#aaa',
    fontSize: 13,
    marginBottom: 8,
  },
  description: {
    color: '#ccc',
    fontSize: 14,
    lineHeight: 20,
  },
  remindButton: {
    alignItems: 'center',
    gap: 4,
  },
  remindText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
  },
});
