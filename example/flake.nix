{
  description = "kmod-ci example — hello kernel module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    kmod-ci.url = "path:..";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.kmod-ci.flakeModules.default ];
      systems = [ "x86_64-linux" ];
      perSystem =
        { ... }:
        {
          kernelModuleCI.hello = {
            module = ./default.nix;
            minKernelVersion = "6.6";
            excludeKernels = [ "linux_testing" ];
            moduleName = "hello";
            # enableVMTest = true;      # requires KVM
            # crossSystems = [ "aarch64-multiplatform" ];
          };
        };
    };
}
