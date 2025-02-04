#include "CloudRenderer.h"

#include "../GLClasses/Texture.h"

#include "../TAAJitter.h"

static float CloudResolution = 1.0f;
bool Checkerboard = false;
static float Coverage = 0.128f;
static float BoxSize = 220.0f;
static float DetailStrength = 0.0f;
static bool Bayer = true;
static bool HighQualityClouds = false;

static std::unique_ptr<GLClasses::Shader> CloudShaderPtr;
static std::unique_ptr<GLClasses::Shader> CloudTemporalFilterPtr;
static std::unique_ptr<GLClasses::Shader> CloudCheckerUpscalerPtr;
static std::unique_ptr<Clouds::NoiseTexture3D> CloudNoise;
static std::unique_ptr<Clouds::NoiseTexture3D> CloudNoiseDetail;
static std::unique_ptr<GLClasses::Texture> CloudCirrus;
static std::unique_ptr<GLClasses::Texture> GrayNoise;

namespace Clouds {
	GLClasses::Framebuffer CurlCloudNoise(128, 128, { { GL_RGB16F, GL_RGB, GL_FLOAT } }, false, false);
	GLClasses::Framebuffer CloudWeatherMap(256, 256, { { GL_RGBA16F, GL_RGBA, GL_FLOAT } }, false, false);
}

void Clouds::CloudRenderer::Initialize()
{
	CloudShaderPtr = std::unique_ptr<GLClasses::Shader>(new GLClasses::Shader);
	CloudTemporalFilterPtr = std::unique_ptr<GLClasses::Shader>(new GLClasses::Shader);
	CloudCheckerUpscalerPtr = std::unique_ptr<GLClasses::Shader>(new GLClasses::Shader);
	CloudNoise = std::unique_ptr<Clouds::NoiseTexture3D>(new Clouds::NoiseTexture3D);
	CloudNoiseDetail = std::unique_ptr<Clouds::NoiseTexture3D>(new Clouds::NoiseTexture3D);
	CloudCirrus = std::unique_ptr<GLClasses::Texture>(new GLClasses::Texture);
	GrayNoise = std::unique_ptr<GLClasses::Texture>(new GLClasses::Texture);

	CloudShaderPtr->CreateShaderProgramFromFile("Core/Shaders/Clouds/CloudVert.glsl", "Core/Shaders/Clouds/CloudFrag.glsl");
	CloudShaderPtr->CompileShaders();
	CloudTemporalFilterPtr->CreateShaderProgramFromFile("Core/Shaders/Clouds/FBOVert.glsl", "Core/Shaders/Clouds/TemporalFilter.glsl");
	CloudTemporalFilterPtr->CompileShaders();
	CloudCheckerUpscalerPtr->CreateShaderProgramFromFile("Core/Shaders/Clouds/FBOVert.glsl", "Core/Shaders/Clouds/CheckerUpscaler.glsl");
	CloudCheckerUpscalerPtr->CompileShaders();
	CloudCirrus->CreateTexture("Res/Misc/cirrus_density.png", false, false);
	GrayNoise->CreateTexture("Res/Misc/GrayNoise.png", false, false);

	CloudNoise->CreateTexture(64, 64, 64, nullptr); // (32 * 3) ^ 3
	CloudNoiseDetail->CreateTexture(32, 32, 32, nullptr);

	std::cout << "\nRendering noise textures!\n";
	CloudWeatherMap.CreateFramebuffer();
	CloudWeatherMap.SetSize(256, 256);

	CurlCloudNoise.CreateFramebuffer();
	CurlCloudNoise.SetSize(128, 128);

	Clouds::RenderNoise(*CloudNoise, 64, false);
	Clouds::RenderNoise(*CloudNoiseDetail, 32, true);

	Clouds::RenderCurlNoise(CurlCloudNoise);
	Clouds::RenderWeatherMap(CloudWeatherMap);

	// mipmap them.
	glBindTexture(GL_TEXTURE_3D, CloudNoise->GetTextureID());
	glGenerateMipmap(GL_TEXTURE_3D);
	glBindTexture(GL_TEXTURE_3D, 0);

	glBindTexture(GL_TEXTURE_3D, CloudNoiseDetail->GetTextureID());
	glGenerateMipmap(GL_TEXTURE_3D);
	glBindTexture(GL_TEXTURE_3D, 0);

	// unbind
	glBindTexture(GL_TEXTURE_2D, 0);
	glBindFramebuffer(GL_FRAMEBUFFER, 0);
	glUseProgram(0);

	std::cout << "\nRendered noise textures!\n";
}



