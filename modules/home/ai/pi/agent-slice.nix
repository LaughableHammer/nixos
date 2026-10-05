{
  pkgs,
  name ? "agent.slice",
  cpuWeight ? 20,
  ioWeight ? 20,
  nice ? 10,
}:

{
  inherit
    name
    cpuWeight
    ioWeight
    nice
    ;

  systemdRun = "${pkgs.systemd}/bin/systemd-run --user --scope --quiet --collect --slice=${name} --nice=${toString nice}";
}
