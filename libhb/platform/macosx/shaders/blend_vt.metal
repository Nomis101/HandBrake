/* blend_vt.metal

   Copyright (c) 2003-2025 HandBrake Team

   This file is part of the HandBrake source code
   Homepage: <http://handbrake.fr/>.
   It may be used under the terms of the GNU General Public License v2.
   For full terms see the file COPYING file or visit http://www.gnu.org/licenses/gpl-2.0.html
 */

#include <metal_stdlib>
#include <metal_integer>
#include <metal_texture>

/*
 * Parameters
 */

constant uint plane      [[function_constant(0)]];
constant uint channels   [[function_constant(1)]];
constant uint subw       [[function_constant(2)]];
constant uint subh       [[function_constant(3)]];
constant uint osubw      [[function_constant(4)]];
constant uint osubh      [[function_constant(5)]];
constant uint shift      [[function_constant(6)]];
constant uint maxv       [[function_constant(7)]];
constant bool subsample  [[function_constant(8)]];
//constant uint chroma_loc [[function_constant(9)]];

struct params {
    uint x;
    uint y;
};

using namespace metal;

/*
 * Blend helpers
 */

#define accesstype access::sample
constexpr sampler s(coord::pixel);

template <typename T>
T blend_pixel(T y_out, T y_in, T a_in)
{
    return ((uint32_t)y_out * (maxv - a_in) + (uint32_t)y_in * a_in) / maxv;
}

template <typename T>
T pos_dst_y(T pos, uint x, uint y)
{
    return ushort2(pos.x + x, pos.y + y);
}

template <typename T>
T pos_dst_u(T pos, uint x, uint y)
{
    return ushort2((pos.x + (x >> subw)) * channels,
                    pos.y + (y >> subh));
}

template <typename T>
T pos_dst_v(T pos, uint x, uint y)
{
    return ushort2((pos.x + (x >> subw)) * channels + 1,
                    pos.y + (y >> subh));
}

template <typename T>
float2 pos_uv_subsample(T pos, uint x, uint y)
{
    uint uvsubw = subw - osubw;
    uint uvsubh = subh - osubh;

    return float2((pos.x << uvsubw) + (x >> osubw),
                  (pos.y << uvsubh) + (y >> osubh));
}

template <typename T>
T pos_a(T pos, uint x, uint y)
{
    return ushort2((pos.x << subw) + x, (pos.y << subh) + y);
}

template <typename T>
T blend_pixel_y(
    texture2d<T, access::read_write> dst,
    texture2d<T, access::read> overlay_y,
    texture2d<T, access::read> overlay_a,
    constant params& p,
    ushort2 pos)
{
    ushort2 pos_ya = pos_dst_y(pos, p.x, p.y);

    T y_in  = overlay_y.read(pos_ya).x << shift;
    T a_in  = overlay_a.read(pos_ya).x << shift;
    T y_out = dst.read(pos_ya).x;

    return blend_pixel(y_out, y_in, a_in);
}

template <typename T, typename V>
V blend_pixel_uv(
    texture2d<T, access::read_write> dst,
    texture2d<T, access::sample> overlay_u,
    texture2d<T, access::sample> overlay_v,
    texture2d<T, access::read> overlay_a,
    constant params& p,
    ushort2 pos)
{
    T u_in;
    T v_in;

    if (subsample) {
        float2 pos_uv = pos_uv_subsample(pos, p.x, p.y);
        u_in = overlay_u.sample(s, pos_uv).x << shift;
        v_in = overlay_v.sample(s, pos_uv).x << shift;
    }
    else {
        ushort2 pos_uv = ushort2(pos.x + (p.x >> osubw), pos.y + (p.y >> osubh));
        u_in = overlay_u.read(pos_uv).x << shift;
        v_in = overlay_v.read(pos_uv).x << shift;
    }

    T u_out = dst.read(pos_dst_u(pos, p.x, p.y)).x;
    T v_out = dst.read(pos_dst_v(pos, p.x, p.y)).x;
    T a_in = overlay_a.read(pos_a(pos, p.x, p.y)).x << shift;

    return V(blend_pixel(u_out, u_in, a_in),
             blend_pixel(v_out, v_in, a_in));
}

/*
 * Kernel dispatch
 */

kernel void blend(
    texture2d<ushort, access::read_write> dst [[texture(0)]],
    texture2d<ushort, access::read>   overlay_y [[texture(1)]],
    texture2d<ushort, access::sample> overlay_u [[texture(2)]],
    texture2d<ushort, access::sample> overlay_v [[texture(3)]],
    texture2d<ushort, access::read>   overlay_a [[texture(4)]],
    constant params& p [[buffer(0)]],
    ushort2 pos [[thread_position_in_grid]])
{
    if (plane == 0) {
        ushort value = blend_pixel_y(dst, overlay_y, overlay_a,
                                     p, pos);
        dst.write(value, pos_dst_y(pos, p.x, p.y));
    }
    else {
        ushort2 value = blend_pixel_uv<ushort, ushort2>(dst, overlay_u,
                                                        overlay_v, overlay_a,
                                                        p, pos);
        dst.write(value.x, pos_dst_u(pos, p.x, p.y));
        dst.write(value.y, pos_dst_v(pos, p.x, p.y));
    }
}