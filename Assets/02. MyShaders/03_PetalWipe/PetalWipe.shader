Shader "MyShaders/PetalWipe"
{
    Properties
    {
        _PetalColor("Petal Color", Color) = (1.0, 0.5, 0.5, 1.0)
        _Progress("Progress", Range(0, 1)) = 0.5
        [HideInInspector] _MainTex("Texture", 2D) = "white" {}
        _GridCount("Grid Count", Range(2, 30)) = 10
        _Stagger("Stagger", Range(0, 0.9)) = 0.6
    }

    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" }
        Blend SrcAlpha OneMinusSrcAlpha // 알파만큼 뒤 화면과 섞음
        ZWrite Off  //깊이를 기록하지 않음 (반투명의 기본 설정)
        ZTest Always //깊이와 무관하게 항상 그림 (UI는 맨 위)
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
            float4 _PetalColor;
            float _Progress;
            float _GridCount;
            float _Stagger;
            CBUFFER_END

            // 화면 uv를 넣으면 칸 안 좌표 cellUV(가운데가 0, 범위 -0.5~0.5)와 칸 번호 cellID가 나옴
            // 화면 비율을 보정해서 칸이 정사각형이 됨
            void GridCell(float2 uv, out float2 cellUV, out float2 cellID)
            {
                float aspect = _ScreenParams.x / _ScreenParams.y;
                float2 p = uv * float2(_GridCount * aspect, _GridCount);
                cellID = floor(p);
                cellUV = frac(p) - 0.5;
            }
            // 칸 안 좌표 p와 크기 size(0~1)를 넣으면 꽃잎 안쪽은 1, 바깥은 0
            // size가 0이면 안 보이고, 1이면 칸 전체를 덮음
            float PetalMask(float2 p, float size)
            {
                float r = size * 1.5;
                float dist = length(float2(abs(p.x) + r * 0.6, p.y));
                return 1.0 - smoothstep(r - 0.02, r, dist);
            }
            // 칸 번호와 전체 진행도를 넣으면 그 칸만의 진행도(0~1)가 나옴
            // 왼쪽 칸부터 먼저 시작하고, 칸마다 조금씩 무작위로 어긋남
            float CellProgress(float2 cellID, float progress)
            {
                float aspect = _ScreenParams.x / _ScreenParams.y;
                float order = cellID.x / (_GridCount * aspect);
                float rnd = frac(sin(dot(cellID, float2(12.9898, 78.233))) * 43758.5453);
                float delay = (order * 0.8 + rnd * 0.2) * _Stagger;
                return saturate((progress - delay) / (1.0 - _Stagger));
            }
            // 따로 건드리지 않은 기본 정점 셰이더. 월드 위치를 클립 위치로 변환하고, uv를 전달
            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);    
                OUT.uv = IN.uv;

                return OUT;
            }
            // 한 픽셀에대해, 칸 안 좌표와 칸 번호를 계산하고, 칸 번호에 따라 진행도를 구해서 꽃잎 마스크를 적용
            half4 frag(Varyings IN) : SV_Target
            {
                
            float2 cellUV; float2 cellID;
                // UV를 격자로 나누는 함수라고 이해
                GridCell(IN.uv, cellUV, cellID);
                
                half4 color;
                color.rgb = _PetalColor.rgb;
                // cellID와 _Progress를 넣으면 그 칸만의 진행도가 나옴. 0~1
                color.a = PetalMask(cellUV, CellProgress(cellID, _Progress));
        
                return color;
            }
            ENDHLSL
        }
    }
}
