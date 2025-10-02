import React from 'react';
import { View, Text, Pressable } from 'react-native';
import { Ionicons } from '@expo/vector-icons';

type Props = {
  selected: 'all'|'movies'|'shows';
  onChange: (tab: 'all'|'movies'|'shows') => void;
  onOpenCategories?: () => void;
};

function Pill({ active, label, onPress }: { active?: boolean; label: string; onPress?: () => void }) {
  return (
    <Pressable onPress={onPress} style={{
      paddingHorizontal: 14,
      paddingVertical: 8,
      borderRadius: 999,
      borderWidth: 1,
      borderColor: active ? '#ffffff' : '#4a4a4a',
      backgroundColor: active ? '#ffffff20' : '#1a1a1a',
      marginRight: 10,
    }}>
      <Text style={{ color: '#fff', fontWeight: '600' }}>{label}</Text>
    </Pressable>
  );
}

export default function Pills({ selected, onChange, onOpenCategories }: Props) {
  return (
    <View style={{ flexDirection: 'row', paddingHorizontal: 16, paddingVertical: 8 }}>
      <Pill label="Shows" active={selected === 'shows'} onPress={() => onChange('shows')} />
      <Pill label="Movies" active={selected === 'movies'} onPress={() => onChange('movies')} />
      <Pressable onPress={onOpenCategories} style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 14, paddingVertical: 8, borderRadius: 999, borderWidth: 1, borderColor: '#4a4a4a', backgroundColor: '#1a1a1a' }}>
        <Text style={{ color: '#fff', fontWeight: '600', marginRight: 6 }}>Categories</Text>
        <Ionicons name="chevron-down" color="#fff" size={16} />
      </Pressable>
    </View>
  );
}

