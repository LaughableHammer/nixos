{
  # CLI digital forensics toolkit for analysing disk images and memory dumps.
  #
  # Analysis-only, and all of it runs unprivileged on image files, so it lives in
  # the user profile rather than environment.systemPackages: no imaging or
  # acquisition tools, and nothing here touches this machine's own disks.
  # Volatility 3 symbol tables (Windows PDB / Linux ISF profiles) are downloaded
  # at runtime, not packaged here.
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    # Read E01/Expert Witness images (ewfinfo, ewfexport).
    libewf

    sleuthkit
    testdisk

    # Offline SAM/SYSTEM hive editing and password hash listing.
    chntpw
    # Registry hive parsing (RegRipper plugins).
    regripper
    # Recycle Bin ($I/$R) metadata parsing.
    rifiuti
    # Outlook PST/OST email storage analysis.
    pff-tool

    # Firmware/file carving and embedded signature scanning.
    binwalk
    # Header/footer based file carving.
    foremost
    scalpel
    # Metadata extraction for images, documents and media.
    exiftool
    # Known-file hashing (md5deep/hashdeep) and fuzzy hashing (ssdeep).
    hashdeep
    ssdeep
    # Bulk data extraction: features, strings, emails, network artefacts.
    bulk_extractor
    # Signature matching for files and memory dumps.
    yara

    # Volatility 3 framework (windows/linux/mac plugins).
    volatility3
  ];
}
