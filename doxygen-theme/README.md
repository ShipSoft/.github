# SHiP Doxygen theme

The look of every ShipSoft Doxygen reference: CERN blue (Pantone 286 C,
`#0033a0`), the SHiP wheel as logo and favicon, light and dark mode, and a
footer linking to the [SHiP Software documentation](https://shipsoft.github.io/Documentation/).
It shares its design tokens with the Zensical theme of
[ShipSoft/Documentation](https://github.com/ShipSoft/Documentation), so a colour
change goes into both `ship-doxygen.css` here and `docs/stylesheets/ship.css`
there.

The theme is [doxygen-awesome-css](https://github.com/jothepro/doxygen-awesome-css)
v2.5.0 (MIT, see `LICENSE.doxygen-awesome`) in its sidebar-only layout, with
the dark-mode toggle, copy buttons, paragraph links, interactive TOC and tabs,
plus `ship-doxygen.css` on top. The scripts and the favicon are wired in through
`footer.html`, which only uses standard Doxygen placeholders and works with
Doxygen 1.9.8 (what `ubuntu-latest` installs) and newer.

## In CI

The `doxygen-pages.yml` and `doxygen-gh-pages.yml` workflows apply the theme by
default. Projects don't need to copy anything or change their Doxyfile. Pass
`theme: false` to build without it.

## Locally

Clone this repository and run the wrapper from the project's root:

```sh
/path/to/ShipSoft/.github/doxygen-theme/doxygen-ship doxygen/Doxyfile
```

`doxygen-ship` sets `SHIP_DOXYGEN_THEME` to its own folder and feeds Doxygen the
project's Doxyfile followed by `@INCLUDE = $SHIP_DOXYGEN_THEME/Doxyfile.ship`.
Because the theme comes last, its HTML settings (logo, footer, stylesheets,
colours, tree view, SVG graphs) win over the project's.

## Notes

- `HTML_COLORSTYLE = LIGHT` needs Doxygen 1.9.5 or newer.
- The dark-mode script loads from the footer, so a page opened in dark mode
  shows light for a few milliseconds. Moving the `<script>` tags into a custom
  `HTML_HEADER` would avoid that, but the header would have to be generated for
  a specific Doxygen version.
- Set `PROJECT_BRIEF` in the project's Doxyfile so the title band shows a one
  line description next to the name.
