// [AI 생성 예시] 이 파일은 AI(Claude)가 작성한 목표 예시이며 과제 제출용 셰이더(Assets/02. MyShaders)가 아닙니다.
// 들판 위를 떠다니는 꽃잎. 전환이 끝난 뒤에도 꽃잎 몇 장이 바람에 실려 지나가게 해서
// 화면 효과(PetalTransition)와 3D 씬을 이어 준다.
// 꽃잎의 위치는 버퍼 없이 "인스턴스 번호의 해시 + 바람 x 시간"으로 만들고,
// 카메라 둘레의 상자 안에서 frac 으로 되감아(wrap) 끝없이 흐르게 한다.
Shader "AIReference/DriftPetal"
{
    Properties
    {
        [HDR] _PetalTipColor ("꽃잎 끝 색", Color) = (1.6, 1.6, 1.7, 1)
        [HDR] _PetalBaseColor ("꽃잎 밑동 색", Color) = (1.5, 0.95, 1.2, 1)
        _Glow ("스스로 내는 빛", Range(0, 2)) = 0.55
        _Size ("크기(m)", Range(0.01, 0.3)) = 0.06
        _BoxSize ("흐르는 범위(m)", Vector) = (36, 9, 36, 0)
        _DriftSpeed ("흐르는 속도", Range(0, 8)) = 2.2
        _FallSpeed ("가라앉는 속도", Range(0, 2)) = 0.35
        _Tumble ("뒤집히는 속도", Range(0, 10)) = 3.0
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent+10" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "Forward"
            Tags { "LightMode" = "UniversalForward" }
            Blend One OneMinusSrcAlpha
            ZWrite Off
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
                half4 _PetalTipColor, _PetalBaseColor;
                float4 _BoxSize;
                float _Glow, _Size, _DriftSpeed, _FallSpeed, _Tumble;
            CBUFFER_END

            float _DriftPetalAmount;      // 0 ~ 1: 보이는 꽃잎의 비율 (MeadowDirector 가 넣는다)
            float3 _MeadowGridCenter;     // 상자 중심(카메라 위치)

            struct Attributes
            {
                float3 positionOS : POSITION;   // -1 ~ 1 사각형
                float2 uv : TEXCOORD0;
                uint instanceID : SV_InstanceID;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 light : TEXCOORD1;
                float alpha : TEXCOORD2;
                float fogFactor : TEXCOORD3;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                float fid = float(v.instanceID);
                float4 r = MHash42(float2(fid, fid * 0.37 + 2.0));
                float4 r2 = MHash42(float2(fid * 1.3 + 9.0, fid));

                float3 box = _BoxSize.xyz;
                float3 wind3 = float3(_MeadowWind.x, 0.0, _MeadowWind.y);
                float time = _MeadowTime;

                // 1) 고정된 출발점 + 바람에 실려 간 거리 + 가라앉음 + 살랑이는 흔들림
                float3 p = r.xyz * box;
                p += wind3 * (time * _DriftSpeed * (0.6 + 0.8 * r.w));
                p.y -= time * _FallSpeed * (0.5 + r2.x);
                p += float3(sin(time * 1.3 + r.x * 40.0), sin(time * 0.9 + r.y * 40.0) * 0.5, cos(time * 1.1 + r.z * 40.0)) * 0.35;

                // 2) 카메라 둘레 상자 안으로 되감기: 상자 밖으로 나간 꽃잎은 반대편에서 다시 나타난다.
                float3 rel = frac((p - _MeadowGridCenter) / box + 0.5) - 0.5;   // -0.5 ~ 0.5
                float3 centerWS = _MeadowGridCenter + rel * box;
                centerWS.y += box.y * 0.35;    // 상자를 조금 위로 올려 풀 위를 날게 한다

                // 3) 되감기는 경계에서는 투명하게 만들어 갑자기 나타나고 사라지는 것을 가린다.
                float3 edge = 1.0 - abs(rel) * 2.0;
                float edgeFade = saturate(min(edge.x, min(edge.y, edge.z)) * 6.0);

                // 4) 꽃잎마다 다른 축으로 빙글빙글 돈다. 두 축을 만들어 사각형을 편다.
                float a1 = time * _Tumble * (0.5 + r2.y) + r2.z * 6.2831;
                float a2 = time * _Tumble * 0.6 * (0.5 + r2.w) + r.w * 6.2831;
                float3 axisU = normalize(float3(cos(a1), sin(a1) * sin(a2), sin(a1) * cos(a2)));
                float3 other = normalize(float3(sin(a2), cos(a2), 0.3));
                float3 axisN = normalize(cross(axisU, other));
                float3 axisV = cross(axisN, axisU);

                // 5) 보이는 비율: 번호가 _DriftPetalAmount 보다 큰 꽃잎은 크기를 0 으로 만들어 지운다.
                float shown = step(r2.x, saturate(_DriftPetalAmount));
                float size = _Size * lerp(0.7, 1.4, r2.y) * shown;

                float3 posWS = centerWS + (axisU * v.positionOS.x + axisV * v.positionOS.y) * size;

                // 6) 빛: 양면이라 법선의 방향(앞/뒤)은 무시하고, 얇은 잎이라 뒤에서 온 빛도 비친다.
                Light mainLight = GetMainLight();
                float ndl = abs(dot(axisN, mainLight.direction)) * 0.6 + 0.4;
                o.light = mainLight.color * ndl + lerp(_MeadowAmbientGround, _MeadowAmbientSky, 0.7);

                o.positionCS = TransformWorldToHClip(posWS);
                o.uv = v.uv;
                o.alpha = edgeFade;
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float2 p = i.uv * 2.0 - 1.0;
                float d = PetalSDF(p * 1.08);
                float aa = max(fwidth(d), 0.002);
                float mask = smoothstep(aa, -aa, d);

                float3 albedo = lerp(_PetalBaseColor.rgb, _PetalTipColor.rgb, smoothstep(-0.9, 0.35, p.y));
                albedo *= 1.0 - 0.14 * exp(-abs(p.x) * 14.0) * saturate(0.8 - p.y);

                // 받은 빛 + 스스로 내는 빛(밤에도 하얗게 빛나도록)
                float3 col = albedo * (i.light * 0.5 + _Glow);
                col = MixFog(col, i.fogFactor);

                float a = mask * i.alpha;
                return half4(col * a, a);
            }
            ENDHLSL
        }
    }
}
