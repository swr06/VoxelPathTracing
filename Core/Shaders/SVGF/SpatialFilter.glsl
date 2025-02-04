#version 330 core

#define bayer4(a)   (bayer2(  0.5 * (a)) * 0.25 + bayer2(a))
#define bayer8(a)   (bayer4(  0.5 * (a)) * 0.25 + bayer2(a))
#define bayer16(a)  (bayer8(  0.5 * (a)) * 0.25 + bayer2(a))
#define bayer32(a)  (bayer16( 0.5 * (a)) * 0.25 + bayer2(a))
#define bayer64(a)  (bayer32( 0.5 * (a)) * 0.25 + bayer2(a))
#define bayer128(a) (bayer64( 0.5 * (a)) * 0.25 + bayer2(a))
#define bayer256(a) (bayer128(0.5 * (a)) * 0.25 + bayer2(a))
#define ESTIMATE_VARIANCE_BASED_ON_NEIGHBOURS

layout (location = 0) out vec4 o_SH;
layout (location = 1) out vec2 o_CoCg;
layout (location = 2) out float o_Variance;
layout (location = 3) out vec2 o_AOAndSkylighting;

in vec2 v_TexCoords;
in vec3 v_RayOrigin;
in vec3 v_RayDirection;

uniform sampler2D u_SH;
uniform sampler2D u_CoCg;
uniform sampler2D u_Utility;

uniform sampler2D u_PositionTexture;
uniform sampler2D u_NormalTexture;
uniform sampler2D u_BlockIDTexture;
uniform sampler2D u_VarianceTexture;
uniform sampler2D u_TemporalMoment;
uniform sampler2D u_AO;

uniform vec2 u_Dimensions;
uniform int u_Step;
uniform bool u_ShouldDetailWeight;
uniform bool DO_SPATIAL;
uniform bool u_LargeKernel;
uniform bool AGGRESSIVE_DISOCCLUSION_HANDLING;

uniform mat4 u_InverseView;
uniform mat4 u_InverseProjection;


uniform float u_ColorPhiBias = 2.0f;
uniform float u_DeltaTime;
uniform float u_Time;
uniform float u_ResolutionScale;

const float POSITION_THRESH = 4.0f;

float bayer2(vec2 a){
    a = floor(a);
    return fract(dot(a, vec2(0.5, a.y * 0.75)));
}

vec3 GetRayDirectionAt(vec2 txc)
{
	vec4 clip = vec4(txc * 2.0f - 1.0f, -1.0f, 1.0f);
	vec4 eye = vec4(vec2(u_InverseProjection * clip), -1.0f, 0.0f);
	return vec3(u_InverseView * eye);
}

vec4 GetPositionAt(vec2 txc)
{
	float Dist = texture(u_PositionTexture, txc).r;
	return vec4(v_RayOrigin + normalize(GetRayDirectionAt(txc)) * Dist, Dist);
}

int GetBlockAt(vec2 txc)
{
	float id = texture(u_BlockIDTexture, txc).r;
	return clamp(int(floor(id * 255.0f)), 0, 127);
}

float GetLuminance(vec3 color) 
{
    return dot(color, vec3(0.299, 0.587, 0.114));
}

bool IsSky(float d)
{
	return d < 0.0f;
}

bool InScreenSpace(in vec2 v) 
{
	return v.x > 0.0f && v.x < 1.0f && v.y > 0.0f && v.y < 1.0f;
}

vec3 Saturate(vec3 x)
{
	return clamp(x, 0.0f, 1.0f);
}

float GaussianVariance(out float BaseVariance)
{
#ifdef ESTIMATE_VARIANCE_BASED_ON_NEIGHBOURS
	vec2 TexelSize = 1.0f / textureSize(u_SH, 0);
	float VarianceSum = 0.0f;

	const float Kernel[3] = float[3](1.0 / 4.0, 1.0 / 8.0, 1.0 / 16.0);
	const float Gaussian[2] = float[2](0.60283f, 0.198585f); // gaussian kernel
	float TotalKernel = 0.0f;

	for (int x = -1 ; x <= 1 ; x++)
	{
		for (int y = -1 ; y <= 1 ; y++)
		{
			vec2 SampleCoord = v_TexCoords + vec2(x, y) * TexelSize;
			
			if (!InScreenSpace(SampleCoord)) { continue ; }

			//float KernelValue = Kernel[abs(x) + abs(y)]; 
			float KernelValue = Gaussian[abs(x)] * Gaussian[abs(y)];
			float V = texture(u_VarianceTexture, SampleCoord).r;

			if (x == 0 && y == 0) { BaseVariance = V; }

			VarianceSum += V * KernelValue;
			TotalKernel += KernelValue;
		}
	}

	return VarianceSum / max(TotalKernel, 0.01f);
#else 
	float x = texture(u_VarianceTexture, v_TexCoords).r;
	BaseVariance = x;
	return x;
#endif
}

