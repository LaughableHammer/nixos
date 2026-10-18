{ pkgs, ... }:

{
  # `notify-send` for shell scripts, Pi, and anything else that wants to raise
  # a desktop notification through the Noctalia notification daemon.
  home.packages = [ pkgs.libnotify ];

  # Source kitty's bash integration from a real .bashrc instead of letting kitty
  # inject it with `bash --posix`. POSIX mode bypasses NixOS's /etc/bashrc and
  # loses the normal user@host prompt. `no-rc` makes kitty set
  # KITTY_SHELL_INTEGRATION without rewriting bash's startup path.
  home.file.".bashrc".text = ''
    if [ -n "$KITTY_INSTALLATION_DIR" ]; then
      source "$KITTY_INSTALLATION_DIR/shell-integration/bash/kitty.bash"
    fi
  '';

  programs.kitty = {
    enable = true;

    shellIntegration.mode = "no-rc";

    # Restore the Noctalia colour scheme that the previous hand-written
    # kitty.conf included. Home Manager now owns kitty.conf, so the include has
    # to be generated here instead.
    extraConfig = ''
      include themes/noctalia.conf
    '';

    settings = {
      # Notify when a command takes at least 5 seconds and the kitty window is
      # not focused. Clear the notification when the window regains focus or
      # the next command finishes.
      notify_on_cmd_finish = "unfocused 5.0 notify focus next";
    };
  };
}
