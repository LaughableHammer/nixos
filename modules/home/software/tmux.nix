{ ... }:

{
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";

    extraConfig = ''
      set -g extended-keys on
      set -g extended-keys-format csi-u
    '';
  };
}
