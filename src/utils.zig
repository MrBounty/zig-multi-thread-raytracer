const std = @import("std");
const math = std.math;
const vec3 = @Vector(3, f64);

pub const Interval = struct {
    min: f64,
    max: f64,

    pub fn inf() Interval {
        return Interval{
            .min = -math.inf(f64),
            .max = math.inf(f64),
        };
    }

    pub fn new(min: f64, max: f64) Interval {
        return Interval{
            .min = min,
            .max = max,
        };
    }

    pub fn size(self: Interval) f64 {
        return self.max - self.min;
    }

    pub fn contains(self: Interval, x: f64) bool {
        return ((self.min <= x) and (x <= self.max));
    }

    pub fn surrounds(self: Interval, x: f64) bool {
        return ((self.min < x) and (x < self.max));
    }

    pub fn clamp(self: Interval, x: f64) f64 {
        if (x < self.min) {
            return self.min;
        }
        if (x > self.max) {
            return self.max;
        }
        return x;
    }
};

pub fn toVec3(x: anytype) vec3 {
    switch (@TypeOf(x)) {
        usize => {
            const x_float = @as(f64, @floatFromInt(x));
            return vec3{ x_float, x_float, x_float };
        },
        comptime_float => {
            const x_float = @as(f64, x);
            return vec3{ x_float, x_float, x_float };
        },
        i64 => {
            const x_float = @as(f64, @floatFromInt(x));
            return vec3{ x_float, x_float, x_float };
        },
        comptime_int => {
            const x_float = @as(f64, @floatFromInt(x));
            return vec3{ x_float, x_float, x_float };
        },
        f64 => {
            return vec3{ x, x, x };
        },
        @Vector(3, f64) => {
            return x;
        },

        else => {
            @panic("Unknow type passed through toVec3\n\n");
        },
    }
}

var rnd = std.rand.DefaultPrng.init(0);

pub fn rand_01() f64 {
    return rnd.random().float(f64);
}

pub fn rand_mm(min: f64, max: f64) f64 {
    return rnd.random().float(f64) * (max - min) + min;
}

pub fn rand_vec3_01() vec3 {
    return vec3{ rand_01(), rand_01(), rand_01() };
}

pub fn rand_vec3_mm(min: f64, max: f64) vec3 {
    return vec3{ rand_mm(min, max), rand_mm(min, max), rand_mm(min, max) };
}

pub fn linear_to_gamma(linear_component: f64) f64 {
    if (linear_component > 0) {
        return @sqrt(linear_component);
    }
    return 0;
}

pub fn degrees_to_radians(degrees: f64) f64 {
    return degrees * math.pi / 180;
}
