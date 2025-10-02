import React, { useEffect, useState, useRef } from 'react';
import { View, Text, TouchableOpacity, ActivityIndicator, StyleSheet, StatusBar, Dimensions } from 'react-native';
import { Video, ResizeMode, AVPlaybackStatus, Audio } from 'expo-av';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import * as ScreenOrientation from 'expo-screen-orientation';
import { MobileApi } from '../api/client';

type RouteParams = {
  route?: {
    params?: {
      type: 'plex' | 'tmdb';
      ratingKey?: string;
      id?: string;
    };
  };
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

  // Store cleanup info in refs so we can access latest values in cleanup without re-running effect
  const cleanupInfoRef = useRef({ plexBaseUrl: '', plexToken: '', sessionId: '' });

  useEffect(() => {
    (async () => {
      // Configure audio session for video playback
      try {
        await Audio.setAudioModeAsync({
          playsInSilentModeIOS: true,
          staysActiveInBackground: true,
          shouldDuckAndroid: true,
        });
      } catch (e) {
        console.warn('[Player] Failed to set audio mode:', e);
      }

      // Enable landscape orientation for video playback
      try {
        await ScreenOrientation.unlockAsync();
      } catch (e) {
        console.warn('[Player] Failed to unlock orientation:', e);
      }

      const a = await MobileApi.load();
      setApi(a);

      if (params.type === 'plex' && params.ratingKey && a) {
        try {
          // Fetch metadata - backend returns the metadata object directly (already unwrapped)
          const m = await a.get(`/api/plex/metadata/${encodeURIComponent(params.ratingKey)}`);
          console.log('[Player] Raw metadata response:', m ? { title: m.title, type: m.type, hasMedia: !!m.Media } : 'null');
          setMetadata(m);

          // Get Plex servers list
          const serversRes = await a.get('/api/plex/servers');
          const servers = Array.isArray(serversRes) ? serversRes : [];
          const activeServer = servers.find((s: any) => s.isActive);

          if (!activeServer) {
            setError('No active Plex server configured');
            setLoading(false);
            return;
          }

          console.log('[Player] Active server:', activeServer);

          // Get server connections
          const connRes = await a.get(`/api/plex/servers/${encodeURIComponent(activeServer.id)}/connections`);
          const connections = connRes?.connections || [];

          // Prefer local connection, then first available
          const selectedConnection = connections.find((c: any) => c.local) || connections[0];

          if (!selectedConnection) {
            setError('No Plex server connection available');
            setLoading(false);
            return;
          }

          console.log('[Player] Selected connection:', selectedConnection);

          const baseUrl = selectedConnection.uri.replace(/\/$/, '');
          setPlexBaseUrl(baseUrl);
          cleanupInfoRef.current.plexBaseUrl = baseUrl;

          // Get Plex token from backend auth endpoint
          const authRes = await a.get('/api/auth/servers');
          const authServers = Array.isArray(authRes) ? authRes : [];
          console.log('[Player] Auth servers:', authServers.map((s: any) => ({ name: s.name, clientId: s.clientIdentifier })));

          // Match by clientIdentifier (which is the same as server id/machineIdentifier)
          const serverWithToken = authServers.find((s: any) =>
            s.clientIdentifier === activeServer.id ||
            s.clientIdentifier === activeServer.machineIdentifier
          );
          const token = serverWithToken?.token;
          setPlexToken(token || '');
          cleanupInfoRef.current.plexToken = token || '';

          if (!token) {
            console.error('[Player] Could not find token. Active server id:', activeServer.id);
            console.error('[Player] Available servers:', authServers);
            setError('Could not get Plex access token');
            setLoading(false);
            return;
          }

          console.log('[Player] Got Plex token');
          console.log('[Player] Metadata:', { title: m?.title, type: m?.type, mediaCount: m?.Media?.length });

          const media = (m?.Media || [])[0];
          console.log('[Player] Media object:', media ? { id: media.id, partCount: media.Part?.length } : 'none');

          const part = media?.Part?.[0];
          console.log('[Player] Part object:', part ? { id: part.id, key: part.key } : 'none');

          if (part?.key) {
            // For mobile, request HLS stream (Plex will transcode if needed)
            // Use universal decision endpoint to get optimal stream
            const partId = part.id;
            const sid = Math.random().toString(36).substring(2, 15);
            setSessionId(sid);
            cleanupInfoRef.current.sessionId = sid;

            // Request decision from Plex (will choose direct play or transcode)
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

            console.log('[Player] Requesting decision from:', decisionUrl);

            try {
              const decisionRes = await fetch(`${decisionUrl}?${decisionParams.toString()}`);
              const decisionData = await decisionRes.text();
              console.log('[Player] Decision response:', decisionData.substring(0, 500));

              // Check decision code: 1000 = direct play approved, 3000 = transcode needed
              // directPlayDecisionCode="1000" means direct play is OK
              const canDirectPlay = decisionData.includes('directPlayDecisionCode="1000"');

              if (canDirectPlay) {
                // Direct play - use the file URL
                const directUrl = `${baseUrl}${part.key}?X-Plex-Token=${token}`;
                console.log('[Player] Using direct play:', directUrl);
                setStreamUrl(directUrl);
              } else {
                // Transcode - start transcode session first, then use HLS stream
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

                // First, start the transcode session
                const startUrl = `${baseUrl}/video/:/transcode/universal/start.m3u8?${transcodeParams.toString()}`;
                console.log('[Player] Starting transcode session:', startUrl);

                try {
                  await fetch(startUrl);
                  // Session started, now use the session playlist URL
                  const hlsUrl = `${baseUrl}/video/:/transcode/universal/session/${sid}/base/index.m3u8?X-Plex-Token=${token}`;
                  console.log('[Player] Using HLS transcode session:', hlsUrl);
                  setStreamUrl(hlsUrl);
                } catch (startErr) {
                  console.error('[Player] Failed to start transcode:', startErr);
                  // Fallback to direct start URL
                  setStreamUrl(startUrl);
                }
              }
            } catch (err) {
              console.error('[Player] Decision failed, falling back to HLS transcode:', err);
              const hlsUrl = `${baseUrl}/video/:/transcode/universal/start.m3u8?${decisionParams.toString()}`;
              setStreamUrl(hlsUrl);
            }

            // Set resume position if available
            if (m?.viewOffset) {
              const resumeMs = parseInt(String(m.viewOffset));
              console.log('[Player] Setting resume position:', resumeMs);
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
            console.error('[Player] No part.key found. Full metadata:', JSON.stringify(m, null, 2));
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
      // Cleanup on unmount - use refs to get latest values without re-running effect
      (async () => {
        const { plexBaseUrl: baseUrl, plexToken: token, sessionId: sid } = cleanupInfoRef.current;

        // Stop transcode session if active
        if (baseUrl && token && sid) {
          try {
            const stopUrl = `${baseUrl}/video/:/transcode/universal/stop?session=${sid}&X-Plex-Token=${token}`;
            await fetch(stopUrl);
            console.log('[Player] Stopped transcode session:', sid);
          } catch (e) {
            console.warn('[Player] Failed to stop transcode:', e);
          }
        }

        // Lock orientation back to portrait
        try {
          await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP);
        } catch (e) {
          console.warn('[Player] Failed to lock orientation:', e);
        }

        // Reset audio mode
        try {
          await Audio.setAudioModeAsync({
            playsInSilentModeIOS: false,
            staysActiveInBackground: false,
            shouldDuckAndroid: false,
          });
        } catch (e) {
          console.warn('[Player] Failed to reset audio mode:', e);
        }
      })();

      if (progressInterval.current) clearInterval(progressInterval.current);
      if (controlsTimeout.current) clearTimeout(controlsTimeout.current);
    };
  }, []);

  // Update progress to Plex periodically (timeline updates)
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
          const res = await fetch(url);
          if (!res.ok) {
            console.warn('[Player] Timeline update failed:', res.status);
          }
        } catch (e) {
          console.error('[Player] Progress update failed:', e);
        }
      }
    };

    progressInterval.current = setInterval(updateProgress, 10000); // Update every 10 seconds

    // Update immediately on play/pause
    updateProgress();

    return () => {
      if (progressInterval.current) clearInterval(progressInterval.current);
    };
  }, [plexBaseUrl, plexToken, sessionId, params.ratingKey, position, duration, isPlaying]);

  // Cleanup when navigating away or app goes to background
  useEffect(() => {
    const cleanup = async () => {
      const { plexBaseUrl: baseUrl, plexToken: token, sessionId: sid } = cleanupInfoRef.current;

      if (!baseUrl || !token) return;

      // Send stopped timeline update to Plex
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
          const timelineUrl = `${baseUrl}/:/timeline?${timelineParams.toString()}`;
          await fetch(timelineUrl);
          console.log('[Player] Sent stopped timeline update');
        } catch (e) {
          console.warn('[Player] Failed to send stopped timeline:', e);
        }
      }

      // Stop transcode session
      if (sid) {
        try {
          const stopUrl = `${baseUrl}/video/:/transcode/universal/stop?session=${sid}&X-Plex-Token=${token}`;
          await fetch(stopUrl);
          console.log('[Player] Stopped transcode session on navigation:', sid);
        } catch (e) {
          console.warn('[Player] Failed to stop transcode:', e);
        }
      }

      // Lock orientation back to portrait
      try {
        await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP);
      } catch (e) {
        console.warn('[Player] Failed to lock orientation:', e);
      }

      // Reset audio mode
      try {
        await Audio.setAudioModeAsync({
          playsInSilentModeIOS: false,
          staysActiveInBackground: false,
          shouldDuckAndroid: false,
        });
      } catch (e) {
        console.warn('[Player] Failed to reset audio mode:', e);
      }
    };

    // Listen for navigation blur (when leaving the screen)
    const unsubscribe = nav.addListener('beforeRemove', () => {
      cleanup();
    });

    return unsubscribe;
  }, [nav, params.ratingKey]);

  // Auto-hide controls
  const resetControlsTimeout = () => {
    if (controlsTimeout.current) clearTimeout(controlsTimeout.current);
    setShowControls(true);
    controlsTimeout.current = setTimeout(() => {
      setShowControls(false);
    }, 3000);
  };

  useEffect(() => {
    if (isPlaying) {
      resetControlsTimeout();
    }
  }, [isPlaying]);

  // Listen for dimension changes (rotation)
  useEffect(() => {
    const subscription = Dimensions.addEventListener('change', ({ window }) => {
      setDimensions({ width: window.width, height: window.height });
    });

    return () => subscription?.remove();
  }, []);

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
    setPosition(status.positionMillis || 0);
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

  const seekTo = async (value: number) => {
    if (!videoRef.current) return;
    await videoRef.current.setPositionAsync(value);
  };

  const skip = async (seconds: number) => {
    if (!videoRef.current) return;
    const newPosition = Math.max(0, Math.min(duration, position + seconds * 1000));
    await videoRef.current.setPositionAsync(newPosition);
  };

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

      {/* Tap area to show/hide controls */}
      <TouchableOpacity
        style={styles.tapArea}
        activeOpacity={1}
        onPress={resetControlsTimeout}
      >
        {/* Controls overlay */}
        {showControls && (
          <View style={styles.controls}>
            {/* Top bar */}
            <View style={styles.topBar}>
              <TouchableOpacity onPress={() => nav.goBack()} style={styles.backButton}>
                <Ionicons name="arrow-back" size={28} color="#fff" />
              </TouchableOpacity>
              {metadata && (
                <View style={styles.titleContainer}>
                  <Text style={styles.title}>{metadata.title}</Text>
                  {metadata.grandparentTitle && (
                    <Text style={styles.subtitle}>{metadata.grandparentTitle}</Text>
                  )}
                </View>
              )}
            </View>

            {/* Center controls */}
            <View style={styles.centerControls}>
              <TouchableOpacity onPress={() => skip(-10)} style={styles.controlButton}>
                <Ionicons name="play-back" size={40} color="#fff" />
                <Text style={styles.skipText}>10</Text>
              </TouchableOpacity>

              <TouchableOpacity onPress={togglePlayPause} style={styles.playButton}>
                <Ionicons
                  name={isPlaying ? 'pause' : 'play'}
                  size={60}
                  color="#fff"
                />
              </TouchableOpacity>

              <TouchableOpacity onPress={() => skip(10)} style={styles.controlButton}>
                <Ionicons name="play-forward" size={40} color="#fff" />
                <Text style={styles.skipText}>10</Text>
              </TouchableOpacity>
            </View>

            {/* Bottom bar with progress */}
            <View style={styles.bottomBar}>
              <Text style={styles.timeText}>{formatTime(position)}</Text>

              <View style={styles.progressContainer}>
                <View style={styles.progressBar}>
                  <View
                    style={[
                      styles.progressFill,
                      { width: duration > 0 ? `${(position / duration) * 100}%` : '0%' }
                    ]}
                  />
                </View>
              </View>

              <Text style={styles.timeText}>{formatTime(duration)}</Text>
            </View>
          </View>
        )}

        {/* Buffering indicator */}
        {buffering && (
          <View style={styles.bufferingContainer}>
            <ActivityIndicator size="large" color="#fff" />
          </View>
        )}
      </TouchableOpacity>
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
  controls: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.3)',
    justifyContent: 'space-between',
  },
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingTop: 50,
    paddingHorizontal: 20,
  },
  backButton: {
    padding: 10,
  },
  titleContainer: {
    flex: 1,
    marginLeft: 10,
  },
  title: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
  },
  subtitle: {
    color: '#ccc',
    fontSize: 14,
    marginTop: 2,
  },
  centerControls: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 60,
  },
  controlButton: {
    position: 'relative',
  },
  playButton: {
    padding: 20,
  },
  skipText: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    textAlign: 'center',
    color: '#fff',
    fontSize: 12,
    fontWeight: '700',
  },
  bottomBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingBottom: 30,
    paddingHorizontal: 20,
  },
  timeText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  progressContainer: {
    flex: 1,
    marginHorizontal: 15,
    justifyContent: 'center',
  },
  progressBar: {
    height: 4,
    backgroundColor: '#666',
    borderRadius: 2,
  },
  progressFill: {
    height: '100%',
    backgroundColor: '#fff',
    borderRadius: 2,
  },
  bufferingContainer: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
    pointerEvents: 'none',
  },
});
