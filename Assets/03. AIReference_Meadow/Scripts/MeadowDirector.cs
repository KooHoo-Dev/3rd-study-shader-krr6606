// [AI 생성 예시] 이 파일은 AI(Claude)가 작성한 목표 예시이며 과제 제출용 셰이더(Assets/02. MyShaders)가 아닙니다.
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// 연출 전체를 지휘한다.
///   낮 -> (꽃잎이 덮음) -> [완전히 덮인 순간에 낮/밤 교체] -> (꽃잎이 흩어짐) -> 밤
/// 셰이더들은 이 스크립트가 넣는 전역 값(_NightBlend, _PetalCover, _PetalScatter, 바람 등)만 읽는다.
/// 조명/안개/환경광/포스트 프로세싱도 같은 값으로 함께 바꾼다.
/// </summary>
[ExecuteAlways]
public class MeadowDirector : MonoBehaviour
{
    [Header("타임라인(초)")]
    public float dayHold = 4f;
    public float coverTime = 1.8f;
    [Tooltip("화면이 완전히 덮인 채 머무는 시간. 이 사이에 낮/밤이 바뀐다")] public float whiteHold = 0.6f;
    public float scatterTime = 3.2f;
    public float nightHold = 30f;
    [Tooltip("밤이 끝나면 같은 전환으로 낮으로 돌아가 반복한다")] public bool loop = true;

    [Header("편집 모드 미리보기 (플레이 중에는 타임라인이 대신한다)")]
    [Tooltip("편집 모드에서도 바람과 별이 움직이게 한다")] public bool animateInEditMode = true;
    [Range(0f, 1f)] public float previewNight;
    [Range(0f, 1f)] public float previewCover;
    [Range(0f, 1f)] public float previewScatter;

    [Header("연결")]
    public Camera targetCamera;
    public Light mainLight;
    public Material skyMaterial;
    public Material petalTransitionMaterial;
    public Material driftPetalMaterial;
    public Volume dayVolume;
    public Volume nightVolume;

    [Header("태양 / 달")]
    [Tooltip("방위각(도): 0 = +Z, 90 = +X")] public float sunAzimuth = 24f;
    public float sunElevation = 27f;
    public Color sunColor = new Color(1f, 0.95f, 0.84f);
    public float sunIntensity = 1.5f;
    public float moonAzimuth = -26f;
    public float moonElevation = 30f;
    public Color moonColor = new Color(0.55f, 0.68f, 1f);
    public float moonIntensity = 0.42f;

    [Header("환경광 (위 / 아래)")]
    [ColorUsage(false, true)] public Color dayAmbientSky = new Color(0.52f, 0.66f, 0.86f);
    [ColorUsage(false, true)] public Color dayAmbientGround = new Color(0.20f, 0.26f, 0.12f);
    [ColorUsage(false, true)] public Color nightAmbientSky = new Color(0.07f, 0.10f, 0.20f);
    [ColorUsage(false, true)] public Color nightAmbientGround = new Color(0.02f, 0.035f, 0.05f);

    [Header("안개 (색은 하늘 머티리얼의 지평선 색을 따른다)")]
    public float dayFogDensity = 0.0045f;
    public float nightFogDensity = 0.006f;

    [Header("바람")]
    [Tooltip("바람이 불어 가는 방향(도): 0 = +Z, 90 = +X")] public float windAngle = 70f;
    public float dayWindStrength = 0.75f;
    public float nightWindStrength = 0.5f;
    [Tooltip("돌풍 무늬가 들판 위를 지나가는 속도(m/s)")] public float gustSpeed = 3f;

    [Header("꽃잎")]
    [Range(3, 14)] public int petalRows = 7;
    [Range(1, 10)] public int petalLayers = 6;
    public int driftPetalCount = 700;
    [Tooltip("평소에 떠다니는 꽃잎의 비율")] [Range(0f, 1f)] public float driftBaseAmount = 0.12f;
    [Tooltip("전환 직후 많아졌던 꽃잎이 평소 양으로 줄어드는 시간(초)")] public float driftSettleTime = 14f;

