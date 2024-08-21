const std = @import("std");
const print = std.debug.print;
const math = std.math;
const vec3 = @Vector(3, f64);
const Ray = @import("hittable.zig").Ray;

const utils = @import("utils.zig");
const toVec3 = utils.toVec3;
const Interval = utils.Interval;

const hit = @import("hittable.zig");
const HittableList = hit.HittableList;
const HitRecord = hit.HitRecord;

const mat_math = @import("mat_math.zig");
const unit_vector = mat_math.unit_vector;
const length = mat_math.length;
const cross = mat_math.cross;

pub const Camera = struct {
    aspect_ratio: f64,
    image_width: i64,
    samples_per_pixel: i64,
    max_depth: i64,
    vfov: f64,
    defocus_angle: f64,
    focus_dist: f64,

    image_height: i64,
    center: vec3,
    pixel_samples_scale: f64,
    pixel00_loc: vec3,
    pixel_delta_u: vec3,
    pixel_delta_v: vec3,
    defocus_disk_u: vec3,
    defocus_disk_v: vec3,

    u: vec3,
    v: vec3,
    w: vec3,

    pub fn new() Camera {
        const aspect_ratio: f64 = 16.0 / 9.0;
        const image_width: i64 = 512; // Possible 128, 256, 512, 1024, 1280, 1920, 2560, 3840, 7680
        const samples_per_pixel = 50;
        const max_depth = 10;
        const vfov = 20;
        const lookfrom = vec3{ 13, 2, 3 };
        const lookat = vec3{ 0, 0, 0 };
        const vup = vec3{ 0, 1, 0 };

        const defocus_angle = 0.6;
        const focus_dist = 10;

        const camera_center = lookfrom;
        const image_height: i64 = image_width / aspect_ratio;
        const pixel_samples_scale = 1.0 / @as(f64, @floatFromInt(samples_per_pixel));

        // Camera
        const theta = utils.degrees_to_radians(vfov);
        const h = @tan(theta / 2);

        const viewport_height: f64 = 2.0 * h * focus_dist;
        const viewport_width: f64 = viewport_height * aspect_ratio;

        const w = unit_vector(lookfrom - lookat);
        const u = unit_vector(cross(vup, w));
        const v = cross(w, u);

        const viewport_u = toVec3(viewport_width) * u;
        const viewport_v = toVec3(viewport_height) * -v;

        const pixel_delta_u = viewport_u / toVec3(image_width);
        const pixel_delta_v = viewport_v / toVec3(image_height);

        const viewport_upper_left = camera_center - toVec3(focus_dist) * w - viewport_u / toVec3(2) - viewport_v / toVec3(2);
        const pixel00_loc = viewport_upper_left + toVec3(0.5) * (pixel_delta_u + pixel_delta_v);

        const defocus_radius = focus_dist * @tan(utils.degrees_to_radians(defocus_angle / 2));
        const defocus_disk_u = u * toVec3(defocus_radius);
        const defocus_disk_v = v * toVec3(defocus_radius);

        return Camera{
            .aspect_ratio = aspect_ratio,
            .image_width = image_width,
            .samples_per_pixel = samples_per_pixel,
            .max_depth = max_depth,
            .vfov = vfov,
            .focus_dist = focus_dist,
            .defocus_angle = defocus_angle,

            .u = u,
            .v = v,
            .w = w,

            .defocus_disk_v = defocus_disk_v,
            .defocus_disk_u = defocus_disk_u,
            .image_height = image_height,
            .center = camera_center,
            .pixel_samples_scale = pixel_samples_scale,
            .pixel00_loc = pixel00_loc,
            .pixel_delta_u = pixel_delta_u,
            .pixel_delta_v = pixel_delta_v,
        };
    }

    pub fn render(self: Camera, world: HittableList, writer: anytype) !void {
        // Write the PPM header
        try writer.print("P3\n{} {}\n255\n", .{ self.image_width, self.image_height });

        // Write the pixel data
        for (0..@as(usize, @intCast(self.image_height))) |i| {
            const h = @as(i64, @intCast(i));
            pbar(h, self.image_height);
            for (0..@as(usize, @intCast(self.image_width))) |j| {
                const w = @as(i64, @intCast(j));

                var pixel_color = vec3{ 0, 0, 0 };
                for (0..@as(usize, @intCast(self.samples_per_pixel))) |_| {
                    const r = self.get_ray(h, w);
                    pixel_color += ray_color(r, self.max_depth, world);
                }

                try writeColor(pixel_color * toVec3(self.pixel_samples_scale), writer);
            }
        }
    }

    fn get_ray(self: Camera, h: i64, w: i64) Ray {
        // Construct a camera ray originating from the origin and directed at randomly sampled
        // point around the pixel location i, j.

        const offset = sample_square();
        const pixel_sample = self.pixel00_loc +
            (toVec3((@as(f64, @floatFromInt(h))) + offset[0]) * self.pixel_delta_v) +
            (toVec3((@as(f64, @floatFromInt(w))) + offset[1]) * self.pixel_delta_u);

        const ray_origin = if (self.defocus_angle <= 0) self.center else self.defocus_disk_sample();
        const ray_direction = pixel_sample - ray_origin;

        return Ray{ .orig = ray_origin, .dir = ray_direction };
    }

    fn defocus_disk_sample(self: Camera) vec3 {
        const p = random_in_unit_disk();
        return self.center + (toVec3(p[0]) * self.defocus_disk_u) + (toVec3(p[1]) * self.defocus_disk_v);
    }
};

