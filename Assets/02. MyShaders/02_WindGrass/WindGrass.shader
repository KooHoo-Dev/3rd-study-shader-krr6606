Shader "MyShaders/WindGrass"
{
    Properties
    {
        _RootColor("Root Color", Color) = (0.0, 0.5, 0.0, 1.0)
        _TipColor("Tip Color", Color) = (0.0, 1.0, 0.0, 1.0)

        _WindStrength("Wind Strength", Range(0.0, 1.0)) = 0.3
        _WindSpeed("Wind Speed", Range(0.0, 5.0)) = 1.5
        _WindScale("Wind Scale", Range(0.1, 2.0)) = 0.5
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry" "RenderPipeline" = "UniversalPipeline" }
        Cull Off // 양면이 보이도록 설정
        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };


            CBUFFER_START(UnityPerMaterial)
            float4 _RootColor;
            float4 _TipColor;

            float _WindStrength;
            float _WindSpeed;
            float _WindScale;
            CBUFFER_END
            // uv가 풀잎 모양 안쪽이면 양수, 바깥이면 음수
            float BladeMask(float2 uv)
            {
                // uv.y가 0~1일 때, uv.x가 0.5에서 멀어질수록 값이 작아지도록 계산
                float halfWidth = 0.5 * (1.0 - uv.y * uv.y);
                // uv.x가 0.5에서 멀어질수록 값이 작아지도록 계산
                return halfWidth - abs(uv.x - 0.5);
            }
            // 월드 위치를 넣으면 그 자리의 바람 세기(-1~1)가 나옴. 시간에 따라 물결처럼 변함
            float WindWave(float3 positionWS)
            {
                float phase = (positionWS.x + positionWS.z * 0.7) * _WindScale;
                float t = _Time.y * _WindSpeed;
                return sin(t + phase) * 0.7 + sin(t * 2.3 + phase * 1.9) * 0.3;
            }
            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                // 오브젝트 공간 위치를 월드 공간 위치로 변환
               float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
               // 휘는 줄: 뿌리(uv.y = 0)는 고정, 끝으로 갈수록 많이 움직임
                positionWS.x += WindWave(positionWS) * _WindStrength * IN.uv.y * IN.uv.y;
                // 월드 공간 위치를 클립 공간 위치로 변환
                OUT.positionHCS = TransformWorldToHClip(positionWS);    
                OUT.uv = IN.uv;

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
            // 한 픽셀에 대해 블레이드 마스크를 계산하고, 마스크에 따라 색상을 결정
            // clip() 함수를 사용하여 블레이드 마스크가 0보다 작은 경우 픽셀을 버림
            // 버리는 이유: 블레이드 마스크가 0보다 작은 경우 해당 픽셀은 풀잎 모양 밖에 위치하므로 렌더링하지 않도록 함
             clip(BladeMask(IN.uv));
             half4 color = lerp(_RootColor, _TipColor, IN.uv.y);
              return color;
            }
            ENDHLSL
        }
    }
}
