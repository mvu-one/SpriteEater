//! Some useful tools for reading bytes from a file, and dealing with
//! the byte-size of packed structs

const File = @import("std").fs.File;

/// Returns the exact byte size of a struct (instead of C-compatible @sizeOf) rounded down.
pub fn bSize(comptime InType: type) usize {
    return @bitSizeOf(InType) / 8;
}

/// Given a struct, determine the difference between @sizeOf and bSize
fn computeByteOffset(comptime InType: type) i64 {
    return @intCast(i64, bSize(InType)) - @intCast(i64, @sizeOf(InType));
}

/// Reads a struct from a File handle, and also compensates
/// for the fact that @sizeOf returns C-compatible values
/// and as such @sizeOf a 6-byte packed struct returns 8, not 6!
/// Need to explore more, anyways this compensates by
/// doing the normal read (which will use sizeOf) and then
/// using bitsize / 8, then seeking backward in the file if 
/// we overshot.
pub fn readStructFromFile(comptime T: type, file: File) !T {
    var out: T = try file.reader().readStruct(T);
    const offset = computeByteOffset(T);
    if (offset != 0) {
        try file.seekBy(offset);
    }
    return out;
}