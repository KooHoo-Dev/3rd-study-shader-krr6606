// [AI 생성 예시] 이 파일은 AI(Claude)가 작성한 목표 예시이며 과제 제출용 셰이더(Assets/02. MyShaders)가 아닙니다.
// 화면 전환: 꽃잎이 피어나 하얀 화면으로 변하고, 그 하얀 화면이 다시 꽃잎으로 변해 흩어진다.
// 꽃잎 한 장 = 사각형 하나. 사각형을 수백 장 인스턴싱하고, 정점 셰이더가 화면 좌표에서 직접 배치한다
// (카메라/월드 행렬을 쓰지 않으므로 항상 화면에 붙어 있다).
//   _PetalCover   0 -> 1 : 제자리에서 꽃잎이 피어나 커지고, 서로 겹치며 무늬를 잃고 하얀 빛으로 녹아든다
//   _PetalScatter 0 -> 1 : 하얀 화면이 바람 위쪽부터 꽃잎 모양으로 갈라지고, 꽃잎이 차례로 날아간다
// 두 값은 MeadowDirector.cs 가 전역 값으로 넣는다.
Shader "AIReference/PetalTransition"
{
    Properties
    {
        [HDR] _PetalTipColor ("꽃잎 끝 색", Color) = (2.2, 2.2, 2.3, 1)
        [HDR] _PetalBaseColor ("꽃잎 밑동 색", Color) = (2.0, 1.25, 1.55, 1)
        [HDR] _FillColor ("하얀 화면의 빛", Color) = (2.2, 2.15, 2.2, 1)
        _PetalSize ("꽃잎 크기", Range(0.3, 2.5)) = 1.15
        _MergeScale ("하얀 화면이 될 때 부푸는 배율", Range(1, 3)) = 1.8
        _MorphPortion ("흰빛 <-> 꽃잎 변형에 쓰는 구간", Range(0.1, 0.8)) = 0.35
        _Travel ("날아가는 거리(화면 높이 배)", Range(0.3, 4)) = 1.7
        _Spin ("회전량", Range(0, 20)) = 8
        _Stagger ("차례차례 정도", Range(0, 1)) = 0.55
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Overlay" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "Forward"
            Tags { "LightMode" = "UniversalForward" }
            Blend One OneMinusSrcAlpha   // 미리 곱한 알파(premultiplied)
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "../Common/MeadowCommon.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _PetalTipColor, _PetalBaseColor, _FillColor;
                float _PetalSize, _MergeScale, _MorphPortion, _Travel, _Spin, _Stagger;
            CBUFFER_END

            float _PetalCover;
            float _PetalScatter;
            float4 _PetalDir;     // xy = 화면에서 꽃잎이 날아가는 방향
            float _PetalCols;     // 한 겹의 가로 칸 수
            float _PetalRows;     // 한 겹의 세로 칸 수(위아래 여유 1칸씩 포함)

            struct Attributes
            {
                float3 positionOS : POSITION;   // -1 ~ 1 사각형
                float2 uv : TEXCOORD0;
                uint instanceID : SV_InstanceID;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;          // 꽃잎: 0~1 UV / 화면 채움: 화면 좌표(높이 1)
                float4 params : TEXCOORD1;      // x = 1 이면 화면 채움 사각형, y = 알파, z = 밝기, w = 흰빛으로 녹아든 정도
            };

            // 화면 위치 -> 순서 값(0 = 바람 위쪽 끝, 1 = 아래쪽 끝). 꽃잎과 화면 채움이 같은 순서로 변한다.
            float AlongWind(float2 screenPos, float2 wind, float aspect)
            {
                float halfSpan = 0.5 * (aspect * abs(wind.x) + abs(wind.y));
                return saturate(dot(screenPos, wind) / halfSpan * 0.5 + 0.5);
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                float aspect = _ScreenParams.x / _ScreenParams.y;

                // 0번 인스턴스는 화면 전체를 덮는 하얀 빛. 알파는 프래그먼트에서 위치별로 정한다.
                if (v.instanceID == 0)
                {
                    o.positionCS = float4(v.positionOS.xy, 0.5, 1.0);
                    o.uv = float2(v.positionOS.x * 0.5 * aspect, v.positionOS.y * 0.5);
                    o.params = float4(1.0, 1.0, 1.0, 1.0);
                    return o;
                }

                o.uv = v.uv;
                float cover = saturate(_PetalCover);
                float scatter = saturate(_PetalScatter);

                // 1) 인스턴스 번호 -> (겹, 칸)
                uint id = v.instanceID - 1;
                uint cols = (uint)_PetalCols;
                uint rows = (uint)_PetalRows;
                uint perLayer = cols * rows;
                uint layer = id / perLayer;
                uint index = id % perLayer;
                float2 cellId = float2(index % cols, index / cols);

                float4 r = MHash42(cellId + float(layer) * 37.0 + 3.1);
                float4 r2 = MHash42(cellId.yx + float(layer) * 71.0 + 11.7);

                // 2) 제자리(home). 화면 높이를 1 로 보는 좌표계(가로는 종횡비만큼 넓다)에서 격자 + 흔들기.
                //    겹마다 칸 크기와 위치를 조금씩 달리해 틈이 겹치지 않게 한다.
                float cell = (1.0 / (_PetalRows - 2.0)) * (1.0 + 0.1 * float(layer));
                float2 layerShift = (MHash22(float2(float(layer), 5.3)) - 0.5) * cell;
                float2 home = (cellId + 0.5 + (r.xy - 0.5) * 0.8 - float2(float(cols), float(rows)) * 0.5) * cell + layerShift;

                // 3) 꽃잎마다 자기 차례가 다르다: 바람 방향 위치(along) + 약간의 무작위.
                //    _Stagger 가 클수록 앞뒤 차이가 커져 "차례차례"가 뚜렷해진다.
                float2 wind = normalize(_PetalDir.xy + float2(1e-4, 0.0));
                float2 perp = float2(-wind.y, wind.x);
                float along = AlongWind(home, wind, aspect);
                float window = 1.0 - _Stagger * 0.8;                 // 한 장이 변하는 데 쓰는 진행 구간

                // 4) 덮는 단계: 제자리에서 피어난다(날아오지 않는다).
                //    c 가 커질수록 꽃잎이 부풀어 이웃과 겹치고, 후반에는 무늬를 잃고 하얀 빛이 된다.
                float startIn = (along * 0.75 + r.z * 0.25) * (1.0 - window);
                float c = saturate((cover - startIn) / window);
                float bloom = 1.0 - pow(1.0 - c, 2.0);
                float whiteIn = smoothstep(0.5, 1.0, c);

                // 5) 흩어지는 단계: 앞부분(_MorphPortion)은 하얀 빛 -> 꽃잎으로 되돌아오는 변형,
                //    나머지는 떨어져 날아가는 움직임.
                float startOut = (along * 0.7 + r.w * 0.3) * (1.0 - window);
                float s = saturate((scatter - startOut) / window);
                float morph = smoothstep(0.0, 1.0, saturate(s / _MorphPortion));
                float fly = saturate((s - _MorphPortion * 0.7) / (1.0 - _MorphPortion * 0.7));
                float fly2 = fly * fly;                              // 천천히 떨어져 점점 빨라진다

                float white = whiteIn * (1.0 - morph);

                // 6) 위치: 제자리에 있다가, 차례가 오면 바람 아래쪽으로 날아간다.
                float2 pos = home;
                pos += wind * fly2 * _Travel * (0.7 + 0.6 * r.w);
                pos += perp * sin(fly * 5.0 + r.x * 6.2831) * fly * 0.12;
                pos.y -= fly2 * 0.15;                                // 살짝 가라앉는다

                // 7) 회전과 뒤집힘. 피어날 때 살짝 돌고, 날아갈 때 빙글 돌며 뒤집힌다.
                float angle = r.x * 6.2831
                            + sin(_MeadowTime * 0.8 + r.y * 6.2831) * 0.08
                            + (1.0 - bloom) * _Spin * 0.25 * (r2.x - 0.5)
                            + fly * _Spin * (r2.y - 0.5);
                float flip = cos(r2.z * 6.2831 + fly * (6.0 + 8.0 * r2.w));
                float squash = lerp(1.0, max(abs(flip), 0.12), saturate(fly * 3.0));   // 한 축을 눌러 뒤집히는 것처럼 보이게

                // 8) 크기: 0 -> (부푼 크기) 로 피어났다가, 꽃잎으로 되돌아오며 제 크기가 되고, 날아가며 작아진다.
                float size = cell * lerp(0.8, 1.1, r.z) * _PetalSize;
                size *= lerp(_MergeScale * bloom, 1.0, morph) * (1.0 - 0.45 * fly);

                float alpha = saturate(c * 6.0) * (1.0 - smoothstep(0.75, 1.0, fly));
                size *= step(0.0001, alpha);

                // 9) 사각형 정점을 눌러 주고(뒤집힘), 돌리고, 화면에 놓는다.
                float2 local = v.positionOS.xy;
                local.x *= squash;
                float sn, cs;
                sincos(angle, sn, cs);
                local = float2(local.x * cs - local.y * sn, local.x * sn + local.y * cs);
                float2 p = pos + local * size;

                o.positionCS = float4(p.x / aspect * 2.0, p.y * 2.0, 0.5, 1.0);
                float shade = lerp(0.8, 1.15, r2.x) * lerp(0.72, 1.0, abs(flip));
                o.params = float4(0.0, alpha, shade, white);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // 화면 채움: 꽃잎들이 하얗게 녹아든 뒤의 틈을 메우는 빛.
                // 꽃잎과 같은 순서 값으로, 바람 위쪽부터 하얘지고 바람 위쪽부터 걷힌다.
                // 완전히 하얀 순간에 낮 -> 밤을 바꾸므로 교체가 눈에 보이지 않는다.
                if (i.params.x > 0.5)
                {
                    float aspect = _ScreenParams.x / _ScreenParams.y;
                    float2 wind = normalize(_PetalDir.xy + float2(1e-4, 0.0));
                    float along = AlongWind(i.uv, wind, aspect);
                    float window = 1.0 - _Stagger * 0.8;

                    float c = saturate((saturate(_PetalCover) - along * 0.75 * (1.0 - window)) / window);
                    float s = saturate((saturate(_PetalScatter) - along * 0.7 * (1.0 - window)) / window);
                    float fill = smoothstep(0.7, 1.0, c) * (1.0 - smoothstep(0.0, _MorphPortion * 0.6, s));
                    return half4(_FillColor.rgb * fill, fill);
                }

                float2 p = i.uv * 2.0 - 1.0;
                float d = PetalSDF(p * 1.08);
                float aa = max(fwidth(d), 0.002);
                float mask = smoothstep(aa, -aa, d);
                float white = i.params.w;

                // 꽃잎일 때: 밑동은 분홍, 끝은 흰색 + 가운데 잎맥 + 가장자리를 살짝 어둡게(겹쳤을 때 층이 보이도록)
                float3 col = lerp(_PetalBaseColor.rgb, _PetalTipColor.rgb, smoothstep(-0.9, 0.35, p.y));
                col *= 1.0 - 0.14 * exp(-abs(p.x) * 14.0) * saturate(0.8 - p.y);
                col *= lerp(0.78, 1.0, smoothstep(0.0, -0.3, d));
                col *= i.params.z;

                // 하얀 화면으로 변할 때: 무늬와 음영이 사라지고 화면 채움과 같은 빛이 되어 경계가 녹는다.
                col = lerp(col, _FillColor.rgb, white);

                float a = mask * i.params.y;
                return half4(col * a, a);
            }
            ENDHLSL
        }
    }
}
