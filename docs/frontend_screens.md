# AI Skincare Advisor — Frontend Screen Documentation

> **Purpose**: Reference document for UI iteration with Google Stitch.  
> **Platform**: Flutter (Android / iOS) • Material Design 3  
> **State Management**: Riverpod • **Font**: Inter (Google Fonts)

---

## Navigation Map

```
LoginScreen ──→ HomeScreen (Dashboard / History / Profile)
                   │
                   ├──→ ChatScreen (text chat with AI)
                   └──→ ConsultationLobbyScreen ──→ ConsultationScreen (live video call)
                                                        │
                                                        └──→ ChatScreen (post-call transcript)
```

| Route                 | Screen                     | Transition |
|-----------------------|----------------------------|------------|
| `/login`              | LoginScreen                | Fade       |
| `/` (home)            | HomeScreen                 | Fade       |
| `/chat`               | ChatScreen                 | Slide-right|
| `/consultation-lobby` | ConsultationLobbyScreen    | Slide-right|
| `/consultation`       | ConsultationScreen         | Slide-right|

---

## Design Tokens

| Token       | Value                  | Usage                        |
|-------------|------------------------|------------------------------|
| Primary     | `#6C63FF` (soft violet)| Buttons, links, active state |
| Secondary   | `#00BFA5` (fresh teal) | Chat card gradient, accents  |
| Tertiary    | `#FF6B9D` (soft rose)  | Decorative highlights        |
| Surface     | `#F8F9FE` (off-white)  | Light background             |
| Error       | `#EF5350`              | Error states                 |
| Font        | Inter                  | All text                     |
| Corner Radius| 16–24 dp              | Buttons, cards, inputs       |

Theme supports **Light**, **Dark**, and **System** modes (persisted via SharedPreferences).

---

## Screen 1 — Login Screen

**Route**: `/login`  
**File**: `lib/screens/login_screen.dart`  
**Target Device**: Mobile (portrait-locked)

### Layout

Full-screen **violet gradient** background (`#6C63FF` → `#9B8FFF`, top-to-bottom).

| Section           | Component                     | Details |
|-------------------|-------------------------------|---------|
| Logo area         | Icon in frosted circle        | `face_retouching_natural` icon, 64px, inside a semi-transparent white rounded container (32 radius) |
| Title             | "AI Skincare Advisor"         | Inter Bold 32px, white, centered |
| Subtitle          | "Your personal skincare…"     | Inter 15px, white 85% opacity |
| Google Sign In    | Full-width `ElevatedButton`   | White bg, violet text, Google icon (`g_mobiledata`), 16px radius |
| Divider           | "— or —"                     | White 30% opacity lines + "or" text |
| Email field       | `TextField`                   | White text, semi-transparent white fill (15%), email icon, 16 radius |
| Password field    | `TextField`                   | Same style, lock icon, obscured |
| Sign In button    | Full-width `ElevatedButton`   | Semi-transparent white (25%), toggles label: "Sign In" / "Create Account" |
| Toggle link       | `TextButton`                  | "Don't have an account? Sign Up" / reverse |
| Error banner      | Rounded container             | Red 20% opacity bg, white text |

### States
- **Loading**: Replaces button label with `CircularProgressIndicator` (white, 2px stroke)
- **Sign Up mode**: Toggles between creating account & signing in
- **Error**: Shows inline error message below toggle link

---

## Screen 2 — Home Screen (Dashboard)

**Route**: `/`  
**File**: `lib/screens/home_screen.dart`  
**Target Device**: Mobile

### Structure

`Scaffold` with bottom `NavigationBar` (3 tabs: Home, History, Profile).

#### Tab 1: Dashboard (Home)

| Section             | Component            | Details |
|---------------------|----------------------|---------|
| Greeting            | "Hello, {name}! 👋"  | Inter Bold 28px, fade+slideY animation |
| Subheading          | "How can I help…"    | Inter 16px, `onSurfaceVariant` color |
| **Live Consultation** card | `_ActionCard`  | Violet gradient (`#6C63FF → #9B8FFF`), videocam icon in frosted circle, title "Live Consultation", subtitle "Video-call with AI…", arrow chevron. Taps → `/consultation-lobby` |
| **Chat with Advisor** card | `_ActionCard` | Teal gradient (`#00BFA5 → #4DD0B8`), chat icon, title "Chat with Advisor", subtitle "Text-based skincare advice…". Taps → `/chat` |
| Quick Actions row   | 3× `_QuickAction`   | Pill-shaped surface cards, icon + 2-line label |
| - Scan Product      | camera icon          | Opens chat with pre-filled skincare product scan message |
| - View Progress     | trending_up icon     | Switches to History tab |
| - Skincare Tips     | lightbulb icon       | Opens chat with pre-filled tips prompt |

