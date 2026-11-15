// [AI 생성 예시] 이 파일은 AI(Claude)가 작성한 목표 예시이며 과제 제출용 셰이더(Assets/02. MyShaders)가 아닙니다.
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

/// <summary>
/// 메뉴 Tools > AI Reference Meadow > Build Demo Scene 으로 들판 데모 씬을 한 번에 만든다.
/// 머티리얼과 볼륨 프로파일은 이미 있으면 다시 만들지 않으므로, 직접 조절한 값은 유지된다.
/// </summary>
public static class MeadowSceneBuilder
{
    const string Root = "Assets/03. AIReference_Meadow";
    const string ScenePath = Root + "/Scenes/AIReference_Meadow.unity";

    [MenuItem("Tools/AI Reference Meadow/Build Demo Scene")]
    public static void Build()
    {
        if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;

        // 1) 머티리얼
        Material sky = GetOrCreateMaterial("AIReference/MeadowSky", Root + "/MeadowSky/MeadowSky.mat");
        Material grass = GetOrCreateMaterial("AIReference/MeadowGrass", Root + "/MeadowGrass/MeadowGrass.mat");
        Material ground = GetOrCreateMaterial("AIReference/MeadowGround", Root + "/MeadowGrass/MeadowGround.mat");
        Material petal = GetOrCreateMaterial("AIReference/PetalTransition", Root + "/PetalTransition/PetalTransition.mat");
        Material meteor = GetOrCreateMaterial("AIReference/Meteor", Root + "/Meteor/Meteor.mat");
        Material drift = GetOrCreateMaterial("AIReference/DriftPetal", Root + "/DriftPetal/DriftPetal.mat");
        if (sky == null || grass == null || ground == null || petal == null || meteor == null || drift == null)
        {
            Debug.LogError("[Meadow] 셰이더를 찾지 못해 씬을 만들지 않았습니다. 콘솔의 셰이더 컴파일 오류를 확인하세요.");
            return;
        }

        // 2) 포스트 프로세싱 프로파일 (낮 / 밤)
        Directory.CreateDirectory(Root + "/Profiles");
        AssetDatabase.Refresh();
        VolumeProfile dayProfile = GetOrCreateProfile(Root + "/Profiles/Meadow_Day.asset", false);
        VolumeProfile nightProfile = GetOrCreateProfile(Root + "/Profiles/Meadow_Night.asset", true);

        // 3) 새 씬
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

        var cameraGo = new GameObject("Main Camera") { tag = "MainCamera" };
        var cam = cameraGo.AddComponent<Camera>();
        cameraGo.AddComponent<AudioListener>();
        cam.transform.SetPositionAndRotation(new Vector3(0f, 1.8f, 0f), Quaternion.Euler(-7f, 0f, 0f));
        cam.fieldOfView = 55f;
        cam.nearClipPlane = 0.05f;
        cam.farClipPlane = 1500f;
        cam.allowHDR = true;
        var camData = cam.GetUniversalAdditionalCameraData();
        camData.renderPostProcessing = true;
        camData.antialiasing = AntialiasingMode.SubpixelMorphologicalAntiAliasing;
        camData.antialiasingQuality = AntialiasingQuality.High;

        var lightGo = new GameObject("Sun-Moon Light");
        var light = lightGo.AddComponent<Light>();
        light.type = LightType.Directional;
        light.shadows = LightShadows.None;

        var dayVolume = CreateVolume("Day Volume", dayProfile, 1f);
        var nightVolume = CreateVolume("Night Volume", nightProfile, 0f);

        var directorGo = new GameObject("Meadow Director");
        var director = directorGo.AddComponent<MeadowDirector>();
        director.targetCamera = cam;
        director.mainLight = light;
        director.skyMaterial = sky;
        director.petalTransitionMaterial = petal;
        director.driftPetalMaterial = drift;
        director.dayVolume = dayVolume;
        director.nightVolume = nightVolume;

        var grassRenderer = directorGo.AddComponent<MeadowGrassRenderer>();
        grassRenderer.grassMaterial = grass;
        grassRenderer.groundMaterial = ground;
        grassRenderer.targetCamera = cam;

        var meteors = directorGo.AddComponent<MeteorShower>();
        meteors.meteorMaterial = meteor;
        meteors.targetCamera = cam;

        // 4) 씬 환경: 스카이박스, 안개, 환경광
        RenderSettings.skybox = sky;
        RenderSettings.sun = light;
        RenderSettings.fog = true;
        RenderSettings.fogMode = FogMode.ExponentialSquared;
        RenderSettings.ambientMode = AmbientMode.Trilight;

        Directory.CreateDirectory(Path.GetDirectoryName(ScenePath));
        EditorSceneManager.SaveScene(scene, ScenePath);
        AssetDatabase.SaveAssets();

        ReportShaderErrors();
        Debug.Log("[Meadow] 데모 씬을 만들었습니다: " + ScenePath + "  (Play 를 누르면 낮 -> 꽃잎 전환 -> 밤 연출이 재생됩니다)");
    }

