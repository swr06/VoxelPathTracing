#version 330 core

layout (location = 0) out vec4 o_Noise;

in vec2 v_TexCoords;

uniform float u_CurrentSlice;
uniform float u_CurrentSliceINT;
uniform vec2 u_Dims;
uniform vec2 u_Offset;

float saturate(float x) {
    return clamp(x,0.0f,1.0f);
}

vec3 Interpolation_C2(vec3 x)
{
    return x * x * x * (x * (x * 6.0 - 15.0) + 10.0);
}

void PerlinHash(vec3 gridcell, float s, bool tile,
								out vec4 lowz_hash_0,
								out vec4 lowz_hash_1,
								out vec4 lowz_hash_2,
								out vec4 highz_hash_0,
								out vec4 highz_hash_1,
								out vec4 highz_hash_2)
{
    vec2 OFFSET = u_Offset;
    const float DOMAIN = 69.0;
    const vec3 SOMELARGEFLOATS = vec3(635.298681, 682.357502, 668.926525);
    const vec3 ZINC = vec3(48.500388, 65.294118, 63.934599);

    gridcell.xyz = gridcell.xyz - floor(gridcell.xyz * (1.0 / DOMAIN)) * DOMAIN;
    float d = DOMAIN - 1.5;
    vec3 gridcell_inc1 = step(gridcell, vec3(d, d, d)) * (gridcell + 1.0);

    gridcell_inc1 = tile ? mod(gridcell_inc1, s) : gridcell_inc1;

    vec4 P = vec4(gridcell.xy, gridcell_inc1.xy) + OFFSET.xyxy;
    P *= P;
    P = P.xzxz * P.yyww;
    vec3 lowz_mod = vec3(1.0 / (SOMELARGEFLOATS.xyz + gridcell.zzz * ZINC.xyz));
    vec3 highz_mod = vec3(1.0 / (SOMELARGEFLOATS.xyz + gridcell_inc1.zzz * ZINC.xyz));
    lowz_hash_0 = fract(P * lowz_mod.xxxx);
    highz_hash_0 = fract(P * highz_mod.xxxx);
    lowz_hash_1 = fract(P * lowz_mod.yyyy);
    highz_hash_1 = fract(P * highz_mod.yyyy);
    lowz_hash_2 = fract(P * lowz_mod.zzzz);
    highz_hash_2 = fract(P * highz_mod.zzzz);
}

float Perlin(vec3 P, float s, bool tile)
{
    P *= s;

    vec3 Pi = floor(P);
    vec3 Pi2 = floor(P);
    vec3 Pf = P - Pi;
    vec3 Pf_min1 = Pf - 1.0;

    vec4 hashx0, hashy0, hashz0, hashx1, hashy1, hashz1;
    PerlinHash(Pi2, s, tile, hashx0, hashy0, hashz0, hashx1, hashy1, hashz1);

    vec4 grad_x0 = hashx0 - 0.49999;
    vec4 grad_y0 = hashy0 - 0.49999;
    vec4 grad_z0 = hashz0 - 0.49999;
    vec4 grad_x1 = hashx1 - 0.49999;
    vec4 grad_y1 = hashy1 - 0.49999;
    vec4 grad_z1 = hashz1 - 0.49999;
    vec4 grad_results_0 = inversesqrt(grad_x0 * grad_x0 + grad_y0 * grad_y0 + grad_z0 * grad_z0) * (vec2(Pf.x, Pf_min1.x).xyxy * grad_x0 + vec2(Pf.y, Pf_min1.y).xxyy * grad_y0 + Pf.zzzz * grad_z0);
    vec4 grad_results_1 = inversesqrt(grad_x1 * grad_x1 + grad_y1 * grad_y1 + grad_z1 * grad_z1) * (vec2(Pf.x, Pf_min1.x).xyxy * grad_x1 + vec2(Pf.y, Pf_min1.y).xxyy * grad_y1 + Pf_min1.zzzz * grad_z1);

    vec3 blend = Interpolation_C2(Pf);
    vec4 res0 = mix(grad_results_0, grad_results_1, blend.z);
    vec4 blend2 = vec4(blend.xy, vec2(1.0 - blend.xy));
    float final = dot(res0, blend2.zxzx * blend2.wwyy);
    final *= 1.0 / sqrt(0.75);
    return ((final * 1.5) + 1.0) * 0.5;
}

float GetPerlin_5_Octaves(vec3 p, bool tile)
{
    vec3 xyz = p;
    float amplitude_factor = 0.5;
    float frequency_factor = 2.0;

    float a = 1.0;
    float perlin_value = 0.0;
    perlin_value += a * Perlin(xyz, 1, tile);
    a *= amplitude_factor;
    xyz *= (frequency_factor + 0.02);
    perlin_value += a * Perlin(xyz, 1, tile);
    a *= amplitude_factor;
    xyz *= (frequency_factor + 0.03);
    perlin_value += a * Perlin(xyz, 1, tile);
    a *= amplitude_factor;
    xyz *= (frequency_factor + 0.01);
    perlin_value += a * Perlin(xyz, 1, tile);
    a *= amplitude_factor;
    xyz *= (frequency_factor + 0.01);
    perlin_value += a * Perlin(xyz, 1, tile);

    return perlin_value;
}

