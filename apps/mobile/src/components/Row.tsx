import React from 'react';
import { View, Text, FlatList } from 'react-native';
import Poster from './Poster';

export default function Row({ title, items, getImageUri, getTitle, authHeaders, onItemPress }: {
  title: string;
  items: any[];
  getImageUri: (item: any) => string | undefined;
  getTitle: (item: any) => string | undefined;
  authHeaders?: Record<string,string>;
  onItemPress?: (item: any) => void;
}) {
  return (
    <View style={{ marginBottom: 16 }}>
      <Text style={{ color: '#fff', fontSize: 16, fontWeight: '700', marginBottom: 8 }}>{title}</Text>
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
