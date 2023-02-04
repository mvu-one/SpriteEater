![SPRITE EATER](example/logo.png)

-----------

This is a *super* basic commandline tool that takes the layers of an **Aseprite** file and spits out `<PALETTE>`, `<TILES>` and `<MAP>` blocks compatible with **TIC-80** javascript files.

In order to work, your Aseprite file most conform to the following requirements:

- INDEXED color mode
- No more than 16 colors
- Dimensions cannot exceed 15360 x 8704 
- Dimensions must be divisible by 8 
- Sum of unique 8x8 cells used across all layers must be no more than 255 
- All layers must fit into the TIC-80 Map 


The tool will take the **first frame** of the provided file and iterate through **visible layers**, finding all unique 8x8 tiles. It will then reconstruct the original layers (in their original dimensions) out of the tiles in the "MAP" format.

Output just goes to `STDOUT`, so you can copy+paste or post-process it before pasting it into your `.js` file.

> NOTE: In order to manually edit TIC-80 JS files, you'll need to used the paid version which allows external editing of projects.

## How to compile
The tool is written in Zig 0.10.0, so you can just download the zig binaries and compile. To compile and run in one step you can do:

```bash
cd /path/to/sprite-eater
/path/to/zig build run -- ./example/logo.aseprite
```


I don't think anybody's ever actually going to use this library except myself, so I'm not including pre-built binaries. This has only been tested on 64-bit Linux.


## Extra Notes and Resources
This is primarily an experimental one-off project, so it won't likely get much use, however most of what I managed to learn in order to build this was from other random projects strewn about the internet. Here's hoping this code helps someone!

It should be noted:

- This is my first non-trivial zig project, likely not idiomatic or correct
- This code won't run on big-endian machines
- Aseprite's official file specs can be found [here](https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md)
- A more complete Zig X Aseprite library can be found [here](https://github.com/BanchouBoo/tatl)

## Plans
None, really. In theory I'd like to support the ability to offset map / tile stuff and maybe add support for Lua files as well as js.

I might revisit this in the future and extend it to do tilemaps or animations from aseprite into TIC-80