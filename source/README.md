# HOTTEXT

A hot medium for plain text.

Reads text from stdin, starts paused.

Inspired by [Stutter](https://ino.is/stutter).

Wrap it up in a script, set it as your PAGER, or just use it directly.
``` sh
fortune | hottext
```

## Install

Requires Nim and SDL2.

``` sh
export PATH=$PATH:$HOME/.nimble/bin
nimble install hottext
```

## Configuration

Configuration is done via environmental variables.

### HOTTEXT_FONT_PATH
Path to a TTF font file. If set at build-time then this font file will be a baked-in default.

### HOTTEXT_FONT_SIZE
Size of font by some definition of size.

### HOTTEXT_WPM
Words-per-minute, defaults to 400.

---

[![Packaging status](https://repology.org/badge/vertical-allrepos/hottext.svg)](https://repology.org/project/hottext/versions)
