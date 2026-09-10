{ pkgs, userName, ... }:

{
  environment.systemPackages = with pkgs; [
    dnsmasq
    docker-compose
  ];

  virtualisation.libvirtd = {
    enable = true;
    qemu.vhostUserPackages = [ pkgs.virtiofsd ];
  };
  programs.virt-manager.enable = true;
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;

  virtualisation.docker.enable = true;

  users.users.${userName}.extraGroups = [
    "libvirtd"
    "docker"
  ];

  networking.firewall.trustedInterfaces = [ "virbr0" ];
}