    static readonly int NightId = Shader.PropertyToID("_NightBlend");
    static readonly int TimeId = Shader.PropertyToID("_MeadowTime");
    static readonly int WindId = Shader.PropertyToID("_MeadowWind");
    static readonly int SunDirId = Shader.PropertyToID("_MeadowSunDir");
    static readonly int MoonDirId = Shader.PropertyToID("_MeadowMoonDir");
    static readonly int AmbientSkyId = Shader.PropertyToID("_MeadowAmbientSky");
    static readonly int AmbientGroundId = Shader.PropertyToID("_MeadowAmbientGround");
    static readonly int CoverId = Shader.PropertyToID("_PetalCover");
    static readonly int ScatterId = Shader.PropertyToID("_PetalScatter");
    static readonly int PetalDirId = Shader.PropertyToID("_PetalDir");
    static readonly int PetalColsId = Shader.PropertyToID("_PetalCols");
    static readonly int PetalRowsId = Shader.PropertyToID("_PetalRows");
    static readonly int DriftAmountId = Shader.PropertyToID("_DriftPetalAmount");
    static readonly int GridCenterId = Shader.PropertyToID("_MeadowGridCenter");
    static readonly int DayHorizonId = Shader.PropertyToID("_DayHorizon");
    static readonly int NightHorizonId = Shader.PropertyToID("_NightHorizon");

    float playStartTime;
    float driftAmount;
    Mesh quad;
    MaterialPropertyBlock petalProps;

    struct State
    {
        public float night, cover, scatter;
        public float sinceTransition;   // 마지막 전환이 끝난 뒤 흐른 시간(전환 전이면 큰 값)
    }

    void OnEnable()
    {
        playStartTime = Time.time;
        driftAmount = driftBaseAmount;
#if UNITY_EDITOR
        UnityEditor.EditorApplication.update += EditorTick;
#endif
    }

    void OnDisable()
    {
#if UNITY_EDITOR
        UnityEditor.EditorApplication.update -= EditorTick;
#endif
        if (quad != null)
        {
            if (Application.isPlaying) Destroy(quad); else DestroyImmediate(quad);
            quad = null;
        }
    }

#if UNITY_EDITOR
    // 편집 모드에서는 Update 가 가만히 있으면 호출되지 않는다. 계속 돌도록 요청한다.
    void EditorTick()
    {
        if (!Application.isPlaying && animateInEditMode && isActiveAndEnabled)
        {
            UnityEditor.EditorApplication.QueuePlayerLoopUpdate();
        }
    }
#endif

    /// <summary>타임라인을 처음부터 다시 재생한다.</summary>
    public void Restart()
    {
        playStartTime = Time.time;
    }

    void Update()
    {
        State state = Application.isPlaying
            ? Evaluate(Time.time - playStartTime)
            : new State { night = previewNight, cover = previewCover, scatter = previewScatter, sinceTransition = 1000f };

        Apply(state);
    }

    // ------------------------------------------------------------------
    // 타임라인: 시간 -> (밤 정도, 덮임, 흩어짐)
    // ------------------------------------------------------------------
    State Evaluate(float t)
    {
        float transition = coverTime + whiteHold + scatterTime;
        float total = dayHold + transition + nightHold + transition;
        if (loop) t = Mathf.Repeat(t, total);

        var s = new State { sinceTransition = 1000f };

        if (t < dayHold)                                   // 낮
        {
            s.night = 0f;
            // 반복 재생에서는 방금 낮으로 돌아온 직후일 수 있다.
            if (loop && Time.time - playStartTime > total) s.sinceTransition = t;
            return s;
        }
        t -= dayHold;

        if (t < transition) return EvaluateTransition(t, 0f, 1f);   // 낮 -> 밤
        t -= transition;

        if (t < nightHold || !loop)                        // 밤
        {
            s.night = 1f;
            s.sinceTransition = t;
            return s;
        }
        t -= nightHold;

        return EvaluateTransition(t, 1f, 0f);              // 밤 -> 낮
    }

