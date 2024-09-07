#include "WorldGenerator.h"

#include "BlockDatabase.h"

#include "Utils/Random.h"

static uint8_t GRASS_ID = 16;
static uint8_t STONE_ID = 32;
static uint8_t DIRT_ID = 48;
static uint8_t SAND_ID = 64;
static uint8_t OAK_ID = 128;
static uint8_t LEAF_ID = 129;
static uint8_t CACTUS_ID = 129;
static uint8_t COBBLE_ID = 129;
typedef int Biome;

static std::random_device rand_dev;
static std::mt19937 gen;
static std::uniform_int_distribution<int> dist;

int random_int() {
	return dist(gen);
}

bool validpos(glm::ivec3 C) {
	if ((C.x >= 0 && C.x < WORLD_SIZE_X &&
		C.y >= 0 && C.y < WORLD_SIZE_Y &&
		C.z >= 0 && C.z < WORLD_SIZE_Z)) {
		return true;
	}
	return false;
}

Biome GetBiome(float chunk_noise)
{
	// Quantize the noise into various levels and frequency

	if (chunk_noise < 90)
	{
		return 0;
	}

	else
	{
		return 1;
	}
}

void SetVerticalBlocks(VoxelRT::World* world, int x, int z, int y_level, int biome, bool swapstone)
{
	for (int y = 0; y < y_level; y++)
	{
		if (biome == 1) {
			if (y >= y_level - 1)
			{
				uint8_t sid = !swapstone ? 1 : (rand() % 8 <= 2 ? COBBLE_ID : STONE_ID);
				world->SetBlock(x, y, z, { swapstone?sid:GRASS_ID });
			}

			else if (y >= y_level - 5)
			{
				world->SetBlock(x, y, z, { DIRT_ID });
			}

			else
			{
				world->SetBlock(x, y, z, { STONE_ID });
			}
		}

		else {
			if (y >= y_level - 1)
			{
				world->SetBlock(x, y, z, { SAND_ID });
			}

			else if (y >= y_level - 8)
			{
				world->SetBlock(x, y, z, { SAND_ID });
			}

			else
			{
				world->SetBlock(x, y, z, { STONE_ID });
			}

		}
	}
}

void GenerateCactii(VoxelRT::World* world, int x, int y, int z) {
	glm::vec3 OriginTree = glm::vec3(x, y + ((rand()%5) + 2), z);
	for (int i = 0; i < 6; i++) {
		world->SetBlock(x, y + i, z, { CACTUS_ID });
	}
}

void GenerateTree(VoxelRT::World* world, int x, int y, int z) {
	glm::vec3 OriginTree = glm::vec3(x, y + 8, z);
	for (int i = 0; i < 6; i++) {
		world->SetBlock(x, y+i, z, { OAK_ID });
	}

	const int SR = 16;
	const int MAX_EXTRAS = 128;

	constexpr std::array<glm::ivec3, 6> VoxelOffsets = { {
		glm::ivec3(-1, 0, 0), // Offset in the negative x direction
		glm::ivec3(1, 0, 0),  // Offset in the positive x direction
		glm::ivec3(0, -1, 0), // Offset in the negative y direction
		glm::ivec3(0, 1, 0),  // Offset in the positive y direction
		glm::ivec3(0, 0, -1), // Offset in the negative z direction
		glm::ivec3(0, 0, 1)   // Offset in the positive z direction
	} };

	for (int xx = -SR; xx <= SR; xx++) {
		for (int yy = -SR; yy <= SR; yy++) {
			for (int zz = -SR; zz <= SR; zz++) {

				glm::ivec3 C = { x + xx,y + yy,z + zz };
				
				if (!validpos(C)) {
					continue;
				}

				if (glm::distance(glm::vec3(C), glm::vec3(OriginTree)) <= 3.5f) {
					world->SetBlock(C.x, C.y, C.z, { LEAF_ID });
				}
			}
		}
	}

	int Extras = 0;
	for (int xx = -SR; xx <= SR; xx++) {
		for (int yy = -SR; yy <= SR; yy++) {
			for (int zz = -SR; zz <= SR; zz++) {

				glm::ivec3 C = { x + xx,y + yy,z + zz };

				if (!validpos(C)) {
					continue;
				}

				if (world->GetBlock(C).block != 0) {
					continue;
				}

				bool NeighbourExist = false;

				for (int i = 0; i < 6; i++) {
					glm::ivec3 Cc = VoxelOffsets[i] + C;
					if (validpos(Cc)) {
						if (world->GetBlock(Cc).block == LEAF_ID) {
							NeighbourExist = true; break;
						}
					}
				}

				if (rand() % 22 == 5 && Extras <= MAX_EXTRAS && NeighbourExist) {
					world->SetBlock(C.x, C.y, C.z, { LEAF_ID });
					Extras++;
				}

				if (Extras > MAX_EXTRAS)
				{
					break;
				}
			}

			if (Extras >= MAX_EXTRAS)
			{
				break;
			}
		}

		if (Extras >= MAX_EXTRAS)
		{
			break;
		}
	}

	for (int i = 0; i < 1; i++) {
		int rh = (rand() % 4) + 1;
		int ra = rand() % 2;
		if (ra == 1) {
			ra = 2;
		}
		int sign = (rand() % 2 == 0) ? -1 : 1;

		glm::ivec3 BaseCoord = glm::ivec3(x, y + rh, z);
		BaseCoord[ra] += sign;
		if (validpos(BaseCoord)) {
			world->SetBlock(BaseCoord.x, BaseCoord.y, BaseCoord.z, { OAK_ID });
		}

		BaseCoord[ra] += sign;
		if (validpos(BaseCoord)) {
			world->SetBlock(BaseCoord.x, BaseCoord.y, BaseCoord.z, { OAK_ID });
		}

		BaseCoord.y += (rand() % 2 == 0) ? 1 : -1;
		if (validpos(BaseCoord)) {
			world->SetBlock(BaseCoord.x, BaseCoord.y, BaseCoord.z, { OAK_ID });
		}
	}
}

