
  # App Builder (超多次修改)

  This is a code bundle for App Builder (超多次修改). The original project is available at https://www.figma.com/design/xrV9OSHTy2Xibx8OV2wuMk/App-Builder--%E8%B6%85%E5%A4%9A%E6%AC%A1%E4%BF%AE%E6%94%B9-.

  ## Running the code

  Run `npm i` to install the dependencies.

  Run `npm run dev` to start the development server.

## Running backend API server

  1. Install the backend dependencies:

     `npm i express ws`

  2. Start API server:

     `npm run start:api`

  3. 默认接口:

     - GET /api/config
     - PUT /api/config
     - GET /api/device/status
     - POST /api/device/mute
     - POST /api/device/led/toggle
     - POST /api/device/restart
     - GET /api/history
     - POST /api/chat
     - GET/POST/PUT/DELETE /api/tasks
     - GET/POST/PUT/DELETE /api/events
     - WS 在 ws://localhost:8000/ws/app

  