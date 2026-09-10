{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # JavaScript / TypeScript
    nodejs_22
    typescript
    typescript-language-server
    eslint
    prettier
    pnpm

    # C / C++
    gcc
    clang-tools
    gnumake
    cmake
    ninja
    gdb
    lldb
    pkg-config

    # Python
    python3
    uv

    # General development tools
    git
    ripgrep
    fd
    jq
    shellcheck
    shfmt
    nixd
    nixfmt
  ];

  # Keep extensions mutable so manually installed extensions remain available.
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    mutableExtensionsDir = true;
    profiles.default.extensions =
      with pkgs.vscode-extensions;
      [
        # JavaScript / TypeScript and web development
        bradlc.vscode-tailwindcss
        dbaeumer.vscode-eslint
        ecmel.vscode-html-css
        esbenp.prettier-vscode

        # C / C++
        llvm-vs-code-extensions.vscode-clangd
        ms-vscode.cmake-tools
        ms-vscode.cpptools
        ms-vscode.makefile-tools

        # Common formats and project tooling
        editorconfig.editorconfig
        github.vscode-github-actions
        jnoortheen.nix-ide
        redhat.vscode-yaml
        tamasfe.even-better-toml
      ]
      ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        {
          # Current theme: "Celestial Echoes"
          publisher = "jemo";
          name = "celestial-echoes";
          version = "0.0.7";
          hash = "sha256-cccCmXUUMhMI8fzehgzYfewwwWEyDlWu3bHsurdNV0A=";
        }
      ];
  };
}
