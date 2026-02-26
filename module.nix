{
  config,
  lib,
  flake-parts-lib,
  withSystem,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (flake-parts-lib) mkPerSystemOption;

  entrySubmodule = types.submodule {
    options = {
      module = mkOption {
        type = types.path;
        description = "callPackage-able kernel module derivation.";
      };
      minKernelVersion = mkOption {
        type = types.str;
        default = "6.6";
        description = "Skip kernels below this version.";
      };
      maxKernelVersion = mkOption {
        type = types.str;
        default = "";
        description = "Skip kernels above this version (empty = no limit).";
      };
      extraKernelPackages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Additional kernel derivations to test.";
      };
      kernelFilter = mkOption {
        type = types.functionTo types.bool;
        default = _: true;
        description = "Custom predicate applied after version/platform filtering.";
      };
      extraArgs = mkOption {
        type = types.attrs;
        default = { };
        description = "Extra arguments passed to callPackage.";
      };
      overlay = mkOption {
        type = types.bool;
        default = false;
        description = "Auto-generate a linuxKernel.packagesFor overlay.";
      };
      defaultKernel = mkOption {
        type = types.str;
        default = "linux_latest";
        description = "Kernel attr name used for packages.default.";
      };
      excludeKernels = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Kernel attribute names to exclude (e.g. [\"linux_hardened\"]).";
      };
      requiredKernelConfig = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "CONFIG_ options (without prefix) that must be y or m. Uses IFD.";
      };
      enableDevShell = mkOption {
        type = types.bool;
        default = true;
        description = "Generate a devShell with kernel headers for this entry.";
      };
      enableVMTest = mkOption {
        type = types.bool;
        default = false;
        description = "Generate a NixOS VM smoke test that loads the module.";
      };
      moduleName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Kernel module name for modprobe. Defaults to entry name.";
      };
      testScript = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom NixOS test script. Default: modprobe + lsmod check.";
      };
      enableNixosModule = mkOption {
        type = types.bool;
        default = false;
        description = "Generate flake.nixosModules.<name> for this entry.";
      };
      crossSystems = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "pkgsCross attr names to cross-compile for (e.g. [\"aarch64-multiplatform\"]).";
      };
    };
  };
