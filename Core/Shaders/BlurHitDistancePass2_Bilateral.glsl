#version 330 core


layout (location = 1) out float o_HitDistance;

in vec2 v_TexCoords;

uniform sampler2D u_PositionTexture;
uniform sampler2D u_HitDist;
uniform sampler2D u_Normals;

// basic wavelet filter
void main() {
	
	vec2 TexelSize = 1.0f/textureSize(u_HitDist,0);
	float Scale = 2.0f;
	const float AtrousWeights[3] = float[3]( 1.0f, 2.0f / 3.0f, 1.0f / 6.0f );

	float BaseHitDistance = texture(u_PositionTexture,v_TexCoords).x;
	float BaseSpecHitDistance = texture(u_HitDist, v_TexCoords).x;

	#ifdef BE_USELESS
		o_HitDistance = BaseSpecHitDistance;
		return;
	#endif

	float TotalWeight = 1.0f;
	float TotalDist = BaseSpecHitDistance;
	float BaseNormals = texture(u_Normals, v_TexCoords).x;

	for (int x = -1 ; x <= 1 ; x++) {
		for (int y = -2 ; y <= 2 ; y++) {
			if (x == 0 && y == 0) { continue; }
			float DistAt = texture(u_PositionTexture,v_TexCoords+vec2(x,y)*TexelSize*Scale).x;
			float HitDistAt = texture(u_HitDist,v_TexCoords+vec2(x,y)*TexelSize*Scale).x;
			float NormalsAt = texture(u_Normals,v_TexCoords+vec2(x,y)*TexelSize*Scale).x;
			float e = abs(DistAt - BaseHitDistance);
			if (e > 1.0f || HitDistAt < 0.0f || abs(NormalsAt-BaseNormals)>0.01f) { continue; }
			float w = AtrousWeights[abs(x)]*AtrousWeights[abs(y)];
			TotalDist += HitDistAt*w;
			TotalWeight += w;
		}
	}

	o_HitDistance = TotalDist / max(TotalWeight, 0.001f);
}