# Bonsai - Nix Flake

A Nix flake that installs [Bonsai-rx](https://bonsai-rx.org/) on Linux via a patched Wine build wrapped in an FHS environment.

## What it provides

- `packages.bonsai` — the `bonsai` launcher and `bonsai-setup` helper (auto-initializes the Wine prefix and installs Bonsai on first run). Symlink-joined with `packages.wine` by default.
- `packages.wine` — a patched WineHQ build (default: 11.0, `wow-full`) wrapped in `buildFHSEnv` with X11, Wayland, GL/Vulkan, plus a `winetricks` shim and aliases for `wineboot`, `wineserver`, `winecfg`, `regedit`, `wineconsole`, `msiexec`, `winefile`, `notepad`, `uninstaller`, `winedbg`.
- `homeManagerModules.bonsai` — a Home Manager module exposing `programs.bonsai`. Adds the resolved package to `home.packages`.
- `nixosModules.bonsai` — a NixOS module exposing the same `programs.bonsai` interface. Adds the resolved package to `environment.systemPackages` for a system-wide install.

Both modules share a common backbone (`nix/common.nix`) that declares submodule options under `programs.bonsai.wine` (version, sha256, variant, mirror, patches, replaceUpstreamPatches, withWinetricks, extraFhsPackages, extraEnv, winePrefixes, prefixName) and `programs.bonsai.bonsai` (version, sha256, mirror, prefixName, wineArch, winetricksVerbs, winetricksArgs, winetricksMarkerTag, installerArgs, extraEnv, bundleWine, winePrefixes), plus an `installWine` toggle declared by each install-site wrapper.

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

The first invocation runs `bonsai-setup`, which boots a Wine prefix at `~/.local/share/wineprefixes/wine-bonsai`, applies winetricks (`dotnet48 allfonts gdiplus` by default), and installs the Bonsai release `.exe`. Subsequent runs reuse the prefix; per-step markers (`.bonsai-booted`, `.bonsai-winetricks-<tag>`, `.bonsai-installed-<version>`) make setup idempotent.

`packages.wine` is exposed separately so you can run `winecfg`, `regedit`, etc. against the same prefix:

```sh
nix run github:ncguilbeault/bonsai-nix#wine -- winecfg
# or, once installed:
WINEPREFIX=~/.local/share/wineprefixes/wine-bonsai winecfg
```

## Patching Wine

Drop one or more `.patch` files into `patches/` (or anywhere reachable) and pass them via the module option. Patches are appended to the upstream Wine patch list by default; set `replaceUpstreamPatches = true` to fully replace them.

```nix
programs.bonsai.wine.patches = [ ./patches/fix-my-bug.patch ];
```

## Home Manager (per-user install)

```nix
{
  inputs.bonsai-nix.url = "github:ncguilbeault/bonsai-nix";

  # in your home configuration:
  imports = [ inputs.bonsai-nix.homeManagerModules.bonsai ];
  programs.bonsai = {
    enable = true;

    wine = {
      variant = "wow-full";
      patches = [ ./patches/fix-my-bug.patch ];
    };

    bonsai = {
      version = "2.9.0";
      winetricksVerbs = [ "dotnet48" "allfonts" "gdiplus" ];
    };
  };
}
```

## NixOS module (system-wide install)

```nix
{
  inputs.bonsai-nix.url = "github:ncguilbeault/bonsai-nix";

  # in your system configuration:
  imports = [ inputs.bonsai-nix.nixosModules.bonsai ];
  programs.bonsai = {
    enable = true;

    wine.patches = [ ./patches/fix-my-bug.patch ];
    bonsai.winetricksVerbs = [ "dotnet48" "allfonts" "gdiplus" ];
  };
}
```

This puts `bonsai`, `bonsai-setup`, and the patched `wine`/`winecfg`/`regedit`/etc. on every user's `PATH`. The Wine prefix itself remains per-user (stateful, created under each user's `$HOME` on first run), so each user gets their own prefix initialized by `bonsai-setup`.

The HM and NixOS modules expose the same `programs.bonsai` interface — pick one based on whether you want a per-user or system-wide install. Don't import both into the same evaluation.

See `nix/common.nix` for the full option set and defaults.

## Layout

```
flake.nix             # inputs, packages, homeManagerModules, nixosModules
patches/              # drop wine .patch files here
nix/
  wine.nix            # WineHQ tarball override + FHS wrapper + aliases
  bonsai.nix          # installer fetch + bonsai-setup / bonsai scripts
  common.nix          # programs.bonsai options + package construction
  hm-module.nix       # Home Manager wrapper (writes home.packages)
  nixos-module.nix    # NixOS wrapper (writes environment.systemPackages)
```
