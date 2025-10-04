import React, { useEffect, useState } from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { View, ActivityIndicator, Text } from 'react-native';
import GlobalTopAppBar from './src/components/GlobalTopAppBar';
import { Ionicons } from '@expo/vector-icons';
import { BlurView } from 'expo-blur';
import Onboarding from './src/screens/Onboarding';
import Login from './src/screens/Login';
import Home from './src/screens/Home';
import Library from './src/screens/Library';
import Details from './src/screens/Details';
import Player from './src/screens/Player';
import Search from './src/screens/Search';
import NewHot from './src/screens/NewHot';
import { MobileApi } from './src/api/client';
import My from './src/screens/My';
import * as Haptics from 'expo-haptics';

// Note: expo-image uses disk cache by default (cachePolicy="disk" or "memory-disk")
// Cache limits are managed by the OS and expo-image internally

type RootStackParamList = {
  Onboarding: undefined;
  Login: undefined;
  Home: undefined;
};

const Stack = createNativeStackNavigator<RootStackParamList>();
const Tab = createBottomTabNavigator();
const HomeStack = createNativeStackNavigator();

export default function App() {
  const [api, setApi] = useState<MobileApi | null>(null);
  const [init, setInit] = useState(true);

  useEffect(() => {
    (async () => {
      const loaded = await MobileApi.load();
      setApi(loaded);
      setInit(false);
    })();
  }, []);

  if (init) {
    return (
      <View style={{ flex: 1, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator color="#fff" />
      </View>
    );
  }

  const HomeStackNavigator = () => (
      <View style={{ flex:1 }}>
        <HomeStack.Navigator screenOptions={{ headerShown: false }}>
          <HomeStack.Screen name="HomeScreen">{() => <Home api={api!} />}</HomeStack.Screen>
          <HomeStack.Screen name="Details" component={Details} options={{ presentation: 'transparentModal', animation: 'fade', gestureEnabled: false }} />
          <HomeStack.Screen name="Player" component={Player} options={{ presentation: 'fullScreenModal', animation: 'fade' }} />
          <HomeStack.Screen name="Library" component={Library} options={{ presentation: 'card', animation: 'fade' }} />
          <HomeStack.Screen name="Search" component={Search} options={{ presentation: 'modal', animation: 'slide_from_bottom' }} />
        </HomeStack.Navigator>
        <GlobalTopAppBar />
      </View>
  );

  const Tabs = () => (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        headerShown: false,
        tabBarShowLabel: true,
        tabBarActiveTintColor: '#fff',
        tabBarInactiveTintColor: '#bdbdbd',
        tabBarStyle: {
          position: 'absolute', left: 0, right: 0, bottom: 0,
          backgroundColor: 'transparent', borderRadius: 0,
          borderTopWidth: 0, height: 68, paddingBottom: 10, paddingTop: 10,
          overflow: 'hidden', zIndex: 100,
        },
        tabBarBackground: () => (
          <BlurView intensity={90} tint="dark" style={{ flex: 1 }} />
        ),
        tabBarIcon: ({ color, size, focused }) => {
          const name = route.name === 'HomeTab' ? (focused ? 'home' : 'home-outline')
            : route.name === 'NewHotTab' ? (focused ? 'play-circle' : 'play-circle-outline')
            : (focused ? 'person' : 'person-outline');
          return <Ionicons name={name as any} size={22} color={color} />;
        }
      })}
      screenListeners={{
        tabPress: () => {
          Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
        }
      }}
    >
      <Tab.Screen name="HomeTab" options={{ title: 'Home' }} component={HomeStackNavigator} />
      <Tab.Screen name="NewHotTab" options={{ title: 'New & Hot' }}>
        {() => (
          <View style={{ flex:1 }}>
            <NewHot />
            <GlobalTopAppBar />
          </View>
        )}
      </Tab.Screen>
      <Tab.Screen name="MyTab" options={{ title: 'My Netflix' }}>{() => api ? <My api={api} /> : <View style={{ flex:1, backgroundColor:'#000' }} />}</Tab.Screen>
    </Tab.Navigator>
  );

  return (
    <NavigationContainer>
      <Stack.Navigator screenOptions={{ headerShown: false }}>
        {!api ? (
          <Stack.Screen name="Onboarding">
            {() => <Onboarding onConnected={(a) => setApi(a)} />}
          </Stack.Screen>
        ) : !api.token ? (
          <Stack.Screen name="Login">
            {() => <Login api={api} onAuthed={(a) => setApi(new MobileApi(a.baseUrl, a.token))} />}
          </Stack.Screen>
        ) : (
          <Stack.Screen name="Home" component={Tabs} />
        )}
      </Stack.Navigator>
    </NavigationContainer>
  );
}
