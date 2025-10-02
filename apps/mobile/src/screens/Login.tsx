import React, { useEffect, useRef, useState } from 'react';
import { View, Text, Pressable, ActivityIndicator, Linking as RNLinking, Alert, AppState, AppStateStatus } from 'react-native';
import * as Linking from 'expo-linking';
import { MobileApi } from '../api/client';

export default function Login({ api, onAuthed }: { api: MobileApi; onAuthed: (api: MobileApi) => void }) {
  const [pin, setPin] = useState<{ id: number; code: string; authUrl: string; clientId: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const pollRef = useRef<any>(null);

  useEffect(() => {
    return () => { if (pollRef.current) clearInterval(pollRef.current); };
  }, []);

  // When app returns to foreground, re-check the PIN once
  useEffect(() => {
    const sub = AppState.addEventListener('change', async (state: AppStateStatus) => {
      if (state === 'active' && pin) {
        try {
          console.log('[Login] App foreground, re-check PIN');
          const status = await api.checkPin(pin.id, pin.clientId);
          if (status?.authenticated) {
            if (pollRef.current) clearInterval(pollRef.current);
            if (status.token) api.setToken(status.token);
            console.log('[Login] Authenticated on foreground check');
            onAuthed(api);
          }
        } catch {}
      }
    });
    return () => sub.remove();
  }, [pin]);

  const start = async () => {
    try {
      console.log('[Login] Start PIN flow');
      setBusy(true);
      const res = await api.createPin();
      const data = { id: res.id, code: res.code, authUrl: res.authUrl || res.url || res.link, clientId: res.clientId };
      if (!data.authUrl) throw new Error('Missing auth URL');
      setPin(data);
      console.log('[Login] Open Plex auth', { code: data.code, id: data.id });
      // Try in-app auth session so we regain focus and can auto-check
      try {
        const WebBrowser: any = await import('expo-web-browser');
        const redirectUri = Linking.createURL('/');
        await WebBrowser.openAuthSessionAsync(data.authUrl, redirectUri);
        console.log('[Login] Auth session closed');
      } catch {
        // Fallback to opening in external browser
        await RNLinking.openURL(data.authUrl);
        console.log('[Login] Opened external browser');
      }

      if (pollRef.current) clearInterval(pollRef.current);
      pollRef.current = setInterval(async () => {
        try {
          console.log('[Login] Poll PIN status');
          const status = await api.checkPin(data.id, data.clientId);
          if (status?.authenticated) {
            if (pollRef.current) clearInterval(pollRef.current);
            if (status.token) api.setToken(status.token);
            console.log('[Login] Authenticated on poll');
            onAuthed(api);
          }
        } catch {}
      }, 2000);
    } catch (e: any) {
      console.log('[Login] PIN flow error', e?.message || e);
      Alert.alert('Login error', e?.message || 'Failed to start');
    } finally {
      setBusy(false);
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
      <Text style={{ color: '#fff', fontSize: 28, fontWeight: '800', marginBottom: 12 }}>Sign in with Plex</Text>
      {pin && (
        <Text style={{ color: '#bbb', fontSize: 16, marginBottom: 24 }}>Code: <Text style={{ color: '#fff', fontWeight: '800' }}>{pin.code}</Text></Text>
      )}
      <Pressable onPress={start} style={{ backgroundColor: '#e50914', paddingHorizontal: 16, paddingVertical: 12, borderRadius: 8 }}>
        {busy ? <ActivityIndicator color="#fff"/> : <Text style={{ color: '#fff', fontWeight: '700' }}>Continue with Plex</Text>}
      </Pressable>
      {/* Manual re-check CTA in case background polling was paused */}
      {pin && (
        <Pressable onPress={async () => {
          try {
            console.log('[Login] Manual re-check');
            const status = await api.checkPin(pin.id, pin.clientId);
            if (status?.authenticated) {
              if (pollRef.current) clearInterval(pollRef.current);
              if (status.token) api.setToken(status.token);
              console.log('[Login] Authenticated on manual re-check');
              onAuthed(api);
            } else {
              Alert.alert('Still waiting', 'Complete sign‑in in the browser, then return here.');
            }
          } catch (e: any) {
            console.log('[Login] Manual re-check failed', e?.message || e);
            Alert.alert('Check failed', e?.message || 'Please try again');
          }
        }} style={{ marginTop: 12 }}>
          <Text style={{ color: '#999', textDecorationLine: 'underline' }}>I’ve authorized — Check now</Text>
        </Pressable>
      )}
      {pin && (
        <Pressable onPress={() => RNLinking.openURL(pin.authUrl)} style={{ marginTop: 12 }}>
          <Text style={{ color: '#999', textDecorationLine: 'underline' }}>Open Plex sign‑in</Text>
        </Pressable>
      )}
    </View>
  )
}
