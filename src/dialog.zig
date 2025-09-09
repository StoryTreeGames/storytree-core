const std = @import("std");

const impl = switch(@import("builtin").os.tag) {
    .windows => @import("windows/dialog.zig"),
    else => @compileError("platform not supported")
};

const Color = @import("./root.zig").Color;
const Font = @import("./root.zig").Font;

pub const Icon = enum {
    warning,
    information,
    question,
    @"error",
};

pub const Buttons = enum {
    abort_retry_ignore,
    cancel_try_continue,
    help,
    ok,
    ok_cancel,
    retry_cancel,
    yes_no,
    yes_no_cancel,

    pub const AbortRetryIgnore = enum { abort, retry, ignore };

    pub const CancelTryContinue = enum { cancel, @"try", @"continue" };

    pub const OkCancel = enum {
        ok,
        cancel,
    };

    pub const RetryCancel = enum {
        retry,
        cancel,
    };

    pub const YesNo = enum {
        yes,
        no,
    };

    pub const YesNoCancel = enum {
        yes,
        no,
        cancel,
    };
};

pub const Button = enum {
    abort,
    retry,
    ignore,
    cancel,
    @"try",
    @"continue",
    ok,
    yes,
    no,
    help,
};

pub const MessageOptions = struct {
    title: ?[]const u8 = null,
    message: ?[]const u8 = null,
    icon: ?Icon = null,
    owner: ?usize = null,
};

pub const FileOpenDialogOptions = struct {
    /// The handle of the window that the dialog will be owned by. If not provided the dialog will be
    /// an independent top-level window.
    owner: ?usize = null,
    /// The text displayed in the title bar of the dialog box
    title: []const u8 = "",
    /// The path to the folder that is always selected when a dialog is opened, regardless of
    /// previous user action. This is not recommended for general use, instead `default_folder`
    /// should be used.
    folder: []const u8 = "",
    /// The file types that are displayed in the File Type dropdown box in the dialog. The first
    /// element is the text description, i.e `"Text Files (*.txt)"` and the second element is the
    /// file extension filter pattern, with multiple entries separated by a semi-colon
    /// i.e `"*.txt;*.log"`
    filters: []const std.meta.Tuple(&.{ []const u8, []const u8 }) = &.{.{ "All types (*.*)", "*.*" }},
    /// The filename to pre-populate in the dialog box
    file_name: []const u8 = "",
    /// Pick folders/directories instead of files
    directory: bool = false,
    /// Allow the user to select more than one item
    multiple: bool = false,
    /// Ensure that the selected item(s) exist
    exists: bool = true,
};


pub const FileSaveDialogOptions = struct {
    /// The HWND of the window that the dialog will be owned by. If not provided the dialog will be
    /// an independent top-level window.
    owner: ?usize = null,
    /// The text displayed in the title bar of the dialog box
    title: []const u8 = "",
    /// The path to the folder that is always selected when a dialog is opened, regardless of
    /// previous user action. This is not recommended for general use, instead `default_folder`
    /// should be used.
    folder: []const u8 = "",
    /// The file types that are displayed in the File Type dropdown box in the dialog. The first
    /// element is the text description, i.e `"Text Files (*.txt)"` and the second element is the
    /// file extension filter pattern, with multiple entries separated by a semi-colon
    /// i.e `"*.txt;*.log"`
    filters: []const std.meta.Tuple(&.{ []const u8, []const u8 }) = &.{.{ "All types (*.*)", "*.*" }},
    /// The filename to pre-populate in the dialog box
    file_name: []const u8 = "",
    /// Whether the user should be prompted when creating or overwritting a file
    prompt_on_create: bool = false,
};

pub const ColorOptions = struct {
    owner: ?usize = null,
    initial: Color = .{ .red = 200, .green = 100, .blue = 100 },
    custom: ?*[16]Color = null,
};

pub const FontOptions = struct {
    owner: ?usize = null,
    color: Color = .{},
    face: []const u8 = "Arial",
    style: []const u8 = "Regular",
    point_size: i32 = 12,
};

pub const message = impl.message;
/// Caller is responsible for freeing the returned array of selected paths
pub const open = impl.open;
pub const save = impl.save;
pub const color = impl.color;
/// Caller is responsible for freeing the returned `Font.name`
pub const font = impl.font;
