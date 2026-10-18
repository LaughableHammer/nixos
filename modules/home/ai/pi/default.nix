{ pkgs, lib, ... }:

let
  settings = {
    theme = "catppuccin-mocha";

    defaultProvider = "openrouter";
    defaultModel = "deepseek/deepseek-v4.1-flash-1017";
    defaultThinkingLevel = "low";

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

  models = {
    providers."llama.cpp".modelOverrides.swift = {
      compat = {
        chatTemplateKwargs = {
          enable_thinking = {
            "$var" = "thinking.enabled";
          };
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

    # OpenRouter serves the 1017 snapshot, but neither pi's built-in catalog
    # nor the pi.dev remote overlay lists it, so it is declared here to be
    # selectable and usable as the default model.
    providers.openrouter.models = [
      {
        id = "deepseek/deepseek-v4.1-flash-1017";
        name = "DeepSeek: DeepSeek V4.1 Flash 1017";
        api = "openai-completions";
        reasoning = true;
        thinkingLevelMap = {
          off = "none";
          minimal = null;
          low = "low";
          medium = null;
          high = "high";
          xhigh = null;
          max = "max";
        };
        input = [
          "text"
          "image"
        ];
        cost = {
          input = 0.15;
          output = 0.6;
          cacheRead = 0.003;
          cacheWrite = 0;
        };
        contextWindow = 1048576;
        maxTokens = 393216;
        compat = {
          supportsDeveloperRole = false;
          thinkingFormat = "openrouter";
          supportsStrictMode = true;
          sendSessionAffinityHeaders = true;
          requiresReasoningContentOnAssistantMessages = true;
        };
      }
    ];
  };

  settingsFile = pkgs.writeText "pi-settings.json" (builtins.toJSON settings);
  modelsFile = pkgs.writeText "pi-models.json" (builtins.toJSON models);

  confinedConfig = pkgs.runCommand "pi-confined-config" { } ''
    mkdir -p $out/extensions
    cp ${settingsFile} $out/settings.json
    cp ${modelsFile} $out/models.json
    cp ${./SYSTEM.md} $out/SYSTEM.md
    cp ${./extensions/cwd-confined.ts} $out/extensions/cwd-confined.ts
  '';

  piWrapper = import ./cwd-confined-wrapper.nix {
    inherit pkgs confinedConfig;
  };

  agentSlice = import ./agent-slice.nix { inherit pkgs; };
in
{
  imports = [ ./pi-gui.nix ];

  systemd.user.slices.${lib.removeSuffix ".slice" agentSlice.name} = {
    Unit.Description = "Pi agent (low resource priority)";
    Slice = {
      CPUWeight = agentSlice.cpuWeight;
      IOWeight = agentSlice.ioWeight;
    };
  };

  # The original package remains in the wrapper's closure, but only this
  # launcher is placed on PATH so its `pi` binary wins without a collision.
  home.packages = [ piWrapper ];

  home.file.".pi/agent/settings.json".source = settingsFile;
  home.file.".pi/agent/models.json".source = modelsFile;

  # Keep Pi customisations in this repository while exposing them in Pi's
  # standard user-level directories. cwd-confined.ts is inert without the
  # launcher's PI_CWD_CONFINED marker.
  home.file.".pi/agent/extensions" = {
    source = ./extensions;
    recursive = true;
  };

  home.file.".pi/agent/prompts" = {
    source = ./prompts;
    recursive = true;
  };

  # Global system prompt applied to all models (replaces the default).
  home.file.".pi/agent/SYSTEM.md" = {
    source = ./SYSTEM.md;
    force = true;
  };
}
