#include "TAAJitter.h"

static glm::vec2 HaltonSequenceData[64];

// inside taa 
float HaltonSequence(int Prime, int index) 
{
	float r = 0.0f;
	float f = 1.0f;
	int i = index;
	while (i > 0)
	{
		f /= Prime;
		r += f * (i % Prime);
		i = (int)std::floor(i / float(Prime));
	}
	return r;
}

void VoxelRT::GenerateJitterStuff()
{
	for (int i = 0; i < 64; i++) 
	{
		// 2, 3 as the primes :D
		HaltonSequenceData[i].x = HaltonSequence(2, i + 1);
		HaltonSequenceData[i].y = HaltonSequence(3, i + 1);
	}
}

glm::mat4 VoxelRT::GetTAAJitterMatrix(int CurrentFrame, const glm::vec2& resolution)
{
	glm::vec2 Jitter = HaltonSequenceData[CurrentFrame % 64];
	glm::vec2 TexelSize = 1.0f / glm::vec2(resolution);
	return glm::translate(glm::mat4(1.0f), glm::vec3((2.0 * Jitter.x - 1.0) * TexelSize.x, (2.0 * Jitter.y - 1.0) * TexelSize.y, 0.0f));
}

glm::vec2 VoxelRT::GetTAAJitter(int CurrentFrame, const glm::vec2& resolution)
{
	glm::vec2 Jitter = HaltonSequenceData[CurrentFrame % 64];
	return Jitter;
}

glm::vec2 VoxelRT::GetTAAJitterSecondary(int CurrentFrame)
{
	glm::vec2 Jitter = HaltonSequenceData[CurrentFrame % 32];
	return Jitter;
}
