

import { initEventBus } from "./event_bus.ts";
import {async_event, register_listener} from "../../wasm-libs/af-wasm/pkg";

export  function initApp() {
  initEventBus();
  register_listener();
}

type InvokeArgs = Record<string, unknown>;

export async function invoke<T>(cmd: string, args?: InvokeArgs): Promise<T> {
  switch (cmd) {
    case "invoke_request":
      const request = args?.request as { ty?: unknown, payload?: unknown } | undefined;
      if (!request || typeof request !== 'object') {
        throw new Error("Invalid or missing 'request' argument in 'invoke_request'");
      }

      const { ty, payload } = request;
      if (typeof ty !== 'string' || !(payload instanceof Uint8Array)) {
        throw new Error("Invalid 'ty' or 'payload' in request for 'invoke_request'");
      }

      return async_event(ty, payload);
    default:
      throw new Error(`Unknown command: ${cmd}`);
  }
}
