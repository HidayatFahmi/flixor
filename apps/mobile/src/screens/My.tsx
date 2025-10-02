import React, { useEffect, useRef, useState } from 'react';
import { View, Text, Pressable, ActivityIndicator, Linking, Platform } from 'react-native';
import { MobileApi, saveTraktTokens, getTraktTokens } from '../api/client';

let WebBrowser: any = null;
try { WebBrowser = require('expo-web-browser'); } catch {}

export default function My({ api }: { api: MobileApi }) {
  const [loading, setLoading] = useState(true);
  const [profile, setProfile] = useState<any | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [deviceCode, setDeviceCode] = useState<any | null>(null);
  const pollRef = useRef<any>(null);

  useEffect(() => {
    (async () => {
      await refreshProfile();
    })();
    return () => { if (pollRef.current) clearInterval(pollRef.current); };
  }, []);

  async function refreshProfile() {
    setLoading(true);
    setError(null);
    try {
      const p = await api.traktProfile();
      setProfile(p);
    } catch (e: any) {
      setProfile(null);
      // 401 is expected when not connected
    } finally { setLoading(false); }
  }

  async function startAuth() {
    try {
      setError(null);
      const dc = await api.traktDeviceCode();
      setDeviceCode(dc);
      // Open verification URL
      try {
        if (WebBrowser && WebBrowser.openBrowserAsync) await WebBrowser.openBrowserAsync(dc.verification_url);
        else Linking.openURL(dc.verification_url);
      } catch {}
      // Start polling
      if (pollRef.current) clearInterval(pollRef.current);
      pollRef.current = setInterval(async () => {
        try {
          const res = await api.traktPollToken(dc.device_code);
          if (res && (res.ok || res.access_token)) {
            // Persist tokens locally (optional; server keeps canonical copy)
            await saveTraktTokens(res.tokens || res);
            clearInterval(pollRef.current);
            setDeviceCode(null);
            await refreshProfile();
          }
        } catch (err: any) {
          const msg = String(err?.message || '');
          if (msg.includes('expired')) {
            clearInterval(pollRef.current);
            setDeviceCode(null);
            setError('Device code expired. Please try again.');
          }
        }
      }, Math.max(5, Number(dc.interval || 5)) * 1000);
      // Auto-expire
      setTimeout(() => { try { if (pollRef.current) clearInterval(pollRef.current); } catch {} }, Math.max(30, Number(dc.expires_in || 600)) * 1000);
    } catch (e: any) {
      setError(e?.message || 'Failed to start Trakt auth');
    }
  }

  const Card = ({ children }: { children: any }) => (
    <View style={{ backgroundColor: '#0f0f12', borderRadius: 16, padding: 16, borderWidth: 1, borderColor: '#1f2030', marginBottom: 16 }}>
      {children}
    </View>
  );

  if (loading) {
    return (
      <View style={{ flex:1, backgroundColor:'#000', alignItems:'center', justifyContent:'center' }}>
        <ActivityIndicator color="#fff" />
      </View>
    );
  }

  return (
    <View style={{ flex:1, backgroundColor:'#000', padding: 16 }}>
      <Text style={{ color:'#fff', fontSize:22, fontWeight:'800', marginBottom: 8 }}>My</Text>
      {error ? (
        <Card><Text style={{ color:'#ff8a80' }}>{error}</Text></Card>
      ) : null}

      {profile ? (
        <Card>
          <Text style={{ color:'#fff', fontSize:18, fontWeight:'800', marginBottom: 6 }}>Trakt Connected</Text>
          <Text style={{ color:'#bbb' }}>@{profile?.username || profile?.ids?.slug}</Text>
          <Text style={{ color:'#888', marginTop: 8 }}>Personalized rows are enabled on Home.</Text>
        </Card>
      ) : (
        <Card>
          <Text style={{ color:'#fff', fontSize:18, fontWeight:'800', marginBottom: 6 }}>Connect Trakt</Text>
          <Text style={{ color:'#bbb', marginBottom: 12 }}>Sign in to Trakt to enable Watchlist, Recently Watched, and Recommendations.</Text>
          {deviceCode ? (
            <>
              <Text style={{ color:'#ddd', marginBottom: 6 }}>1) Open: {deviceCode.verification_url}</Text>
              <Text style={{ color:'#ddd', marginBottom: 12 }}>2) Enter code: {deviceCode.user_code}</Text>
              <Pressable onPress={()=> Linking.openURL(deviceCode.verification_url)} style={{ backgroundColor:'#1f2430', paddingVertical: 10, borderRadius: 10, alignItems:'center', marginBottom: 8 }}>
                <Text style={{ color:'#fff', fontWeight:'700' }}>Open Verification Page</Text>
              </Pressable>
              <Text style={{ color:'#888' }}>Waiting for authorization…</Text>
            </>
          ) : (
            <Pressable onPress={startAuth} style={{ backgroundColor:'#fff', paddingVertical: 12, borderRadius: 12, alignItems:'center' }}>
              <Text style={{ color:'#000', fontWeight:'900' }}>Connect Trakt</Text>
            </Pressable>
          )}
        </Card>
      )}

      <Text style={{ color:'#666', marginTop: 8 }}>Tip: After connecting, return to Home to see personalized rows populate.</Text>
    </View>
  );
}
