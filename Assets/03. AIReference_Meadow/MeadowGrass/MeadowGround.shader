// [AI 생성 예시] 이 파일은 AI(Claude)가 작성한 목표 예시이며 과제 제출용 셰이더(Assets/02. MyShaders)가 아닙니다.
// 잔디 밑의 땅. 풀과 같은 색/바람/지형 함수를 써서, 풀이 듬성해지는 먼 곳에서도 들판이 이어져 보이게 한다.
// 먼 곳에서는 풀 포기 대신 이 면이 "돌풍 물결"을 지평선까지 보여 준다.
Shader "AIReference/MeadowGround"
{
    Properties
    {
        _BaseColor ("뿌리 색", Color) = (0.05, 0.22, 0.04, 1)
        _TipColor ("끝 색", Color) = (0.42, 0.72, 0.16, 1)
        _DryColor ("얼룩 색(마른 풀)", Color) = (0.62, 0.66, 0.22, 1)
        _DryAmount ("얼룩 양", Range(0, 1)) = 0.35
        _NearDark ("풀 밑 어둡기", Range(0, 1)) = 0.35
        _FarBlendStart ("먼 색 시작 거리", Float) = 10
        _FarBlendEnd ("먼 색 끝 거리", Float) = 45
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry-1" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "Forward"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "../Common/MeadowCommon.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor, _TipColor, _DryColor;
                float _DryAmount, _NearDark, _FarBlendStart, _FarBlendEnd;
            CBUFFER_END

            struct Attributes
            {
                float3 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float fogFactor : TEXCOORD1;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 posWS = TransformObjectToWorld(v.positionOS);
                posWS.y = MeadowHeight(posWS.xz);   // 풀과 같은 높이 함수 -> 풀이 뜨거나 묻히지 않는다
                o.positionWS = posWS;
                o.positionCS = TransformWorldToHClip(posWS);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float2 xz = i.positionWS.xz;
                float3 N = MeadowNormal(xz);
                float dist = distance(_WorldSpaceCameraPos, i.positionWS);
                float farMix = smoothstep(_FarBlendStart, _FarBlendEnd, dist);

                float tuft = MeadowPatch(xz);
                float gust = MeadowGust(xz);

                // 가까이: 풀에 가려진 어두운 흙빛 초록 / 멀리: 풀 전체를 평균한 색
                float3 nearCol = _BaseColor.rgb * _NearDark;
                float3 farCol = lerp(_BaseColor.rgb, _TipColor.rgb, 0.55);
                farCol = lerp(farCol, _DryColor.rgb * 0.8, smoothstep(0.45, 0.9, tuft) * _DryAmount);
                // 잔디 결처럼 보이는 잔무늬(멀수록 흐리게)
                float grain = MNoise2(xz * 3.1) * 0.5 + MNoise2(xz * 0.9 + 4.0) * 0.5;
                farCol *= lerp(0.85, 1.12, grain);
                float3 albedo = lerp(nearCol, farCol, farMix);

                Light mainLight = GetMainLight();
                float wrap = saturate(dot(N, mainLight.direction)) * 0.6 + 0.4;
                float3 ambient = lerp(_MeadowAmbientGround, _MeadowAmbientSky, N.y * 0.5 + 0.5);
                float3 col = albedo * (mainLight.color * wrap + ambient);
                col *= 1.0 + gust * 0.22 * farMix;    // 먼 들판 위를 지나가는 돌풍 물결

                col = MixFog(col, i.fogFactor);
                return half4(col, 1.0);
            }
            ENDHLSL
        }
    }
}
