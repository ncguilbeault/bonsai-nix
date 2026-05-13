# Bonsai - Nix Flake

A Nix flake that installs [Bonsai-rx](https://bonsai-rx.org/) on Linux via a patched Wine build wrapped in an FHS environment.

## What it provides

- `packages.bonsai` — the `bonsai` launcher and `bonsai-setup` helper (auto-initializes the Wine prefix and installs Bonsai on first run).
- `packages.wine` — a patched WineHQ build (default: 11.0, `wow-full`) wrapped in `buildFHSEnv` with X11, Wayland, GL/Vulkan, and a `winetricks` shim.
- `homeManagerModules.bonsai` — a Home Manager module exposing `programs.bonsai` with options for Wine version/variant/patches and Bonsai version, winetricks verbs, prefix name, and environment variables.

## Quick start

Run Bonsai directly:

```sh
nix run github:ncguilbeault/bonsai-nix
```

Or install into your profile:

```sh
nix profile install github:ncguilbeault/bonsai-nix
bonsai
```

The first invocation runs `bonsai-setup`, which boots a Wine prefix at `~/.local/share/wineprefixes/bonsai`, applies winetricks (`dotnet48 allfonts gdiplus` by default), and installs the Bonsai release `.exe`.

## Home Manager

```nix
{
  inputs.bonsai-nix.url = "github:ncguilbeault/bonsai-nix";

  # in your home configuration:
  imports = [ inputs.bonsai-nix.homeManagerModules.bonsai ];
  programs.bonsai = {
    enable = true;
    bonsai.version = "2.9.0";
    wine.variant = "wow-full";
  };
}
```

See `nix/hm-module.nix` for the full option set.
