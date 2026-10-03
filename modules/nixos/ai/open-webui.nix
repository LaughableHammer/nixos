{ ... }:

{
  services.open-webui = {
    enable = true;
    # Only reachable from this machine; openwebui.local resolves to this.
    host = "127.0.0.1";
    port = 8081;
    openFirewall = false;

    environment = {
      # Talk to the local llama-cpp server started by the ai module.
      OPENAI_API_BASE_URL = "http://127.0.0.1:8080/v1";
      # Key is unused by llama-cpp but Open WebUI requires one.
      OPENAI_API_KEY = "sk-local";
    };
  };
}
