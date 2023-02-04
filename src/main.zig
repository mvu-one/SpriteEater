//! This tool takes an aseprite with the below conditions and converts FRAME 1 into
//! sprites and maps usabled by TIC-80 in Javascript mode. \n
//! Aseprite requirements: \n
//! - Dimensions cannot exceed 15360 x 8704 \n
//! - Dimensions must be divisible by 8 \n
//! - Sum of unique 8x8 cells used accross all layers must be no more than 255 \n
//! - All layers must fit in TIC-80 Map \n
//! - Color mode must be set to INDEXED \n
//! - Only 16 colors will be used.  \n
//! NOTE: Will not work on big-endian CPUs.

const std = @import("std");
const err = std.log.err;
const ase = @import("./aseprite.zig");
const bsize = @import("./bytes.zig").bSize;
const readStructFromFile = @import("./bytes.zig").readStructFromFile;
const assert = std.debug.assert;


fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    err(fmt, args);
    std.process.exit(1);
}


fn validateHeader(h: ase.Header)void{
    if (h.magic_number != 0xa5e0) fail ("Bad magic number -- is the input a .aseprite file?", .{});
    if (h.width > 15360 or h.height > 8704) fail ("Canvas too large. Must be smaller than 15360 x 8704", .{});
    if (h.color_depth != 8) fail ("Only supports INDEXED color mode", .{});
    if (h.num_colors > 16) fail ("Must use less than 16 colors", .{});
    if (@mod(h.width, 8) != 0 or @mod(h.height, 8) != 0) fail ("Canvas width and height must be divisble by 8", .{});
}

fn validateFirstFrame(f: ase.FrameHeader)void{
    std.debug.print("{x}", .{f.magic_number});
    if (f.magic_number != 0xf1fa) fail ("Failed to read first frame. Check that your .aseprite file isn't corrupted and has at least 1 frame", .{});
}


pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    // Using a big ol' arena allocator so I can just drop everything at the end
    // TODO use a better allocator lol.
    var gp = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = gp.deinit();
    const alloc = gp.allocator();

    // Each visible layer will be stored as an array of sprite indices
    // (The indices need to be converted to x,y coordinate format later)
    var valid_layers = std.AutoArrayHashMap(u16, []u8).init(alloc);

    // Unique chunks are keyed by an array of pixels, values are the index of the sprite we'll create
    var unique_blocks = std.AutoArrayHashMap([8 * 8]u8, u8).init(alloc);
    var unique_block_index: u8 = 1;

    // TODO, make this a CLI flag
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2){
        fail("Must provide path to .aseprite file", .{});
    }
    
    const file = try std.fs.cwd().openFile(args[1], .{});
    errdefer file.close();

    const header = try readStructFromFile(ase.Header, file);
    validateHeader(header);

    
    // We only process the first frame (that's where the layers are)
    const first_frame = try readStructFromFile(ase.FrameHeader, file);
    validateFirstFrame(first_frame);

    // We'll be drawing each layer to the canvas to ensure our pixels align
    var canvas: []u8 = try alloc.alloc(u8, header.width * header.height);

    // Some helper variables we'll use later (width and height in blocks)
    const block_dim_width = header.width / 8;
    const block_dim_height = header.height / 8;

    // Running total of bytes read. Will be used to seek through the file
    var read_bytes: usize = 0;

    const frame_size = first_frame.frame_bytes - @sizeOf(ase.FrameHeader);

    var layer_index: u16 = 0;
    while (read_bytes < frame_size) {
        var chunk_start = try file.getPos();
        var read_chunk = try readStructFromFile(ase.ChunkHead, file);

        if (read_chunk.type == .Palette){
            var palette_data = try readStructFromFile(ase.PaletteHeader, file);
            var result = [_]u8{0} ** (3 * 16);
            var col_index:usize = 0;
            while (col_index < palette_data.size) : (col_index += 1){
                var color = try readStructFromFile(ase.PaletteEntry, file);
                if (color.has_name == 1){
                    var s_size = try file.reader().readIntNative(u16);
                    _ = try file.reader().skipBytes(@as(usize, s_size), .{});
                }
                result[col_index * 3] = color.red;
                result[col_index * 3 + 1] = color.green;
                result[col_index * 3 + 2] = color.blue;
            }

            try stdout.print("// <PALETTE>\n// 000:", .{});
            for (result) |r|{
                try stdout.print("{x:0<2}", .{r});
            }
            try stdout.print("\n// </PALETTE>\n\n", .{});
            try bw.flush();
        }

        if (read_chunk.type == .Layer) {
            // For valid (normal + visible) layers, we simply allocate a slice for the blocks for later

            var layer_data = try readStructFromFile(ase.LayerInfo, file);
            if (layer_data.type == .Normal and layer_data.flags.visible) {
                var m: []u8 = try alloc.alloc(u8, block_dim_width * block_dim_height);
                try valid_layers.put(layer_index, m);
            }
            layer_index += 1;
        } else if (read_chunk.type == .Cel) {
            // For VISIBLE and COMPRESSED cels, we need to decompress their image data

            var cel_data = try readStructFromFile(ase.CelInfo, file);

            // std.debug.print("Cel Type {}, index: {}, x: {}, y: {}, opacity: {}, \n", .{ cel_data.type, cel_data.layer_index, cel_data.x_pos, cel_data.y_pos, cel_data.opacity });

            if (valid_layers.get(cel_data.layer_index)) |layer_data| {
                if (cel_data.type == .Compressed) {
                    // Width and height...
                    var cel_width = try file.reader().readIntNative(u16);
                    var cel_height = try file.reader().readIntNative(u16);

                    // Clear out our canvas so we can draw to it
                    for (canvas) |*el| {
                        el.* = 0;
                    }

                    // Use zlib to undompress the cel pixel data into a buffer
                    var buf: []u8 = try alloc.alloc(u8, cel_width * cel_height);
                    var stream = try std.compress.zlib.zlibStream(alloc, file.reader());
                    _ = try stream.reader().readAll(buf);

                    // Paste the smaller image into the larger blank canvas (to ensure alignment for the 8x8 blocks)
                    // Algo generated via ChatGPT
                    {
                        var y: usize = 0;
                        while (y < cel_height) : (y += 1) {
                            var x: usize = 0;
                            while (x < cel_width) : (x += 1) {
                                const canvas_index = ((y + @intCast(usize, cel_data.y_pos)) * header.width) + (x + @intCast(usize, cel_data.x_pos));
                                const cel_index = (y * cel_width) + x;
                                canvas[canvas_index] = buf[cel_index];
                            }
                        }
                    }

                    // Cut the data into 8x8 blocks and check if they're unique.
                    // If they are, we'll add them to our hashmap and increase the index
                    var y: usize = 0;
                    while (y < header.height) : (y += 8) {
                        var x: usize = 0;
                        while (x < header.width) : (x += 8) {
                            var yi: usize = 0;
                            var block = [_]u8{0} ** (8 * 8);
                            while (yi < 8) : (yi += 1) {
                                var xi: usize = 0;
                                while (xi < 8) : (xi += 1) {
                                    const index = (y + yi) * header.width + (x + xi);
                                    const block_index = yi * 8 + xi;
                                    block[block_index] = canvas[index];
                                }
                            }

                            // Is the block unique?
                            if (!unique_blocks.contains(block)) {
                                //std.debug.print("BLOCK: {any}\n", .{block});
                                try unique_blocks.put(block, unique_block_index);
                                unique_block_index += 1;
                            }

                            // get the block ID and put it in our map :)
                            // layer_maps[id].push(....)
                            const map_index = (y / 8 * block_dim_width) + (x / 8);
                            layer_data[map_index] = unique_blocks.get(block).?;
                        }
                    }
                }
            }
        }

        // Seek to the end of the "chunk" as defined in the chunk header.
        // We need to do this because some of these chunks (looking at you, zlibreader)
        // can read past the end of the chunk. Also sometimes we don't read ENOUGH data
        // so this will get us back to where we need to be for the next chunk.
        try file.seekTo(chunk_start + read_chunk.chunk_bytes);
        read_bytes += @intCast(usize, read_chunk.chunk_bytes);
    }

    // Done with this now!
    file.close();


    // First up is sprites -- easy enough we just need to print out the unique blocks!
    var sprite_it = unique_blocks.iterator();
    try stdout.print("// <TILES>\n", .{});
    while(sprite_it.next()) |entry| {
        try stdout.print("// {:0>3}:", .{entry.value_ptr.*});
        for (entry.key_ptr.*) |px| {
            try stdout.print("{x}", .{px});
        }
        try stdout.print("\n", .{});
    }
    try stdout.print("// </TILES>\n\n", .{});
    try bw.flush();

    // Next up is maps! First we need to determine how many "maps" we can fit per line...
    // 136 * 8 / document width
    // And how many layers do we have??
    // we will need X 'rows' in the map :)

    const max_layers_per_row = 64*30 / @as(usize, header.width);  // 30 * 8 / (width / 8)
    const num_full_rows = valid_layers.count() / max_layers_per_row;
    const remainder_row_length = @rem(valid_layers.count(), max_layers_per_row);

    var map_row_index:usize=0;

    try stdout.print("// <MAP>\n", .{});

    {
        var full_row_index: usize=0;
        while(full_row_index < num_full_rows) : ( full_row_index += 1 ) {
            var mp = MapPrinter{
                .width = header.width / 8,
                .height = header.height / 8,
                .layer_slice=valid_layers.values()[full_row_index * max_layers_per_row..(full_row_index+1)*max_layers_per_row]};
            while(mp.next()) |m| : (map_row_index += 1){
                try stdout.print("// {:0>3}:{s}\n", .{map_row_index, m});
            }
        }
    }

    // Take care of stragglers
    if (remainder_row_length > 0){
        var mp = MapPrinter{
            .width = header.width / 8,
            .height = header.height / 8,
            .layer_slice=valid_layers.values()[valid_layers.count() - remainder_row_length..]};
        while(mp.next()) |m| : (map_row_index += 1){
            try stdout.print("// {:0>3}:{s}\n", .{map_row_index, m});
        }
    }

    try stdout.print("// </MAP>\n\n", .{});
    try bw.flush();


}

fn int_to_hex_char(int: u8) u8 {
    const chars = "0123456789abcdef";
    return chars[int & 0xf];
}

const MapPrinter = struct{
    layer_slice: [][]u8,
    width: u32,
    height: u32,
    index: u32 = 0,

    pub fn next(it: *MapPrinter) ?[480]u8{
        if (it.index >= it.height) return null;
        var result = [_]u8{'0'} ** 480;
        var cha_index:usize = 0;
        for (it.layer_slice) |layer| {
            var start = it.width * it.index;
            var i: usize = 0;
            while (i < it.width) : (i += 1){
                const sprite_index = layer[start + i];
                const sprite_x = @rem(sprite_index, 16);
                const sprite_y = sprite_index / 16;
                result[cha_index] = int_to_hex_char(sprite_x);
                result[cha_index+1] = int_to_hex_char(sprite_y);
                cha_index += 2;
            }
        }
        it.index += 1;
        return result;
    }
    
    pub fn reset(it: *MapPrinter)void{
        it.index = 0;
    }
};


test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
