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
        swtpm.enable = true; # Enables software TPM emulation
        vhostUserPackages = [ pkgs.virtiofsd ];
      };
    };
    docker = {
      enable = true;
    };
  };

  programs.virt-manager.enable = true;
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;

  users.users.${userName}.extraGroups = [
    "libvirtd"
    "docker"
  ];

  networking.firewall.trustedInterfaces = [ "virbr0" ];
}
