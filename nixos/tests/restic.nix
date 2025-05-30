{ pkgs, ... }:

let
  remoteRepository = "/root/restic-backup";
  remoteFromFileRepository = "/root/restic-backup-from-file";
  remoteInhibitTestRepository = "/root/restic-backup-inhibit-test";
  remoteNoInitRepository = "/root/restic-backup-no-init";
  rcloneRepository = "rclone:local:/root/restic-rclone-backup";

  backupPrepareCommand = ''
    touch /root/backupPrepareCommand
    test ! -e /root/backupCleanupCommand
  '';

  backupCleanupCommand = ''
    rm /root/backupPrepareCommand
    touch /root/backupCleanupCommand
  '';

  testDir = pkgs.stdenvNoCC.mkDerivation {
    name = "test-files-to-backup";
    unpackPhase = "true";
    installPhase = ''
      mkdir $out
      echo some_file > $out/some_file
      echo some_other_file > $out/some_other_file
      mkdir $out/a_dir
      echo a_file > $out/a_dir/a_file
      echo a_file_2 > $out/a_dir/a_file_2
    '';
  };

  passwordFile = "${pkgs.writeText "password" "correcthorsebatterystaple"}";
  paths = [ "/opt" ];
  exclude = [ "/opt/excluded_file_*" ];
  pruneOpts = [
    "--keep-daily 2"
    "--keep-weekly 1"
    "--keep-monthly 1"
    "--keep-yearly 99"
  ];
