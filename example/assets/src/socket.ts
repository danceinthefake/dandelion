// One Phoenix Channels connection for the whole page (`Platform.Web.UserSocket`).
import { Socket } from "phoenix";

export const socket = new Socket("/socket");
socket.connect();
