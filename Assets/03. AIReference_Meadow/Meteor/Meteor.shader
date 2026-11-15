// [AI 생성 예시] 이 파일은 AI(Claude)가 작성한 목표 예시이며 과제 제출용 셰이더(Assets/02. MyShaders)가 아닙니다.
// 유성(별똥별). 길쭉한 사각형 하나에 "밝은 머리 + 가늘어지는 꼬리"를 그리고 가산 블렌딩으로 하늘에 더한다.
// 사각형의 위치/방향/길이는 MeteorShower.cs 가 행렬로 넣고, 셰이더는 UV 로 모양만 만든다.
// HDR 로 1 보다 밝게 내보내므로 Bloom 이 번짐을 만들어 준다.
Shader "AIReference/Meteor"
{
    Properties
    {
        [HDR] _HeadColor ("머리 색", Color) = (4.0, 4.5, 6.0, 1)
        [HDR] _TailColor ("꼬리 색", Color) = (0.6, 1.2, 3.0, 1)
        _TailFalloff ("꼬리 감쇠", Range(0.5, 8)) = 2.2
        _CoreSharpness ("심지 굵기(클수록 가늘다)", Range(2, 80)) = 22
        _HeadSize ("머리 크기", Range(0.005, 0.2)) = 0.035
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "Forward"
            Tags { "LightMode" = "UniversalForward" }
            Blend One One      // 가산: 빛은 더해질 뿐 뒤를 가리지 않는다
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "../Common/MeadowCommon.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _HeadColor, _TailColor;
                float _TailFalloff, _CoreSharpness, _HeadSize;
            CBUFFER_END

            float _MeteorLife;        // 0(생성) ~ 1(소멸). MaterialPropertyBlock 으로 유성마다 다르게 들어온다
            float _MeteorBrightness;

            struct Attributes
            {
                float3 positionOS : POSITION;
                float2 uv : TEXCOORD0;   // x: 0 = 머리, 1 = 꼬리 끝 / y: 0~1 = 폭
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS);
                o.uv = v.uv;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // 머리가 사각형 앞쪽 가장자리에서 잘리지 않도록 머리 중심을 조금 안쪽에 둔다.
                float u = i.uv.x - _HeadSize * 2.5;
                float w = (i.uv.y - 0.5) * 2.0;     // -1 ~ 1

                // 꼬리: 머리에서 멀어질수록 어두워지고(감쇠) 가늘어진다.
                float tu = saturate(u);
                float taper = lerp(1.0, 0.15, tu);
                float core = exp(-w * w * _CoreSharpness / (taper * taper));
                float tail = pow(1.0 - tu, _TailFalloff) * core * step(0.0, u);

                // 머리: 둥근 빛 덩어리
                float2 hp = float2(u / _HeadSize, w / 0.6);
                float head = exp(-dot(hp, hp));

                // 수명: 나타날 때 빠르게 밝아지고, 끝에서 타들어 가듯 사라진다.
                float life = saturate(_MeteorLife);
                float envelope = smoothstep(0.0, 0.12, life) * (1.0 - smoothstep(0.65, 1.0, life));

                // 사각형 가장자리에서 딱 잘리지 않도록 끝을 0 으로 내린다.
                float edge = smoothstep(1.0, 0.85, abs(w)) * smoothstep(1.0, 0.9, i.uv.x);

                float3 col = _TailColor.rgb * tail + _HeadColor.rgb * head;
                col *= envelope * edge * _MeteorBrightness * saturate(_NightBlend);
                return half4(col, 1.0);
            }
            ENDHLSL
        }
    }
}
