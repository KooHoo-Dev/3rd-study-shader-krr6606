// [AI 생성 예시] 이 파일은 AI(Claude)가 작성한 목표 예시이며 과제 제출용 셰이더(Assets/02. MyShaders)가 아닙니다.
// 낮과 밤을 한 셰이더로 그리는 절차적 스카이박스.
// - 낮: 천정~지평선 그라디언트, 태양 원반과 헤일로, 옅은 구름
// - 밤: 별(반짝임), 은하수, 달
// 텍스처를 쓰지 않고 "바라보는 방향"만으로 전부 계산한다. 전역 값 _NightBlend 로 낮/밤을 섞는다.
Shader "AIReference/MeadowSky"
{
    Properties
    {
        [Header(Day)]
        [HDR] _DayZenith ("낮 천정 색", Color) = (0.10, 0.32, 0.85, 1)
        [HDR] _DayHorizon ("낮 지평선 색", Color) = (0.62, 0.80, 0.97, 1)
        [HDR] _SunColor ("태양 색", Color) = (1.0, 0.93, 0.78, 1)
        _SunSize ("태양 크기(라디안)", Range(0.005, 0.1)) = 0.032
        _SunHalo ("태양 헤일로 세기", Range(0, 3)) = 1.0

        [Header(Night)]
        [HDR] _NightZenith ("밤 천정 색", Color) = (0.008, 0.014, 0.045, 1)
        [HDR] _NightHorizon ("밤 지평선 색", Color) = (0.035, 0.065, 0.14, 1)
        [HDR] _MoonColor ("달 색", Color) = (0.85, 0.92, 1.0, 1)
        _MoonSize ("달 크기(라디안)", Range(0.005, 0.1)) = 0.028
        _StarDensity ("별 밀도", Range(0, 1)) = 0.5
        _StarBrightness ("별 밝기", Range(0, 8)) = 3.0
        _TwinkleSpeed ("별 반짝임 속도", Range(0, 8)) = 2.5
        [HDR] _MilkyColor ("은하수 색", Color) = (0.30, 0.34, 0.55, 1)
        _MilkyWay ("은하수 세기", Range(0, 2)) = 0.7

        [Header(Shared)]
        _HorizonFalloff ("지평선 그라디언트 굽기", Range(1, 12)) = 4.5
        _CloudAmount ("구름 양", Range(0, 1)) = 0.32
        _CloudScale ("구름 크기", Range(0.2, 4)) = 1.1
        _CloudSpeed ("구름 속도", Range(0, 0.2)) = 0.012
    }

    SubShader
    {
        Tags { "Queue" = "Background" "RenderType" = "Background" "PreviewType" = "Skybox" "RenderPipeline" = "UniversalPipeline" }
        Cull Off
        ZWrite Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "../Common/MeadowCommon.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _DayZenith, _DayHorizon, _SunColor;
                half4 _NightZenith, _NightHorizon, _MoonColor, _MilkyColor;
                float _SunSize, _SunHalo, _MoonSize;
                float _StarDensity, _StarBrightness, _TwinkleSpeed, _MilkyWay;
                float _HorizonFalloff, _CloudAmount, _CloudScale, _CloudSpeed;
            CBUFFER_END

            struct Attributes
            {
                float3 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 dir : TEXCOORD0;   // 스카이박스 큐브의 정점 위치 = 바라보는 방향
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS);
                o.dir = v.positionOS;
                return o;
            }

            // 별 한 겹. 방향을 3D 격자로 나누고, 칸마다 무작위 위치에 별을 하나 둔다.
            // 구면 UV 를 쓰지 않으므로 천정에서 별이 늘어나거나 몰리지 않는다.
            float3 StarLayer(float3 d, float scale, float seed, float densityBoost)
            {
                float3 p = d * scale;
                float3 id = floor(p);
                float3 f = frac(p) - 0.5;
                float3 rnd = MHash33(id + seed);

                // 칸 가장자리에서 잘리지 않도록 별 중심을 칸 안쪽에만 둔다.
                float3 center = (rnd - 0.5) * 0.6;
                float dist = length(f - center);

                // 밀도: 일부 칸에만 별이 있다.
                float present = step(1.0 - saturate(_StarDensity * densityBoost), MHash31(id + seed * 1.7 + 5.0));

                // 대부분은 작고, 가끔 큰 별이 나오도록 4제곱
                float size = lerp(0.035, 0.11, pow(rnd.x, 4.0));
                float core = smoothstep(size, 0.0, dist);
                float glow = (size * size) / (dist * dist + 0.0008) * 0.04 * smoothstep(0.45, 0.15, dist);

                float twinkle = 0.65 + 0.35 * sin(_MeadowTime * _TwinkleSpeed * (0.5 + rnd.y) + rnd.z * 6.2831);

                // 푸른 별 ~ 주황 별
                float3 tint = lerp(float3(0.70, 0.82, 1.0), float3(1.0, 0.86, 0.70), rnd.y);
                return tint * (core + glow) * present * twinkle;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 d = normalize(i.dir);
                float night = saturate(_NightBlend);

                // 1) 바탕 그라디언트. 지평선 아래는 지평선 색으로 채운다(안개 색과 같아서 땅 끝이 녹아든다).
                float up = saturate(d.y);
                float grad = pow(1.0 - up, _HorizonFalloff);
                float3 dayCol = lerp(_DayZenith.rgb, _DayHorizon.rgb, grad);
                float3 nightCol = lerp(_NightZenith.rgb, _NightHorizon.rgb, grad);
                float3 col = lerp(dayCol, nightCol, night);
                float above = smoothstep(-0.02, 0.06, d.y);

                // 2) 밤: 은하수 띠
                float3 bandAxis = normalize(float3(0.45, 0.35, -0.82));
                float bandDist = dot(d, bandAxis);
                float band = exp(-bandDist * bandDist * 18.0);
                float lanes = MFbm3(d * 5.0);
                col += _MilkyColor.rgb * band * smoothstep(0.25, 0.9, lanes) * _MilkyWay * night * above;

                // 3) 밤: 별 두 겹(크고 드문 별 + 작고 많은 별). 은하수 안에서는 더 빽빽하게.
                float boost = 1.0 + band * 1.5;
                float3 stars = StarLayer(d, 45.0, 0.0, boost * 0.6) * 1.4 + StarLayer(d, 95.0, 13.0, boost);
                stars *= smoothstep(0.0, 0.3, d.y);   // 지평선 근처는 대기에 가려 흐리게

                // 4) 달
                float3 moonDir = normalize(_MeadowMoonDir + float3(0, 1e-4, 0));
                float md = dot(d, moonDir);
                float moonDisk = smoothstep(cos(_MoonSize * 1.08), cos(_MoonSize), md);
                float moonHalo = pow(saturate(md), 600.0) * 0.8 + pow(saturate(md), 40.0) * 0.12;
                float moonShade = lerp(0.72, 1.0, MFbm3(d * 70.0));

                col += stars * _StarBrightness * night * (1.0 - moonDisk);
                col += _MoonColor.rgb * moonHalo * night * above;
                col = lerp(col, _MoonColor.rgb * moonShade * 2.2, moonDisk * night * above);

                // 5) 낮: 태양 원반 + 헤일로(좁은 것, 넓은 것을 겹쳐 대기 산란 느낌)
                float3 sunDir = normalize(_MeadowSunDir + float3(0, 1e-4, 0));
                float sd = dot(d, sunDir);
                float sunDisk = smoothstep(cos(_SunSize * 1.15), cos(_SunSize), sd);
                float sunHalo = pow(saturate(sd), 400.0) * 1.5 + pow(saturate(sd), 40.0) * 0.35 + pow(saturate(sd), 6.0) * 0.12;
                col += _SunColor.rgb * (sunDisk * 8.0 + sunHalo * _SunHalo) * (1.0 - night) * above;

                // 6) 구름: 하늘을 평면에 투영한 좌표로 fBm 을 읽는다. 별과 달 위를 덮는다.
                float2 cuv = d.xz / (d.y + 0.18) * _CloudScale + _MeadowWind.xy * (_MeadowTime * _CloudSpeed);
                float cn = MFbm2(cuv);
                float cloud = smoothstep(1.0 - _CloudAmount, 1.0 - _CloudAmount + 0.35, cn) * smoothstep(0.02, 0.3, d.y);
                float3 cloudDay = lerp(float3(1.0, 1.0, 1.0), _SunColor.rgb * 1.3, pow(saturate(sd), 8.0));
                float3 cloudNight = _NightHorizon.rgb * 1.4 + _MoonColor.rgb * pow(saturate(md), 12.0) * 0.25;
                col = lerp(col, lerp(cloudDay, cloudNight, night), cloud * 0.75);

                // 7) 그라디언트 줄무늬(밴딩)를 막는 아주 약한 디더
                col += (MHash21(i.positionCS.xy) - 0.5) / 255.0;

                return half4(max(col, 0.0), 1.0);
            }
            ENDHLSL
        }
    }
}