void VoxelRT::GenerateWorld(World* world, bool gen_type, bool gen_structures)
{
	std::vector<glm::ivec2> StructureCoords;

	int STRUCTURE_FREQ = 624;
	gen = std::mt19937(rand_dev());
	dist = std::uniform_int_distribution<int>(0, STRUCTURE_FREQ);

	srand(time(0));
	static FastNoise BiomeGenerator(rand()%50000); // Biome generator (quintized simplex noise)
	static FastNoise NoiseGenerator(rand() % 50000); // Simplex fractal
	static FastNoise StoneRando(rand()%50000); // Simplex fractal

	BiomeGenerator.SetNoiseType(FastNoise::Simplex);
	StoneRando.SetNoiseType(FastNoise::Simplex);

	GRASS_ID = VoxelRT::BlockDatabase::GetBlockID("Grass");
	DIRT_ID = VoxelRT::BlockDatabase::GetBlockID("Dirt");
	STONE_ID = VoxelRT::BlockDatabase::GetBlockID("Stone");
	SAND_ID = VoxelRT::BlockDatabase::GetBlockID("Sand");
	OAK_ID = VoxelRT::BlockDatabase::GetBlockID("oak_log");
	LEAF_ID = VoxelRT::BlockDatabase::GetBlockID("oak_leaves");
	CACTUS_ID = VoxelRT::BlockDatabase::GetBlockID("Cactus");
	COBBLE_ID = VoxelRT::BlockDatabase::GetBlockID("Cobblestone");

	if (gen_type)
	{
		NoiseGenerator.SetNoiseType(FastNoise::SimplexFractal);
		NoiseGenerator.SetFrequency(0.00385);
		NoiseGenerator.SetFractalOctaves(6);

		StoneRando.SetFrequency(0.06f);
		StoneRando.SetFractalOctaves(16);

		for (int x = 0; x < WORLD_SIZE_X; x++)
		{
			for (int z = 0; z < WORLD_SIZE_Z; z++)
			{
				float real_x = x;
				float real_z = z;
				float height;
				float h;

				h = (NoiseGenerator.GetNoise(real_x, real_z));
				height = ((h + 1.0f) / 2.0f) * 40.0f;

				float column_noise = BiomeGenerator.GetNoise(real_x/2.0f, real_z/2.0f);
				column_noise = ((column_noise + 1.0f) / 2) * 240;

				Biome b = GetBiome(column_noise);

				float stone_noise = StoneRando.GetNoise(real_x / 2.0f, real_z / 2.0f) * 100.0f;
				stone_noise = std::abs(stone_noise);

				int Yc = height + 8;

				bool ConvertStone = (stone_noise > 70.0f) && gen_structures;
				SetVerticalBlocks(world, x, z, Yc, b, (b == 1) ? ConvertStone : false);

				if (gen_structures) {
					if (random_int() == STRUCTURE_FREQ / 2) {

						if ((b == 1 && !ConvertStone) || b != 1)
						{

							bool can_spawn = true;

							for (auto& e : StructureCoords) {
								if (int(glm::distance(glm::vec2(e), glm::vec2(x, z))) <= 6) {
									can_spawn = false;
									break;
								}
							}

							if (can_spawn) {

								if (b == 1) {
									GenerateTree(world, x, Yc, z);
								}

								else {
									GenerateCactii(world, x, Yc, z);
								}
								StructureCoords.push_back({ x,z });
							}
						}
					}
				}
			}
		}
	}

	else
	{
		for (int x = 0; x < WORLD_SIZE_X; x++)
		{
			for (int z = 0; z < WORLD_SIZE_Z; z++)
			{
				float real_x = x;
				float real_z = z;

				SetVerticalBlocks(world, x, z, 50,1,false);
			}
		}
	}
}