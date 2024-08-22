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

const AtomicOrder = @import("std").builtin.AtomicOrder;
const Thread = std.Thread;
const Semaphore = std.Thread.Semaphore;

const Pixel = struct {
    w: usize,
    h: usize,
    color: vec3,
};

const ThreadInfo = struct {
    thread_index: usize,
    semaphore_ptr: *Semaphore,
};

// Resolution
const aspect_ratio: f64 = 16.0 / 9.0;
const image_width: usize = 2560; // Possible 128, 256, 512, 1024, 1280, 1920, 2560, 3840, 7680
const image_height: usize = image_width / aspect_ratio;

// Ray precision
const samples_per_pixel = 500;
const max_depth = 50;

// Camera lenses
const defocus_angle = 0.6;
const focus_dist = 10;
const vfov = 20;

// Camera position
const lookfrom = vec3{ 13, 2, 3 };
const lookat = vec3{ 0, 0, 0 };
const vup = vec3{ 0, 1, 0 };

// Number of thread to use
const n_threads_to_spawn = 100;

// Global var for multi-thread
var completion_count: usize = 0;
var next_entry_to_do: usize = 0;
var entry_count: usize = 0;
var entry_buffer: [image_width * image_height]Pixel = undefined;
var _camera: *const Camera = undefined;

fn addWork(semaphore_ptr: *Semaphore) void {
    const entry_index = @atomicLoad(usize, &entry_count, AtomicOrder.seq_cst);

    // SeqCst guarantees that the msg write above is visible before the entry_count write below can be seen.
    @atomicStore(usize, &entry_count, entry_index + 1, AtomicOrder.seq_cst);

    semaphore_ptr.post(); // Wake up all threads
}

fn doWork(info: *ThreadInfo) void {
    while (true) {
        if (@atomicLoad(usize, &next_entry_to_do, AtomicOrder.seq_cst) < @atomicLoad(usize, &entry_count, AtomicOrder.seq_cst)) {
            const entry_index = @atomicRmw(usize, &next_entry_to_do, .Add, 1, AtomicOrder.seq_cst);
            const pixel = entry_buffer[entry_index];

            var pixel_color = vec3{ 0, 0, 0 };
            for (0.._camera.samples_per_pixel) |_| {
                const r = _camera.get_ray(pixel.h, pixel.w);
                pixel_color += ray_color(r, _camera.max_depth, _camera.world);
            }
            entry_buffer[entry_index].color = pixel_color;

            _ = @atomicRmw(usize, &completion_count, .Add, 1, AtomicOrder.seq_cst);
        } else {
            info.semaphore_ptr.wait(); // Put all threads to sleep
        }
    }
}

