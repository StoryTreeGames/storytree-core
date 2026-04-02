const std = @import("std");

pub fn relativeFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var exe_dir_buffer: [260]u8 = undefined;
    var exe_dir = try std.fs.cwd().openDir(try std.fs.selfExeDirPath(&exe_dir_buffer), .{});
    defer exe_dir.close();

    return exe_dir.realpathAlloc(allocator, path);
}

pub fn relative_file_uri(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var exe_dir_buffer: [260]u8 = undefined;
    var exe_dir = try std.fs.cwd().openDir(std.fs.selfExeDirPath(&exe_dir_buffer), .{});
    defer exe_dir.close();

    const file_path =  exe_dir.realpathAlloc(allocator, path);
    defer allocator.free(file_path);

    std.debug.print("{s}\n", .{ file_path });

    const uri = try std.fmt.allocPrint(allocator, "file:///{s}", .{ file_path });
    return uri;
}
