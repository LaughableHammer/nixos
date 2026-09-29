{ inputs, pkgs, ... }:

{
  services.llama-cpp = {
    enable = true;
    package = inputs.nixpkgs-llama.legacyPackages.${pkgs.stdenv.hostPlatform.system}.pkgsRocm.llama-cpp;
    openFirewall = false;

    settings = {
      # Keep the API available only to applications on this machine.
      host = "127.0.0.1";
      port = 8080;

      # Omitting `model` starts router mode. Add GGUF files manually to this
      # service-managed directory; rebuilding does not download any models.
      models-dir = "/var/lib/llama-cpp";
      models-max = 1;
      no-models-autoload = true;
      no-warmup = true;
      # Offload model layers to the AMD GPU (subject to available VRAM).
      gpu-layers = "auto";
      ctx-size = 65536;
      jinja = true;

      # Sleep after 5 minutes of idleness to free VRAM. The model will be
      # reloaded on next use (autoload is still enabled for on-demand loading).
      sleep-idle-seconds = 300;
    };
  };

  # Allow the service's dynamic user to access AMD GPU devices.
  systemd.services.llama-cpp.serviceConfig.SupplementaryGroups = [ "render" "video" ];
}
