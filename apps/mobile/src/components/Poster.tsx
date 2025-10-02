import React from 'react';
import { View, Text, Pressable } from 'react-native';

let ExpoImage: any = null;
try {
  // Lazy require to avoid hard dependency if not installed yet
  ExpoImage = require('expo-image').Image;
} catch {}

export default function Poster({ uri, title, width = 110, height = 165, authHeaders, onPress }: { uri?: string; title?: string; width?: number; height?: number; authHeaders?: Record<string,string>; onPress?: ()=>void }) {
  const border = { borderRadius: 8, overflow: 'hidden' } as const;
  return (
    <Pressable onPress={onPress} style={{ width, marginRight: 12 }}>
      <View style={[{ width, height, backgroundColor: '#222' }, border]}>
        {uri ? (
          ExpoImage ? (
            <ExpoImage
              source={{ uri, headers: authHeaders }}
              style={{ width: '100%', height: '100%' }}
              contentFit="cover"
              transition={150}
            />
          ) : (
            // Fallback without headers support
            <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
              <Text style={{ color: '#888', fontSize: 12, textAlign: 'center', paddingHorizontal: 8 }}>Install expo-image to show artwork</Text>
            </View>
          )
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
