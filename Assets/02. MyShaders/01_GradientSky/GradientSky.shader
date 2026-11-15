Shader "MyShaders/GradientSky"
{
    Properties
    {
        _ZenithColor("Zenith Color", Color) = (0.0, 0.5, 1.0, 1.0)
        _HorizonColor("Horizon Color", Color) = (1.0, 0.5, 0.0, 1.0)
        _HorizonFalloff("Horizon Falloff", Range(0.1, 4.0)) = 0.5

        _SunDirection("Sun Direction", Vector) = (0.3, 0.5, 0.6, 0)
        [HDR] _SunColor("Sun Color", Color) = 	(1, 0.95, 0.8, 1)
        _SunSize("Sun Size", Range(0.01, 0.3)) = 0.05
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Background" "PreviewType" = "Skybox" "RenderPipeline" = "UniversalPipeline" }
        Cull Off
        ZWrite Off
        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 DirectionObg : TEXCOORD0;
            };


            CBUFFER_START(UnityPerMaterial)
                half4 _ZenithColor;
                half4 _HorizonColor;    
                float _HorizonFalloff;

                float4 _SunDirection;
                half4 _SunColor;
                float _SunSize;
            CBUFFER_END
            // 방향 dir이 태양 원반 안이면 1, 밖이면 0, 가장자리는 부드럽게 0~1 아무튼 태양 원반을 계산하는 함수
            float SunDisk(float3 dir, float3 sunDir, float size)
            {
                float d = dot(dir, normalize(sunDir));
                return smoothstep(cos(size), cos(size * 0.9), d);
            }
            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.DirectionObg = IN.positionOS.xyz;

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                
                // saturate(x) (내부적으로 clamp(x, 0.0, 1.0)과 동일하지만, 하드웨어 최적화로 더 빠르게 동작하는 경우가 많습니다).
                float3 DirectionNormalized = normalize(IN.DirectionObg.xyz);
                float t = saturate(DirectionNormalized.y);
                // 태양 원반을 계산하여 색상에 추가
                float4 sun = SunDisk(DirectionNormalized, _SunDirection.xyz, _SunSize) * _SunColor;
                // 수평선에서의 색상 변화 정도를 조절
                t = pow(t, _HorizonFalloff);

                // 태양 색상을 포함한 하늘 색상 계산
                float4 color = lerp(_HorizonColor + sun, _ZenithColor,t);
                return color;
            }
            ENDHLSL
        }
    }
}
