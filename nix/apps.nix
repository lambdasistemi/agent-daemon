{ pkgs, checks, packages }:
(builtins.mapAttrs (_: app: {
  type = "app";
  program = pkgs.lib.getExe app;
}) checks.apps) // {
  default = {
    type = "app";
    program = pkgs.lib.getExe packages.tmux-ws;
  };
  tmux-ws = {
    type = "app";
    program = pkgs.lib.getExe packages.tmux-ws;
  };
  agent-daemon = {
    type = "app";
    program = pkgs.lib.getExe packages.agent-daemon;
  };
}
