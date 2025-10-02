import React, { useEffect, useRef } from 'react';
import { Animated, View, Text, StyleSheet, Easing } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import Feather from '@expo/vector-icons/Feather';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { BlurView } from 'expo-blur';
import Pills from './Pills';
import { LinearGradient } from 'expo-linear-gradient';

export default function TopAppBar({ visible, username, showFilters, selected, onChange, onOpenCategories }: {
  visible: boolean;
  username?: string;
  showFilters?: boolean;
  selected?: 'all'|'movies'|'shows';
  onChange?: (t:'all'|'movies'|'shows')=>void;
  onOpenCategories?: ()=>void;
}) {
  const opacity = useRef(new Animated.Value(0)).current;
  const filterOpacity = useRef(new Animated.Value(0)).current;
  const heightAnim = useRef(new Animated.Value(0)).current;
  const blurIntensity = useRef(new Animated.Value(0)).current;
  const insets = useSafeAreaInsets();
  const AnimatedBlurView: any = Animated.createAnimatedComponent(BlurView);
  // Fade-only animation (no drop/slide)

  useEffect(() => {
    Animated.timing(opacity, {
      toValue: visible ? 1 : 0,
      duration: 260,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: false,
    }).start();
    Animated.timing(blurIntensity, {
      toValue: visible ? 90 : 0,
      duration: 260,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: false,
    }).start();
  }, [visible]);

  useEffect(() => {
    Animated.timing(filterOpacity, {
      toValue: showFilters ? 1 : 0,
      duration: 220,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: false,
    }).start();
  }, [showFilters]);

  useEffect(() => {
    const base = 44; // main row
    const extra = showFilters ? 48 : 0; // pills row
    const target = insets.top + base + extra + 8; // + padding bottom
    Animated.timing(heightAnim, {
      toValue: visible ? target : 0,
      duration: 180,
      useNativeDriver: false,
    }).start();
  }, [visible, showFilters, insets.top]);

  return (
    <Animated.View
      pointerEvents={visible ? 'auto' : 'none'}
      style={{ position: 'absolute', top: 0, left: 0, right: 0, zIndex: 20, height: heightAnim }}
    >
      {/* Full-bleed frosted background including status bar area */}
      <AnimatedBlurView intensity={blurIntensity as any} tint="dark" style={{...StyleSheet.absoluteFillObject}} />
      {/* Subtle glass tint + gradient to enhance visibility over flat backgrounds */}
      {/* <LinearGradient
        pointerEvents="none"
        colors={[ 'rgba(255,255,255,0.06)', 'rgba(255,255,255,0.02)' ]}
        style={StyleSheet.absoluteFillObject}
      /> */}
      <View pointerEvents="none" style={[StyleSheet.absoluteFillObject, { backgroundColor: 'rgba(27,10,16,0.12)' }]} />
      {/* Hairline separator at bottom */}
      <View style={{ position:'absolute', left:0, right:0, bottom:0, height: StyleSheet.hairlineWidth, backgroundColor:'rgba(255,255,255,0.08)' }} />
      <SafeAreaView edges={["top"]} style={{ flex: 1 }}>
        <Animated.View style={{ paddingHorizontal: 16, paddingTop: 8, opacity }}>
          {/* Header row */}
          <View style={{ height: 44, flexDirection: 'row', alignItems:'center', justifyContent:'space-between', paddingHorizontal: 4 }}>
            <Text style={{ color: '#fff', fontSize: 18, fontWeight: '800' }}>For {username || 'You'}</Text>
            <View style={{ flexDirection: 'row' }}>
              <Feather name="cast" size={20} color="#fff" style={{ marginHorizontal: 8 }} />
              <Ionicons name="download-outline" size={20} color="#fff" style={{ marginHorizontal: 8 }} />
              <Ionicons name="search-outline" size={20} color="#fff" style={{ marginHorizontal: 8 }} />
            </View>
          </View>
          {/* Animated filters row under header (covered by same blur) */}
          <Animated.View style={{ opacity: filterOpacity }}>
            {showFilters ? (
              <Pills selected={selected || 'all'} onChange={(t)=> onChange && onChange(t)} onOpenCategories={onOpenCategories} />
            ) : null}
          </Animated.View>
        </Animated.View>
      </SafeAreaView>
    </Animated.View>
  );
}
