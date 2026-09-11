{ lib, ... }:

{
  options.my.noctalia.sessionActions = lib.mkOption {
    type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
    default = [ ];
    description = "Host-specific actions appended to Noctalia's session menu.";
  };
}
