import React from 'react';
import { View, Text, Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import Feather from '@expo/vector-icons/Feather';

export default function HomeHeader({ username, onSearch }: { username?: string; onSearch?: () => void }) {
  return (
    <View style={{ paddingHorizontal: 16, paddingTop: 8, paddingBottom: 6, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
      <Text style={{ color: '#fff', fontSize: 26, fontWeight: '800' }}>For {username || 'You'}</Text>
      <View style={{ flexDirection: 'row', gap: 18 }}>
        <Feather name="cast" size={20} color="#fff" style={{ marginHorizontal: 8 }} />
        <Ionicons name="download-outline" size={22} color="#fff" />
        <Pressable onPress={onSearch}>
          <Ionicons name="search-outline" size={22} color="#fff" />
        </Pressable>
      </View>
    </View>
  );
}

