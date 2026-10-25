{ pkgs, lib, config, ... }:

let
  settings = {
    theme = "catppuccin-mocha";

    defaultProvider = "openrouter";
    defaultModel = "deepseek/deepseek-v4.1-flash-1017";
    defaultThinkingLevel = "low";

    packages = [
      "npm:pi-usage-cli@1.1.3"
      "npm:pi-token-speed@0.10.2"
      "npm:@narumitw/pi-plan-mode@0.59.4"
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

  agentSlice = import ./agent-slice.nix { inherit pkgs; };

  # Fallback used when my.piSandbox.enable is false: no sandboxing at all.
  plainLauncher = pkgs.writeShellScriptBin "pi" ''
    if [[ -z "''${PI_AGENT_SLICE:-}" && -S "''${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]]; then
      export PI_AGENT_SLICE=1
      exec ${agentSlice.systemdRun} "$0" "$@"
    fi
    exec ${pkgs.pi-coding-agent}/bin/pi "$@"
  '';
in
{
  imports = [ ./sandbox ];

  systemd.user.slices.${lib.removeSuffix ".slice" agentSlice.name} = {
    Unit.Description = "Pi agent (low resource priority)";
    Slice = {
      CPUWeight = agentSlice.cpuWeight;
      IOWeight = agentSlice.ioWeight;
    };
  };

  # The sandbox module replaces this launcher with one that parses the sandbox
  # flags and routes built-in tools into a container; see ./sandbox.
  home.packages = [
    (if config.my.piSandbox.enable then config.my.piSandbox.launcher else plainLauncher)
    # Backs the host-side web_search extension (./extensions/brave-search.ts).
    pkgs.brave-search-cli
  ];

  home.file.".pi/agent/settings.json".source = settingsFile;
  home.file.".pi/agent/models.json".source = modelsFile;

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

  # Global system prompt applied to all models (replaces the default).
  home.file.".pi/agent/SYSTEM.md" = {
    source = ./SYSTEM.md;
    force = true;
  };
}
