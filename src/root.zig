const std = @import("std");
const Env = @import("dotenv");
const httpz = @import("httpz");
const pg = @import("pg");

const presence = @import("presence.zig");

const PORT = 8080;

const ArrayList = std.ArrayList;
const Presence = presence.Presence;
const PresenceBuilder = presence.PresenceBuilder;

const RequestError = error{
    BadRequest,
    InternalServerError,
};

const App = struct {
    db: *pg.Pool,
};

pub fn startServer() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var db = try pg.Pool.init(allocator, .{ .connect = .{ .port = 5432, .host = "localhost" }, .auth = .{ .password = "postgres", .username = "postgres", .database = "postgres", .timeout = 10_000 }, .timeout = 10_000 });
    defer db.deinit();

    std.debug.print("Successfully connected to the db\n", .{});

    var app = App{
        .db = db,
    };

    var server = try httpz.Server(*App).init(allocator, .{ .port = PORT, .request = .{ .max_form_count = 20 } }, &app);
    var router = try server.router(.{});

    router.get("/*", resouces_handler, .{});
    router.post("/", presence_handler, .{});
    std.debug.print("Starting server at http://localhost:{d}\n", .{PORT});
    try server.listen();
}

fn resouces_handler(
    _: *App,
    req: *httpz.Request,
    res: *httpz.Response,
) !void {
    var path = req.url.path;
    if (std.mem.eql(u8, path, "/")) {
        path = "/index.html";
    }

    var pathBuf: [128]u8 = undefined;
    path = try std.fmt.bufPrint(&pathBuf, "public{s}", .{path});

    const fileContent = std.fs.cwd().readFileAlloc(res.arena, path, 10 * 1024 * 1024) catch {
        res.status = 404;
        res.body = "Not Found";
        return;
    };

    res.body = try std.fmt.allocPrint(res.arena, "{s}", .{fileContent});
}

fn presence_handler(
    app: *App,
    req: *httpz.Request,
    res: *httpz.Response,
) !void {
    var formData = try req.formData();
    var it = formData.iterator();
    var builder = try PresenceBuilder.init(req.arena);
    while (it.next()) |kv| {
        builder.setProp(kv.key, kv.value);
    }

    const presences = try builder.build();
    defer req.arena.free(presences);

    var insertedRow = (try app.db.row(
        \\ INSERT INTO presences (name, phone, restriction)
        \\ VALUES ($1,$2,$3)
        \\ RETURNING id
    , .{ presences[0].name, presences[0].phone, presences[0].restriction })) orelse return error.InternalServerError;
    defer insertedRow.deinit() catch {};

    const insertedId = insertedRow.get(i32, 0);
    if (presences.len > 1) {
        for (presences[1..]) |pres| {
            _ = try app.db.exec("INSERT INTO presences (name, phone, restriction, invited_by) VALUES ($1, $2, $3, $4)", .{
                pres.name,
                pres.phone,
                pres.restriction,
                insertedId,
            });
        }
    }

    res.status = 200;
}
