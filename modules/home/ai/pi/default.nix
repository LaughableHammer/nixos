{ pkgs, ... }:

{
  home.packages = [ pkgs.pi-coding-agent ];

  home.file.".pi/agent/settings.json".text = builtins.toJSON {
    theme = "catppuccin-mocha";
    packages = [
      "npm:pi-usage-cli@1.1.3"
      "npm:pi-token-speed@0.10.2"
      "git:https://github.com/hasit/pi-community-themes@v0.5.0"
    ];
    tokenSpeed = {
      display = "tps";
      useProviderTokens = true;
      countStrategy = "estimate";
    };
  };

  home.file.".pi/agent/models.json".text = builtins.toJSON {
    providers."llama.cpp".modelOverrides.swift = {
      compat = {
        chatTemplateKwargs = {
          enable_thinking = { "$var" = "thinking.enabled"; };
          preserve_thinking = true;
          reasoning_effort = {
            "$var" = "thinking.effort";
            omitWhenOff = true;
          };
        };
        thinkingFormat = "chat-template";
      };
      reasoning = true;
      thinkingLevelMap = {
        high = null;
        low = "low";
        medium = "medium";
        minimal = null;
        off = "off";
        xhigh = "xhigh";
      };
    };
  };

  # Keep Pi customisations in this repository while exposing them in Pi's
  # standard user-level directories.
  home.file.".pi/agent/extensions" = {
    source = ./extensions;
    recursive = true;
  };

  home.file.".pi/agent/prompts" = {
    source = ./prompts;
    recursive = true;
  };
}
