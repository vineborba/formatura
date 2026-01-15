const std = @import("std");
const Env = @import("dotenv");
const httpz = @import("httpz");
const pg = @import("pg");

const presence = @import("presence.zig");

const PORT = 8080;
const MAX_BODY_SIZE = 10 * 1024 * 1024;

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

    std.log.info("Successfully connected to the db\n", .{});

    var app = App{
        .db = db,
    };

    var server = try httpz.Server(*App).init(allocator, .{ .port = PORT, .request = .{ .max_form_count = 20 } }, &app);
    var router = try server.router(.{});

    router.get("/*", resources_handler, .{});
    router.post("/", presence_handler, .{});
    std.log.info("Starting server at http://localhost:{d}\n", .{PORT});
    try server.listen();
}

fn resources_handler(
    _: *App,
    req: *httpz.Request,
    res: *httpz.Response,
) !void {
    var path = req.url.path;
    if (std.mem.eql(u8, path, "/")) {
        path = "/index.html";
    }

    if (std.mem.endsWith(u8, path, "/")) {
        path = std.mem.trimEnd(u8, path, "/");
    }

    const basename = std.fs.path.basename(path);
    if (!std.mem.containsAtLeast(u8, basename, 1, ".")) {
        path = try std.mem.concat(
            req.arena,
            u8,
            &[_][]const u8{ path, ".html" },
        );
    }

    var publicDir = try std.fs.cwd().openDir("public", .{ .iterate = true });
    defer publicDir.close();

    const safePath = path[1..];
    var file = publicDir.openFile(safePath, .{ .mode = .read_only }) catch |err| {
        if (err == error.FileNotFound) {
            res.status = 404;
            res.body = "Not Found";
            return;
        }

        res.status = 403;
        res.body = "Forbidden";
        return;
    };
    defer file.close();

    const fileContent = file.readToEndAlloc(res.arena, MAX_BODY_SIZE) catch {
        res.status = 500;
        res.body = "Internal Server Error";
        return;
    };

    res.content_type = httpz.ContentType.forFile(path);
    res.body = fileContent;
}

fn presence_handler(
    app: *App,
    req: *httpz.Request,
    res: *httpz.Response,
) !void {
    var formData = try req.formData();
    var it = formData.iterator();
    var builder = try PresenceBuilder.init(req.arena);
    defer builder.deinit();
    while (it.next()) |kv| {
        builder.setProp(kv.key, kv.value) catch {
            res.status = 400;
            res.body = "Invalid form data";
            return;
        };
    }

    const presences = try builder.build();

    var insertedRow = (try app.db.row(
        \\ INSERT INTO presences (name, phone, restriction)
        \\ VALUES ($1,$2,$3)
        \\ RETURNING id
    , .{ presences[0].name, presences[0].phone, presences[0].restriction })) orelse {
        res.status = 500;
        res.body = "Internal Server Errro";
        return;
    };

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

    res.status = 303;
    res.headers.add("Location", "success");
    return;
}
