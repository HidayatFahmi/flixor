import React from 'react';
import { View, Text, Pressable, Alert } from 'react-native';
import { Ionicons } from '@expo/vector-icons';

let ExpoImage: any = null;
try { ExpoImage = require('expo-image').Image; } catch {}

type Hero = {
  title: string;
  subtitle?: string; // e.g., "#2 in Movies Today"
  imageUri?: string;
};

export default function HeroCard({ hero, authHeaders, onPlay, onAdd }: { hero: Hero; authHeaders?: Record<string,string>; onPlay?: ()=>void; onAdd?: ()=>void }) {
  return (
    <View style={{ paddingHorizontal: 16, paddingTop: 10 }}>
      <View style={{ borderRadius: 18, overflow: 'hidden', backgroundColor: '#111', shadowColor: '#000', shadowOpacity: 0.35, shadowRadius: 12, shadowOffset: { width: 0, height: 6 }, elevation: 8 }}>
        <View style={{ width: '100%', aspectRatio: 0.72 }}>
          {hero.imageUri && ExpoImage ? (
            <ExpoImage source={{ uri: hero.imageUri, headers: authHeaders }} style={{ width: '100%', height: '100%' }} contentFit="cover" />
          ) : (
            <View style={{ flex:1, alignItems:'center', justifyContent:'center' }}>
              <Text style={{ color:'#666' }}>No Artwork</Text>
            </View>
          )}

          {/* Soft vignette at bottom for button legibility */}
          <View style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: '45%', backgroundColor: 'rgba(0,0,0,0.35)' }} />
        </View>
      </View>

      {hero.subtitle ? (
        <Text style={{ color: '#ccc', textAlign: 'center', marginTop: 12 }}>{hero.subtitle}</Text>
      ) : null}

      <View style={{ flexDirection: 'row', justifyContent: 'center', marginTop: 12, gap: 12 }}>
        <Pressable onPress={onPlay || (()=>Alert.alert('Play', 'TODO'))} style={{ backgroundColor: '#fff', paddingVertical: 10, paddingHorizontal: 22, borderRadius: 10, flexDirection: 'row', alignItems: 'center' }}>
          <Ionicons name="play" size={16} color="#000" style={{ marginRight: 6 }} />
          <Text style={{ color: '#000', fontWeight: '800' }}>Play</Text>
        </Pressable>
        <Pressable onPress={onAdd || (()=>Alert.alert('My List', 'TODO'))} style={{ backgroundColor: '#222', paddingVertical: 10, paddingHorizontal: 16, borderRadius: 10 }}>
          <Text style={{ color: '#fff', fontWeight: '800' }}>+  My List</Text>
        </Pressable>
      </View>
    </View>
  );
}
