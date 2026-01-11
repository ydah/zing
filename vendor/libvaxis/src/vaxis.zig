pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub const Cell = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    bold: bool = false,
    underline: bool = false,
    italic: bool = false,
};

pub const Dummy = struct {};
