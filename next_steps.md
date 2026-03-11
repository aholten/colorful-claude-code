# Next Steps: Mintty Nerd Font Icon Rendering

## Key Discovery

mintty issue #1104 confirms the maintainer implemented **overdraw rendering** for PUA characters.
This means full-size Nerd Font icons should render without clipping in mintty 3.7.7.

We haven't tried the right combination yet.

## What to try next

### Attempt: FontChoice with non-Mono as secondary font

Previous attempt used `Font2=FiraCode Nerd Font Mono` (small icons, no clipping).
This time, use the **non-Mono** variant as Font2 so icons are full-size, and let mintty's overdraw handle the rest.

```ini
# .minttyrc
Font=FiraCode Nerd Font Mono
Font2=FiraCode Nerd Font
FontChoice=Private:2
```

The idea: main font is Mono (all text renders normally in 1 cell). PUA characters (Nerd Font icons)
get routed to the non-Mono variant via FontChoice. Mintty's overdraw feature (from issue #1104)
should let the full-size glyphs render beyond their cell without clipping.

### If that still clips, try the "+" prefix

The mintty docs mention that "+" in FontChoice adjusts secondary font sizing:

```ini
FontChoice=+Private:2
```

### If that doesn't work either, try CharNarrowing

Issue #1104 mentions `CharNarrowing=100` (disables auto-narrowing). Combine with above:

```ini
Font=FiraCode Nerd Font Mono
Font2=FiraCode Nerd Font
FontChoice=Private:2
CharNarrowing=100
```

### Nuclear option: revert to ambig-wide

If nothing else works, `Charwidth=ambig-wide` is the only thing confirmed to produce
full-size, unclipped icons. The tradeoff is it makes other ambiguous-width characters
(like some Claude Code UI elements) double-wide too.

## Current .minttyrc state

Should be reverted to clean state before testing:

```ini
Font=FiraCode Nerd Font
FontHeight=12
```

(Remove `Charwidth=ambig-wide` if still present)
