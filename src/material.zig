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
const near_zero = mat_math.near_zero;
const unit_vector = mat_math.unit_vector;
const random_unit_vector = mat_math.random_unit_vector;
const dot = mat_math.dot;
const length_squared = mat_math.length_squared;
const math = @import("std").math;

// Mother struct

pub const Material = union(enum) {
    lambertian: Lambertian,
    metal: Metal,
    dielectric: Dielectric,

    pub fn scatter(self: *const Material, ray_in: Ray, rec: *HitRecord, attenuation: *vec3, ray_scattered: *Ray) bool {
        return switch (self.*) {
            .lambertian => |s| s.scatter(rec, attenuation, ray_scattered),
            .metal => |s| s.scatter(ray_in, rec, attenuation, ray_scattered),
            .dielectric => |s| s.scatter(ray_in, rec, attenuation, ray_scattered),
        };
    }
};

// Materiaux

pub const Lambertian = struct {
    albedo: vec3,

    pub fn scatter(self: *const Lambertian, rec: *HitRecord, attenuation: *vec3, ray_scattered: *Ray) bool {
        var scatter_direction = rec.*.normal + random_unit_vector();

        if (near_zero(scatter_direction)) {
            scatter_direction = rec.*.normal;
        }

        ray_scattered.* = Ray{ .orig = rec.*.p, .dir = scatter_direction };
        attenuation.* = self.albedo;

        return true;
    }
};

pub const Metal = struct {
    albedo: vec3,
    fuzz: f64,

    pub fn scatter(self: *const Metal, r_in: Ray, rec: *HitRecord, attenuation: *vec3, ray_scattered: *Ray) bool {
        var reflected = reflect(r_in.dir, rec.*.normal);
        reflected = unit_vector(reflected) + (toVec3(self.fuzz) * random_unit_vector());
        ray_scattered.* = Ray{ .orig = rec.p, .dir = reflected };
        attenuation.* = self.albedo;
        return (dot(ray_scattered.dir, rec.normal) > 0);
    }
};

pub const Dielectric = struct {
    refraction_index: f64,

    pub fn scatter(self: *const Dielectric, r_in: Ray, rec: *HitRecord, attenuation: *vec3, ray_scattered: *Ray) bool {
        attenuation.* = vec3{ 1, 1, 1 };
        const ri = if (rec.front_face) (1.0 / self.refraction_index) else self.refraction_index;

        const unit_direction = unit_vector(r_in.dir);
        const cos_theta = @min(dot(-unit_direction, rec.normal), 1.0);
        const sin_theta = @sqrt(1.0 - cos_theta * cos_theta);

        const cannot_refract = ri * sin_theta > 1.0;
        var direction = vec3{ 0, 0, 0 };
        if ((cannot_refract) and (reflectance(cos_theta, ri) > utils.rand_01())) {
            direction = reflect(unit_direction, rec.normal);
        } else {
            direction = refract(unit_direction, rec.normal, ri);
        }

        ray_scattered.* = Ray{ .orig = rec.p, .dir = direction };
        return true;
    }
};

// Physics

fn reflect(v: vec3, n: vec3) vec3 {
    return v - toVec3(2 * dot(v, n)) * n;
}

fn refract(uv: vec3, n: vec3, etai_over_etat: f64) vec3 {
    const cos_theta = @min(dot(-uv, n), 1.0);
    const r_out_perp = toVec3(etai_over_etat) * (uv + toVec3(cos_theta) * n);
    const r_out_parallel = toVec3(-@sqrt(@abs(1.0 - length_squared(r_out_perp)))) * n;
    return r_out_perp + r_out_parallel;
}

fn reflectance(cosine: f64, refraction_index: f64) f64 {
    var r0 = (1 - refraction_index) / (1 + refraction_index);
    r0 = r0 * r0;
    return r0 + (1 - r0) * math.pow(f64, (1 - cosine), 5);
}
