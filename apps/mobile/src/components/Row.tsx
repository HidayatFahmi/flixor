import React from 'react';
import { View, Text, FlatList, Pressable } from 'react-native';
import Poster from './Poster';
import * as Haptics from 'expo-haptics';

export default function Row({ title, items, getImageUri, getTitle, authHeaders, onItemPress, onTitlePress }: {
  title: string;
  items: any[];
  getImageUri: (item: any) => string | undefined;
  getTitle: (item: any) => string | undefined;
  authHeaders?: Record<string,string>;
  onItemPress?: (item: any) => void;
  onTitlePress?: () => void;
}) {
  const handleTitlePress = () => {
    if (onTitlePress) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      onTitlePress();
    }
  };

  return (
    <View style={{ marginBottom: 16 }}>
      <Pressable onPress={handleTitlePress} disabled={!onTitlePress}>
        <Text style={{ color: '#fff', fontSize: 16, fontWeight: '700', marginBottom: 8 }}>{title}</Text>
      </Pressable>
      <FlatList
        horizontal
        data={items}
        keyExtractor={(_, idx) => String(idx)}
        renderItem={({ item }) => (
          <Poster uri={getImageUri(item)} title={getTitle(item)} authHeaders={authHeaders} onPress={() => onItemPress && onItemPress(item)} />
        )}
        showsHorizontalScrollIndicator={false}
      />
    </View>
  );
}