    [MenuItem("Tools/AI Reference Meadow/Check Shader Errors")]
    public static void ReportShaderErrors()
    {
        string[] names =
        {
            "AIReference/MeadowSky", "AIReference/MeadowGrass", "AIReference/MeadowGround",
            "AIReference/PetalTransition", "AIReference/Meteor", "AIReference/DriftPetal",
        };
        int errors = 0;
        foreach (string name in names)
        {
            Shader shader = Shader.Find(name);
            if (shader == null)
            {
                Debug.LogError("[Meadow] 셰이더 없음: " + name);
                errors++;
                continue;
            }
            foreach (ShaderMessage message in ShaderUtil.GetShaderMessages(shader))
            {
                if (message.severity != UnityEditor.Rendering.ShaderCompilerMessageSeverity.Error) continue;
                Debug.LogError("[Meadow] " + name + " 컴파일 오류: " + message.message + " (" + message.file + ":" + message.line + ")");
                errors++;
            }
        }
        if (errors == 0) Debug.Log("[Meadow] 셰이더 6개 모두 오류 없음");
    }

    static Material GetOrCreateMaterial(string shaderName, string path)
    {
        var material = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (material != null) return material;

        Shader shader = Shader.Find(shaderName);
        if (shader == null) return null;

        material = new Material(shader);
        AssetDatabase.CreateAsset(material, path);
        return material;
    }

    static Volume CreateVolume(string name, VolumeProfile profile, float weight)
    {
        var go = new GameObject(name);
        var volume = go.AddComponent<Volume>();
        volume.isGlobal = true;
        volume.sharedProfile = profile;
        volume.weight = weight;
        return volume;
    }

    static VolumeProfile GetOrCreateProfile(string path, bool night)
    {
        var profile = AssetDatabase.LoadAssetAtPath<VolumeProfile>(path);
        if (profile != null) return profile;

        profile = ScriptableObject.CreateInstance<VolumeProfile>();
        AssetDatabase.CreateAsset(profile, path);

        // Bloom: HDR 로 1 보다 밝은 부분(태양, 별, 유성, 꽃잎)이 번지게 한다.
        var bloom = AddComponent<Bloom>(profile);
        bloom.threshold.Override(night ? 0.85f : 1.0f);
        bloom.intensity.Override(night ? 1.1f : 0.45f);
        bloom.scatter.Override(night ? 0.75f : 0.65f);
        bloom.highQualityFiltering.Override(true);

        var tonemapping = AddComponent<Tonemapping>(profile);
        tonemapping.mode.Override(TonemappingMode.Neutral);

        var color = AddComponent<ColorAdjustments>(profile);
        color.postExposure.Override(night ? 0.15f : 0.1f);
        color.contrast.Override(night ? 14f : 8f);
        color.saturation.Override(night ? 6f : 14f);
        color.colorFilter.Override(night ? new Color(0.92f, 0.96f, 1f) : Color.white);

        var vignette = AddComponent<Vignette>(profile);
        vignette.intensity.Override(night ? 0.34f : 0.18f);
        vignette.smoothness.Override(0.45f);

        EditorUtility.SetDirty(profile);
        return profile;
    }

    static T AddComponent<T>(VolumeProfile profile) where T : VolumeComponent
    {
        T component = profile.Add<T>(true);
        component.hideFlags = HideFlags.HideInInspector | HideFlags.HideInHierarchy;
        AssetDatabase.AddObjectToAsset(component, profile);
        return component;
    }
}
