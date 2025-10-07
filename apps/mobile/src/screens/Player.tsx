import React, { useEffect, useState, useRef, useCallback } from 'react';
import { View, Text, TouchableOpacity, ActivityIndicator, StyleSheet, StatusBar, Dimensions } from 'react-native';
import { Video, ResizeMode, AVPlaybackStatus, Audio } from 'expo-av';
import { Image as ExpoImage } from 'expo-image';
import Slider from '@react-native-community/slider';
import { useNavigation, StackActions } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import * as ScreenOrientation from 'expo-screen-orientation';
import { LinearGradient } from 'expo-linear-gradient';
import { MobileApi } from '../api/client';
import { Replay10Icon, Forward10Icon } from '../components/icons/SkipIcons';
import { TopBarStore } from '../components/TopBarStore';

type RouteParams = {
  route?: {
    params?: {
      type: 'plex' | 'tmdb';
      ratingKey?: string;
      id?: string;
    };
  };
};

type NextEpisode = {
  ratingKey: string;
  title: string;
  thumb?: string;
  episodeLabel?: string;
};

export default function Player({ route }: RouteParams) {
  const params = route?.params || {};
  const nav = useNavigation();
  const videoRef = useRef<Video>(null);

  const [api, setApi] = useState<MobileApi | null>(null);
  const [loading, setLoading] = useState(true);
  const [streamUrl, setStreamUrl] = useState<string>('');
  const [metadata, setMetadata] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  // Playback state
  const [isPlaying, setIsPlaying] = useState(true);
  const [duration, setDuration] = useState(0);
  const [position, setPosition] = useState(0);
  const [buffering, setBuffering] = useState(false);
  const [showControls, setShowControls] = useState(true);

  // Markers for skip intro/credits
  const [markers, setMarkers] = useState<Array<{ type: string; startTimeOffset: number; endTimeOffset: number }>>([]);

  // Next episode for auto-play
  const [nextEpisode, setNextEpisode] = useState<NextEpisode | null>(null);
  const [nextEpisodeCountdown, setNextEpisodeCountdown] = useState<number | null>(null);

  // Store Plex server info for timeline updates
  const [plexBaseUrl, setPlexBaseUrl] = useState<string>('');
  const [plexToken, setPlexToken] = useState<string>('');
  const [sessionId, setSessionId] = useState<string>('');

  // Track screen dimensions for rotation
  const [dimensions, setDimensions] = useState({
    width: Dimensions.get('window').width,
    height: Dimensions.get('window').height,
  });

  const progressInterval = useRef<NodeJS.Timeout | null>(null);
  const controlsTimeout = useRef<NodeJS.Timeout | null>(null);

  // Store cleanup info in refs
  const cleanupInfoRef = useRef({ plexBaseUrl: '', plexToken: '', sessionId: '' });
  const isReplacingRef = useRef(false);

  // Scrubbing state
  const [isScrubbing, setIsScrubbing] = useState(false);
  // Legacy pan scrub state removed (using Slider now)

  useEffect(() => {
    // Hide TopBar and TabBar when Player is shown
    TopBarStore.setVisible(false);
    TopBarStore.setTabBarVisible(false);

    (async () => {
      // Configure audio session
      try {
        await Audio.setAudioModeAsync({
          playsInSilentModeIOS: true,
          staysActiveInBackground: true,
          shouldDuckAndroid: true,
        });
      } catch (e) {
        console.warn('[Player] Failed to set audio mode:', e);
      }

      // Enable landscape orientation
      try {
        await ScreenOrientation.unlockAsync();
      } catch (e) {
        console.warn('[Player] Failed to unlock orientation:', e);
      }

      const a = await MobileApi.load();
      setApi(a);

      if (params.type === 'plex' && params.ratingKey && a) {
        try {
          // Fetch metadata
          const m = await a.get(`/api/plex/metadata/${encodeURIComponent(params.ratingKey)}`);
          console.log('[Player] Metadata:', m ? { title: m.title, type: m.type } : 'null');
          setMetadata(m);

          // Fetch markers - use plexBackendDir endpoint
          try {
            const markersRes = await a.get(`/api/plex/dir/library/metadata/${encodeURIComponent(params.ratingKey)}?includeMarkers=1`);
            console.log('[Player] Markers raw response:', JSON.stringify(markersRes).substring(0, 200));

            // Check if it's wrapped in MediaContainer
            const markerData = markersRes?.MediaContainer?.Metadata?.[0] || markersRes;
            const markersList = markerData?.Marker || [];

            setMarkers(markersList);
            console.log('[Player] Markers found:', markersList.length, markersList.map((mk: any) => `${mk.type}: ${mk.startTimeOffset}-${mk.endTimeOffset}`));
          } catch (e) {
            console.error('[Player] Failed to fetch markers:', e);
          }

          // Fetch next episode if this is an episode
          if (m?.type === 'episode') {
            try {
              // Get season episodes to find next episode
              const parentRK = m.parentRatingKey;
              if (parentRK) {
                const seasonEps = await a.get(`/api/plex/dir/library/metadata/${encodeURIComponent(parentRK)}/children`);
                const episodes = seasonEps?.Metadata || [];
                const currentIndex = episodes.findIndex((ep: any) => String(ep.ratingKey) === String(params.ratingKey));
                if (currentIndex >= 0 && episodes[currentIndex + 1]) {
                  const nextEp = episodes[currentIndex + 1];
                  const seasonNum = nextEp.parentIndex || nextEp.parentIndexTag || nextEp.parent?.index;
                  const epNum = nextEp.index;
                  const episodeLabel = (seasonNum && epNum) ? `S${seasonNum}:E${epNum}` : undefined;
                  setNextEpisode({
                    ratingKey: String(nextEp.ratingKey),
                    title: nextEp.title || 'Next Episode',
                    thumb: nextEp.thumb,
                    episodeLabel,
                  } as any);
                  console.log('[Player] Next episode:', nextEp.title);
                }
              }
            } catch (e) {
              console.warn('[Player] Failed to fetch next episode:', e);
            }
          }

          // Get Plex server connection details...
          const serversRes = await a.get('/api/plex/servers');
          const servers = Array.isArray(serversRes) ? serversRes : [];
          const activeServer = servers.find((s: any) => s.isActive);

          if (!activeServer) {
            setError('No active Plex server configured');
            setLoading(false);
            return;
          }

          const connRes = await a.get(`/api/plex/servers/${encodeURIComponent(activeServer.id)}/connections`);
          const connections = connRes?.connections || [];
          const selectedConnection = connections.find((c: any) => c.local) || connections[0];

          if (!selectedConnection) {
            setError('No Plex server connection available');
            setLoading(false);
            return;
          }

          const baseUrl = selectedConnection.uri.replace(/\/$/, '');
          setPlexBaseUrl(baseUrl);
          cleanupInfoRef.current.plexBaseUrl = baseUrl;

          const authRes = await a.get('/api/auth/servers');
          const authServers = Array.isArray(authRes) ? authRes : [];
          const serverWithToken = authServers.find((s: any) =>
            s.clientIdentifier === activeServer.id ||
            s.clientIdentifier === activeServer.machineIdentifier
          );
          const token = serverWithToken?.token;
          setPlexToken(token || '');
          cleanupInfoRef.current.plexToken = token || '';

          if (!token) {
            setError('Could not get Plex access token');
            setLoading(false);
            return;
          }

          const media = (m?.Media || [])[0];
          const part = media?.Part?.[0];

          if (part?.key) {
            const sid = Math.random().toString(36).substring(2, 15);
            setSessionId(sid);
            cleanupInfoRef.current.sessionId = sid;

            // Request streaming decision from Plex
            const decisionUrl = `${baseUrl}/video/:/transcode/universal/decision`;
            const decisionParams = new URLSearchParams({
              'X-Plex-Token': token,
              'path': `/library/metadata/${params.ratingKey}`,
              'mediaIndex': '0',
              'partIndex': '0',
              'protocol': 'hls',
              'directPlay': '1',
              'directStream': '1',
              'subtitleSize': '100',
              'audioBoost': '100',
              'location': 'lan',
              'session': sid,
              'X-Plex-Product': 'Flixor Mobile',
              'X-Plex-Version': '1.0.0',
              'X-Plex-Client-Identifier': sid,
              'X-Plex-Platform': 'iOS',
              'X-Plex-Platform-Version': '17.0',
              'X-Plex-Device': 'iPhone',
              'X-Plex-Device-Name': 'Mobile'
            });

            try {
              const decisionRes = await fetch(`${decisionUrl}?${decisionParams.toString()}`);
              const decisionData = await decisionRes.text();

              const canDirectPlay = decisionData.includes('directPlayDecisionCode="1000"');

              if (canDirectPlay) {
                const directUrl = `${baseUrl}${part.key}?X-Plex-Token=${token}`;
                setStreamUrl(directUrl);
              } else {
                // Transcode - start session
                const transcodeParams = new URLSearchParams({
                  'hasMDE': '1',
                  'path': `/library/metadata/${params.ratingKey}`,
                  'mediaIndex': '0',
                  'partIndex': '0',
                  'protocol': 'hls',
                  'fastSeek': '1',
                  'directPlay': '0',
                  'directStream': '0',
                  'directStreamAudio': '0',
                  'subtitleSize': '100',
                  'audioBoost': '100',
                  'location': 'lan',
                  'addDebugOverlay': '0',
                  'autoAdjustQuality': '0',
                  'mediaBufferSize': '102400',
                  'session': sid,
                  'videoQuality': '100',
                  'videoResolution': '1920x1080',
                  'maxVideoBitrate': '20000',
                  'copyts': '1',
                  'X-Plex-Platform': 'iOS',
                  'X-Plex-Client-Identifier': sid,
                  'X-Plex-Product': 'Flixor Mobile',
                  'X-Plex-Device': 'iPhone',
                  'X-Plex-Token': token
                });

                const startUrl = `${baseUrl}/video/:/transcode/universal/start.m3u8?${transcodeParams.toString()}`;
                await fetch(startUrl);
                const hlsUrl = `${baseUrl}/video/:/transcode/universal/session/${sid}/base/index.m3u8?X-Plex-Token=${token}`;
                setStreamUrl(hlsUrl);
              }
            } catch (err) {
              console.error('[Player] Decision failed:', err);
              const hlsUrl = `${baseUrl}/video/:/transcode/universal/start.m3u8?${decisionParams.toString()}`;
              setStreamUrl(hlsUrl);
            }

            // Set resume position
            if (m?.viewOffset) {
              const resumeMs = parseInt(String(m.viewOffset));
              if (resumeMs > 0) {
                setTimeout(async () => {
                  if (videoRef.current) {
                    await videoRef.current.setPositionAsync(resumeMs);
                  }
                }, 500);
              }
            }

            setLoading(false);
          } else {
            setError('No playable media found');
            setLoading(false);
          }
        } catch (e: any) {
          console.error('[Player] Error:', e);
          setError(e.message || 'Failed to load video');
          setLoading(false);
        }
      }
    })();

    return () => {
      // Restore TopBar and TabBar when Player is closed
      TopBarStore.setVisible(true);
      TopBarStore.setTabBarVisible(true);

      // Cleanup
      (async () => {
        const { plexBaseUrl: baseUrl, plexToken: token, sessionId: sid } = cleanupInfoRef.current;

        if (baseUrl && token && sid) {
          try {
            const stopUrl = `${baseUrl}/video/:/transcode/universal/stop?session=${sid}&X-Plex-Token=${token}`;
            await fetch(stopUrl);
            console.log('[Player] Stopped transcode session:', sid);
          } catch (e) {
            console.warn('[Player] Failed to stop transcode:', e);
          }
        }

        // Only reset orientation/audio if we're leaving the Player entirely,
        // not when we're replacing to another Player instance
        if (!isReplacingRef.current) {
          try {
            await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP);
          } catch (e) {}

          try {
            await Audio.setAudioModeAsync({
              playsInSilentModeIOS: false,
              staysActiveInBackground: false,
              shouldDuckAndroid: false,
            });
          } catch (e) {}
        }
      })();

      if (progressInterval.current) clearInterval(progressInterval.current);
      if (controlsTimeout.current) clearTimeout(controlsTimeout.current);
    };
  }, []);

  // Update progress to Plex
  useEffect(() => {
    if (!plexBaseUrl || !plexToken || !params.ratingKey) return;

    const updateProgress = async () => {
      if (position > 0 && duration > 0) {
        try {
          const timelineParams = new URLSearchParams({
            'ratingKey': String(params.ratingKey),
            'key': `/library/metadata/${params.ratingKey}`,
            'state': isPlaying ? 'playing' : 'paused',
            'time': String(Math.floor(position)),
            'duration': String(Math.floor(duration)),
            'X-Plex-Token': plexToken,
            'X-Plex-Client-Identifier': sessionId || 'flixor-mobile',
            'X-Plex-Product': 'Flixor Mobile',
            'X-Plex-Device': 'iPhone'
          });

          const url = `${plexBaseUrl}/:/timeline?${timelineParams.toString()}`;
          await fetch(url);
        } catch (e) {
          console.error('[Player] Progress update failed:', e);
        }
      }
    };

    progressInterval.current = setInterval(updateProgress, 10000);
    updateProgress();

    return () => {
      if (progressInterval.current) clearInterval(progressInterval.current);
    };
  }, [plexBaseUrl, plexToken, sessionId, params.ratingKey, position, duration, isPlaying]);

  // Cleanup on navigation
  useEffect(() => {
    const cleanup = async () => {
      const { plexBaseUrl: baseUrl, plexToken: token, sessionId: sid } = cleanupInfoRef.current;

      if (!baseUrl || !token) return;

      if (params.ratingKey) {
        try {
          const timelineParams = new URLSearchParams({
            'ratingKey': String(params.ratingKey),
            'key': `/library/metadata/${params.ratingKey}`,
            'state': 'stopped',
            'time': '0',
            'duration': '0',
            'X-Plex-Token': token,
            'X-Plex-Client-Identifier': sid || 'flixor-mobile',
            'X-Plex-Product': 'Flixor Mobile',
            'X-Plex-Device': 'iPhone'
          });
          await fetch(`${baseUrl}/:/timeline?${timelineParams.toString()}`);
        } catch (e) {}
      }

      if (sid) {
        try {
          await fetch(`${baseUrl}/video/:/transcode/universal/stop?session=${sid}&X-Plex-Token=${token}`);
        } catch (e) {}
      }
    };

    const unsubscribe = nav.addListener('beforeRemove', () => {
      cleanup();
    });

    const focusSub = nav.addListener('focus', async () => {
      try {
        await ScreenOrientation.unlockAsync();
        await Audio.setAudioModeAsync({ playsInSilentModeIOS: true, staysActiveInBackground: true, shouldDuckAndroid: true });
        // If we just replaced into this screen, ensure playback starts and orientation is landscape
        if (isReplacingRef.current) {
          isReplacingRef.current = false;
          try { await ScreenOrientation.unlockAsync(); } catch {}
          try { await videoRef.current?.playAsync?.(); } catch {}
        }
      } catch {}
    });

    const blurSub = nav.addListener('blur', async () => {
      try {
        await videoRef.current?.pauseAsync?.();
      } catch {}
    });

    return () => { unsubscribe(); focusSub(); blurSub(); };
  }, [nav, params.ratingKey]);

  // Auto-hide controls
  const resetControlsTimeout = () => {
    if (controlsTimeout.current) clearTimeout(controlsTimeout.current);
    setShowControls(true);
    controlsTimeout.current = setTimeout(() => {
      setShowControls(false);
    }, 4000);
  };

  useEffect(() => {
    if (isPlaying) {
      resetControlsTimeout();
    }
  }, [isPlaying]);

  // Listen for dimension changes
  useEffect(() => {
    const subscription = Dimensions.addEventListener('change', ({ window }) => {
      setDimensions({ width: window.width, height: window.height });
    });

    return () => subscription?.remove();
  }, []);

  // Next episode countdown logic
  useEffect(() => {
    if (metadata?.type !== 'episode' || !nextEpisode || !duration) {
      setNextEpisodeCountdown(null);
      return;
    }

    const creditsMarker = markers.find(m => m.type === 'credits');
    const triggerStart = creditsMarker ? (creditsMarker.startTimeOffset / 1000) : Math.max(0, duration - 30000) / 1000;

    if (position / 1000 >= triggerStart) {
      const remaining = Math.max(0, Math.ceil((duration - position) / 1000));
      setNextEpisodeCountdown(remaining);
    } else {
      setNextEpisodeCountdown(null);
    }
  }, [metadata, nextEpisode, duration, position, markers]);

  // Auto-play next episode
  useEffect(() => {
    if (nextEpisodeCountdown !== null && nextEpisodeCountdown <= 0 && nextEpisode) {
      playNext();
    }
  }, [nextEpisodeCountdown, nextEpisode, playNext]);

  // Movie end handling
  useEffect(() => {
    if (metadata?.type !== 'movie' || !duration) return;

    const creditsMarker = markers.find(m => m.type === 'credits');
    const creditsStart = creditsMarker ? (creditsMarker.startTimeOffset / 1000) : Math.max(0, duration - 30000) / 1000;

    if (position / 1000 > 1 && position / 1000 >= creditsStart) {
      nav.goBack();
    }
  }, [metadata, duration, position, markers, nav]);

  const onPlaybackStatusUpdate = (status: AVPlaybackStatus) => {
    if (!status.isLoaded) {
      if (status.error) {
        console.error('[Player] Playback error:', status.error);
        setError(`Playback error: ${status.error}`);
      }
      return;
    }

    setIsPlaying(status.isPlaying);
    setDuration(status.durationMillis || 0);
    if (!isScrubbing) {
      setPosition(status.positionMillis || 0);
    }
    setBuffering(status.isBuffering);
  };

  const togglePlayPause = async () => {
    if (!videoRef.current) return;
    if (isPlaying) {
      await videoRef.current.pauseAsync();
    } else {
      await videoRef.current.playAsync();
    }
  };

  const skip = async (seconds: number) => {
    if (!videoRef.current) return;
    const newPosition = Math.max(0, Math.min(duration, position + seconds * 1000));
    await videoRef.current.setPositionAsync(newPosition);
  };

  const skipMarker = async (marker: { type: string; startTimeOffset: number; endTimeOffset: number }) => {
    if (!videoRef.current) return;
    await videoRef.current.setPositionAsync(marker.endTimeOffset + 1000);
  };

  const restart = async () => {
    if (!videoRef.current) return;
    await videoRef.current.setPositionAsync(0);
    await videoRef.current.playAsync();
  };

  const cleanup = useCallback(async () => {
    const { plexBaseUrl: baseUrl, plexToken: token, sessionId: sid } = cleanupInfoRef.current;

    if (baseUrl && token && sid) {
      try {
        const stopUrl = `${baseUrl}/video/:/transcode/universal/stop?session=${sid}&X-Plex-Token=${token}`;
        await fetch(stopUrl);
        console.log('[Player] Stopped transcode session:', sid);
      } catch (e) {
        console.warn('[Player] Failed to stop transcode:', e);
      }
    }

    if (progressInterval.current) clearInterval(progressInterval.current);
    if (controlsTimeout.current) clearTimeout(controlsTimeout.current);
    try {
      await videoRef.current?.stopAsync?.();
    } catch {}
  }, []);

  const playNext = useCallback(async () => {
    if (nextEpisode) {
      // Cleanup current player before navigating
      isReplacingRef.current = true;
      await cleanup();
      // Replace current route using stack action for compatibility
      // @ts-ignore - navigation may not expose replace; use dispatch
      nav.dispatch(StackActions.replace('Player', { type: 'plex', ratingKey: nextEpisode.ratingKey }));
    }
  }, [nextEpisode, cleanup, nav]);

  const currentMarker = markers.find(m =>
    position >= m.startTimeOffset && position <= m.endTimeOffset
  );

  // Pan responder for draggable scrubber
  // PanResponder no longer used; Slider provides built-in seeking UX

  const formatTime = (ms: number) => {
    const totalSeconds = Math.floor(ms / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    if (hours > 0) {
      return `${hours}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
    }
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  };

  if (loading) {
    return (
      <View style={styles.loading}>
        <ActivityIndicator size="large" color="#fff" />
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.error}>
        <Text style={styles.errorText}>{error}</Text>
        <TouchableOpacity onPress={() => nav.goBack()} style={styles.errorButton}>
          <Text style={styles.errorButtonText}>Go Back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <StatusBar hidden />

      {streamUrl ? (
        <Video
          ref={videoRef}
          source={{ uri: streamUrl, headers: api?.token ? { Authorization: `Bearer ${api.token}` } : undefined }}
          style={{ width: dimensions.width, height: dimensions.height }}
          resizeMode={ResizeMode.CONTAIN}
          shouldPlay={true}
          isMuted={false}
          volume={1.0}
          onPlaybackStatusUpdate={onPlaybackStatusUpdate}
          useNativeControls={false}
        />
      ) : null}

      {/* Background tap area to show/hide controls */}
      <View style={styles.tapArea} pointerEvents="box-none">
        <TouchableOpacity style={StyleSheet.absoluteFillObject} activeOpacity={1} onPress={resetControlsTimeout} />
        {/* Controls overlay */}
        {showControls && (
          <>
            {/* Top gradient bar */}
            <LinearGradient
              colors={['rgba(0,0,0,0.7)', 'transparent']}
              style={styles.topGradient}
            >
              <View style={styles.topBar}>
                <TouchableOpacity onPress={() => nav.goBack()} style={styles.backButton}>
                  <Ionicons name="chevron-back" size={32} color="#fff" />
                </TouchableOpacity>
                {metadata && (
                  <View style={styles.titleContainer}>
                    <Text style={styles.title} numberOfLines={1}>
                      {metadata.grandparentTitle || metadata.title}
                    </Text>
                    {metadata.grandparentTitle && (
                      <Text style={styles.subtitle} numberOfLines={1}>
                        {metadata.title}
                      </Text>
                    )}
                  </View>
                )}
                <View style={styles.topIcons}>
                  <TouchableOpacity style={styles.iconButton}>
                    <Ionicons name="search" size={24} color="#fff" />
                  </TouchableOpacity>
                  <TouchableOpacity style={styles.iconButton}>
                    <Ionicons name="ellipsis-horizontal" size={24} color="#fff" />
                  </TouchableOpacity>
                </View>
              </View>
            </LinearGradient>

            {/* Center play controls */}
            <View style={styles.centerControls}>
              <TouchableOpacity onPress={() => skip(-10)} style={styles.skipButton}>
                <Replay10Icon size={48} color="#fff" />
              </TouchableOpacity>

              <TouchableOpacity onPress={togglePlayPause} style={styles.playPauseButton}>
                <Ionicons
                  name={isPlaying ? 'pause' : 'play'}
                  size={50}
                  color="#fff"
                />
              </TouchableOpacity>

              <TouchableOpacity onPress={() => skip(10)} style={styles.skipButton}>
                <Forward10Icon size={48} color="#fff" />
              </TouchableOpacity>
            </View>

            {/* Bottom gradient controls */}
            <LinearGradient
              colors={['transparent', 'rgba(0,0,0,0.8)']}
              style={styles.bottomGradient}
              pointerEvents="box-none"
            >
              {/* Progress bar */}
              <View style={styles.progressSection} pointerEvents="box-none">
                <Slider
                  style={{ width: '100%', height: 28 }}
                  minimumValue={0}
                  maximumValue={Math.max(1, duration)}
                  value={Math.max(0, Math.min(duration, position))}
                  minimumTrackTintColor="#fff"
                  maximumTrackTintColor="rgba(255,255,255,0.3)"
                  thumbTintColor="#fff"
                  onSlidingStart={() => setIsScrubbing(true)}
                  onValueChange={(val: number) => setPosition(val)}
                  onSlidingComplete={async (val: number) => {
                    if (videoRef.current) {
                      await videoRef.current.setPositionAsync(Math.max(0, Math.min(duration, val)));
                    }
                    setIsScrubbing(false);
                  }}
                />
                <View style={styles.timeContainer} pointerEvents="none">
                  <Text style={styles.timeText}>{formatTime(position)}</Text>
                  <Text style={styles.timeText}>{formatTime(duration - position)}</Text>
                </View>
              </View>

              {/* Bottom action buttons */}
              <View style={styles.bottomActions}>
                <TouchableOpacity onPress={restart} style={styles.actionButton}>
                  <Ionicons name="play-skip-back" size={18} color="#fff" />
                  <Text style={styles.actionText}>RESTART</Text>
                </TouchableOpacity>

                {metadata?.type === 'episode' && (
                  <TouchableOpacity onPress={playNext} style={[styles.actionButton, !nextEpisode && styles.actionButtonDisabled]}>
                    <Ionicons name="play-skip-forward" size={18} color={nextEpisode ? "#fff" : "#666"} />
                    <Text style={[styles.actionText, !nextEpisode && styles.actionTextDisabled]}>PLAY NEXT</Text>
                  </TouchableOpacity>
                )}
              </View>
            </LinearGradient>
          </>
        )}

        {/* Skip Intro/Credits button */}
        {currentMarker && (
          <View style={styles.skipMarkerContainer}>
            <TouchableOpacity
              onPress={() => skipMarker(currentMarker)}
              style={styles.skipMarkerButton}
            >
              <Ionicons name="play-skip-forward" size={20} color="#000" />
              <Text style={styles.skipMarkerText}>
                SKIP {currentMarker.type === 'intro' ? 'INTRO' : currentMarker.type === 'credits' ? 'CREDITS' : 'MARKER'}
              </Text>
            </TouchableOpacity>
          </View>
        )}

        {/* Next episode countdown */}
        {nextEpisodeCountdown !== null && nextEpisode && (
          <View style={styles.nextEpisodeContainer}>
            <View style={styles.nextEpisodeCard}>
              <TouchableOpacity
                style={styles.nextEpisodeInfo}
                onPress={playNext}
                activeOpacity={0.7}
              >
                <View style={styles.nextEpisodeThumbnail}>
                  {nextEpisode.thumb && api ? (
                    <ExpoImage
                      source={{
                        uri: `${api.baseUrl}/api/image/plex?path=${encodeURIComponent(nextEpisode.thumb)}&w=300&h=169&f=webp`,
                        headers: api.token ? { Authorization: `Bearer ${api.token}` } : undefined,
                      }}
                      style={{ width: '100%', height: '100%', borderRadius: 4 }}
                      contentFit="cover"
                    />
                  ) : (
                    <Ionicons name="play-circle" size={40} color="#fff" />
                  )}
                </View>
                <View style={styles.nextEpisodeDetails}>
                  <Text style={styles.nextEpisodeOverline} numberOfLines={1}>
                    {nextEpisode.episodeLabel ? `${nextEpisode.episodeLabel} •` : ''} NEXT EPISODE • Playing in {nextEpisodeCountdown}s
                  </Text>
                  <Text style={styles.nextEpisodeTitle} numberOfLines={1}>
                    {nextEpisode.title}
                  </Text>
                </View>
              </TouchableOpacity>
              <TouchableOpacity
                onPress={() => nav.goBack()}
                style={styles.seeAllButton}
              >
                <Text style={styles.seeAllText}>SEE ALL EPISODES</Text>
              </TouchableOpacity>
            </View>
          </View>
        )}

        {/* Buffering indicator */}
        {buffering && (
          <View style={styles.bufferingContainer}>
          <ActivityIndicator size="large" color="#fff" />
        </View>
      )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  loading: {
    flex: 1,
    backgroundColor: '#000',
    alignItems: 'center',
    justifyContent: 'center',
  },
  error: {
    flex: 1,
    backgroundColor: '#000',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
  },
  errorText: {
    color: '#fff',
    fontSize: 16,
    textAlign: 'center',
    marginBottom: 20,
  },
  errorButton: {
    backgroundColor: '#e50914',
    paddingHorizontal: 30,
    paddingVertical: 12,
    borderRadius: 4,
  },
  errorButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '700',
  },
  tapArea: {
    ...StyleSheet.absoluteFillObject,
  },
  topGradient: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    paddingTop: 50,
    paddingBottom: 20,
  },
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
  },
  backButton: {
    padding: 4,
  },
  titleContainer: {
    flex: 1,
    marginLeft: 12,
  },
  title: {
    color: '#fff',
    fontSize: 20,
    fontWeight: '700',
  },
  subtitle: {
    color: '#ccc',
    fontSize: 14,
    marginTop: 2,
  },
  topIcons: {
    flexDirection: 'row',
    gap: 16,
  },
  iconButton: {
    padding: 4,
  },
  centerControls: {
    position: 'absolute',
    top: '50%',
    left: 0,
    right: 0,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 60,
    transform: [{ translateY: -40 }],
  },
  skipButton: {
    position: 'relative',
    alignItems: 'center',
  },
  skipLabel: {
    position: 'absolute',
    bottom: -2,
    color: '#fff',
    fontSize: 11,
    fontWeight: '700',
  },
  playPauseButton: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: 'rgba(255, 255, 255, 0.15)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  bottomGradient: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    paddingBottom: 30,
    paddingHorizontal: 16,
  },
  progressSection: {
    marginBottom: 16,
  },
  // legacy styles (unused now that we use Slider) kept minimal in case of fallback
  timeContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 8,
  },
  timeText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
  },
  bottomActions: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 24,
  },
  actionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingVertical: 8,
    paddingHorizontal: 16,
  },
  actionText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: 0.5,
  },
  actionButtonDisabled: {
    opacity: 0.5,
  },
  actionTextDisabled: {
    color: '#666',
  },
  skipMarkerContainer: {
    position: 'absolute',
    bottom: 140,
    right: 20,
  },
  skipMarkerButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: '#fff',
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderRadius: 4,
  },
  skipMarkerText: {
    color: '#000',
    fontSize: 14,
    fontWeight: '700',
    letterSpacing: 0.5,
  },
  nextEpisodeContainer: {
    position: 'absolute',
    bottom: 60,
    left: 20,
    right: 20,
    zIndex: 5,
  },
  nextEpisodeCard: {
    backgroundColor: 'transparent',
    borderRadius: 8,
    overflow: 'hidden',
    flexDirection: 'row',
    alignItems: 'center',
    paddingRight: 12,
  },
  nextEpisodeInfo: {
    flexDirection: 'row',
    padding: 16,
    gap: 12,
    flex: 1,
  },
  nextEpisodeThumbnail: {
    width: 92,
    height: 52,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    borderRadius: 4,
    alignItems: 'center',
    justifyContent: 'center',
  },
  nextEpisodeDetails: {
    flex: 1,
    justifyContent: 'center',
  },
  nextEpisodeOverline: {
    color: '#ddd',
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 0.4,
    marginBottom: 2,
  },
  nextEpisodeTitle: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '800',
  },
  seeAllButton: {
    borderWidth: 2,
    borderColor: '#fff',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 6,
    alignItems: 'center',
    justifyContent: 'center',
  },
  seeAllText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '900',
    letterSpacing: 1,
  },
  bufferingContainer: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
    pointerEvents: 'none',
  },
});
