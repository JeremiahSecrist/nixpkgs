{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.snips-sh;
  docUrl = "https://github.com/robherley/snips.sh/blob/main/docs/self-hosting.md";
in
{
  options = {
    services.snips-sh = {
      enable = lib.mkEnableOption "snips-sh";

      package = lib.mkPackageOption pkgs "snips-sh" { };
      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/snips-sh";
        description = ''
          storage location for snips.sh
        '';
        example = lib.literalExpression "";
      };
      settings = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = {
          SNIPS_HTTP_INTERNAL = "http://0.0.0.0:8888";
          SNIPS_SSH_INTERNAL = "ssh://0.0.0.0:2222";
        };
        description = ''
          The contents of the configuration file for snips-sh.
          See <${docUrl}>.
        '';
        example = lib.literalExpression ''
          SNIPS_HTTP_INTERNAL="http://0.0.0.0:8888";
          SNIPS_SSH_INTERNAL="ssh://0.0.0.0:2222";
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {

    systemd.services.snips-sh = {
      description = "Snips server";
      documentation = [ docUrl ];
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = cfg.settings;
      serviceConfig = {

        Type = "simple";
        DynamicUser = true;
        Restart = "always";
        ExecStart = "${lib.getExe cfg.package}";
        StateDirectory = "snips-sh";
        WorkingDirectory = cfg.stateDir;
        RuntimeDirectory = "snips-sh";
        RuntimeDirectoryMode = "0750";
        ProcSubset = "pid";
        ProtectProc = "invisible";
        UMask = "0027";
        CapabilityBoundingSet = "";
        ProtectHome = true;
        PrivateDevices = true;
        PrivateUsers = true;
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictRealtime = true;
        RemoveIPC = true;
        PrivateMounts = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@cpu-emulation @debug @keyring @module @mount @obsolete @privileged @raw-io @reboot @setuid @swap"
        ];
      };
    };
  };

  meta.maintainers = [ ];
}
