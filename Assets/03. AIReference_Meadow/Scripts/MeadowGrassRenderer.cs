// [AI 생성 예시] 이 파일은 AI(Claude)가 작성한 목표 예시이며 과제 제출용 셰이더(Assets/02. MyShaders)가 아닙니다.
using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>C# 쪽 지형 높이. MeadowCommon.hlsl 의 MeadowHeight 와 식이 같아야 한다.</summary>
public static class MeadowTerrain
{
    public static float Height(float x, float z, float hill)
    {
        return hill * (0.9f * Mathf.Sin(x * 0.045f + 1.3f) * Mathf.Sin(z * 0.038f + 0.4f)
                     + 0.35f * Mathf.Sin(x * 0.11f + z * 0.07f + 2.0f));
    }
}

/// <summary>
/// 잔디와 지면을 그린다. 풀 한 포기 메시를 Graphics.RenderMeshPrimitives 로 인스턴싱하고,
/// 포기의 위치는 MeadowGrass 셰이더가 인스턴스 번호에서 직접 만든다(버퍼 없음).
/// 거리 단계(LOD)마다 격자 칸 크기를 키워, 먼 곳은 적은 포기를 넓게 그린다.
/// </summary>
[ExecuteAlways]
public class MeadowGrassRenderer : MonoBehaviour
{
    [Serializable]
    public struct Level
    {
        [Tooltip("격자 한 칸 크기(m). 칸마다 풀 한 포기")] public float cellSize;
        [Tooltip("격자 한 변의 칸 수. 포기 수 = 칸 수의 제곱")] public int gridDim;
        public float fadeInner;
        public float fadeOuter;
        public float fadeBand;
        [Tooltip("포기 수가 줄어든 만큼 폭을 넓혀 빈틈을 메운다")] public float widthScale;
        public float heightScale;
        [Tooltip("풀 한 포기의 마디 수(많을수록 부드럽게 휜다)")] public int segments;
    }

    public Material grassMaterial;
    public Material groundMaterial;
    public Camera targetCamera;

    [Header("지형")]
    [Tooltip("언덕 높이 배율. 0 이면 평지")] public float hillHeight = 1f;
    public bool keepCameraOnGround = true;
    public float cameraEyeHeight = 1.15f;

    [Header("지면")]
    public float groundSize = 700f;
    public int groundResolution = 160;

    [Header("거리 단계")]
    public Level[] levels =
    {
        new Level { cellSize = 0.075f, gridDim = 420, fadeInner = -100f, fadeOuter = 14f,  fadeBand = 3f,  widthScale = 1f,   heightScale = 1f,    segments = 5 },
        new Level { cellSize = 0.2f,   gridDim = 420, fadeInner = 14f,   fadeOuter = 40f,  fadeBand = 6f,  widthScale = 1.9f, heightScale = 1.03f, segments = 3 },
        new Level { cellSize = 0.5f,   gridDim = 420, fadeInner = 40f,   fadeOuter = 100f, fadeBand = 18f, widthScale = 3.8f, heightScale = 1.08f, segments = 2 },
    };

    static readonly int CellSizeId = Shader.PropertyToID("_CellSize");
    static readonly int GridDimId = Shader.PropertyToID("_GridDim");
    static readonly int FadeInnerId = Shader.PropertyToID("_FadeInner");
    static readonly int FadeOuterId = Shader.PropertyToID("_FadeOuter");
    static readonly int FadeBandId = Shader.PropertyToID("_FadeBand");
    static readonly int WidthScaleId = Shader.PropertyToID("_WidthScale");
    static readonly int HeightScaleId = Shader.PropertyToID("_HeightScale");
    static readonly int GridCenterId = Shader.PropertyToID("_MeadowGridCenter");
    static readonly int HillId = Shader.PropertyToID("_MeadowHill");
    static readonly int BaseColorId = Shader.PropertyToID("_BaseColor");
    static readonly int TipColorId = Shader.PropertyToID("_TipColor");
    static readonly int DryColorId = Shader.PropertyToID("_DryColor");
    static readonly int DryAmountId = Shader.PropertyToID("_DryAmount");

