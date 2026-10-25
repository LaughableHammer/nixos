{ pkgs, userName, ... }:

{
  environment.systemPackages = with pkgs; [
    dnsmasq
    docker-compose
    swtpm
  ];

  virtualisation = {
    libvirtd = {
      enable = true;
      qemu = {
        swtpm.enable = true;
        vhostUserPackages = [ pkgs.virtiofsd ];
      };
    };
    docker = {
      enable = true;
      # Rootless Docker maps container-root to the invoking user, so the Pi
      # sandbox can run as root (needed for `apk`) without writing root-owned
      # files into bind-mounted host directories. Sandbox runs select this daemon
      # via DOCKER_HOST; other Docker usage keeps the default socket.
      rootless = {
        enable = true;
        setSocketVariable = false;
      };
    };
  };

  programs.virt-manager.enable = true;

  users.users.${userName}.extraGroups = [
    "libvirtd"
    "docker"
  ];

  networking.firewall.trustedInterfaces = [ "virbr0" ];
}
