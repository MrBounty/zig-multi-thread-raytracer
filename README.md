# Simple raytracer using zig

Project used to introduce me to Zig.

Greatly inspired by [Ray Tracing in a Weekend](https://raytracing.github.io/books/RayTracingInOneWeekend.html). 
Added multi-thread and other stuffs.

![alt text](https://github.com/MrBounty/zig-multi-thread-raytracer/blob/main/image%20fullhd.png)

***Generated in 4200s on a Qualcomm X Elite 80.***

# Parameters

They are all in `camera.zig`.

```zig
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
```
