// [AI 생성 예시] 이 파일은 AI(Claude)가 작성한 목표 예시이며 과제 제출용 셰이더(Assets/02. MyShaders)가 아닙니다.
// 들판 씬의 모든 셰이더가 함께 쓰는 전역 값과 함수 모음.
// 전역 값은 MeadowDirector.cs 가 Shader.SetGlobal* 로 넣는다.
// (주의) 전역 값은 머티리얼 Properties 에 선언하면 안 된다. 선언하면 머티리얼 값이 우선되어
//        Shader.SetGlobalFloat 로 바꿔도 반영되지 않는다.
#ifndef MEADOW_COMMON_INCLUDED
#define MEADOW_COMMON_INCLUDED

float  _NightBlend;        // 0 = 낮, 1 = 밤
float  _MeadowTime;        // 초 단위 시간 (편집 모드에서도 흐르도록 직접 넣는다)
float4 _MeadowWind;        // xy = 바람 방향(월드 XZ, 정규화), z = 세기, w = 돌풍 이동 속도(m/s)
float3 _MeadowSunDir;      // 태양을 향하는 방향
float3 _MeadowMoonDir;     // 달을 향하는 방향
float  _MeadowHill;        // 언덕 높이 배율 (0 이면 평지)
float3 _MeadowAmbientSky;  // 위에서 오는 환경광
float3 _MeadowAmbientGround; // 아래에서 오는 환경광

// ---------------------------------------------------------------------------
// 해시: 좌표를 넣으면 0~1 사이의 "무작위처럼 보이는" 값을 돌려준다. (sin 을 쓰지 않는 방식)
// ---------------------------------------------------------------------------
float MHash21(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float2 MHash22(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

float4 MHash42(float2 p)
{
    float4 p4 = frac(float4(p.xyxy) * float4(0.1031, 0.1030, 0.0973, 0.1099));
    p4 += dot(p4, p4.wzxy + 33.33);
    return frac((p4.xxyz + p4.yzzw) * p4.zywx);
}

float MHash31(float3 p3)
{
    p3 = frac(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return frac((p3.x + p3.y) * p3.z);
}

float3 MHash33(float3 p3)
{
    p3 = frac(p3 * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return frac((p3.xxy + p3.yxx) * p3.zyx);
}

// ---------------------------------------------------------------------------
// 값 노이즈: 격자 꼭짓점의 해시 값을 부드럽게 보간한다.
// ---------------------------------------------------------------------------
float MNoise2(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = MHash21(i);
    float b = MHash21(i + float2(1, 0));
    float c = MHash21(i + float2(0, 1));
    float d = MHash21(i + float2(1, 1));
    return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}

float MNoise3(float3 p)
{
    float3 i = floor(p);
    float3 f = frac(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float n000 = MHash31(i);
    float n100 = MHash31(i + float3(1, 0, 0));
    float n010 = MHash31(i + float3(0, 1, 0));
    float n110 = MHash31(i + float3(1, 1, 0));
    float n001 = MHash31(i + float3(0, 0, 1));
    float n101 = MHash31(i + float3(1, 0, 1));
    float n011 = MHash31(i + float3(0, 1, 1));
    float n111 = MHash31(i + float3(1, 1, 1));
    return lerp(lerp(lerp(n000, n100, u.x), lerp(n010, n110, u.x), u.y),
                lerp(lerp(n001, n101, u.x), lerp(n011, n111, u.x), u.y), u.z);
}

// 여러 크기의 노이즈를 겹친 것(fBm). 구름, 은하수처럼 크고 작은 무늬가 섞인 모양을 만든다.
float MFbm2(float2 p)
{
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++)
    {
        sum += MNoise2(p) * amp;
        p = p * 2.03 + 17.3;
        amp *= 0.5;
    }
    return sum / 0.9375;
}

float MFbm3(float3 p)
{
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 3; i++)
    {
        sum += MNoise3(p) * amp;
        p = p * 2.07 + 11.1;
        amp *= 0.5;
    }
    return sum / 0.875;
}

// ---------------------------------------------------------------------------
// 지형: 사인 몇 개를 더한 완만한 언덕. C# 쪽(MeadowTerrain.Height)과 식이 같아야 한다.
// ---------------------------------------------------------------------------
float MeadowHeight(float2 xz)
{
    return _MeadowHill * (0.9 * sin(xz.x * 0.045 + 1.3) * sin(xz.y * 0.038 + 0.4)
                        + 0.35 * sin(xz.x * 0.11 + xz.y * 0.07 + 2.0));
}

float3 MeadowNormal(float2 xz)
{
    const float e = 0.5;
    float hx = MeadowHeight(xz + float2(e, 0)) - MeadowHeight(xz - float2(e, 0));
    float hz = MeadowHeight(xz + float2(0, e)) - MeadowHeight(xz - float2(0, e));
    return normalize(float3(-hx, 2.0 * e, -hz));
}

// ---------------------------------------------------------------------------
// 바람: 월드 좌표에서 바람 방향으로 흘러가는 노이즈. 값이 큰 곳이 "돌풍이 지나가는 띠"다.
// 월드 좌표를 쓰기 때문에 이웃한 풀은 비슷하게, 먼 풀은 다르게 흔들린다.
// ---------------------------------------------------------------------------
float MeadowGust(float2 xz)
{
    float2 p = xz - _MeadowWind.xy * (_MeadowTime * _MeadowWind.w);
    float g = MNoise2(p * 0.045) * 0.6 + MNoise2(p * 0.13 + 7.7) * 0.4;
    return smoothstep(0.25, 0.8, g);
}

// 들판의 넓은 색 얼룩(풀 무리마다 키와 색이 조금씩 다르게)
float MeadowPatch(float2 xz)
{
    return MNoise2(xz * 0.035 + 31.0) * 0.6 + MNoise2(xz * 0.11) * 0.4;
}

// ---------------------------------------------------------------------------
// 꽃잎 모양 SDF. p 는 꽃잎 로컬 좌표(-1~1), +y 가 꽃잎 끝. 음수면 꽃잎 안쪽.
// 밑동은 좁고 끝으로 갈수록 넓어지는 타원에, 끝의 작은 홈을 뺀 모양.
// ---------------------------------------------------------------------------
float PetalSDF(float2 p)
{
    float w = 0.22 + 0.5 * smoothstep(-1.0, 0.35, p.y);
    float d = (length(float2(p.x / w, p.y)) - 1.0) * w;
    float notch = 0.16 - length(p - float2(0.0, 1.04));
    return max(d, notch);
}

#endif
