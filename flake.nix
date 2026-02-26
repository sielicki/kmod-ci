{
  description = "Reusable flake-parts module for out-of-tree kernel module CI";

  outputs = _: {
    flakeModules.default = ./module.nix;
    templates.default = {
      path = ./template;
      description = "Out-of-tree kernel module with kmod-ci";
    };
  };
}
