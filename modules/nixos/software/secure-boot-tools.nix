{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    sbctl
    limine-full
  ];
}
