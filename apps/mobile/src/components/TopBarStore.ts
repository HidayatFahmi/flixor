import { Animated } from 'react-native';
import React from 'react';

type Pill = 'all'|'movies'|'shows';

type State = {
  visible: boolean;
  username?: string;
  showFilters: boolean;
  selected: Pill;
  scrollY?: Animated.Value;
  showPills?: Animated.Value;
  onNavigateLibrary?: (tab: 'movies'|'shows')=>void;
  onClose?: ()=>void;
  onSearch?: ()=>void;
  compact?: boolean;
  customFilters?: React.ReactNode;
  height: number;
};

type Listener = () => void;

const state: State = {
  visible: true,
  username: undefined,
  showFilters: true, // default to true so pills are visible
  selected: 'all',
  scrollY: undefined,
  showPills: undefined,
  onNavigateLibrary: undefined,
  onClose: undefined,
  onSearch: undefined,
  compact: false,
  customFilters: undefined,
  height: 90,
};

const listeners = new Set<Listener>();

function emit() { listeners.forEach(l => l()); }

export const TopBarStore = {
  subscribe(fn: Listener) { listeners.add(fn); return () => listeners.delete(fn); },
  getState(): State { return state; },
  setVisible(v: boolean) { if (state.visible !== v) { state.visible = v; emit(); } },
  setUsername(u?: string) { if (state.username !== u) { state.username = u; emit(); } },
  setShowFilters(v: boolean) { if (state.showFilters !== v) { state.showFilters = v; emit(); } },
  setSelected(p: Pill) { if (state.selected !== p) { state.selected = p; emit(); } },
  setCompact(v: boolean) { if (state.compact !== v) { state.compact = v; emit(); } },
  setCustomFilters(v?: React.ReactNode) { if (state.customFilters !== v) { state.customFilters = v; emit(); } },
  setScrollY(y?: Animated.Value) { 
    // Don't emit on scrollY change since Animated.Value changes don't need React updates
    state.scrollY = y; 
  },
  setShowPills(v?: Animated.Value) {
    // Don't emit - Animated.Value changes don't need React updates
    state.showPills = v;
  },
  setHandlers(h: { onNavigateLibrary?: (tab:'movies'|'shows')=>void; onClose?: ()=>void; onSearch?: ()=>void }) {
    let changed = false;
    if (state.onNavigateLibrary !== h.onNavigateLibrary) { state.onNavigateLibrary = h.onNavigateLibrary; changed = true; }
    if (state.onClose !== h.onClose) { state.onClose = h.onClose; changed = true; }
    if (state.onSearch !== h.onSearch) { state.onSearch = h.onSearch; changed = true; }
    if (changed) emit();
  },
  setHeight(h: number) { if (state.height !== h) { state.height = h; emit(); } },
  navigateLibrary(tab: 'movies'|'shows') { state.onNavigateLibrary && state.onNavigateLibrary(tab); },
};

export function useTopBarStore<T>(selector: (s: State) => T): T {
  return React.useSyncExternalStore(TopBarStore.subscribe, () => selector(TopBarStore.getState()), () => selector(TopBarStore.getState()));
}