float SHToY(vec4 shY)
{
    return max(0, 3.544905f * shY.w); // get luminance (Y) from the first spherical harmonic
}

bool CompareFloatNormal(float x, float y) {
    return abs(x - y) < 0.02f;
}

vec3 GetNormalFromID(float n) {
	const vec3 Normals[6] = vec3[]( vec3(0.0f, 0.0f, 1.0f), vec3(0.0f, 0.0f, -1.0f),
					vec3(0.0f, 1.0f, 0.0f), vec3(0.0f, -1.0f, 0.0f), 
					vec3(-1.0f, 0.0f, 0.0f), vec3(1.0f, 0.0f, 0.0f));
    int idx = int(round(n*10.0f));

    if (idx > 5) {
        return vec3(1.0f, 1.0f, 1.0f);
    }

    return Normals[idx];
}

vec3 SampleNormalFromTex(sampler2D samp, vec2 txc) { 
	return GetNormalFromID(texture(samp, txc).x);
}

float sqr(float x) { return x * x; }
float GetSaturation(in vec3 v) { return length(v); }

float GradientNoise()
{
	vec2 coord = gl_FragCoord.xy + mod(u_Time * 100.493850275f, 500.0f);
	float noise = fract(52.9829189f * fract(0.06711056f * coord.x + 0.00583715f * coord.y));
	return noise;
}

float TweakVariance(float V, float E) {
	float FittedEstimate = V;
	FittedEstimate = clamp(FittedEstimate, 0.0f, 1.0f);
	float T = 1.0f - FittedEstimate;
	FittedEstimate = FittedEstimate * pow(T, E + 6.0f);
	return FittedEstimate;
}