    readonly Dictionary<int, Mesh> bladeMeshes = new Dictionary<int, Mesh>();
    Mesh groundMesh;
    MaterialPropertyBlock[] levelProps;
    MaterialPropertyBlock groundProps;

    void OnDisable()
    {
        foreach (var mesh in bladeMeshes.Values) DestroySafe(mesh);
        bladeMeshes.Clear();
        DestroySafe(groundMesh);
        groundMesh = null;
    }

    void OnValidate()
    {
        // 값이 바뀌면 메시를 다시 만든다.
        OnDisable();
    }

    void LateUpdate()
    {
        Camera cam = targetCamera != null ? targetCamera : Camera.main;
        if (cam == null || grassMaterial == null) return;

        Shader.SetGlobalFloat(HillId, hillHeight);

        if (keepCameraOnGround)
        {
            Vector3 p = cam.transform.position;
            p.y = MeadowTerrain.Height(p.x, p.z, hillHeight) + cameraEyeHeight;
            cam.transform.position = p;
        }

        Vector3 center = cam.transform.position;
        Shader.SetGlobalVector(GridCenterId, center);

        // 셰이더가 정점을 옮기므로 메시 자체의 범위로는 컬링할 수 없다. 넉넉한 범위를 직접 준다.
        // (범위가 작으면 화면 가장자리에서 풀이 갑자기 사라진다)
        var bounds = new Bounds(center, new Vector3(600f, 200f, 600f));

        if (levelProps == null || levelProps.Length != levels.Length)
        {
            levelProps = new MaterialPropertyBlock[levels.Length];
            for (int i = 0; i < levelProps.Length; i++) levelProps[i] = new MaterialPropertyBlock();
        }

        for (int i = 0; i < levels.Length; i++)
        {
            Level level = levels[i];
            if (level.gridDim <= 0 || level.cellSize <= 0f) continue;

            MaterialPropertyBlock props = levelProps[i];
            props.SetFloat(CellSizeId, level.cellSize);
            props.SetFloat(GridDimId, level.gridDim);
            props.SetFloat(FadeInnerId, level.fadeInner);
            props.SetFloat(FadeOuterId, level.fadeOuter);
            props.SetFloat(FadeBandId, level.fadeBand);
            props.SetFloat(WidthScaleId, level.widthScale);
            props.SetFloat(HeightScaleId, level.heightScale);

            var rp = new RenderParams(grassMaterial)
            {
                worldBounds = bounds,
                matProps = props,
                shadowCastingMode = ShadowCastingMode.Off,
                receiveShadows = false,
            };
            Graphics.RenderMeshPrimitives(rp, GetBladeMesh(level.segments), 0, level.gridDim * level.gridDim);
        }

        if (groundMaterial != null)
        {
            if (groundMesh == null) groundMesh = BuildGroundMesh(Mathf.Clamp(groundResolution, 8, 250));
            if (groundProps == null) groundProps = new MaterialPropertyBlock();

            // 지면은 풀 머티리얼의 색을 그대로 따라간다.
            groundProps.SetColor(BaseColorId, grassMaterial.GetColor(BaseColorId));
            groundProps.SetColor(TipColorId, grassMaterial.GetColor(TipColorId));
            groundProps.SetColor(DryColorId, grassMaterial.GetColor(DryColorId));
            groundProps.SetFloat(DryAmountId, grassMaterial.GetFloat(DryAmountId));

            // 격자 간격 단위로만 따라가게 해서, 카메라가 움직일 때 지면 정점이 울렁이지 않게 한다.
            float step = groundSize / Mathf.Clamp(groundResolution, 8, 250);
            var pos = new Vector3(Mathf.Floor(center.x / step) * step, 0f, Mathf.Floor(center.z / step) * step);
            Matrix4x4 matrix = Matrix4x4.TRS(pos, Quaternion.identity, new Vector3(groundSize, 1f, groundSize));

            var rp = new RenderParams(groundMaterial)
            {
                matProps = groundProps,
                shadowCastingMode = ShadowCastingMode.Off,
                receiveShadows = false,
            };
            Graphics.RenderMesh(rp, groundMesh, 0, matrix);
        }
    }

