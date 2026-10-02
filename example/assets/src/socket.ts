// The WebSocket (`Platform.Web.UserSocket`): opened with the login token, after
// logging in, and closed on logging out.
import { Socket } from "phoenix";
import { getToken } from "./auth";

let socket: Socket | null = null;

export function connectSocket(): Socket {
  socket?.disconnect();
  socket = new Socket("/socket", { params: { token: getToken() ?? "" } });
  socket.connect();
  return socket;
}

export function disconnectSocket() {
  socket?.disconnect();
  socket = null;
}