float GetPerlin_5_Octaves(vec3 p, float s, bool tile)
{
    vec3 xyz = p;
    float f = 1.0;
    float a = 1.0;

    float perlin_value = 0.0;
    perlin_value += a * Perlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    perlin_value += a * Perlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    perlin_value += a * Perlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    perlin_value += a * Perlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    perlin_value += a * Perlin(xyz, s * f, tile);

    return perlin_value;
}

float GetPerlin_3_Octaves(vec3 p, float s, bool tile)
{
    vec3 xyz = p;
    float f = 1.0;
    float a = 1.0;

    float perlin_value = 0.0;
    perlin_value += a * Perlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    perlin_value += a * Perlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    perlin_value += a * Perlin(xyz, s * f, tile);

    return perlin_value;
}

float GetPerlin_7_Octaves(vec3 p, float s, bool tile)
{
    vec3 xyz = p;
    float f = 1.0;
    float a = 1.0;

    float perlin_value = 0.0;
    perlin_value += a * Perlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    perlin_value += a * Perlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    perlin_value += a * Perlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    perlin_value += a * Perlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    perlin_value += a * Perlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    perlin_value += a * Perlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    perlin_value += a * Perlin(xyz, s * f, tile);

    return perlin_value;
}

///////////////////////////////////// Worley Noise //////////////////////////////////////////////////

vec3 VoronoiHash(vec3 x, float s)
{
    x = mod(x,s);
    x = vec3(dot(x, vec3(127.1, 311.7, 74.7)),
							dot(x, vec3(269.5, 183.3, 246.1)),
							dot(x, vec3(113.5, 271.9, 124.6)));
				
    return fract(sin(x) * 43758.5453123);
}

vec3 Voronoi(in vec3 x, float s, float seed, bool inverted)
{
    x *= s;
    x += 0.5;
    vec3 p = floor(x);
    vec3 f = fract(x);

    float id = 0.0;
    vec2 res = vec2(1.0, 1.0);
    for (int k = -1; k <= 1; k++)
    {
        for (int j = -1; j <= 1; j++)
        {
            for (int i = -1; i <= 1; i++)
            {
                vec3 b = vec3(i, j, k);
                vec3 r = vec3(b) - f + VoronoiHash(p + b + seed * 10, s);
                float d = dot(r, r);

                if (d < res.x)
                {
                    id = dot(p + b, vec3(1.0, 57.0, 113.0));
                    res = vec2(d, res.x);
                }
                else if (d < res.y)
                {
                    res.y = d;
                }
            }
        }
    }

    vec2 result = res;
    id = abs(id);

    if (inverted)
        return vec3(1.0 - result, id);
    else
        return vec3(result, id);
}

float GetWorley_2_Octaves(vec3 p, float s, float seed)
{
    vec3 xyz = p;

    float worley_value1 = Voronoi(xyz, 1.0 * s, seed, true).r;
    float worley_value2 = Voronoi(xyz, 2.0 * s, seed, false).r;

    worley_value1 = saturate(worley_value1);
    worley_value2 = saturate(worley_value2);

    float worley_value = worley_value1;
    worley_value = worley_value - worley_value2 * 0.25;

    return worley_value;
}

float GetWorley_2_Octaves(vec3 p, float s)
{
    return GetWorley_2_Octaves(p, s, 0);
}

float GetWorley_3_Octaves(vec3 p, float s, float seed)
{
    vec3 xyz = p;

    float worley_value1 = Voronoi(xyz, 1.0 * s, seed, true).r;
    float worley_value2 = Voronoi(xyz, 2.0 * s, seed, false).r;
    float worley_value3 = Voronoi(xyz, 4.0 * s, seed, false).r;

    worley_value1 = saturate(worley_value1);
    worley_value2 = saturate(worley_value2);
    worley_value3 = saturate(worley_value3);

    float worley_value = worley_value1;
    worley_value = worley_value - worley_value2 * 0.3;
    worley_value = worley_value - worley_value3 * 0.3;

    return worley_value;
}

float GetWorley_3_Octaves(vec3 p, float s)
{
    return GetWorley_3_Octaves(p, s, 0);
}

////////////////////////////////////// Curl Noise ////////////////////////////////////////////////

