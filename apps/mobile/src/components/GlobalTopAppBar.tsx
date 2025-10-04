import React from 'react';
import TopAppBar from './TopAppBar';
import { useTopBarStore, TopBarStore } from './TopBarStore';

export default function GlobalTopAppBar() {
  // Force re-render when any store value changes to pick up new scrollY
  const [, forceUpdate] = React.useReducer(x => x + 1, 0);
  
  const visible = useTopBarStore((st) => st.visible);
  const username = useTopBarStore((st) => st.username);
  const showFilters = useTopBarStore((st) => st.showFilters);
  const selected = useTopBarStore((st) => st.selected);
  const onClose = useTopBarStore((st) => st.onClose);
  const onNavigateLibrary = useTopBarStore((st) => st.onNavigateLibrary);
  const onSearch = useTopBarStore((st) => st.onSearch);
  const compact = useTopBarStore((st) => st.compact);
  
  // Re-render when any tracked value changes to pick up latest scrollY
  React.useEffect(() => {
    forceUpdate();
  }, [visible, username, showFilters, selected, compact]);
  
  // Read scrollY and showPills directly from store (don't cause re-renders)
  const scrollY = TopBarStore.getState().scrollY;
  const showPills = TopBarStore.getState().showPills;
    
  return (
    <TopAppBar
      visible={visible}
      username={username}
      showFilters={showFilters}
      selected={selected}
      onChange={(t)=> TopBarStore.setSelected(t)}
      onOpenCategories={()=>{}}
      onNavigateLibrary={onNavigateLibrary}
      onClose={onClose}
      onSearch={onSearch}
      scrollY={scrollY}
      showPills={showPills}
      compact={compact}
      onHeightChange={(h)=> TopBarStore.setHeight(h)}
    />
  );
}