void main()
{
	const float AtrousWeights[3] = float[3]( 1.0f, 2.0f / 3.0f, 1.0f / 6.0f );
	const float AtrousWeights2[5] = float[5] (0.0625, 0.25, 0.375, 0.25, 0.0625);

	vec2 TexelSize = 1.0f / u_Dimensions;
	vec4 TotalColor = vec4(0.0f);

	bool FilterAO = u_Step <= 4;
	bool FilterSky = u_Step <= 6;
	FilterSky = FilterSky || FilterAO;



	ivec2 Jitter = ivec2((GradientNoise() - 0.5f) * float(u_Step * 0.8f));
	//vec4 BasePosition = GetPositionAt(v_TexCoords);
	float BaseDepth = texture(u_PositionTexture, v_TexCoords).x;
	bool BaseIsSky = BaseDepth < 0.0f;
	vec3 BaseNormal = SampleNormalFromTex(u_NormalTexture, v_TexCoords).xyz;
	vec3 BaseUtility = texture(u_Utility, v_TexCoords).xyz;
	vec4 BaseSH = texture(u_SH, v_TexCoords).xyzw;
	vec2 BaseCoCg = texture(u_CoCg, v_TexCoords).xy;
	float BaseLuminance = SHToY(BaseSH);
	float BaseVariance = 0.0f;
	float VarianceEstimate = GaussianVariance(BaseVariance);
	vec2 BaseAOSky = texture(u_AO, v_TexCoords).rg;

	if (!DO_SPATIAL) { 
		o_SH = BaseSH;
		o_CoCg = BaseCoCg;
		o_Variance = BaseVariance;
		o_AOAndSkylighting = BaseAOSky;
		return;
	}

	// Start with the base inputs, one iteration of the loop can then be skipped
	vec4 TotalSH = BaseSH;
	vec2 TotalCoCg = BaseCoCg;
	float TotalWeight = 1.0f;
	float TotalVariance = BaseVariance;
	vec2 TotalAOSky = BaseAOSky;
	float TotalAOWeight = 1.0f;

	float AccumulatedFrames = texture(u_TemporalMoment, v_TexCoords).x;
	bool DoStrongSpatial = AccumulatedFrames <= 8.0f && AGGRESSIVE_DISOCCLUSION_HANDLING && u_Step <= 8;

	float CurveExponent = 0.0f;

	if (VarianceEstimate < 0.01f) {
		CurveExponent = 128.0f;
	}

	else if (VarianceEstimate < 0.025f) {
		CurveExponent = 112.0f;
	}

	else if (VarianceEstimate < 0.05f) {
		CurveExponent = 96.0f;
	}

	else if (VarianceEstimate < 0.075f) {
		CurveExponent = 84.0f;
	}

	else if (VarianceEstimate < 0.1f) {
		CurveExponent = 70.0f;
	}

	float TweakedVariance = VarianceEstimate < 0.1f ? TweakVariance(VarianceEstimate, CurveExponent) : VarianceEstimate;
	float PhiColor = sqrt(max(0.0f, 0.000001f + TweakedVariance));
	PhiColor /= max(u_ColorPhiBias, 0.1f); 


	//float Bayer = bayer2(gl_FragCoord.xy);

	// 9 SPATIAL samples, with 5 atrous passes and 1 initial pass
	int KernelSampleSize = u_LargeKernel ? 2 : 1;

	// Resolution scale weight ->
	float AdditionalScale = mix(1.0f, 2.4f, u_ResolutionScale);

	for (int x = -KernelSampleSize ; x <= KernelSampleSize ; x++)
	{
		for (int y = -KernelSampleSize ; y <= KernelSampleSize ; y++)
		{
			if (x == 0 && y == 0) { continue ; }
			

			vec2 SampleCoord = v_TexCoords + (((vec2(x, y) * float(u_Step) * AdditionalScale) + (vec2(Jitter) * 0.5f))) * TexelSize ;
			if (!InScreenSpace(SampleCoord)) { continue; }


			float SampleDepth = texture(u_PositionTexture, SampleCoord).x;

			// Weights : 
			//vec3 PositionDifference = abs(SamplePosition.xyz - BasePosition.xyz);
            //float DistSqr = dot(PositionDifference, PositionDifference);
			float DepthDiff = abs(SampleDepth - BaseDepth);
			vec3 SampleNormal = SampleNormalFromTex(u_NormalTexture, SampleCoord).xyz;

			if (BaseDepth < 0.0f == DepthDiff < 0.0f) 
			{
				//float DepthDiff = abs(BasePosition.w-SamplePosition.w);
				//float DepthWeight =  clamp(exp(-DepthDiff), 0.001f, 1.0f);
				//DepthWeight = pow(DepthWeight, 1.0f);
				//DepthWeight = clamp(DepthWeight, 0.001f, 1.0f);

				// Samples :
				vec4 SampleSH = texture(u_SH, SampleCoord).xyzw;
				vec2 SampleCoCg = texture(u_CoCg, SampleCoord).xy;
				float SampleLuma = SHToY(SampleSH);
				float SampleVariance = texture(u_VarianceTexture, SampleCoord).r;

				// :D
				float NormalWeight = pow(max(dot(BaseNormal, SampleNormal), 0.0f), 32.0f);
				NormalWeight = clamp(NormalWeight, 0.001f, 1.0f);
				float LuminosityWeight = abs(SampleLuma - BaseLuminance) / PhiColor;
				float DepthWeight = clamp(pow(exp(-max(DepthDiff, 0.00001f)), 2.0f), 0.0001f, 1.0f);
				float Weight = DoStrongSpatial ? (NormalWeight * DepthWeight) : (exp(-LuminosityWeight) * NormalWeight * DepthWeight); // * DepthWeight;
				Weight = clamp(Weight, 0.001f, 1.0f);

				// Kernel Weights : 
				float XWeight = AtrousWeights[abs(x)];
				float YWeight = AtrousWeights[abs(y)];

				Weight = (XWeight * YWeight) * Weight;
				Weight = max(Weight, 0.00000001f);

				TotalSH += SampleSH * Weight;
				TotalCoCg += SampleCoCg * Weight;
				TotalVariance += sqr(Weight) * SampleVariance;
				TotalWeight += Weight;

				// Remove this later?
				if (FilterSky || FilterAO)
				{
					float CurrAOWeight = 1.0f;

					const float aopow = pow(2.0f, 6.0f);
					CurrAOWeight = clamp((XWeight * YWeight) * NormalWeight * DepthWeight, 0.000001f, 1.0f);

					vec2 AOAndSkySample = texture(u_AO, SampleCoord).xy;
					TotalAOSky.x += AOAndSkySample.x * CurrAOWeight;
					TotalAOSky.y += AOAndSkySample.y * CurrAOWeight;

					TotalAOWeight += CurrAOWeight;
				}
			}
		}
	}
	
	TotalSH /= TotalWeight;
	TotalCoCg /= TotalWeight;
	TotalVariance /= sqr(TotalWeight);
	TotalAOSky /= TotalAOWeight;
	
	// Output : 
	o_SH = TotalSH;
	o_CoCg = TotalCoCg;
	o_Variance = TotalVariance;
	o_AOAndSkylighting = TotalAOSky;

	if (!FilterAO) {
		o_AOAndSkylighting.x = BaseAOSky.x;
	}

	const bool DontFilter = false;

	if (!DO_SPATIAL) { 
		o_SH = BaseSH;
		o_CoCg = BaseCoCg;
		o_Variance = BaseVariance;
		o_AOAndSkylighting = BaseAOSky;
	}

    // clamp
	o_SH = clamp(o_SH, -100.0f, 100.0f);
	o_CoCg = clamp(o_CoCg, -10.0f, 100.0f);
	o_Variance = clamp(o_Variance, -1.0f, 50.0f);
	o_AOAndSkylighting = clamp(o_AOAndSkylighting, 0.0f, 1.0f);
}