pub const Camera = struct {
    aspect_ratio: f64,
    image_width: usize,
    samples_per_pixel: usize,
    max_depth: usize,
    vfov: f64,
    defocus_angle: f64,
    focus_dist: f64,
    world: *const HittableList,

    image_height: usize,
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

    pub fn render(self: Camera, writer: anytype) !void {
        _camera = &self;

        var semaphore = Semaphore{};
        var infos: [n_threads_to_spawn]ThreadInfo = undefined;
        for (&infos, 0..) |*info, thread_index| {
            info.thread_index = thread_index;
            info.semaphore_ptr = &semaphore;
            const handle = try Thread.spawn(.{}, doWork, .{info});
            handle.detach();
        }

        // Write the PPM header
        try writer.print("P3\n{} {}\n255\n", .{ self.image_width, self.image_height });

        for (0..self.image_width) |w| {
            for (0..self.image_height) |h| {
                entry_buffer[w * self.image_height + h] = Pixel{ .w = w, .h = h, .color = vec3{ -1, -1, -1 } };
                addWork(&semaphore);
            }
        }

        print("\nStarting rendering using {d} threads\n", .{n_threads_to_spawn});
        while (entry_count != @atomicLoad(usize, &completion_count, AtomicOrder.seq_cst)) {
            pbar(@atomicLoad(usize, &completion_count, AtomicOrder.seq_cst), self.image_height * self.image_width);
        }

        pbar(100, 100);

        for (0..self.image_height) |h| {
            for (0..self.image_width) |w| {
                try writeColor(self.get_pixel_color(w, h) * toVec3(self.pixel_samples_scale), writer);
            }
        }
    }

    fn get_pixel_color(self: Camera, w: usize, h: usize) vec3 {
        const pixel = entry_buffer[w * self.image_height + h];
        if ((pixel.w == w) and (pixel.h == h)) {
            return pixel.color;
        }
        print("Pixel with different coordinates w: {}, h: {}, pixel.w: {}, pixel.h: {}", .{ w, h, pixel.w, pixel.h });
        return vec3{ 0, 0, 0 };
    }

    fn get_ray(self: Camera, h: usize, w: usize) Ray {
        // Construct a camera ray originating from the origin and directed at randomly sampled
        // point around the pixel location i, j.

        const offset = sample_square();
        const pixel_sample = self.pixel00_loc +
            (toVec3(h) + toVec3(offset[0])) * self.pixel_delta_v +
            (toVec3(w) + toVec3(offset[1])) * self.pixel_delta_u;

        const ray_origin = if (self.defocus_angle <= 0) self.center else self.defocus_disk_sample();
        const ray_direction = pixel_sample - ray_origin;

        return Ray{ .orig = ray_origin, .dir = ray_direction };
    }

    fn defocus_disk_sample(self: Camera) vec3 {
        const p = random_in_unit_disk();
        return self.center + (toVec3(p[0]) * self.defocus_disk_u) + (toVec3(p[1]) * self.defocus_disk_v);
    }

    pub fn new(world: *const HittableList) Camera {
        const camera_center = lookfrom;
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

        const defocus_radius = focus_dist * @tan(utils.degrees_to_radians(defocus_angle / 2.0));
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
            .world = world,

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
};

fn splitPixels(allocator: std.mem.Allocator, pixels: []Pixel, num_sublists: usize) ![][]Pixel {
    const len = pixels.len;
    if (num_sublists == 0 or num_sublists > len) {
        return error.InvalidNumberOfSublists;
    }

    const sublist_size = len / num_sublists;
    const remainder = len % num_sublists;

    var result = try allocator.alloc([]Pixel, num_sublists);
    var start: usize = 0;

    for (0..num_sublists) |i| {
        var end = start + sublist_size;
        if (i < remainder) {
            end += 1;
        }
        result[i] = pixels[start..end];
        start = end;
    }

    return result;
}

fn random_in_unit_disk() vec3 {
    while (true) {
        const p = vec3{ utils.rand_mm(-1, 1), utils.rand_mm(-1, 1), 0 };
        if (mat_math.length_squared(p) < 1)
            return p;
    }
}

fn ray_color(ray: Ray, depth: usize, world: *const HittableList) vec3 {
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

    if ((r_float < -0.999) or (g_float < -0.999) or (b_float < -0.999)) {
        @panic("-1 color detected");
    }

    r_float = utils.linear_to_gamma(r_float);
    g_float = utils.linear_to_gamma(g_float);
    b_float = utils.linear_to_gamma(b_float);

    const intensity = Interval{ .min = 0, .max = 0.99 };

    const r: u8 = @intFromFloat(256 * intensity.clamp(r_float));
    const g: u8 = @intFromFloat(256 * intensity.clamp(g_float));
    const b: u8 = @intFromFloat(256 * intensity.clamp(b_float));
    try writer.print("{} {} {}\n", .{ r, g, b });
}

fn pbar(value: usize, max: usize) void {
    const used_char = "-";
    const number_of_char = 60;
    const percent_done: usize = if (value == max - 1) 100 else @divFloor(value * 100, max);
    const full_char: usize = @divFloor(number_of_char * percent_done, 100);

    print("\r|", .{});

    var i: usize = 0;
    while (i < number_of_char) : (i += 1) {
        if (i < full_char) {
            print("{s}", .{used_char});
        } else {
            print(" ", .{});
        }
    }

    print("| {}% |", .{percent_done});
    print(" {} ", .{value});
    print("/ {}", .{max});

    if (percent_done == 100) {
        print("\n", .{});
    }
}
