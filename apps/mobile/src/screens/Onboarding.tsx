import React, { useState } from 'react';
import { View, Text, TextInput, Pressable, ActivityIndicator, Alert } from 'react-native';
import { MobileApi, saveBaseUrl } from '../api/client';

export default function Onboarding({ onConnected }: { onConnected: (api: MobileApi) => void }) {
  const [base, setBase] = useState('http://192.168.1.2:3001');
  const [busy, setBusy] = useState(false);

  const test = async () => {
    try {
      console.log('[Onboarding] Testing base URL', base);
      setBusy(true);
      const api = new MobileApi(base.replace(/\/$/, ''));
      const health = await api.health();
      console.log('[Onboarding] Health response', health);
      if (!health || health.status !== 'healthy') throw new Error('Unhealthy');
      await saveBaseUrl(api.baseUrl);
      console.log('[Onboarding] Saved base URL', api.baseUrl);
      onConnected(api);
    } catch (e: any) {
      console.log('[Onboarding] Test failed', e?.message || e);
      Alert.alert('Connection failed', e?.message || 'Unable to reach backend');
    } finally {
      setBusy(false);
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
      <Text style={{ color: '#fff', fontSize: 24, fontWeight: '800', marginBottom: 12 }}>Connect to Flixor Server</Text>
      <Text style={{ color: '#bbb', fontSize: 14, marginBottom: 24, textAlign: 'center' }}>
        Enter your backend URL (e.g., http://192.168.1.10:3001)
      </Text>
      <TextInput
        value={base}
        onChangeText={setBase}
        placeholder="http://<ip>:3001"
        placeholderTextColor="#666"
        autoCapitalize="none"
        keyboardType="url"
        style={{ width: '100%', maxWidth: 520, borderWidth: 1, borderColor: '#333', color: '#fff', padding: 12, borderRadius: 8 }}
      />
      <Pressable onPress={test} style={{ marginTop: 16, backgroundColor: '#e50914', paddingHorizontal: 16, paddingVertical: 12, borderRadius: 8 }}>
        {busy ? <ActivityIndicator color="#fff"/> : <Text style={{ color: '#fff', fontWeight: '700' }}>Test & Continue</Text>}
      </Pressable>
    </View>
  );
}