in
{
  options.perSystem = mkPerSystemOption (
    {
      config,
      pkgs,
      system,
      ...
    }:
    {
      options.kernelModuleCI = mkOption {
        type = types.attrsOf entrySubmodule;
        default = { };
        description = "Out-of-tree kernel module CI configurations.";
      };
    }
  );

  config =
    let
      overlayEntries = withSystem (builtins.head config.systems) (
        { config, ... }:
        lib.filterAttrs (_: v: v.overlay) config.kernelModuleCI
      );
      nixosModuleEntries = withSystem (builtins.head config.systems) (
        { config, ... }:
        lib.filterAttrs (_: v: v.enableNixosModule) config.kernelModuleCI
      );
    in
    {
      perSystem =
        {
          config,
          pkgs,
          lib,
          system,
          ...
        }:
        let
          cfg = config.kernelModuleCI;
          names = builtins.attrNames cfg;

          buildFor =
            targetPkgs: entry: kernel:
            (targetPkgs.linuxPackagesFor kernel).callPackage entry.module entry.extraArgs;

          discoverKernels =
            targetPkgs: targetSystem: entry:
            let
              allLinuxNames = builtins.filter (lib.hasPrefix "linux_") (builtins.attrNames targetPkgs);
              allNames = builtins.filter (n: !(builtins.elem n entry.excludeKernels)) allLinuxNames;
              tryKernel =
                name:
                let
                  eval = builtins.tryEval targetPkgs.${name};
                  kernel = eval.value;
                  maxOk =
                    entry.maxKernelVersion == ""
                    || lib.versionOlder kernel.version entry.maxKernelVersion;
                  configOk =
                    entry.requiredKernelConfig == [ ]
                    || builtins.all (
                      opt:
                      let
                        r = builtins.tryEval (
                          let
                            v = kernel.config."CONFIG_${opt}";
                          in
                          v == "y" || v == "m"
                        );
                      in
                      r.success && r.value
                    ) entry.requiredKernelConfig;
                in
                if
                  eval.success
                  && lib.versionAtLeast kernel.version entry.minKernelVersion
                  && maxOk
                  && lib.meta.availableOn { system = targetSystem; } kernel
                  && configOk
                  && entry.kernelFilter kernel
                then
                  { ${name} = kernel; }
                else
                  { };
            in
            lib.mergeAttrsList (map tryKernel allNames);

          checksForEntry =
            name: entry:
            let
              discovered = discoverKernels pkgs system entry;
              discoveredChecks = lib.mapAttrs' (
                kName: kernel: lib.nameValuePair "${name}-${kName}" (buildFor pkgs entry kernel)
              ) discovered;
              extraChecks = lib.listToAttrs (
                lib.imap0 (
                  i: kernel:
                  lib.nameValuePair "${name}-extra-${toString i}" (buildFor pkgs entry kernel)
                ) entry.extraKernelPackages
              );
            in
            discoveredChecks // extraChecks;

          allChecks = lib.mergeAttrsList (lib.mapAttrsToList checksForEntry cfg);

          allPackages = lib.mapAttrs (
            name: entry: buildFor pkgs entry pkgs.${entry.defaultKernel}
          ) cfg;

          singleEntry = builtins.length names == 1;
          defaultPackage =
            if singleEntry then
              { default = allPackages.${builtins.head names}; }
            else
              { };

          # devShells
          devShellForEntry =
            name: entry:
            let
              kernel = pkgs.${entry.defaultKernel};
            in
            pkgs.mkShell {
              nativeBuildInputs = kernel.moduleBuildDependencies;
              shellHook = ''
                export KDIR="${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
              '';
            };

          allDevShells = lib.mapAttrs devShellForEntry (
            lib.filterAttrs (_: e: e.enableDevShell) cfg
          );
          defaultDevShell =
            if singleEntry && (builtins.head (builtins.attrValues cfg)).enableDevShell then
              { default = allDevShells.${builtins.head names}; }
            else
              { };

          # VM tests
          effectiveModuleName = name: entry: if entry.moduleName != null then entry.moduleName else name;

          vmTestForEntry =
            name: entry:
            let
              modName = effectiveModuleName name entry;
              defaultScript = ''
                machine.wait_for_unit("multi-user.target")
                machine.succeed("lsmod | grep -q ${modName}")
              '';
            in
            pkgs.nixosTest {
              name = "${name}-vm-test";
              nodes.machine =
                { config, ... }:
                {
                  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.${entry.defaultKernel};
                  boot.extraModulePackages = [
                    (config.boot.kernelPackages.callPackage entry.module entry.extraArgs)
                  ];
                  boot.kernelModules = [ modName ];
                };
              testScript = if entry.testScript != null then entry.testScript else defaultScript;
            };

          vmTestChecks = lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") (
            lib.mapAttrs' (
              name: entry: lib.nameValuePair "${name}-vm-test" (vmTestForEntry name entry)
            ) (lib.filterAttrs (_: e: e.enableVMTest) cfg)
          );

          # Cross-compilation
          crossChecksForEntry =
            name: entry:
            lib.mergeAttrsList (
              map (
                crossName:
                let
                  crossPkgs = pkgs.pkgsCross.${crossName};
                  crossSystem = crossPkgs.stdenv.hostPlatform.system;
                  discovered = discoverKernels crossPkgs crossSystem entry;
                in
                lib.mapAttrs' (
                  kName: kernel:
                  lib.nameValuePair "${name}-cross-${crossName}-${kName}" (buildFor crossPkgs entry kernel)
                ) discovered
              ) entry.crossSystems
            );

          allCrossChecks = lib.mergeAttrsList (lib.mapAttrsToList crossChecksForEntry cfg);

          crossPackagesForEntry =
            name: entry:
            lib.listToAttrs (
              map (
                crossName:
                let
                  crossPkgs = pkgs.pkgsCross.${crossName};
                  kernel = crossPkgs.${entry.defaultKernel};
                in
                lib.nameValuePair "${name}-cross-${crossName}" (buildFor crossPkgs entry kernel)
              ) entry.crossSystems
            );

          allCrossPackages = lib.mergeAttrsList (lib.mapAttrsToList crossPackagesForEntry cfg);
        in
        lib.mkIf (cfg != { }) {
          checks = allChecks // vmTestChecks // allCrossChecks;
          packages = allPackages // defaultPackage // allCrossPackages;
          devShells = allDevShells // defaultDevShell;
        };

      flake.overlays = lib.mapAttrs (
        name: entry:
        final: prev: {
          linuxKernel = prev.linuxKernel // {
            packagesFor =
              kernel:
              (prev.linuxKernel.packagesFor kernel).extend (
                kFinal: _: { ${name} = kFinal.callPackage entry.module entry.extraArgs; }
              );
          };
        }
      ) overlayEntries;

      flake.nixosModules = lib.mapAttrs (
        name: entry:
        { config, ... }:
        let
          modName = if entry.moduleName != null then entry.moduleName else name;
        in
        {
          boot.extraModulePackages = [
            (config.boot.kernelPackages.callPackage entry.module entry.extraArgs)
          ];
          boot.kernelModules = [ modName ];
        }
      ) nixosModuleEntries;
    };
}
