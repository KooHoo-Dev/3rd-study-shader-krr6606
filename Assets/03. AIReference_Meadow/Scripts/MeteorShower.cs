// [AI 생성 예시] 이 파일은 AI(Claude)가 작성한 목표 예시이며 과제 제출용 셰이더(Assets/02. MyShaders)가 아닙니다.
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// 밤에만 가끔 유성을 떨어뜨린다. 유성 하나는 길쭉한 사각형이고,
/// 머리 위치/진행 방향/꼬리 길이를 매 프레임 행렬로 만들어 Meteor 셰이더로 그린다.
/// </summary>
[ExecuteAlways]
public class MeteorShower : MonoBehaviour
{
    public Material meteorMaterial;
    public Camera targetCamera;

    [Header("빈도")]
    [Tooltip("유성 사이의 대기 시간(초) 범위")] public Vector2 interval = new Vector2(3f, 9f);
    [Tooltip("한 번에 여러 개가 연달아 떨어질 확률")] [Range(0f, 1f)] public float burstChance = 0.25f;

    [Header("모양")]
    public float domeRadius = 500f;
    public Vector2 speed = new Vector2(260f, 420f);
    public Vector2 duration = new Vector2(0.6f, 1.1f);
    public Vector2 tailLength = new Vector2(70f, 130f);
    public float width = 5f;
    public float brightness = 1f;

    struct Meteor
    {
        public bool active;
        public Vector3 startOffset;   // 카메라 기준 시작 위치
        public Vector3 direction;     // 진행 방향
        public float speed, duration, length, age, brightness;
    }

    const int PoolSize = 6;
    static readonly int LifeId = Shader.PropertyToID("_MeteorLife");
    static readonly int BrightnessId = Shader.PropertyToID("_MeteorBrightness");
    static readonly int NightId = Shader.PropertyToID("_NightBlend");

    readonly Meteor[] meteors = new Meteor[PoolSize];
    MaterialPropertyBlock[] props;
    Mesh quad;
    float nextSpawn = 2f;
    int pendingBurst;

    void OnDisable()
    {
        if (quad != null)
        {
            if (Application.isPlaying) Destroy(quad); else DestroyImmediate(quad);
            quad = null;
        }
    }

    void Update()
    {
        Camera cam = targetCamera != null ? targetCamera : Camera.main;
        if (cam == null || meteorMaterial == null) return;

        float dt = Application.isPlaying ? Time.deltaTime : 1f / 60f;
        float night = Shader.GetGlobalFloat(NightId);

        // 밤일 때만 새 유성을 만든다.
        if (night > 0.6f)
        {
            nextSpawn -= dt;
            if (nextSpawn <= 0f)
            {
                Spawn(cam);
                if (pendingBurst > 0)
                {
                    pendingBurst--;
                    nextSpawn = Random.Range(0.15f, 0.5f);
                }
                else
                {
                    nextSpawn = Random.Range(interval.x, interval.y);
                    if (Random.value < burstChance) pendingBurst = Random.Range(1, 3);
                }
            }
        }

        if (quad == null) quad = BuildQuad();
        if (props == null)
        {
            props = new MaterialPropertyBlock[PoolSize];
            for (int i = 0; i < PoolSize; i++) props[i] = new MaterialPropertyBlock();
        }

        Vector3 camPos = cam.transform.position;
        for (int i = 0; i < PoolSize; i++)
        {
            if (!meteors[i].active) continue;

            meteors[i].age += dt;
            Meteor m = meteors[i];
            float life = m.age / m.duration;
            if (life >= 1f)
            {
                meteors[i].active = false;
                continue;
            }

            Vector3 head = camPos + m.startOffset + m.direction * (m.speed * m.age);
            // 꼬리는 나타난 직후 짧았다가 금방 제 길이가 된다.
            float length = m.length * Mathf.Clamp01(life * 4f);

            // 사각형의 x 축 = 꼬리 방향, y 축 = 화면에서 폭이 보이도록 시선과 수직인 방향
            Vector3 toCamera = (camPos - head).normalized;
            Vector3 side = Vector3.Cross(toCamera, m.direction).normalized;
            Matrix4x4 matrix = Matrix4x4.identity;
            matrix.SetColumn(0, -m.direction * Mathf.Max(length, 0.01f));
            matrix.SetColumn(1, side * width);
            matrix.SetColumn(2, toCamera);
            matrix.SetColumn(3, new Vector4(head.x, head.y, head.z, 1f));

            props[i].SetFloat(LifeId, life);
            props[i].SetFloat(BrightnessId, m.brightness * brightness);

            var rp = new RenderParams(meteorMaterial)
            {
                matProps = props[i],
                shadowCastingMode = ShadowCastingMode.Off,
                receiveShadows = false,
                worldBounds = new Bounds(head, Vector3.one * (m.length * 2f + 10f)),
            };
            Graphics.RenderMesh(rp, quad, 0, matrix);
        }
    }

    void Spawn(Camera cam)
    {
        int slot = -1;
        for (int i = 0; i < PoolSize; i++)
        {
            if (!meteors[i].active) { slot = i; break; }
        }
        if (slot < 0) return;

        // 카메라가 보는 쪽 하늘에서 시작한다.
        Vector3 forward = cam.transform.forward;
        forward.y = 0f;
        forward = forward.sqrMagnitude > 1e-4f ? forward.normalized : Vector3.forward;
        float yaw = Random.Range(-45f, 45f);
        float pitch = Random.Range(22f, 48f);
        Vector3 skyDir = Quaternion.AngleAxis(yaw, Vector3.up) * forward;
        Vector3 right = Vector3.Cross(Vector3.up, skyDir).normalized;
        skyDir = Quaternion.AngleAxis(-pitch, right) * skyDir;

        // 진행 방향: 아래로 비스듬히. 시선과 수직이 되게 해서 화면을 가로지르게 한다.
        Vector3 travel = (-Vector3.up * Random.Range(0.45f, 0.9f) + right * Random.Range(-1f, 1f)).normalized;
        travel = Vector3.ProjectOnPlane(travel, skyDir).normalized;

        meteors[slot] = new Meteor
        {
            active = true,
            startOffset = skyDir * domeRadius,
            direction = travel,
            speed = Random.Range(speed.x, speed.y),
            duration = Random.Range(duration.x, duration.y),
            length = Random.Range(tailLength.x, tailLength.y),
            brightness = Random.Range(0.6f, 1.3f),
            age = 0f,
        };
    }

    /// <summary>x: 0(머리)~1(꼬리 끝), y: -0.5~0.5(폭) 인 사각형.</summary>
    static Mesh BuildQuad()
    {
        var mesh = new Mesh { name = "MeteorQuad", hideFlags = HideFlags.HideAndDontSave };
        mesh.vertices = new[]
        {
            new Vector3(0f, -0.5f, 0f), new Vector3(1f, -0.5f, 0f),
            new Vector3(1f, 0.5f, 0f), new Vector3(0f, 0.5f, 0f),
        };
        mesh.uv = new[] { new Vector2(0f, 0f), new Vector2(1f, 0f), new Vector2(1f, 1f), new Vector2(0f, 1f) };
        mesh.triangles = new[] { 0, 2, 1, 0, 3, 2 };
        mesh.RecalculateBounds();
        return mesh;
    }
}
