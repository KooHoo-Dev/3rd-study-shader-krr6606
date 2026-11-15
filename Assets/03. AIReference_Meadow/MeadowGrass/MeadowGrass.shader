// [AI 생성 예시] 이 파일은 AI(Claude)가 작성한 목표 예시이며 과제 제출용 셰이더(Assets/02. MyShaders)가 아닙니다.
// 바람에 흔들리는 잔디. 풀 한 포기(블레이드) 메시를 GPU 인스턴싱으로 수십만 번 그린다.
// 포기마다의 위치/키/방향은 버퍼 없이 "인스턴스 번호 -> 격자 칸 -> 해시"로 정점 셰이더에서 만든다.
// 격자는 카메라를 따라다니므로 들판이 끝없이 이어진다. (MeadowGrassRenderer.cs 가 그린다)
Shader "AIReference/MeadowGrass"
{
    Properties
    {
        [Header(Color)]
        _BaseColor ("뿌리 색", Color) = (0.05, 0.22, 0.04, 1)
        _TipColor ("끝 색", Color) = (0.42, 0.72, 0.16, 1)
        _DryColor ("얼룩 색(마른 풀)", Color) = (0.62, 0.66, 0.22, 1)
        _DryAmount ("얼룩 양", Range(0, 1)) = 0.35
        [HDR] _SheenColor ("광택 색", Color) = (1.0, 1.0, 0.85, 1)
        _Sheen ("광택 세기", Range(0, 2)) = 0.45
        _Translucency ("역광 투과", Range(0, 3)) = 1.2

        [Header(Shape)]
        _BladeHeight ("풀 키(m)", Range(0.1, 2)) = 0.55
        _BladeWidth ("풀 폭(m)", Range(0.005, 0.2)) = 0.035
        _HeightVariation ("키 편차", Range(0, 1)) = 0.5
        _StaticLean ("기본 기울기", Range(0, 1)) = 0.28
        _FaceCamera ("카메라 쪽으로 돌리기", Range(0, 1)) = 0.6

        [Header(Wind)]
        _WindBend ("바람에 눕는 정도", Range(0, 2)) = 0.75
        _Flutter ("잔떨림", Range(0, 0.5)) = 0.1
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "Forward"
            Tags { "LightMode" = "UniversalForward" }
            Cull Off

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "../Common/MeadowCommon.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor, _TipColor, _DryColor, _SheenColor;
                float _DryAmount, _Sheen, _Translucency;
                float _BladeHeight, _BladeWidth, _HeightVariation, _StaticLean, _FaceCamera;
                float _WindBend, _Flutter;
            CBUFFER_END

            // 거리 단계(LOD)마다 MeadowGrassRenderer 가 MaterialPropertyBlock 으로 넣는 값
            float _CellSize;     // 격자 한 칸 크기(m). 칸마다 풀 한 포기
            float _GridDim;      // 격자 한 변의 칸 수
            float _FadeInner;    // 이 거리보다 가까우면 그리지 않는다(더 촘촘한 단계가 맡는다)
            float _FadeOuter;    // 이 거리보다 멀면 그리지 않는다
            float _FadeBand;     // 경계를 흐리는 폭
            float _WidthScale;   // 먼 단계일수록 포기 수가 줄어드는 만큼 폭을 넓힌다
            float _HeightScale;
            float3 _MeadowGridCenter; // 격자 중심(카메라 위치)

            struct Attributes
            {
                float3 positionOS : POSITION;   // x = -0.5~0.5(폭, 끝으로 갈수록 좁음), y = 0~1(높이)
                float2 uv : TEXCOORD0;          // y = 뿌리 0 ~ 끝 1
                uint instanceID : SV_InstanceID;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float4 data : TEXCOORD2;        // x = 높이 비율, y = 돌풍, z = 포기별 난수, w = 얼룩
                float3 groundNormal : TEXCOORD3;
                float fogFactor : TEXCOORD4;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;

                // 1) 인스턴스 번호 -> 격자 칸. 격자는 칸 크기 단위로 카메라를 따라간다(스냅).
                uint dim = (uint)_GridDim;
                uint ix = v.instanceID % dim;
                uint iz = v.instanceID / dim;
                float2 cell = floor(_MeadowGridCenter.xz / _CellSize) + float2(ix, iz) - float(dim) * 0.5;

                // 2) 칸 번호로 난수를 뽑는다. 같은 칸은 항상 같은 값이라 카메라가 움직여도 풀이 튀지 않는다.
                float4 rnd = MHash42(cell + _CellSize * 91.7);
                float2 rootXZ = (cell + rnd.xy) * _CellSize;

                // 3) 거리 단계 경계. 포기마다 경계 거리를 조금씩 다르게 해서 선이 보이지 않게 한다.
                float dist = distance(rootXZ, _MeadowGridCenter.xz);
                float jitter = (rnd.z - 0.5) * _FadeBand;
                float visible = step(_FadeInner + jitter, dist) * step(dist, _FadeOuter + jitter);

                float tuft = MeadowPatch(rootXZ);
                float gust = MeadowGust(rootXZ);
                float t = v.uv.y;

                float height = _BladeHeight * _HeightScale * lerp(1.0 - _HeightVariation, 1.0, rnd.w) * lerp(0.7, 1.15, tuft) * visible;
                float width = _BladeWidth * _WidthScale * lerp(0.75, 1.25, rnd.z) * visible;

                // 4) 풀의 폭 방향. 무작위 방향을 카메라와 수직인 방향 쪽으로 섞어, 옆으로 서서 실처럼 보이는 것을 줄인다.
                float phase = rnd.x * 6.2831;
                float2 face = float2(cos(phase * 1.7), sin(phase * 1.7));
                float2 toCam = normalize(_WorldSpaceCameraPos.xz - rootXZ + 1e-4);
                float2 perp = float2(-toCam.y, toCam.x);
                perp *= (dot(face, perp) < 0.0) ? -1.0 : 1.0;
                face = normalize(lerp(face, perp, _FaceCamera));

                // 5) 기울기 = 원래 삐딱한 정도 + 바람. 돌풍이 지나갈 때 더 눕고, 포기마다 위상이 다른 잔떨림을 더한다.
                float2 windDir = _MeadowWind.xy;
                float flutter = sin(_MeadowTime * (2.5 + rnd.y * 2.0) + phase) * _Flutter * (0.4 + gust);
                float2 lean = float2(cos(phase), sin(phase)) * _StaticLean * rnd.w
                            + windDir * (_WindBend * _MeadowWind.z * (0.25 + 0.75 * gust) + flutter)
                            + float2(-windDir.y, windDir.x) * flutter * 0.5;
                float leanLen = min(length(lean), 1.2);
                lean = normalize(lean + 1e-5) * leanLen;

                // 6) 휘어짐은 높이의 제곱에 비례 -> 뿌리(t=0)는 절대 움직이지 않는다.
                //    많이 누울수록 y 를 줄여 풀 길이가 늘어나 보이지 않게 한다.
                float curve = t * t;
                float3 rootWS = float3(rootXZ.x, MeadowHeight(rootXZ), rootXZ.y);
                float3 posWS;
                posWS.xz = rootWS.xz + face * (v.positionOS.x * width) + lean * (curve * height);
                posWS.y = rootWS.y + height * (t - 0.4 * leanLen * leanLen * curve);

                // 7) 법선: 휘어진 풀의 접선과 폭 방향의 외적. 좌우로 살짝 벌려 둥근 잎처럼 보이게 한다.
                float3 tangent = normalize(float3(lean.x * 2.0 * t, 1.0 - 0.8 * leanLen * leanLen * t, lean.y * 2.0 * t));
                float3 faceDir = float3(face.x, 0.0, face.y);
                float3 n = normalize(cross(tangent, faceDir)) + faceDir * (v.positionOS.x * 1.2);

                o.positionWS = posWS;
                o.positionCS = TransformWorldToHClip(posWS);
                o.normalWS = n;
                o.groundNormal = MeadowNormal(rootXZ);
                o.data = float4(t, gust, rnd.y, tuft);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float t = i.data.x;
                float gust = i.data.y;
                float rnd = i.data.z;
                float tuft = i.data.w;

                float3 V = normalize(_WorldSpaceCameraPos - i.positionWS);
                float3 N = normalize(i.normalWS);
                N *= (dot(N, V) < 0.0) ? -1.0 : 1.0;                   // 양면: 항상 보는 쪽을 향하게
                N = normalize(lerp(N, normalize(i.groundNormal), 0.55)); // 땅 법선과 섞어 들판 전체가 부드럽게 밝아지게

                Light mainLight = GetMainLight();
                float3 L = mainLight.direction;

                // 색: 뿌리~끝 그라디언트 + 넓은 얼룩 + 포기별 밝기 차이
                float3 albedo = lerp(_BaseColor.rgb, _TipColor.rgb, pow(t, 1.4));
                albedo = lerp(albedo, _DryColor.rgb * lerp(0.45, 1.0, t), smoothstep(0.45, 0.9, tuft) * _DryAmount);
                albedo *= lerp(0.88, 1.12, rnd);

                float ao = lerp(0.3, 1.0, t);                           // 뿌리 쪽은 서로 가려 어둡다
                float wrap = saturate(dot(N, L)) * 0.6 + 0.4;           // 부드러운 확산광
                float3 ambient = lerp(_MeadowAmbientGround, _MeadowAmbientSky, N.y * 0.5 + 0.5);

                // 역광 투과: 빛을 마주 볼 때 얇은 잎 끝이 환하게 비친다.
                float trans = pow(saturate(dot(V, -L)), 4.0) * t * _Translucency;

                // 광택: 돌풍으로 누운 풀이 하늘빛을 반사해 밝은 물결이 지나가는 것처럼 보인다.
                float3 H = normalize(L + V);
                float spec = pow(saturate(dot(N, H)), 24.0) * t * t * _Sheen * (0.4 + gust);

                float3 col = albedo * (mainLight.color * wrap + ambient) * ao;
                col += albedo * mainLight.color * trans;
                col += _SheenColor.rgb * mainLight.color * spec;
                col *= 1.0 + gust * 0.18 * t;

                col = MixFog(col, i.fogFactor);
                return half4(col, 1.0);
            }
            ENDHLSL
        }
    }
}
