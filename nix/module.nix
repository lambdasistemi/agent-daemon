{ self }:
{ config, lib, pkgs, ... }:
let
  cfg = config.services.agent-daemon;
in
{
  options.services.agent-daemon = {
    enable = lib.mkEnableOption "agent-daemon";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to listen on.";
    };

    baseDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/agent-daemon";
      description = "Base directory for git worktrees.";
    };

    staticDir = lib.mkOption {
      type = lib.types.path;
      default = self.packages.${pkgs.system}.static;
      description = "Directory for static web files.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.system}.default;
      description = "The agent-daemon package to use.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "agent-daemon";
      description = "User to run the service as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "agent-daemon";
      description = "Group to run the service as.";
    };

    createUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to create a dedicated system user and group. Disable when running as an existing user.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = lib.mkIf cfg.createUser {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.baseDir;
      createHome = true;
    };

    users.groups.${cfg.group} = lib.mkIf cfg.createUser { };

    systemd.services.agent-daemon = {
      description = "Agent daemon — Claude Code session manager";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      path = [ pkgs.tmux pkgs.git pkgs.openssh ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.baseDir;
        ExecStart = lib.concatStringsSep " " [
          "${cfg.package}/bin/agent-daemon"
          "--port ${toString cfg.port}"
          "--base-dir ${cfg.baseDir}"
          "--static-dir ${cfg.staticDir}"
        ];
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
