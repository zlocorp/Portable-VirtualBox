# Fixed Alpine console observation fixtures

These are exact BGRA pixels from this project's own disposable Windows CI guest screenshots, gzip-compressed; not imported font source or a general font library. No external font table/code is included. The small glyph dictionary was measured independently at the listed zero-based 8x16 cell coordinates in the successful screenshot, only for the fixed prompt and hexadecimal acknowledgment alphabet. It makes no claim to decode arbitrary guests, fonts, resolutions, colored output or languages. Unknown glyphs are `?`, never guessed.

Successful source: run 43835728404 artifact 14211365592. Failed source: run 43844144887 artifact 14214542310. Both original filenames: `protected-guest-disk-command.png`.

- observed-shell: PNG SHA-256 `db708bdca3abdac4f0b2c9784eb00943ea03164fca599d9468bbbf02ca0d7720`; BGRA SHA-256 `7d25e97d5ebe026ad22f4877673b84916b76b604a8fcbe46fc1fc531c2db7cba`.
- command-as-login: PNG SHA-256 `9967215310bbd7bad6ecea6b28afd9946d3b133f0b0094772d1eac4c88b65592`; BGRA SHA-256 `c1c7ed36890f66116bfe6be7c74b415305e7d1b61315dc48c8b2d197ae5e574f`.

Glyph observations (character, column, row):

- U+0020: (9, 32)
- U+0023: (11, 43)
- U+0030: (54, 43)
- U+0031: (57, 43)
- U+0032: (53, 43)
- U+0033: (30, 46)
- U+0034: (93, 43)
- U+0035: (82, 43)
- U+0036: (56, 43)
- U+0037: (60, 43)
- U+0038: (94, 43)
- U+0039: (28, 46)
- U+003A: (15, 32)
- U+0042: (20, 43)
- U+004F: (21, 43)
- U+0050: (18, 43)
- U+0056: (19, 43)
- U+0058: (22, 43)
- U+005F: (23, 43)
- U+0061: (3, 32)
- U+0062: (79, 43)
- U+0063: (2, 32)
- U+0064: (64, 43)
- U+0065: (13, 43)
- U+0066: (68, 43)
- U+0067: (12, 32)
- U+0068: (5, 32)
- U+0069: (13, 32)
- U+006C: (0, 32)
- U+006E: (14, 32)
- U+006F: (1, 32)
- U+0072: (17, 32)
- U+0073: (7, 32)
- U+0074: (8, 32)
- U+007E: (10, 43)

The failed screen shows the disk command submitted as a login name, followed by Password. It must never pass login, shell or write acknowledgment. The successful historical screen proves shell recognition only, not the new fresh acknowledgment protocol.