**Animations**: All cards stagger fadeIn + slideY with increasing delays (200–550ms).

#### _ActionCard Component
- Rounded container (24 radius), `LinearGradient` background
- Row: icon in frosted circle (14px padding, white 20% bg) → title + subtitle → chevron
- Title: Inter Bold 20px white; Subtitle: Inter 13px white 85%

#### _QuickAction Component
- `surfaceContainerLow` background, 20 radius
- Column: colored icon (28px) → 12px label (Inter 12px, w500)

---

#### Tab 2: History

| State         | UI |
|---------------|----|
| Loading       | Centered `CircularProgressIndicator` |
| Error         | Cloud-off icon + error text + "Retry" button |
| Empty         | Timeline icon (30% opacity) + "No history yet" message |
| Populated     | Pull-to-refresh `ListView` of `_SessionCard` items |

**_SessionCard**: `Card` with 16 radius, `surfaceContainerLow` color. Row: circle avatar (chat icon in primary 10% bg) → "Consultation" title + relative date + last message preview → chevron. Taps → opens `/chat` with `sessionId`.

---

#### Tab 3: Profile

| Section           | Component |
|-------------------|-----------|
| Avatar            | `CircleAvatar` (48 radius), shows user photo or person icon |
| Name              | Inter w600 20px |
| Email             | Inter 14px, `onSurfaceVariant` |
| Notifications     | `ListTile` → opens bottom sheet (notification toggles) |
| Appearance        | `ListTile` → opens bottom sheet (System/Light/Dark theme picker) |
| About             | `ListTile` → shows Flutter `AboutDialog` |
| Sign Out          | `OutlinedButton` with error color border |

**Notification Bottom Sheet**: Drag handle → title → 3 toggle switches (Routine Reminders, Progress Updates, Product Deals). Preferences persisted to SharedPreferences.

**Appearance Bottom Sheet**: Drag handle → title → 3 radio `_ThemeOption` tiles (System Default, Light, Dark) with icons and subtitles.

---

## Screen 3 — Chat Screen

**Route**: `/chat`  
**File**: `lib/screens/chat_screen.dart`  
**Target Device**: Mobile

### Layout

| Section          | Component | Details |
|------------------|-----------|---------|
| AppBar           | Custom    | Gradient circle avatar (violet→teal, face icon) + "Glow" title + "AI Skincare Advisor" subtitle + green/red connection dot |
| Connection banner| Conditional| (Connecting): primary 10% bg + spinner + "Connecting to advisor…" |
| Error banner     | Conditional| error 10% bg + error message |
| Empty state      | Center    | Face icon (30% opacity) + "Chat with Glow" + helper text |
| Message list     | `ListView`| `_MessageBubble` items + optional typing indicator |
| Input bar        | Bottom    | `TextField` (rounded 24, `surfaceContainerLow` fill) + circular send button (primary color) |

### _MessageBubble
- **User**: Right-aligned, primary color bg, white text, rounded (20/20/20/4)
- **AI**: Left-aligned, `surfaceContainerLow` bg, `onSurface` text, rounded (20/20/4/20)
- Agent label: shown above AI messages in uppercase, primary color, Inter w700 10px
- Max width: 78% of screen

### Typing Indicator
- 3 animated dots (8px circles, pulsing opacity 0.3→1.0, staggered 200ms delay)
- Left-aligned rounded bubble

### Behavior
- Lazy WebSocket connection (connects on first message send)
- Supports `prefill` argument for auto-sending messages from Quick Actions
- Supports `sessionId` argument for resuming sessions
- Local message caching via `ChatHistoryService`

---

## Screen 4 — Consultation Lobby

**Route**: `/consultation-lobby`  
**File**: `lib/screens/consultation_lobby_screen.dart`  
**Target Device**: Mobile

### Layout

Full-screen dark theme (`#0D0D1A` background) with optional camera preview (dimmed at 35% opacity + gradient overlay).

| Section             | Component | Details |
|---------------------|-----------|---------|
| Back button         | `IconButton` | Top-left, white icon, semi-transparent bg |
| AI Avatar           | Circle (100px) | Gradient `#6C63FF → #00BFA5`, face icon 48px, glowing box shadow, scale+fade animation |
| Title               | "Meet Glow" | Inter Bold 26px, white |
| Subtitle            | "Your AI skincare…" | Inter 15px, white 60%, centered |
| Permission rows     | 2× `_PermissionRow` | Microphone (required) + Camera (optional) |
| Grant Permissions   | `TextButton` | Shown only when microphone not granted |
| Start button        | Full-width `ElevatedButton` | Violet bg, "Start Consultation" + videocam icon, 20 radius, shadow glow. **Disabled** if microphone not granted |
| Footer text         | Helper text | "Camera & microphone will activate after you start" / "Microphone permission is required" |

