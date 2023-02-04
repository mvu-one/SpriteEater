//! A partial implementation of the specifications at https://github.com/aseprite/aseprite/blob/v1.2.40/docs/ase-file-specs.md
//! Most chunk types and options are ignored entirely.

pub const Header = packed struct {
    filesize: u32,
    magic_number: u16,
    num_frames: u16,
    width: u16,
    height: u16,
    color_depth: u16,
    flags: u32,
    speed: u16,
    _pad1: u64,
    palette_mask: u8,
    _pad2: u24,
    num_colors: u16,
    pixel_width: u8,
    pixel_height: u8,
    grid_x: i16,
    grid_y: i16,
    grid_width: u16,
    grid_height: u16,
    _pad3: u672,
};

pub const FrameHeader = packed struct {
    frame_bytes: u32,
    magic_number: u16,
    _pad1: u80, // Discard the rest
};

/// Layer Flags for layers. We only care about visibility so only the visible flag is used.
const LayerFlags = packed struct {
    visible: bool,
    _unused: u15,
};

const LayerType = enum(u16) {
    Normal = 0,
    Group = 1,
    Tilemap = 2,
};

/// Only implements flags and layer type
pub const LayerInfo = packed struct {
    flags: LayerFlags,
    type: LayerType,
    // Ignore the rest :) 
};

// ChunkType Enum borrowed from https://github.com/BanchouBoo/tatl/blob/master/tatl.zig
const ChunkType = enum(u16) {
    OldPaletteA = 0x0004,
    OldPaletteB = 0x0011,
    Layer = 0x2004,
    Cel = 0x2005,
    CelExtra = 0x2006,
    ColorProfile = 0x2007,
    Mask = 0x2016,
    Path = 0x2017,
    Tags = 0x2018,
    Palette = 0x2019,
    UserData = 0x2020,
    Slices = 0x2022,
    Tileset = 0x2023,
    _,
};

pub const ChunkHead = packed struct {
    chunk_bytes: u32,
    type: ChunkType,
};

const CelType = enum(u16) {
    Raw = 0,
    Linked = 1,
    Compressed = 2,
    CompressedTilemap = 3,
    _,
};

pub const CelInfo = packed struct {
    layer_index: u16,
    x_pos: i16,
    y_pos: i16,
    opacity: u8,
    type: CelType,
    _unused: u56,
};

pub const PaletteHeader = packed struct {
    size: u32,
    i_from: u32,
    i_to: u32,
    _pad: u64,
};

pub const PaletteEntry = packed struct {
    // Does not include name -- will need to manually skip if present
    has_name: u16,
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8,
};