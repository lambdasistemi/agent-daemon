{ pkgs, checks }:
builtins.mapAttrs (_: app: {
  type = "app";
  program = pkgs.lib.getExe app;
}) checks.apps