### _PermissionRow Component
- Rounded container (14 radius), semi-transparent white bg + green border if granted
- Icon (green if granted, white 40% if not) → label → status badge ("Required" in orange / "Optional" / green checkmark)

### Animations
- Avatar: fadeIn (500ms) + scale from 0.8 with easeOutBack
- Text: staggered fadeIn (200ms, 300ms)
- Permissions: fadeIn at 400ms
- Start button: fadeIn at 500ms + slideY from 0.15

---

## Screen 5 — Live Consultation

**Route**: `/consultation`  
**File**: `lib/screens/consultation_screen.dart`  
**Target Device**: Mobile (portrait)

### Layout

Full-screen video-call experience with black background. Camera preview fills the entire background.

| Layer (bottom→top)    | Component | Details |
|-----------------------|-----------|---------|
| Background            | CameraPreview | Full-screen, fitted cover. When camera is off: dark gradient (`#1a1a2e → #16213e`) + "Camera off" icon |
| Top bar               | Status pill | Semi-transparent black (50%), green/red connection dot + status text + call timer (MM:SS, tabular figures) |
| Camera flip button    | `IconButton` | Top-right, `flip_camera_ios` icon |
| Modality chips        | 3× `_ModalityChip` | Row centered below top bar: "Seeing" (active when camera on), "Hearing" (active when not muted), "Speaking" (active when AI speaking) |
| AI presence indicator | Animated circle | 100px circle, gradient changes: speaking = violet→teal with glow + pulse animation + `graphic_eq` icon; idle = semi-transparent white + face icon. Shows "Glow" name + "Speaking…" / "Listening to you" |
| User transcript       | Overlay bubble | Semi-transparent white (15%), italic text, bottom-positioned above AI transcript |
| AI transcript         | Overlay bubble | Semi-transparent black (60%), white text 15px, bottom-positioned above controls. Max 4 lines with ellipsis |
| Bottom controls       | Gradient bar | Black gradient from transparent → 80%. Contains 3 `_CallBtn` buttons |

### Bottom Controls

| Button     | Icon                  | Default Color           | Active Color |
|------------|-----------------------|-------------------------|--------------|
| Mute       | `mic` / `mic_off`     | White 20% opacity       | Red (when muted) |
| Camera     | `videocam` / `videocam_off` | White 20% opacity | Red (when off) |
| End Call   | `call_end_rounded`    | Red (always)            | — |

**End Call** button is larger (`large: true`) to emphasize urgency.

### Overlays
- **Connecting overlay**: Full-screen black 85%, large spinner (60px, violet) + "Connecting to your AI advisor…" + "Setting up camera, microphone & voice" + Cancel button
- **Permission denied overlay**: Full-screen black 90%, mic_off icon + "Permissions Required" title + explanation + "Open Settings" button + "Go Back" link
- **Connection failed overlay**: Full-screen black 85%, wifi_off icon + "Connection Failed" message + retry options

### Real-time Streaming
- **Audio in**: PCM recorded at device sample rate → binary WebSocket frames
- **Video in**: Camera frames at 1 FPS → base64 JPEG → WebSocket
- **Audio out**: Base64 PCM chunks → WAV conversion (24kHz, 16-bit, mono) → `just_audio` playback
- **Transcription**: Live user + AI speech shown as overlays; messages persisted for history

---

## Services Layer

| Service                | File | Purpose |
|------------------------|------|---------|
| `AuthService`          | `auth_service.dart` | Firebase Auth (Google Sign-In + email/password), exposes `authStateProvider` and `authServiceProvider` |
| `WebSocketService`     | `websocket_service.dart` | Bidirectional WebSocket to Cloud Run backend. Sends text, audio (binary), images (base64). Receives ADK events (text, audio, transcription, turn signals) |
| `AudioService`         | `audio_service.dart` | Microphone recording via `record` package, outputs base64 PCM stream |
| `CameraService`        | `camera_service.dart` | Camera initialization, frame capture at N FPS, outputs base64 JPEG stream, flip camera support |
| `ChatHistoryService`   | `chat_history_service.dart` | Local message caching (SharedPreferences) + remote session fetching via REST API |
| `NotificationService`  | `notification_service.dart` | Firebase Cloud Messaging (FCM) setup, token registration with backend |

---

## Backend Connection

| Setting        | Value |
|----------------|-------|
| WebSocket URL  | `wss://skincare-advisor-{id}.us-central1.run.app/ws/{userId}/{sessionId}` |
| REST Base URL  | Same host, HTTPS scheme |
| App name       | `skincare_advisor` (ADK) |
| Auth           | Firebase ID token passed as query param or header |
