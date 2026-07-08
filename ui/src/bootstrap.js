import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebglAddon } from "@xterm/addon-webgl";
import { WebLinksAddon } from "@xterm/addon-web-links";
import { Unicode11Addon } from "@xterm/addon-unicode11";
import { createElement, icons } from "lucide";

globalThis.AgentTerminal = {
  Terminal,
  FitAddon,
  WebglAddon,
  WebLinksAddon,
  Unicode11Addon
};
globalThis.lucide = { createElement, icons };