    State EvaluateTransition(float t, float from, float to)
    {
        var s = new State { sinceTransition = 0f };
        if (t < coverTime)                                 // 덮는 중: 아직 이전 장면
        {
            s.cover = t / Mathf.Max(coverTime, 0.01f);
            s.night = from;
        }
        else if (t < coverTime + whiteHold)                // 완전히 덮임: 여기서 낮/밤을 바꾼다
        {
            s.cover = 1f;
            s.night = Mathf.Lerp(from, to, Mathf.SmoothStep(0f, 1f, (t - coverTime) / Mathf.Max(whiteHold, 0.01f)));
        }
        else                                               // 흩어지는 중: 이미 새 장면
        {
            s.cover = 1f;
            s.scatter = (t - coverTime - whiteHold) / Mathf.Max(scatterTime, 0.01f);
            s.night = to;
        }
        return s;
    }

    // ------------------------------------------------------------------
    // 적용: 전역 셰이더 값, 조명, 안개, 환경광, 포스트 프로세싱, 꽃잎 그리기
    // ------------------------------------------------------------------
    void Apply(State state)
    {
        float night = Mathf.Clamp01(state.night);

        // 시간이 너무 커지면 float 정밀도가 떨어져 노이즈가 떨리므로 한 시간마다 되감는다.
        double now = Application.isPlaying ? Time.timeAsDouble : GetEditorTime();
        float shaderTime = (float)(now % 3600.0);

        float windRad = windAngle * Mathf.Deg2Rad;
        var windDir = new Vector2(Mathf.Sin(windRad), Mathf.Cos(windRad));
        float windStrength = Mathf.Lerp(dayWindStrength, nightWindStrength, night);

        Vector3 sunDir = DirectionFromAngles(sunAzimuth, sunElevation);
        Vector3 moonDir = DirectionFromAngles(moonAzimuth, moonElevation);
        Color ambientSky = Color.Lerp(dayAmbientSky, nightAmbientSky, night);
        Color ambientGround = Color.Lerp(dayAmbientGround, nightAmbientGround, night);

        Shader.SetGlobalFloat(NightId, night);
        Shader.SetGlobalFloat(TimeId, shaderTime);
        Shader.SetGlobalVector(WindId, new Vector4(windDir.x, windDir.y, windStrength, gustSpeed));
        Shader.SetGlobalVector(SunDirId, sunDir);
        Shader.SetGlobalVector(MoonDirId, moonDir);
        // 색 공간 변환이 확실하도록 직접 리니어로 바꿔 벡터로 넣는다.
        Shader.SetGlobalVector(AmbientSkyId, (Vector4)ambientSky.linear);
        Shader.SetGlobalVector(AmbientGroundId, (Vector4)ambientGround.linear);
        Shader.SetGlobalFloat(CoverId, state.cover);
        Shader.SetGlobalFloat(ScatterId, state.scatter);

        // 주 조명: 낮에는 태양, 밤에는 달. 방향이 바뀌는 순간은 꽃잎에 가려져 있다.
        if (mainLight != null)
        {
            Vector3 toLight = night < 0.5f ? sunDir : moonDir;
            mainLight.transform.rotation = Quaternion.LookRotation(-toLight);
            mainLight.color = Color.Lerp(sunColor, moonColor, night);
            mainLight.intensity = Mathf.Lerp(sunIntensity, moonIntensity, night);
        }

        // 안개 색 = 하늘의 지평선 색 -> 들판 끝이 하늘로 녹아들어 끝없이 이어져 보인다.
        if (skyMaterial != null)
        {
            RenderSettings.fogColor = Color.Lerp(skyMaterial.GetColor(DayHorizonId), skyMaterial.GetColor(NightHorizonId), night);
        }
        RenderSettings.fogDensity = Mathf.Lerp(dayFogDensity, nightFogDensity, night);
        RenderSettings.ambientSkyColor = ambientSky;
        RenderSettings.ambientEquatorColor = Color.Lerp(ambientSky, ambientGround, 0.5f);
        RenderSettings.ambientGroundColor = ambientGround;

        if (dayVolume != null) dayVolume.weight = 1f - night;
        if (nightVolume != null) nightVolume.weight = night;

        DrawPetals(state, windDir);
    }