GLuint Clouds::CloudRenderer::Update(
	const  glm::mat4& CurrentProjection,
	const  glm::mat4& CurrentView,
	const glm::mat4& PrevProjection,
	const glm::mat4& PrevView,
	const glm::vec3& CurrentPosition,
	const glm::vec3& PrevPosition,
	GLClasses::VertexArray& VAO,
	const glm::vec3& SunDirection,
	GLuint BlueNoise,
	int AppWidth, int AppHeight, int CurrentFrame, GLuint atmosphere, GLuint pos_tex, glm::vec3 PreviousPosition, GLuint pos_tex_prev, glm::vec2 modifiers,
	bool Clamp, glm::vec3 DetailParams, float TimeScale, bool curlnoise, float cirrusstrength, float CirrusScale, glm::ivec3 StepCounts, bool CHECKER_STEP_COUNT, float SunVisibility, float CloudDetailFBMPower,
	bool lodlighting, bool CloudForceSupersample, float CloudSuperSampleRes, bool CloudSpatialUpscale, float AmbientDensityMultiplier, GLuint EquiangularCloudMap, bool update_projection, float thickness, float detailcontrib, bool equiangularrender, glm::vec3 CelestialDirections[2], GLuint skymapmain, glm::vec2 Strengths)
{
	Checkerboard = false;
	DetailStrength = detailcontrib;


	static GLClasses::Framebuffer CloudFBO(16, 16, {{ GL_RGBA16F, GL_RGBA, GL_FLOAT, true, true }, { GL_R16F, GL_RED, GL_FLOAT, true, true }}, false);
	static GLClasses::Framebuffer CloudTemporalFBO1(16, 16, { GL_RGBA16F, GL_RGBA, GL_FLOAT, true, true }, false);
	static GLClasses::Framebuffer CloudTemporalFBO2(16, 16, { GL_RGBA16F, GL_RGBA, GL_FLOAT, true, true }, false);

	
	//static GLClasses::Framebuffer CheckerUpscaled(16, 16, { GL_RGBA, GL_RGBA, GL_UNSIGNED_BYTE, true, true }, false);
	//static GLClasses::Framebuffer CloudTemporalFBO1(16, 16, { GL_RGBA, GL_RGBA, GL_UNSIGNED_BYTE, true, true }, false);
	//static GLClasses::Framebuffer CloudTemporalFBO2(16, 16, { GL_RGBA, GL_RGBA, GL_UNSIGNED_BYTE, true, true }, false);


	auto& CloudTemporalFBO = (CurrentFrame % 2 == 0) ? CloudTemporalFBO1 : CloudTemporalFBO2;
	auto& PrevCloudTemporalFBO = (CurrentFrame % 2 == 0) ? CloudTemporalFBO2 : CloudTemporalFBO1;

	

	float TemporalResolution = CloudForceSupersample ? CloudSuperSampleRes : CloudResolution * 2.0f;
	CloudTemporalFBO1.SetSize(AppWidth * TemporalResolution, AppHeight * TemporalResolution);
	CloudTemporalFBO2.SetSize(AppWidth * TemporalResolution, AppHeight * TemporalResolution);

	CloudFBO.SetSize(AppWidth * CloudResolution, AppHeight * CloudResolution);


	glm::vec2 JitterValue = VoxelRT::GetTAAJitter(CurrentFrame, glm::vec2(AppWidth * CloudResolution, AppHeight * CloudResolution));

	GLClasses::Shader& CloudShader = *CloudShaderPtr;
	GLClasses::Shader& TemporalFilter = *CloudTemporalFilterPtr;
	GLClasses::Shader& CheckerUpscaler = *CloudCheckerUpscalerPtr;

	glDisable(GL_CULL_FACE);
	glDisable(GL_DEPTH_TEST);

	{
		glm::mat4 inv_view = glm::inverse(CurrentView);
		glm::mat4 inv_projection = glm::inverse(CurrentProjection);

		CloudFBO.Bind();
		CloudShader.Use();

		CloudShader.SetMatrix4("u_InverseView", inv_view);
		CloudShader.SetMatrix4("u_InverseProjection", inv_projection);
		CloudShader.SetInteger("u_WorleyNoise", 0);
		CloudShader.SetInteger("u_CloudNoise", 1);
		CloudShader.SetInteger("u_BlueNoise", 2);
		CloudShader.SetInteger("u_CloudDetailedNoise", 3);
		CloudShader.SetInteger("u_CurlNoise", 6);
		CloudShader.SetInteger("u_CloudWeatherMap", 8);
		CloudShader.SetInteger("u_CirrusClouds", 9);
		CloudShader.SetInteger("u_MainSkymap", 10);
		CloudShader.SetInteger("u_GrayNoise", 12);
		CloudShader.SetFloat("u_Time", glfwGetTime());
		CloudShader.SetFloat("u_Coverage", Coverage);
		CloudShader.SetFloat("BoxSize", BoxSize);
		CloudShader.SetFloat("u_DetailIntensity", DetailStrength);
		CloudShader.SetFloat("u_TimeScale", TimeScale);
		CloudShader.SetFloat("u_CirrusStrength", cirrusstrength);
		CloudShader.SetFloat("u_CirrusScale", CirrusScale);
		CloudShader.SetFloat("u_AmbientDensityMultiplier", AmbientDensityMultiplier);
		CloudShader.SetFloat("u_CloudDetailFBMPower", CloudDetailFBMPower);
		CloudShader.SetFloat("u_SunVisibility", SunVisibility);
		CloudShader.SetFloat("u_ResolutionScale", CloudResolution);
		CloudShader.SetFloat("CloudThickness", thickness);
		CloudShader.SetFloat("u_CloudThickness", thickness);
		CloudShader.SetInteger("u_CurrentFrame", CurrentFrame);
		CloudShader.SetInteger("u_SliceCount", 256);
		CloudShader.SetVector2f("u_Dimensions", glm::vec2(AppWidth, AppHeight));
		CloudShader.SetVector2f("u_VertDimensions", glm::vec2(AppWidth, AppHeight));
		CloudShader.SetVector2f("u_Modifiers", glm::vec2(modifiers));
		CloudShader.SetVector2f("u_CelestialStrengths", glm::vec2(Strengths));
		CloudShader.SetVector3f("u_DetailParams", glm::vec3(DetailParams));
		CloudShader.SetVector3f("u_SunDirection", glm::normalize(SunDirection));
		CloudShader.SetVector3f("u_ViewerPosition", CurrentPosition);
		CloudShader.SetVector3f("u_PlayerPosition", CurrentPosition);
		CloudShader.SetVector3f("u_ViewerPosition", CurrentPosition);
		CloudShader.SetInteger("u_VertCurrentFrame", CurrentFrame);
		CloudShader.SetInteger("u_Atmosphere", 4);
		CloudShader.SetInteger("u_PositionTex", 5);
		CloudShader.SetBool("u_Checker", Checkerboard);
		CloudShader.SetBool("u_UseBayer", Bayer);
		CloudShader.SetBool("u_HighQualityClouds", HighQualityClouds);
		CloudShader.SetBool("u_CurlNoiseOffset", curlnoise);
		CloudShader.SetBool("u_LodLighting", lodlighting);
		CloudShader.SetBool("u_InitialEquiangularRender", equiangularrender);
		CloudShader.SetVector2f("u_WindowDimensions", glm::vec2(AppWidth, AppHeight));
		CloudShader.SetVector2f("u_JitterValue", glm::vec2(JitterValue));
		CloudShader.SetVector3f("u_StepCounts", glm::vec3(StepCounts));
		CloudShader.SetVector3f("u_SunDirectionActual", CelestialDirections[0]);
		CloudShader.SetVector3f("u_MoonDirectionActual", CelestialDirections[1]);
		CloudShader.SetBool("CHECKER_STEP_COUNT", CHECKER_STEP_COUNT);

		glActiveTexture(GL_TEXTURE1);
		glBindTexture(GL_TEXTURE_3D, CloudNoise->GetTextureID());

		glActiveTexture(GL_TEXTURE2);
		glBindTexture(GL_TEXTURE_2D, BlueNoise);

		glActiveTexture(GL_TEXTURE3);
		glBindTexture(GL_TEXTURE_3D, CloudNoiseDetail->GetTextureID());

		glActiveTexture(GL_TEXTURE4);
		glBindTexture(GL_TEXTURE_CUBE_MAP, atmosphere);
		
		glActiveTexture(GL_TEXTURE10);
		glBindTexture(GL_TEXTURE_CUBE_MAP, skymapmain);

		glActiveTexture(GL_TEXTURE5);
		glBindTexture(GL_TEXTURE_2D, pos_tex);

		glActiveTexture(GL_TEXTURE6);
		glBindTexture(GL_TEXTURE_2D, CurlCloudNoise.GetTexture());

		glActiveTexture(GL_TEXTURE8);
		glBindTexture(GL_TEXTURE_2D, CloudWeatherMap.GetTexture());

		glActiveTexture(GL_TEXTURE9);
		glBindTexture(GL_TEXTURE_2D, CloudCirrus->GetTextureID());

		glActiveTexture(GL_TEXTURE10);
		glBindTexture(GL_TEXTURE_CUBE_MAP, skymapmain);
		
		glActiveTexture(GL_TEXTURE12);
		glBindTexture(GL_TEXTURE_2D, GrayNoise->GetTextureID());

		VAO.Bind();
		glDrawArrays(GL_TRIANGLES, 0, 6);
		VAO.Unbind();
	}

	// Temporally filter the clouds
	{
		TemporalFilter.Use();
		CloudTemporalFBO.Bind();

		TemporalFilter.SetInteger("u_CurrentColorTexture", 0);
		TemporalFilter.SetInteger("u_PreviousColorTexture", 1);
		TemporalFilter.SetInteger("u_CurrentPositionData", 2);
		TemporalFilter.SetInteger("u_PrevPositionData", 3);
		TemporalFilter.SetInteger("u_Transversals", 4);
		TemporalFilter.SetInteger("u_CurrentFrame", CurrentFrame);
		TemporalFilter.SetMatrix4("u_PrevProjection", PrevProjection);
		TemporalFilter.SetMatrix4("u_PrevView", PrevView);
		TemporalFilter.SetMatrix4("u_Projection", CurrentProjection);
		TemporalFilter.SetMatrix4("u_View", CurrentView);
		TemporalFilter.SetMatrix4("u_InverseProjection", glm::inverse(CurrentProjection));
		TemporalFilter.SetMatrix4("u_InverseView", glm::inverse(CurrentView));
		TemporalFilter.SetFloat("u_Time", glfwGetTime());
		TemporalFilter.SetVector3f("u_CurrentPosition", CurrentPosition);
		TemporalFilter.SetVector3f("u_PreviousPosition", PreviousPosition);
		TemporalFilter.SetBool("u_Clamp", Clamp);
		TemporalFilter.SetBool("u_CloudSpatialUpscale", CloudSpatialUpscale);
		TemporalFilter.SetBool("u_SpatialUpscale", CloudSpatialUpscale);
		TemporalFilter.SetBool("u_UpdateProjection", update_projection);
		TemporalFilter.SetBool("u_InitialEquiangularRender", equiangularrender);

		float mix_factor = (CurrentPosition != PrevPosition) ? 0.25f : 0.75f;
		TemporalFilter.SetFloat("u_MixModifier", mix_factor);

		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, CloudFBO.GetTexture());

		glActiveTexture(GL_TEXTURE1);
		glBindTexture(GL_TEXTURE_2D, PrevCloudTemporalFBO.GetTexture());

		glActiveTexture(GL_TEXTURE2);
		glBindTexture(GL_TEXTURE_2D, pos_tex);

		glActiveTexture(GL_TEXTURE3);
		glBindTexture(GL_TEXTURE_2D, pos_tex_prev);
		
		glActiveTexture(GL_TEXTURE4);
		glBindTexture(GL_TEXTURE_2D, CloudFBO.GetTexture(1));

		glBindImageTexture(4, EquiangularCloudMap, 0, 0, 0, GL_READ_WRITE, GL_RGBA8);

		VAO.Bind();
		glDrawArrays(GL_TRIANGLES, 0, 6);
		VAO.Unbind();
	}

	if (equiangularrender) {
		return CloudTemporalFBO.GetFramebuffer();
	}

	return CloudTemporalFBO.GetTexture();
}


void Clouds::CloudRenderer::RecompileShaders()
{
	CloudShaderPtr->Recompile();
	CloudTemporalFilterPtr->Recompile();
	CloudCheckerUpscalerPtr->Recompile();
}

void Clouds::CloudRenderer::SetCoverage(float v)
{
	Coverage = v;
}


void Clouds::CloudRenderer::SetResolution(float v)
{
	CloudResolution = v;
}
