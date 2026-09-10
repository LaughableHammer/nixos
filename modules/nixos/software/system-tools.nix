{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vim
    wget
    neovim
    git
    zip
    unzip
  ];
}
