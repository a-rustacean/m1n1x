{
  config,
  lib,
  pkgs,
  m1n1xPackages,
  ...
}:
let
  cfg = config.hardware.m1n1x;
  kernel = m1n1xPackages.linuxKernel;
  graviton = m1n1xPackages.graviton;
  m1n1xBoot = m1n1xPackages.m1n1xBoot;
  m1n1xReport = m1n1xPackages.m1n1xReport;
  espTidy = pkgs.writeShellScript "m1n1x-esp-tidy" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    esp=${lib.escapeShellArg cfg.efiMountPoint}
    dest=/var/lib/m1n1x/installer
    mkdir -p "$dest"
    chmod 700 "$dest"
    for name in gravity vendorfw; do
      [ -e "$esp/$name" ] || continue
      target=$dest/$name
      [ -e "$target" ] && target=$dest/$name-$(date +%Y%m%d%H%M%S)
      rm -rf "$target.part"
      cp -r --preserve=timestamps "$esp/$name" "$target.part"
      sync -f "$target.part"
      mv "$target.part" "$target"
      rm -rf "''${esp:?}/$name"
      echo "moved $esp/$name to $target"
    done
    sync -f "$esp"
  '';
in
{
  options.hardware.m1n1x = {
    enable = lib.mkEnableOption "m1n1x on an Apple M4 MacBook Air or Mac mini";

    board = lib.mkOption {
      type = lib.types.enum [
        "j713"
        "j773g"
      ];
      default = "j713";
      description = "Target board: the 13-inch M4 MacBook Air or M4 Mac mini.";
    };

    efiMountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/boot/efi";
      description = "Where the EFI system partition holding m1n1/boot.bin is mounted.";
    };

    wifiRegion = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[A-Z]{2}");
      default = null;
      example = "US";
      description = "ISO 3166 country code for Wi-Fi regulatory rules.";
    };

    image = {
      rootUuid = lib.mkOption {
        type = lib.types.strMatching "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
        default = "5b0c6f2e-8d4a-4e1b-9c3f-7a2d1e6b4f80";
        description = "Filesystem UUID used by the root image.";
      };

      label = lib.mkOption {
        type = lib.types.str;
        default = "m1n1x";
        description = "Filesystem label used by the root image.";
      };
    };

    mesa = lib.mkOption {
      type = lib.types.package;
      default = m1n1xPackages.mesa;
      description = "Mesa build with the M4 Asahi GPU drivers.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
        message = "hardware.m1n1x needs nixpkgs.hostPlatform = \"aarch64-linux\".";
      }
    ];

    hardware.deviceTree = {
      enable = true;
      filter = "t8132-${cfg.board}.dtb";
    };

    system.systemBuilderCommands = ''
      ln -s ${graviton}/lib/m1n1/m1n1.bin $out/m1n1.bin
    '';

    boot.kernelPackages = pkgs.linuxPackagesFor kernel;
    boot.kernelParams = [
      "panic=0"
      "console=tty0"
      "fbcon=nodefer"
      "log_buf_len=1M"
      "systemd.gpt_auto=0"
      "rd.systemd.gpt_auto=0"
      "nvme_apple.flush_interval=0"
      "firmware_class.path=/vendorfw"
      "pcie_aspm.policy=powersupersave"
      "apple_pmp_report.cpu_vote=0"
    ];
    boot.consoleLogLevel = 4;
    system.boot.loader.kernelFile = "Image.gz";
    boot.initrd.includeDefaultModules = false;
    boot.initrd.availableKernelModules = [ "nvme-apple" ];
    boot.initrd.systemd.tpm2.enable = false;
    boot.initrd.compressor = "gzip";

    environment.systemPackages = [
      m1n1xBoot
      m1n1xReport
      pkgs.iw
      pkgs.lm_sensors
      pkgs.pciutils
      pkgs.tmux
      pkgs.usbutils
    ];

    boot.initrd.systemd.tmpfiles.settings."10-m1n1x-vendorfw"."/run/vendorfw".C.argument = "/vendorfw";
    system.activationScripts.m1n1x-vendorfw = ''
      mkdir -p /lib
      ln -sfn /run/vendorfw /lib/firmware
    '';
    hardware.firmware = [
      (pkgs.runCommand "rtl8153-firmware" { } ''
        install -Dm444 -t $out/lib/firmware/rtl_nic \
          ${pkgs.linux-firmware}/lib/firmware/rtl_nic/rtl8153*.fw
      '')
    ];
    hardware.wirelessRegulatoryDatabase = true;
    boot.extraModprobeConfig = lib.mkIf (cfg.wifiRegion != null) ''
      options cfg80211 ieee80211_regdom="${cfg.wifiRegion}"
    '';

    hardware.graphics.package = lib.mkOverride 999 cfg.mesa;
    boot.kernelModules = [ "apple_soc_cpufreq" ];

    services.udev.extraRules = lib.mkIf (cfg.board == "j713") ''
      ACTION=="add", SUBSYSTEM=="thermal", KERNEL=="thermal_zone*", ATTR{type}=="cpu-thermal", ATTR{k_po}="205", ATTR{k_pu}="100", ATTR{k_i}="52"
    '';

    systemd.sleep.settings.Sleep = {
      AllowSuspend = "no";
      AllowHibernation = "no";
      AllowHybridSleep = "no";
      AllowSuspendThenHibernate = "no";
    };
    services.logind.settings.Login = {
      HandleLidSwitch = "poweroff";
      HandleLidSwitchExternalPower = "poweroff";
      HandleLidSwitchDocked = "ignore";
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
    };

    fileSystems."/" = lib.mkDefault {
      device = "/dev/disk/by-uuid/${cfg.image.rootUuid}";
      fsType = "ext4";
      autoResize = true;
    };
    boot.initrd.systemd = {
      additionalUpstreamUnits = [ "systemd-growfs@.service" ];
      storePaths = [ "${config.boot.initrd.systemd.package}/lib/systemd/systemd-growfs" ];
    };
    boot.postBootCommands = ''
      if [ -f /nix-path-registration ]; then
        set -euo pipefail
        ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration
        touch /etc/NIXOS
        ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
        rm -f /nix-path-registration
      fi
    '';

    systemd.services.m1n1x-esp = {
      description = "Mount the EFI system partition named by m1n1";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      path = [
        pkgs.coreutils
        pkgs.util-linux
        config.systemd.package
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mountpoint -q ${lib.escapeShellArg cfg.efiMountPoint} && exit 0
        uuid=$(tr -d '\0' < '/proc/device-tree/chosen/gravity,efi-system-partition')
        case "$uuid" in
          ????????-????-????-????-????????????) ;;
          *) echo "m1n1 named no valid EFI partition: '$uuid'" >&2; exit 1 ;;
        esac
        device=/dev/disk/by-partuuid/''${uuid,,}
        udevadm wait --timeout=120 "$device"
        mkdir -p ${lib.escapeShellArg cfg.efiMountPoint}
        mount -t vfat -o umask=0077,nodev,nosuid,noexec "$device" ${lib.escapeShellArg cfg.efiMountPoint}
      '';
    };
    systemd.services.m1n1x-esp-tidy = {
      description = "Move the installer's files off the EFI system partition";
      wantedBy = [ "multi-user.target" ];
      requires = [ "m1n1x-esp.service" ];
      after = [ "m1n1x-esp.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = espTidy;
      };
    };

    boot.loader.grub.enable = false;
    boot.loader.external = {
      enable = true;
      installHook = pkgs.writeShellScript "m1n1x-boot-install" ''
        set -e
        if ! ${pkgs.util-linux}/bin/mountpoint -q ${lib.escapeShellArg cfg.efiMountPoint}; then
          ${config.systemd.package}/bin/systemctl start m1n1x-esp.service
        fi
        ${espTidy}
        exec ${lib.getExe m1n1xBoot} install "$1" --efi ${lib.escapeShellArg cfg.efiMountPoint} --apply
      '';
    };
  };
}
