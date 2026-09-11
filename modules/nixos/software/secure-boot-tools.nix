{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    sbctl
    efibootmgr
    limine-full
  ];
}