fn random_in_unit_disk() vec3 {
    while (true) {
        const p = vec3{ utils.rand_mm(-1, 1), utils.rand_mm(-1, 1), 0 };
        if (mat_math.length_squared(p) < 1)
            return p;
    }
}

fn ray_color(ray: Ray, depth: i64, world: HittableList) vec3 {
    if (depth <= 0) {
        return vec3{ 0, 0, 0 };
    }

    var rec = HitRecord.new();
    if (world.hit(ray, Interval{ .min = 0.001, .max = math.inf(f64) }, &rec)) {
        var ray_scattered = Ray{ .orig = vec3{ 0, 0, 0 }, .dir = vec3{ 0, 0, 0 } };
        var attenuation = vec3{ 0, 0, 0 };

        if (rec.material.scatter(ray, &rec, &attenuation, &ray_scattered)) {
            return attenuation * ray_color(ray_scattered, depth - 1, world);
        }

        return vec3{ 0, 0, 0 };
    }

    const unit_direction = unit_vector(ray.dir);
    const a = 0.5 * (unit_direction[1] + 1.0);
    return toVec3(1.0 - a) * toVec3(1.0) + toVec3(a) * vec3{ 0.5, 0.7, 1.0 };
}

fn sample_square() vec3 {
    return vec3{ utils.rand_01() - 0.5, utils.rand_01() - 0.5, 0 };
}

fn writeColor(color: vec3, writer: anytype) !void {
    var r_float = color[0];
    var g_float = color[1];
    var b_float = color[2];

    r_float = utils.linear_to_gamma(r_float);
    g_float = utils.linear_to_gamma(g_float);
    b_float = utils.linear_to_gamma(b_float);

    const intensity = Interval{ .min = 0, .max = 0.99 };

    const r: u8 = @intFromFloat(256 * intensity.clamp(r_float));
    const g: u8 = @intFromFloat(256 * intensity.clamp(g_float));
    const b: u8 = @intFromFloat(256 * intensity.clamp(b_float));
    try writer.print("{} {} {}\n", .{ r, g, b });
}

fn pbar(value: i64, max: i64) void {
    const used_char = "-";
    const number_of_char = 60;
    const percent_done: i64 = if (value == max - 1) 100 else @divFloor(value * 100, max);
    const full_char: i64 = @divFloor(number_of_char * percent_done, 100);

    print("\r|", .{});

    var i: usize = 0;
    while (i < number_of_char) : (i += 1) {
        if (i < full_char) {
            print("{s}", .{used_char});
        } else {
            print(" ", .{});
        }
    }

    print("| {}%", .{percent_done});

    if (percent_done == 100) {
        print("\n", .{});
    }
}
