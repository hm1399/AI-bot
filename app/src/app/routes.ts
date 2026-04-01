import { createBrowserRouter, redirect } from "react-router";
import { Root } from "./Root";
import { Home } from "./screens/Home";
import { Chat } from "./screens/Chat";
import { TasksEvents } from "./screens/TasksEvents";
import { Settings } from "./screens/Settings";
import { Connect } from "./screens/Connect";

export const router = createBrowserRouter([
  {
    path: "/",
    loader: () => redirect("/connect"),
  },
  {
    path: "/connect",
    Component: Connect,
  },
  {
    path: "/app",
    Component: Root,
    children: [
      { index: true, Component: Home },
      { path: "chat", Component: Chat },
      { path: "tasks", Component: TasksEvents },
      { path: "settings", Component: Settings },
    ],
  },
]);