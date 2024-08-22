const std = @import("std");
const print = std.debug.print;
const math = std.math;
const vec3 = @Vector(3, f64);

const utils = @import("utils.zig");
const Interval = utils.Interval;
const toVec3 = utils.toVec3;

const hit = @import("hittable.zig");
const Sphere = hit.Sphere;
const Hittable = hit.Hittable;
const HittableList = hit.HittableList;
const HitRecord = hit.HitRecord;
const Ray = hit.Ray;

const mat_math = @import("mat_math.zig");
const unit_vector = mat_math.unit_vector;
const length = mat_math.length;

const cam = @import("camera.zig");
const Camera = cam.Camera;

const mat_import = @import("material.zig");
const Material = mat_import.Material;
const Lambertian = mat_import.Lambertian;
const Metal = mat_import.Metal;
const Dielectric = mat_import.Dielectric;

pub fn main() !void {
    const file = try std.fs.cwd().createFile("image.ppm", .{});
    defer file.close();
    var buffered_writer = std.io.bufferedWriter(file.writer());
    const writer = buffered_writer.writer();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer arena.deinit();
    const alloc = arena.allocator();

    const world = try generateRandomScene(alloc);
    const camera = Camera.new(&world);

    const start_time: i64 = std.time.milliTimestamp();
    try camera.render(&writer);
    const end_time: i64 = std.time.milliTimestamp();
    const total_time: f64 = @as(f64, @floatFromInt(end_time - start_time)) / 1000;

    print("Rendering took {d} s\n\n", .{total_time});

    // Flush the buffered writer to ensure all data is written to the file
    try buffered_writer.flush();

    try run_convert_image();
    try run_open_image();
}

pub fn run_convert_image() !void {
    const exec_result = try std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{
            "convert",
            "image.ppm",
            "image.png",
        },
    });

    switch (exec_result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Convert image: Command exited with non-zero status code: {}\n", .{code});
            }
        },
        else => {
            std.debug.print("Convert image: Command did not exit normally\n", .{});
        },
    }
}

pub fn run_open_image() !void {
    const exec_result = try std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{
            "explorer.exe",
            "image.png",
        },
    });

    switch (exec_result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Open image: Command exited with non-zero status code: {}\n", .{code});
            }
        },
        else => {
            std.debug.print("Open image: Command did not exit normally\n", .{});
        },
    }
}

pub fn generateSameScene(alloc: std.mem.Allocator) !HittableList {
    var spheres = std.ArrayList(Hittable).init(alloc);

    // Ground sphere
    try spheres.append(.{
        .sphere = Sphere{
            .center = vec3{ 0, -1000, 0 },
            .radius = 1000,
            .material = Material{ .lambertian = Lambertian{ .albedo = vec3{ 0.5, 0.5, 0.5 } } },
        },
    });

    // Three large spheres
    try spheres.append(.{
        .sphere = Sphere{
            .center = vec3{ 0, 1, 0 },
            .radius = 1.0,
            .material = Material{ .dielectric = Dielectric{ .refraction_index = 1.5 } },
        },
    });
    try spheres.append(.{
        .sphere = Sphere{
            .center = vec3{ -4, 1, 0 },
            .radius = 1.0,
            .material = Material{ .lambertian = Lambertian{ .albedo = vec3{ 0.4, 0.2, 0.1 } } },
        },
    });
    try spheres.append(.{
        .sphere = Sphere{
            .center = vec3{ 4, 1, 0 },
            .radius = 1.0,
            .material = Material{ .metal = Metal{ .albedo = vec3{ 0.7, 0.6, 0.5 }, .fuzz = 0.0 } },
        },
    });

    // Convert ArrayList to a slice and create HittableList
    return HittableList{ .list = spheres.items };
}

pub fn generateRandomScene(alloc: std.mem.Allocator) !HittableList {
    var spheres = std.ArrayList(Hittable).init(alloc);

    // Ground sphere
    try spheres.append(.{
        .sphere = Sphere{
            .center = vec3{ 0, -1000, 0 },
            .radius = 1000,
            .material = Material{ .lambertian = Lambertian{ .albedo = vec3{ 0.5, 0.5, 0.5 } } },
        },
    });

    // Smaller spheres
    var a: i32 = -6;
    while (a < 11) : (a += 1) {
        var b: i32 = -6;
        while (b < 6) : (b += 1) {
            if ((-1 < a) and (a < 1) or ((-1 < b) and (b < 1))) {
                continue;
            }
            const choose_mat = utils.rand_01();
            const center = vec3{
                @as(f64, @floatFromInt(a)) + 0.9 * utils.rand_01(),
                0.2,
                @as(f64, @floatFromInt(b)) + 0.9 * utils.rand_01(),
            };

            var sphere_material: Material = undefined;

            if (choose_mat < 0.5) {
                // diffuse
                const albedo = utils.rand_vec3_01();
                sphere_material = Material{ .lambertian = Lambertian{ .albedo = albedo } };
            } else if (choose_mat < 0.8) {
                // metal
                const albedo = utils.rand_vec3_01();
                const fuzz = utils.rand_01() * 0.5;
                sphere_material = Material{ .metal = Metal{ .albedo = albedo, .fuzz = fuzz } };
            } else {
                // glass
                sphere_material = Material{ .dielectric = Dielectric{ .refraction_index = 1.5 } };
            }

            try spheres.append(.{
                .sphere = Sphere{
                    .center = center,
                    .radius = 0.2,
                    .material = sphere_material,
                },
            });
        }
    }

    // Three large spheres
    try spheres.append(.{
        .sphere = Sphere{
            .center = vec3{ 0, 1, 0 },
            .radius = 1.0,
            .material = Material{ .dielectric = Dielectric{ .refraction_index = 1.5 } },
        },
    });
    try spheres.append(.{
        .sphere = Sphere{
            .center = vec3{ -4, 1, 0 },
            .radius = 1.0,
            .material = Material{ .lambertian = Lambertian{ .albedo = vec3{ 0.4, 0.2, 0.1 } } },
        },
    });
    try spheres.append(.{
        .sphere = Sphere{
            .center = vec3{ 4, 1, 0 },
            .radius = 1.0,
            .material = Material{ .metal = Metal{ .albedo = vec3{ 0.7, 0.6, 0.5 }, .fuzz = 0.0 } },
        },
    });

    // Convert ArrayList to a slice and create HittableList
    return HittableList{ .list = spheres.items };
}
