const vec3 = @Vector(3, f64);
const std = @import("std");
const math = std.math;

const utils = @import("utils.zig");
const toVec3 = utils.toVec3;

const hit = @import("hittable.zig");
const HitRecord = hit.HitRecord;
const Ray = hit.Ray;

pub fn dot(u: vec3, v: vec3) f64 {
    return u[0] * v[0] + u[1] * v[1] + u[2] * v[2];
}

pub fn length(v: vec3) f64 {
    return math.sqrt(math.pow(f64, v[0], 2) + math.pow(f64, v[1], 2) + math.pow(f64, v[2], 2));
}

pub fn length_squared(v: vec3) f64 {
    return v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
}

pub fn unit_vector(v: vec3) vec3 {
    return v / toVec3(length(v));
}

pub fn random_in_unit_sphere() vec3 {
    while (true) {
        const p = utils.rand_vec3_mm(-1, 1);
        if (length_squared(p) < 1.0) {
            return p;
        }
    }
}

pub fn random_on_hemisphere(normal: vec3) vec3 {
    const on_unit_sphere = random_unit_vector();
    if (dot(on_unit_sphere, normal) > 0.0) {
        return on_unit_sphere;
    } else {
        return -on_unit_sphere;
    }
}

pub fn random_unit_vector() vec3 {
    return unit_vector(random_in_unit_sphere());
}

pub fn set_face_normal(rec: *HitRecord, ray: Ray, outward_normal: vec3) void {
    rec.front_face = dot(ray.dir, outward_normal) < 0;
    rec.normal = if (rec.front_face) outward_normal else -outward_normal;
}

pub fn near_zero(v: vec3) bool {
    const s = 1e-8;
    return ((@abs(v[0]) < s) and (@abs(v[1]) < s) and (@abs(v[2]) < s));
}

pub fn cross(u: vec3, v: vec3) vec3 {
    return vec3{
        u[1] * v[2] - u[2] * v[1],
        u[2] * v[0] - u[0] * v[2],
        u[0] * v[1] - u[1] * v[0],
    };
}