    void DrawPetals(State state, Vector2 windDir)
    {
        Camera cam = targetCamera != null ? targetCamera : Camera.main;
        if (cam == null) return;
        if (quad == null) quad = BuildQuad();

        var hugeBounds = new Bounds(cam.transform.position, Vector3.one * 2000f);

        // 1) 화면 전환 꽃잎: 전환 중에만, 게임 카메라에만 그린다.
        bool transitioning = state.cover > 0f && state.scatter < 1f;
        if (transitioning && petalTransitionMaterial != null)
        {
            // 월드의 바람 방향을 화면의 좌/우로 옮겨, 풀이 눕는 쪽으로 꽃잎도 날아가게 한다.
            Vector3 wind3 = new Vector3(windDir.x, 0f, windDir.y);
            float screenX = Vector3.Dot(wind3, cam.transform.right) >= 0f ? 1f : -1f;
            Vector2 petalDir = new Vector2(screenX, 0.28f).normalized;

            int rows = petalRows + 2;                                   // 위아래 여유 1칸씩
            int cols = Mathf.CeilToInt(petalRows * cam.aspect) + 3;
            int count = 1 + rows * cols * petalLayers;                  // +1 = 화면 채움 사각형

            if (petalProps == null) petalProps = new MaterialPropertyBlock();
            petalProps.SetFloat(PetalColsId, cols);
            petalProps.SetFloat(PetalRowsId, rows);
            petalProps.SetVector(PetalDirId, petalDir);

            var rp = new RenderParams(petalTransitionMaterial)
            {
                camera = cam,
                worldBounds = hugeBounds,
                matProps = petalProps,
                shadowCastingMode = ShadowCastingMode.Off,
                receiveShadows = false,
            };
            Graphics.RenderMeshPrimitives(rp, quad, 0, count);
        }

        // 2) 떠다니는 꽃잎: 흩어지는 동안 늘어났다가 천천히 평소 양으로 돌아간다.
        float target = driftBaseAmount;
        if (transitioning) target = Mathf.Lerp(driftBaseAmount, 1f, Mathf.Clamp01(state.scatter * 2f));
        else if (state.sinceTransition < driftSettleTime)
            target = Mathf.Lerp(1f, driftBaseAmount, state.sinceTransition / Mathf.Max(driftSettleTime, 0.01f));
        driftAmount = Application.isPlaying ? Mathf.MoveTowards(driftAmount, target, Time.deltaTime * 1.5f) : target;
        Shader.SetGlobalFloat(DriftAmountId, driftAmount);

        if (driftPetalMaterial != null && driftPetalCount > 0 && driftAmount > 0.001f)
        {
            // 잔디 렌더러가 없을 때도 상자 중심이 카메라를 따라가도록 여기서도 넣는다.
            Shader.SetGlobalVector(GridCenterId, cam.transform.position);
            var rp = new RenderParams(driftPetalMaterial)
            {
                worldBounds = hugeBounds,
                shadowCastingMode = ShadowCastingMode.Off,
                receiveShadows = false,
            };
            Graphics.RenderMeshPrimitives(rp, quad, 0, driftPetalCount);
        }
    }

    static Vector3 DirectionFromAngles(float azimuth, float elevation)
    {
        float az = azimuth * Mathf.Deg2Rad;
        float el = elevation * Mathf.Deg2Rad;
        return new Vector3(Mathf.Sin(az) * Mathf.Cos(el), Mathf.Sin(el), Mathf.Cos(az) * Mathf.Cos(el));
    }

    static double GetEditorTime()
    {
#if UNITY_EDITOR
        return UnityEditor.EditorApplication.timeSinceStartup;
#else
        return Time.realtimeSinceStartupAsDouble;
#endif
    }

    /// <summary>-1 ~ 1 사각형. 꽃잎 한 장, 또는 화면 전체를 덮는 데 쓴다.</summary>
    static Mesh BuildQuad()
    {
        var mesh = new Mesh { name = "PetalQuad", hideFlags = HideFlags.HideAndDontSave };
        mesh.vertices = new[]
        {
            new Vector3(-1f, -1f, 0f), new Vector3(1f, -1f, 0f),
            new Vector3(1f, 1f, 0f), new Vector3(-1f, 1f, 0f),
        };
        mesh.uv = new[] { new Vector2(0f, 0f), new Vector2(1f, 0f), new Vector2(1f, 1f), new Vector2(0f, 1f) };
        mesh.triangles = new[] { 0, 2, 1, 0, 3, 2 };
        mesh.bounds = new Bounds(Vector3.zero, Vector3.one * 2000f);
        return mesh;
    }
}
