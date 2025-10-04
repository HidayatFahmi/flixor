import React from 'react';
import { View, Text, Pressable } from 'react-native';
import { Image as ExpoImage } from 'expo-image';
import * as Haptics from 'expo-haptics';

// Blurhash placeholder for LQIP (Low Quality Image Placeholder)
const BLURHASH_PLACEHOLDER = 'L6PZfSi_.AyE_3t7t7R**0o#DgR4'; // Neutral dark gray

export default function Poster({ uri, title, width = 110, height = 165, authHeaders, onPress }: { uri?: string; title?: string; width?: number; height?: number; authHeaders?: Record<string,string>; onPress?: ()=>void }) {
  const border = { borderRadius: 8, overflow: 'hidden' } as const;

  const handlePress = () => {
    if (onPress) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      onPress();
    }
  };

  return (
    <Pressable onPress={handlePress} style={{ width, marginRight: 12 }} disabled={!onPress}>
      <View style={[{ width, height, backgroundColor: '#222' }, border]}>
        {uri ? (
          <ExpoImage
            source={{ uri, headers: authHeaders }}
            placeholder={{ blurhash: BLURHASH_PLACEHOLDER }}
            style={{ width: '100%', height: '100%' }}
            contentFit="cover"
            transition={200}
            cachePolicy="memory-disk"
            priority="normal"
          />
        ) : (
          <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
            <Text style={{ color: '#555', fontSize: 12 }}>No Image</Text>
          </View>
        )}
      </View>
      {title ? (
        <Text style={{ color: '#ddd', fontSize: 12, marginTop: 6 }} numberOfLines={1}>{title}</Text>
      ) : null}
    </Pressable>
  );
}
