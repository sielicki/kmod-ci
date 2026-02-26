# kmod-ci

A reusable [flake-parts](https://flake.parts) module that automatically discovers nixpkgs kernel packages and builds your out-of-tree kernel module against each of them, giving you per-kernel `checks` and `packages` outputs with zero boilerplate. Get started with:

```
nix flake init -t github:sielicki/kmod-ci
```

See [`example/`](example/) for a working end-to-end reference and [`module.nix`](module.nix) for all available options.

## Options

### Core

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `module` | path | *required* | `callPackage`-able kernel module derivation |
| `minKernelVersion` | string | `"6.6"` | Skip kernels below this version |
| `maxKernelVersion` | string | `""` | Skip kernels above this version (empty = no limit) |
| `defaultKernel` | string | `"linux_latest"` | Kernel attr used for `packages.default` |
| `extraKernelPackages` | list of package | `[]` | Additional kernel derivations to test |
| `kernelFilter` | function | `_: true` | Custom predicate after version/platform filtering |
| `extraArgs` | attrs | `{}` | Extra arguments passed to `callPackage` |
| `overlay` | bool | `false` | Auto-generate a `linuxKernel.packagesFor` overlay |

### Kernel Filtering

#### `excludeKernels`

Filter out specific kernel attribute names by exact match:

```nix
kernelModuleCI.my-kmod = {
  module = ./default.nix;
  excludeKernels = [ "linux_hardened" "linux_testing" "linux_rt" ];
};
```

#### `requiredKernelConfig`

Only build against kernels that have specific `CONFIG_` options set to `y` or `m`. Specify option names without the `CONFIG_` prefix:

```nix
kernelModuleCI.my-kmod = {
  module = ./default.nix;
  requiredKernelConfig = [ "NET" "NETFILTER" ];
};
```

**Note:** This uses IFD (import-from-derivation) to read kernel config files. Kernels with missing config attributes are skipped gracefully.

### Dev Shells

Enabled by default. Generates a `devShell` per entry with kernel build dependencies and `KDIR` set:

```nix
kernelModuleCI.my-kmod = {
  module = ./default.nix;
  enableDevShell = true;  # default
};
```

```console
$ nix develop
$ make -C $KDIR M=$PWD
```

When there is a single CI entry, `devShells.default` is set automatically.

### VM Tests

Generate NixOS VM tests that boot a VM, load the module, and verify it appears in `lsmod`:

```nix
kernelModuleCI.my-kmod = {
  module = ./default.nix;
  moduleName = "my_kmod";
  enableVMTest = true;
};
```

The default test script runs `modprobe` and checks `lsmod`. Supply a custom `testScript` for more complex validation:

```nix
kernelModuleCI.my-kmod = {
  module = ./default.nix;
  moduleName = "my_kmod";
  enableVMTest = true;
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("modprobe my_kmod")
    machine.succeed("lsmod | grep -q my_kmod")
    machine.succeed("dmesg | grep -q 'my_kmod: initialized'")
  '';
};
```

VM tests are only generated on `x86_64-linux` and `aarch64-linux` (requires KVM).

### NixOS Module

Generate `flake.nixosModules.<name>` that configures `boot.extraModulePackages` and `boot.kernelModules`:

```nix
kernelModuleCI.my-kmod = {
  module = ./default.nix;
  moduleName = "my_kmod";
  enableNixosModule = true;
};
```

Consumers use it like any NixOS module:

```nix
{ inputs, ... }:
{
  imports = [ inputs.my-kmod.nixosModules.my-kmod ];
}
```

### Cross-Compilation

Build your module against cross-compiled kernels:

```nix
kernelModuleCI.my-kmod = {
  module = ./default.nix;
  crossSystems = [ "aarch64-multiplatform" "riscv64" ];
};
```

This produces cross-compiled checks (`my-kmod-cross-aarch64-multiplatform-linux_latest`, ...) and packages (`my-kmod-cross-aarch64-multiplatform`). The `crossSystems` values are `pkgsCross` attribute names.