in
{
  name = "restic";

  meta = with pkgs.lib.maintainers; {
    maintainers = [
      bbigras
      i077
    ];
  };

  nodes = {
    server =
      { pkgs, ... }:
      {
        services.restic.backups = {
          remotebackup = {
            inherit
              passwordFile
              paths
              exclude
              pruneOpts
              backupPrepareCommand
              backupCleanupCommand
              ;
            repository = remoteRepository;
            initialize = true;
            timerConfig = null; # has no effect here, just checking that it doesn't break the service
          };
          remote-from-file-backup = {
            inherit passwordFile exclude pruneOpts;
            initialize = true;
            repositoryFile = pkgs.writeText "repositoryFile" remoteFromFileRepository;
            paths = [
              "/opt/a_dir/a_file"
              "/opt/a_dir/a_file_2"
            ];
            dynamicFilesFrom = ''
              find /opt -mindepth 1 -maxdepth 1 ! -name a_dir # all files in /opt except for a_dir
            '';
          };
          inhibit-test = {
            inherit
              passwordFile
              paths
              exclude
              pruneOpts
              ;
            repository = remoteInhibitTestRepository;
            initialize = true;
            inhibitsSleep = true;
          };
          remote-noinit-backup = {
            inherit
              passwordFile
              exclude
              pruneOpts
              paths
              ;
            initialize = false;
            repository = remoteNoInitRepository;
          };
          rclonebackup = {
            inherit
              passwordFile
              paths
              exclude
              pruneOpts
              ;
            initialize = true;
            repository = rcloneRepository;
            rcloneConfig = {
              type = "local";
              one_file_system = true;
            };

            # This gets overridden by rcloneConfig.type
            rcloneConfigFile = pkgs.writeText "rclone.conf" ''
              [local]
              type=ftp
            '';
          };
          remoteprune = {
            inherit passwordFile;
            repository = remoteRepository;
            pruneOpts = [ "--keep-last 1" ];
          };
          custompackage = {
            inherit passwordFile paths;
            repository = "some-fake-repository";
            package = pkgs.writeShellScriptBin "restic" ''
              echo "$@" >> /root/fake-restic.log;
            '';

            pruneOpts = [ "--keep-last 1" ];
            checkOpts = [ "--some-check-option" ];
          };
        };

        environment.sessionVariables.RCLONE_CONFIG_LOCAL_TYPE = "local";
      };
  };

  testScript = ''
    server.start()
    server.wait_for_unit("dbus.socket")
    server.fail(
        "restic-remotebackup snapshots",
        'restic-remote-from-file-backup snapshots"',
        "restic-rclonebackup snapshots",
        "grep 'backup.* /opt' /root/fake-restic.log",
    )
    server.succeed(
        # set up
        "cp -rT ${testDir} /opt",
        "touch /opt/excluded_file_1 /opt/excluded_file_2",
        "mkdir -p /root/restic-rclone-backup",
    )

    server.fail(
        # test that noinit backup in fact does not initialize the repository
        # and thus fails without a pre-initialized repository
        "systemctl start restic-backups-remote-noinit-backup.service",
    )

    server.succeed(
        # test that remotebackup runs custom commands and produces a snapshot
        "timedatectl set-time '2016-12-13 13:45'",
        "systemctl start restic-backups-remotebackup.service",
        "rm /root/backupCleanupCommand",
        'restic-remotebackup snapshots --json | ${pkgs.jq}/bin/jq "length | . == 1"',

        # test that restoring that snapshot produces the same directory
        "mkdir /tmp/restore-1",
        "restic-remotebackup restore latest -t /tmp/restore-1",
        "diff -ru ${testDir} /tmp/restore-1/opt",

        # test that remote-from-file-backup produces a snapshot
        "systemctl start restic-backups-remote-from-file-backup.service",
        'restic-remote-from-file-backup snapshots --json | ${pkgs.jq}/bin/jq "length | . == 1"',
        "mkdir /tmp/restore-2",
        "restic-remote-from-file-backup restore latest -t /tmp/restore-2",
        "diff -ru ${testDir} /tmp/restore-2/opt",

        # test that remote-noinit-backup produces a snapshot once initialized
        "restic-remote-noinit-backup init",
        "systemctl start restic-backups-remote-noinit-backup.service",
        'restic-remote-noinit-backup snapshots --json | ${pkgs.jq}/bin/jq "length | . == 1"',

        # test that restoring that snapshot produces the same directory
        "mkdir /tmp/restore-3",
        "${pkgs.restic}/bin/restic -r ${remoteRepository} -p ${passwordFile} restore latest -t /tmp/restore-3",
        "diff -ru ${testDir} /tmp/restore-3/opt",

        # test that rclonebackup produces a snapshot
        "systemctl start restic-backups-rclonebackup.service",
        'restic-rclonebackup snapshots --json | ${pkgs.jq}/bin/jq "length | . == 1"',

        # test that custompackage runs both `restic backup` and `restic check` with reasonable commandlines
        "systemctl start restic-backups-custompackage.service",
        "grep 'backup' /root/fake-restic.log",
        "grep 'check.* --some-check-option' /root/fake-restic.log",

        # test that we can create four snapshots in remotebackup and rclonebackup
        "timedatectl set-time '2017-12-13 13:45'",
        "systemctl start restic-backups-remotebackup.service",
        "rm /root/backupCleanupCommand",
        "systemctl start restic-backups-rclonebackup.service",

        "timedatectl set-time '2018-12-13 13:45'",
        "systemctl start restic-backups-remotebackup.service",
        "rm /root/backupCleanupCommand",
        "systemctl start restic-backups-rclonebackup.service",

        "timedatectl set-time '2018-12-14 13:45'",
        "systemctl start restic-backups-remotebackup.service",
        "rm /root/backupCleanupCommand",
        "systemctl start restic-backups-rclonebackup.service",

        "timedatectl set-time '2018-12-15 13:45'",
        "systemctl start restic-backups-remotebackup.service",
        "rm /root/backupCleanupCommand",
        "systemctl start restic-backups-rclonebackup.service",

        "timedatectl set-time '2018-12-16 13:45'",
        "systemctl start restic-backups-remotebackup.service",
        "rm /root/backupCleanupCommand",
        "systemctl start restic-backups-rclonebackup.service",

        'restic-remotebackup snapshots --json | ${pkgs.jq}/bin/jq "length | . == 4"',
        'restic-rclonebackup snapshots --json | ${pkgs.jq}/bin/jq "length | . == 4"',

        # test that remoteprune brings us back to 1 snapshot in remotebackup
        "systemctl start restic-backups-remoteprune.service",
        'restic-remotebackup snapshots --json | ${pkgs.jq}/bin/jq "length | . == 1"',

    )

    # test that the inhibit option is working
    server.systemctl("start --no-block restic-backups-inhibit-test.service")
    server.wait_until_succeeds(
        "systemd-inhibit --no-legend --no-pager | grep -q restic",
        5
    )
  '';
}
