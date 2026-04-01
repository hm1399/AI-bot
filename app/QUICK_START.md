# Quick Start Guide

## 🚀 Getting Started in 3 Steps

### Step 1: Install Dependencies
```bash
pnpm install
```

### Step 2: Start Development Server
```bash
pnpm run dev
```

### Step 3: Connect to Your Device
1. Open the app in your browser
2. You'll see the **Connect** screen
3. Either:
   - Click **"Scan Network"** to auto-discover your device
   - Or manually enter your server IP and port (default: 8000)
4. Click **"Connect"**

## 📱 App Overview

### Main Screens

#### 🏠 Home Dashboard
Your command center for device control:
- **Device Status Card**: View battery, WiFi signal, and current state
- **Quick Actions**: 
  - 🔇 Mute the device
  - 💡 Toggle LED lights
  - 🔄 Restart the device

#### 💬 Chat
Talk with your AI assistant:
- Send text messages
- View conversation history
- See tool execution results
- Voice input (button ready for future implementation)

#### ✅ Tasks & Events
Manage your productivity:
- **Tasks Tab**:
  - Organized by priority (High/Medium/Low)
  - Mark as complete
  - Delete tasks
  - Add new tasks with due dates
- **Events Tab**:
  - View upcoming events
  - Add events with time and location
  - Delete past events

#### ⚙️ Settings
Configure everything:
- **Server Connection**: IP, port, connection status
- **LLM Config**: API key, model selection
- **Voice Settings**: TTS voice, speed, volume
- **LED Settings**: Choose lighting mode and color
- **About**: Version and device info

## 🎨 UI Features

### Bottom Navigation Bar
- 🏠 Home
- 💬 Chat
- 📅 Tasks
- ⚙️ Settings

### Connection Status
- **Green bar**: Connected to device ✅
- **Red bar**: Disconnected ❌

### Toast Notifications
Get instant feedback for all actions:
- ✅ Success messages (green)
- ❌ Error messages (red)
- ℹ️ Info messages (blue)

## 🔌 Backend Requirements

Your backend server should provide:

### WebSocket Endpoint
```
ws://YOUR_SERVER_IP:8000/ws/app
```

Sends real-time updates for:
- Device status changes
- New chat messages
- Task/event updates
- Configuration changes

### REST API Endpoints
```
http://YOUR_SERVER_IP:8000/api/
```

**Required endpoints:**
- `GET /config` - App configuration
- `GET /device/status` - Device status
- `GET /history` - Chat history
- `GET /tasks` - Task list
- `GET /events` - Event list
- `POST /chat` - Send message
- `POST /device/mute` - Mute device
- And more... (see API docs)

## 📖 Common Tasks

### Adding a New Task
1. Go to **Tasks** tab
2. Tap **"New Task"** button
3. Fill in:
   - Title (required)
   - Description (optional)
   - Priority (high/medium/low)
   - Due date (optional)
4. Tap **"Create Task"**

### Creating an Event
1. Go to **Events** tab
2. Tap **"New Event"** button
3. Fill in:
   - Title (required)
   - Description (optional)
   - Start time (required)
   - End time (required)
   - Location (optional)
4. Tap **"Create Event"**

### Sending a Chat Message
1. Go to **Chat** tab
2. Type your message in the input field
3. Tap the **Send** button (➤)
4. Wait for AI response

### Changing Settings
1. Go to **Settings** tab
2. Modify any setting
3. Tap **"Save Settings"** at the bottom
4. See confirmation toast

## 🐛 Troubleshooting

### Can't Connect
**Problem**: "Disconnected" shows in red bar

**Solutions**:
- ✅ Verify your device is powered on
- ✅ Check both devices are on same WiFi network
- ✅ Confirm backend server is running
- ✅ Try manual IP entry instead of auto-discovery
- ✅ Check firewall isn't blocking port 8000

### No Response in Chat
**Problem**: Messages send but no reply

**Solutions**:
- ✅ Check WebSocket connection (green bar at top)
- ✅ Verify LLM API key is set in Settings
- ✅ Check backend logs for errors
- ✅ Ensure backend is processing chat messages

### Tasks Not Saving
**Problem**: Created tasks disappear

**Solutions**:
- ✅ Check connection status
- ✅ Verify backend `/api/tasks` endpoint works
- ✅ Check browser console for errors
- ✅ Try refreshing the page

### Settings Won't Save
**Problem**: Settings revert after saving

**Solutions**:
- ✅ Ensure you're connected to server
- ✅ Check backend `/api/config` endpoint
- ✅ Look for error toast messages
- ✅ Verify backend persists configuration

## 💡 Tips

1. **Auto-Reconnect**: If connection drops, the app will automatically try to reconnect after 5 seconds

2. **Offline Mode**: Some features work offline with cached data, but full functionality requires connection

3. **Mobile Friendly**: The app is designed for mobile screens - works great on phones and tablets

4. **Safe Area**: On notched phones, the app respects safe areas for status bars and home indicators

5. **Persistent Storage**: Connection settings are saved locally, so you don't need to re-enter them

## 🎯 Next Steps

Now that you're set up:
1. ✅ Connect to your device
2. ✅ Explore each screen
3. ✅ Try creating a task
4. ✅ Send a chat message
5. ✅ Customize settings to your liking

## 📚 Additional Resources

- **Full Documentation**: See `APP_README.md`
- **Development Guide**: See `DEVELOPMENT.md`
- **Architecture Document**: See attached `project-proposal.md`

## 🆘 Need Help?

Check browser console (F12) for detailed error messages. Most issues are related to:
- Network connectivity
- Backend configuration
- API endpoint mismatches

Happy coding! 🎉
