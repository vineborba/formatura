const std = @import("std");
const Env = @import("dotenv");

const Allocator = std.mem.Allocator;

const AppConfig = struct {
    port: u16,

    const Self = @This();

    pub fn init(env: *Env) !Self {
        const port = try std.fmt.parseInt(
            u16,
            env.getWithDefault("APP__PORT", "8080"),
            10,
        );

        return Self{
            .port = port,
        };
    }
};

const DbConfig = struct {
    host: []const u8,
    user: []const u8,
    pass: []const u8,
    db: []const u8,
    port: u16,

    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, env: *Env) !Self {
        const host = env.getWithDefault("DB__HOST", "localhost");
        const user = env.getWithDefault("DB__USER", "postgres");
        const pass = env.getWithDefault("DB__PASS", "postgres");
        const db = env.getWithDefault("DB__DB", "postgres");
        const port = try std.fmt.parseInt(
            u16,
            env.getWithDefault("DB__PORT", "5432"),
            10,
        );

        return Self{
            .host = host,
            .user = user,
            .pass = pass,
            .db = db,
            .port = port,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.host);
        self.allocator.free(self.user);
        self.allocator.free(self.pass);
        self.allocator.free(self.db);
    }
};

pub const Config = struct {
    db: DbConfig,
    app: AppConfig,
    env: Env,

    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var env = try Env.initWithPath(allocator, ".env", 1024 * 1024, true);

        const db = try DbConfig.init(allocator, &env);
        const app = try AppConfig.init(&env);

        return Self{
            .env = env,
            .app = app,
            .db = db,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.db.deinit();
        self.env.deinit();
    }
};