    Mesh GetBladeMesh(int segments)
    {
        segments = Mathf.Clamp(segments, 1, 12);
        if (bladeMeshes.TryGetValue(segments, out Mesh mesh) && mesh != null) return mesh;
        mesh = BuildBladeMesh(segments);
        bladeMeshes[segments] = mesh;
        return mesh;
    }

    /// <summary>풀 한 포기: 아래는 넓고 위로 갈수록 좁아지는 띠. x = 폭(-0.5~0.5), y = 높이(0~1).</summary>
    static Mesh BuildBladeMesh(int segments)
    {
        var vertices = new List<Vector3>();
        var uvs = new List<Vector2>();
        var triangles = new List<int>();

        for (int i = 0; i < segments; i++)
        {
            float t = (float)i / segments;
            float half = 0.5f * (1f - 0.8f * Mathf.Pow(t, 1.6f));
            vertices.Add(new Vector3(-half, t, 0f));
            vertices.Add(new Vector3(half, t, 0f));
            uvs.Add(new Vector2(0f, t));
            uvs.Add(new Vector2(1f, t));
        }
        vertices.Add(new Vector3(0f, 1f, 0f));   // 끝점
        uvs.Add(new Vector2(0.5f, 1f));

        for (int i = 0; i < segments - 1; i++)
        {
            int a = i * 2;
            triangles.Add(a); triangles.Add(a + 2); triangles.Add(a + 1);
            triangles.Add(a + 1); triangles.Add(a + 2); triangles.Add(a + 3);
        }
        int last = (segments - 1) * 2;
        triangles.Add(last); triangles.Add(last + 2); triangles.Add(last + 1);

        var mesh = new Mesh { name = "GrassBlade_" + segments, hideFlags = HideFlags.HideAndDontSave };
        mesh.SetVertices(vertices);
        mesh.SetUVs(0, uvs);
        mesh.SetTriangles(triangles, 0);
        mesh.bounds = new Bounds(Vector3.zero, Vector3.one * 1000f);
        return mesh;
    }

    /// <summary>지면: 높이는 셰이더가 넣으므로 평평한 격자만 만든다. 크기 1, 중심 원점.</summary>
    static Mesh BuildGroundMesh(int resolution)
    {
        int n = resolution + 1;
        var vertices = new Vector3[n * n];
        var triangles = new int[resolution * resolution * 6];

        for (int z = 0; z < n; z++)
        {
            for (int x = 0; x < n; x++)
            {
                vertices[z * n + x] = new Vector3((float)x / resolution - 0.5f, 0f, (float)z / resolution - 0.5f);
            }
        }

        int index = 0;
        for (int z = 0; z < resolution; z++)
        {
            for (int x = 0; x < resolution; x++)
            {
                int a = z * n + x;
                triangles[index++] = a; triangles[index++] = a + n; triangles[index++] = a + 1;
                triangles[index++] = a + 1; triangles[index++] = a + n; triangles[index++] = a + n + 1;
            }
        }

        var mesh = new Mesh { name = "MeadowGround", hideFlags = HideFlags.HideAndDontSave, indexFormat = IndexFormat.UInt32 };
        mesh.vertices = vertices;
        mesh.triangles = triangles;
        // 셰이더가 y 를 올리고 내리므로 세로 범위를 넉넉히 준다.
        mesh.bounds = new Bounds(Vector3.zero, new Vector3(1f, 40f, 1f));
        return mesh;
    }

    static void DestroySafe(UnityEngine.Object obj)
    {
        if (obj == null) return;
        if (Application.isPlaying) Destroy(obj);
        else DestroyImmediate(obj);
    }
}
