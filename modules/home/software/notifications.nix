{ pkgs, ... }:

{
  # `notify-send` for shell scripts, Pi, and anything else that wants to raise
  # a desktop notification through the Noctalia notification daemon.
  home.packages = [ pkgs.libnotify ];

  programs.kitty = {
    enable = true;

    # Use kitty's own automatic shell integration (bash/zsh) instead of
    # home-manager injecting it into managed shell rc files. This repo does not
    # manage bash/zsh startup files, so `null` leaves kitty's default
    # `shell_integration enabled` behaviour untouched.
    shellIntegration.mode = null;

    settings = {
      shell_integration = "enabled";

      # Notify when a command takes at least 5 seconds and the kitty window is
      # not focused. Clear the notification when the window regains focus or
      # the next command finishes. Kitty only tracks commands started at a
      # shell prompt; commands spawned by Pi's bash tool are captured by Pi
      # rather than reported as shell-integration jobs, so they are silent.
      notify_on_cmd_finish = "unfocused 5.0 notify focus next";
    };
  };
}
