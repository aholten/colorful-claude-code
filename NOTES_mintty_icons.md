# Mintty Nerd Font Icon Rendering — Problem & Options

## Problem

Nerd Font icons (Private Use Area Unicode characters) don't render well in mintty (Git Bash on Windows):

- **FiraCode Nerd Font Mono**: Icons fit in 1 cell but are too small to be legible
- **FiraCode Nerd Font** (non-Mono): Icons are full-size but get clipped on the right side because mintty allocates only 1 cell

`Charwidth=unicode` doesn't help because PUA characters aren't classified as wide in Unicode.

## Options

### Option 1: FontChoice + Mono for icons only (best bet)

Use the non-Mono font for text but assign the Mono variant to PUA characters. `CharNarrowing=100` disables automatic glyph shrinking so Mono icons render at full cell size.

```ini
# .minttyrc
Font=FiraCode Nerd Font
Font2=FiraCode Nerd Font Mono
FontChoice=Private:2
CharNarrowing=100
```

### Option 2: Charwidth=ambig-wide

Different from `Charwidth=unicode` and `Charwidth=ambiguous`. May convince mintty to treat icon characters as double-width.

```ini
# .minttyrc
Charwidth=ambig-wide
```

### Option 3: ECMA-48 escape sequences in the hook script

Emit `CSI 1 SP Z` (Presentation Expand Or Contract) before each icon to force double-cell rendering. Requires mintty 3.0.3+.

- `\e[1 Z` — enforce double-cell
- `\e[0 Z` — reset to default width

Would need to modify `annotate-pre.sh` to wrap each icon with these sequences.

### Option 4: Switch terminal emulator

These terminals handle non-Mono Nerd Fonts correctly without workarounds:

- **Windows Terminal** — renders double-width glyphs natively
- **WezTerm** — bundles Nerd Font Symbols, works out of the box
- **Alacritty** — allows glyph overdraw (some Windows 11 issues reported)

## Mintty version notes

- 3.0.3+: Added `CharNarrowing` and alternative font support (Font1-Font10)
- 3.1.5+: Enabled auto-narrowing for Private Use characters (Nerd Font support)
- 3.4.5+: Further double-width character detection improvements

Check version: Right-click mintty title bar > About

## Result

**Option 2 (`Charwidth=ambig-wide`) worked.** Full-size icons, no clipping, no extra escape sequences needed.

Final `.minttyrc`:
```ini
Font=FiraCode Nerd Font
FontHeight=12
Charwidth=ambig-wide
```

Options 1 and 3 did not solve the problem. Option 1 (FontChoice + Mono) prevented clipping but icons were still too small. Option 3 (ECMA-48 PEC sequences) had no visible effect.
