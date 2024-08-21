const std = @import("std");
const vec3 = @Vector(3, f64);

const utils = @import("utils.zig");
const Interval = utils.Interval;
const toVec3 = utils.toVec3;

const mat_math = @import("mat_math.zig");
const dot = mat_math.dot;
const set_face_normal = mat_math.set_face_normal;

const material_import = @import("material.zig");
const Material = material_import.Material;
const Metal = material_import.Metal;

pub const Ray = struct {
    orig: vec3,
    dir: vec3,
};

pub const Hittable = union(enum) {
    sphere: Sphere,
    //cube: Cube,

    pub fn hit(self: *const Hittable, ray: Ray, interval: Interval, rec: *HitRecord) bool {
        return switch (self.*) {
            .sphere => |*s| s.hit(ray, interval, rec),
            //.cube => |*c| c.hit(),
        };
    }
};

pub const HittableList = struct {
    list: []const Hittable,

    pub fn hit(self: *const HittableList, ray: Ray, ray_t: Interval, rec: *HitRecord) bool {
        var temp_rec: HitRecord = HitRecord.new();
        var hit_anything = false;
        var closest_so_far = ray_t.max;

        for (self.list) |obj| {
            if (obj.hit(ray, Interval{ .min = ray_t.min, .max = closest_so_far }, &temp_rec)) {
                hit_anything = true;
                closest_so_far = temp_rec.t;
                rec.* = temp_rec;
            }
        }

        return hit_anything;
    }
};

pub const HitRecord = struct {
    p: vec3,
    normal: vec3,
    material: Material,
    t: f64,
    front_face: bool,

    pub fn new() HitRecord {
        return HitRecord{
            .p = vec3{ 0, 0, 0 },
            .normal = vec3{ 0, 0, 0 },
            .material = Material{ .metal = Metal{ .albedo = vec3{ 0, 0, 0 }, .fuzz = 1.0 } },
            .t = 0,
            .front_face = false,
        };
    }
};

pub const Sphere = struct {
    center: vec3,
    radius: f64,
    material: Material,

    pub fn hit(self: Sphere, ray: Ray, ray_t: Interval, rec: *HitRecord) bool {
        const oc = self.center - ray.orig;
        const a = dot(ray.dir, ray.dir);
        const h = dot(ray.dir, oc);
        const c = dot(oc, oc) - self.radius * self.radius;
        const discriminant = h * h - a * c;
        if (discriminant < 0) {
            return false;
        }

        const sqrtd = @sqrt(discriminant);

        // Find the nearest root that lies in the acceptable range.
        const root = (h - sqrtd) / a;
        if (!ray_t.surrounds(root)) {
            return false;
        }

        rec.t = root;
        rec.p = at(ray, rec.t);
        rec.normal = (rec.p - self.center) / toVec3(self.radius);
        const outward_normal = (rec.p - self.center) / toVec3(self.radius);
        set_face_normal(rec, ray, outward_normal);
        rec.material = self.material;

        return true;
    }
};

fn at(ray: Ray, t: f64) vec3 {
    return ray.orig + toVec3(t) * ray.dir;
}
