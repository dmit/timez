const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const stderr = std.io.getStdErr().writer();

    var args = try std.process.argsAlloc(alloc);
    if (args.len == 1) {
        try stderr.print("Usage: {s} command [arguments...]", .{args[0]});
        std.process.exit(0);
    }

    var proc = std.process.Child.init(args[1..], alloc);
    proc.request_resource_usage_statistics = true;
    try proc.spawn();
    const timings = try waitForProcess(&proc);

    var exitCode: u8 = 2;
    switch (try proc.term.?) {
        .Exited => |status| {
            exitCode = status;
            try stderr.print("\nExited with code: {d}\n", .{status});
        },
        .Signal => |signal| try stderr.print("\nExited with signal: {d}\n", .{signal}),
        .Stopped => |signal| try stderr.print("\nStopped with signal: {d}\n", .{signal}),
        .Unknown => |signal| try stderr.print("\nExited (unknown) with signal: {d}\n", .{signal}),
    }

    // .PeakVirtualSize,
    // .VirtualSize,
    // .PageFaultCount,
    // .PeakWorkingSetSize,
    // .WorkingSetSize,
    // .QuotaPeakPagedPoolUsage,
    // .QuotaPagedPoolUsage,
    // .QuotaPeakNonPagedPoolUsage,
    // .QuotaNonPagedPoolUsage,
    // .PagefileUsage,
    // .PeakPagefileUsage,
    const usg = proc.resource_usage_statistics.rusage;
    try stderr.print("\n Working set: {d:.3}MB\n", .{byteToMegabytes(usg.?.PeakWorkingSetSize)});
    try stderr.print(" Page faults: {d}\n", .{usg.?.PageFaultCount});

    if (timings) |t| {
        try stderr.print("Elapsed time: {d:.3}s\n", .{t.elapsedSecs()});
        try stderr.print(" Kernel time: {d:.3}s\n", .{t.kernelSecs()});
        try stderr.print("   User time: {d:.3}s\n", .{t.userSecs()});
    } else {
        try stderr.writeAll("\nFailed to get process timings.\n");
        std.process.exit(1);
    }

    std.process.exit(exitCode);
}

inline fn byteToMegabytes(bytes: usize) f64 {
    const bytesFloat: f64 = @floatFromInt(bytes);
    return bytesFloat / 1024.0 / 1024.0;
}

inline fn filetimeDurationNanos(ft: std.os.windows.FILETIME) i128 {
    const timeUnits = (@as(i128, ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
    return timeUnits * 100;
}

const ProcessTimings = struct {
    elapsedNanos: i128,
    kernelNanos: i128,
    userNanos: i128,

    inline fn nanosToSeconds(nanos: i128) f64 {
        const nanosFloat: f64 = @floatFromInt(nanos);
        return nanosFloat / 1_000_000_000.0;
    }

    pub fn elapsedSecs(self: *const @This()) f64 {
        return nanosToSeconds(self.elapsedNanos);
    }

    pub fn kernelSecs(self: *const @This()) f64 {
        return nanosToSeconds(self.kernelNanos);
    }

    pub fn userSecs(self: *const @This()) f64 {
        return nanosToSeconds(self.userNanos);
    }
};

fn waitForProcess(self: *std.process.Child) !?ProcessTimings {
    const os = std.os;
    const windows = os.windows;
    const Child = std.process.Child;

    const result = windows.WaitForSingleObjectEx(self.id, windows.INFINITE, false);

    self.term = @as(Child.SpawnError!Child.Term, x: {
        var exit_code: windows.DWORD = undefined;
        if (windows.kernel32.GetExitCodeProcess(self.id, &exit_code) == 0) {
            break :x Child.Term{ .Unknown = 0 };
        } else {
            break :x Child.Term{ .Exited = @as(u8, @truncate(exit_code)) };
        }
    });

    if (self.request_resource_usage_statistics) {
        self.resource_usage_statistics.rusage = try windows.GetProcessMemoryInfo(self.id);
    }

    var creationTime: std.os.windows.FILETIME = undefined;
    var exitTime: std.os.windows.FILETIME = undefined;
    var kernelTime: std.os.windows.FILETIME = undefined;
    var userTime: std.os.windows.FILETIME = undefined;
    const processTimesSuccess = GetProcessTimes(self.id, &creationTime, &exitTime, &kernelTime, &userTime);

    windows.CloseHandle(self.id);
    windows.CloseHandle(self.thread_handle);
    cleanupStreams(self);

    try result;

    if (processTimesSuccess == 0) {
        return null;
    }
    const elapsedNanos = std.os.windows.fileTimeToNanoSeconds(exitTime) - std.os.windows.fileTimeToNanoSeconds(creationTime);

    return .{ .elapsedNanos = elapsedNanos, .kernelNanos = filetimeDurationNanos(kernelTime), .userNanos = filetimeDurationNanos(userTime) };
}

fn cleanupStreams(self: *std.process.Child) void {
    if (self.stdin) |*stdin| {
        stdin.close();
        self.stdin = null;
    }
    if (self.stdout) |*stdout| {
        stdout.close();
        self.stdout = null;
    }
    if (self.stderr) |*stderr| {
        stderr.close();
        self.stderr = null;
    }
}

// Extern Windows function that's not exposed by std
const BOOL = std.os.windows.BOOL;
const FILETIME = std.os.windows.FILETIME;
const HANDLE = std.os.windows.HANDLE;
const WINAPI = std.os.windows.WINAPI;
extern "kernel32" fn GetProcessTimes(in_hProcess: HANDLE, out_lpCreationTime: *FILETIME, out_lpExitTime: *FILETIME, out_lpKernelTime: *FILETIME, out_lpUserTime: *FILETIME) callconv(WINAPI) BOOL;
