{ pkgs, userName, ... }:

{
  systemd.services.reboot-to-windows = {
    description = "Set Windows Boot Manager as UEFI BootNext and reboot";
    serviceConfig.Type = "oneshot";
    script = ''
      windows_entry="$(${pkgs.efibootmgr}/bin/efibootmgr | ${pkgs.gawk}/bin/awk '
        /^Boot[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]\*?[[:space:]]+Windows Boot Manager/ {
          print substr($1, 5, 4)
          exit
        }
      ')"

      if [ -z "$windows_entry" ]; then
        echo "Windows Boot Manager was not found in the UEFI boot entries" >&2
        exit 1
      fi

      ${pkgs.efibootmgr}/bin/efibootmgr --bootnext "$windows_entry"
      ${pkgs.systemd}/bin/systemctl reboot
    '';
  };

  # Permit only the active local primary user to start this one root service.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "reboot-to-windows.service" &&
          action.lookup("verb") == "start" &&
          subject.user == "${userName}" &&
          subject.active && subject.local) {
        return polkit.Result.YES;
      }
    });
  '';
}
