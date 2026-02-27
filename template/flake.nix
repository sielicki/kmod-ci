{
  description = "My kernel module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    kmod-ci.url = "github:sielicki/kmod-ci";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.kmod-ci.flakeModules.default ];
      systems = [ "x86_64-linux" ];
      perSystem =
        { ... }:
        {
          kernelModuleCI.my-kmod = {
            module = ./default.nix;
            minKernelVersion = "6.6";
            # excludeKernels = [ "linux_hardened" "linux_testing" ];
            # requiredKernelConfig = [ "NET" "NETFILTER" ];  # uses IFD
            # moduleName = "my_kmod";
            # enableDevShell = true;       # enabled by default
            # enableNixosModule = true;    # enabled by default
            # overlay = true;             # enabled by default
            # enableVMTest = true;         # requires KVM
            # testScript = ''
            #   machine.wait_for_unit("multi-user.target")
            #   machine.succeed("modprobe my_kmod")
            #   machine.succeed("lsmod | grep -q my_kmod")
            # '';
            # crossSystems = [ "aarch64-multiplatform" ];
          };
        };
    };
}