vec3 CurlNoise(vec3 pos)
{
    float e = 0.05;
    float n1, n2, a, b;
    vec3 c;

    n1 = GetPerlin_5_Octaves(pos.xyz + vec3(0, e, 0), false);
    n2 = GetPerlin_5_Octaves(pos.xyz + vec3(0, -e, 0), false);
    a = (n1 - n2) / (2 * e);
    n1 = GetPerlin_5_Octaves(pos.xyz + vec3(0, 0, e), false);
    n2 = GetPerlin_5_Octaves(pos.xyz + vec3(0, 0, -e), false);
    b = (n1 - n2) / (2 * e);

    c.x = a - b;

    n1 = GetPerlin_5_Octaves(pos.xyz + vec3(0, 0, e), false);
    n2 = GetPerlin_5_Octaves(pos.xyz + vec3(0, 0, -e), false);
    a = (n1 - n2) / (2 * e);
    n1 = GetPerlin_5_Octaves(pos.xyz + vec3(e, 0, 0), false);
    n2 = GetPerlin_5_Octaves(pos.xyz + vec3(-e, 0, 0), false);
    b = (n1 - n2) / (2 * e);

    c.y = a - b;

    n1 = GetPerlin_5_Octaves(pos.xyz + vec3(e, 0, 0), false);
    n2 = GetPerlin_5_Octaves(pos.xyz + vec3(-e, 0, 0), false);
    a = (n1 - n2) / (2 * e);
    n1 = GetPerlin_5_Octaves(pos.xyz + vec3(0, e, 0), false);
    n2 = GetPerlin_5_Octaves(pos.xyz + vec3(0, -e, 0), false);
    b = (n1 - n2) / (2 * e);

    c.z = a - b;

    return c;
}

vec3 DecodeCurlNoise(vec3 c)
{
    return (c - 0.5) * 2.0;
}

vec3 EncodeCurlNoise(vec3 c)
{
    return (c + 1.0) * 0.5;
}

////////////////////////////////////// Shared Utils ////////////////////////////////////////////////

// Remap an original value from an old range (minimum and maximum) to a new one.
float Remap(float original_value, float original_min, float original_max, float new_min, float new_max)
{
    return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
}

// Remap an original value from an old range (minimum and maximum) to a new one, clamped to the new range.
float RemapClamped(float original_value, float original_min, float original_max, float new_min, float new_max)
{
    return new_min + (saturate((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
}

float Remap01(float value, float low, float high)
{
    return saturate((value - low) / (high - low));
}

float DilatePerlinWorley(float p, float w, float x)
{
    float curve = 0.75;
    if (x < 0.5)
    {
        x = x / 0.5;
        float n = p + w * x;
        return n * mix(1, 0.5, pow(x, curve));
    }
    else
    {
        x = (x - 0.5) / 0.5;
        float n = w + p * (1.0 - x);
        return n * mix(0.5, 1.0, pow(x, 1.0 / curve));
    }
}

void main()
{
    o_Noise = vec4(0.0f);
    
    vec2 UV = v_TexCoords;
    vec3 pos = vec3(v_TexCoords, u_CurrentSlice);
    vec3 TexelPosition = vec3(vec2(gl_FragCoord.xy), float(u_CurrentSliceINT));

    const float perlinWorleyDifference = 0.3;
    const float perlinDilateLowRemap = 0.3;
    const float perlinDilateHighRemap = 1.4;
    
    const float worleyDilateLowRemap = -0.3;
    const float worleyDilateHighRemap = 1.3;
    
    const float totalWorleyLowRemap = -0.4;
    const float totalWorleyHighRemap = 1.0;
    const float totalSize = 1.0;
    
    // Generate Noises
    float perlinDilateNoise = GetPerlin_7_Octaves(pos, 4.0 * totalSize, true);
    float worleyDilateNoise = GetWorley_3_Octaves(pos, 6.0 * totalSize);
    
    float worleyLarge = GetWorley_3_Octaves(pos, 6.0 * totalSize);
    float worleyMedium = GetWorley_3_Octaves(pos, 12.0 * totalSize);
    float worleySmall = GetWorley_3_Octaves(pos, 24.0 * totalSize);

    // Remap Noises    
    perlinDilateNoise = Remap01(perlinDilateNoise, perlinDilateLowRemap, perlinDilateHighRemap);
    worleyDilateNoise = Remap01(worleyDilateNoise, worleyDilateLowRemap, worleyDilateHighRemap);
    
    worleyLarge = Remap01(worleyLarge, totalWorleyLowRemap, totalWorleyHighRemap);
    worleyMedium = Remap01(worleyMedium, totalWorleyLowRemap, totalWorleyHighRemap);
    worleySmall = Remap01(worleySmall, totalWorleyLowRemap, totalWorleyHighRemap);

    // Dilate blend perlin and worley main
    float perlinWorleyNoise = DilatePerlinWorley(perlinDilateNoise, worleyDilateNoise, perlinWorleyDifference);
    o_Noise = vec4(perlinWorleyNoise, worleyLarge, worleyMedium, worleySmall);
}