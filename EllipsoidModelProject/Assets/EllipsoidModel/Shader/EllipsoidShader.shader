Shader "EllipsoidShader"
{
    Properties
    {
        _Ambient("Ambient Light in the Scene", Color) = (0,0,0,0)
        _CameraDirection ("Camera Direction From Object", Vector) = (0,1,0,0)
        _Diffuse ("Diffuse Texture", 2D) = "white" {}
        _Gloss ("Gloss Texture", 2D) = "white" {}
        _SDiagonals ("SDiagonals Texture", 2D) = "white" {}
        _SOffDiagonals ("SOffDiagonals Texture", 2D) = "white" {}
        _Bias ("Fresnel Bias", Float) = 1
        _Scale ("Fresnel Scale", Float) = 0
        _Power ("Fresnel Power", Float) = 0
        
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"
            #include "AutoLight.cginc"

            float compute_vSv(float Sxx, float Syy, float Szz, float Sxy, float Syz, float Szx, float3 v);
            float compute_vS_zcomponent(float Szx, float Syz, float Szz, float3 v);

            // Input to Vertex Shader
            struct VertexInput
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv0 : TEXCOORD0;
                // float4 colors : COLOR;
                // float4 tangent : TANGENT;
                // float2 uv1 : TEXCOORD1;
            };

            // Input to Frag Shader
            struct VertexOutput
            {
                float4 vertex : SV_POSITION;
                float3 normalWorldPos : NORMAL0;
                float3 normal : NORMAL1;
                float2 uv0 : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float R : TEXCOORD2;
            };

            // Connect Properties to Shader Language
            float4 _Ambient;
            float4 _CameraDirection;

            sampler2D _Diffuse;
            sampler2D  _Gloss; 
            sampler2D  _SDiagonals; 
            sampler2D  _SOffDiagonals;

            float _Bias;
            float _Scale;
            float _Power;

            // Helper Functions
            /** Compute the product (v^T)*S*v for the vector v and return the result */
            float compute_vSv(float Sxx, float Syy, float Szz, float Sxy, float Syz, float Szx, float3 v) 
            {
                return float(Sxx*v.x*v.x + Syy*v.y*v.y + Szz*v.z*v.z + 2*(Sxy*v.x*v.y + Syz*v.y*v.z + Szx*v.z*v.x)); 
            }

            float compute_vS_zcomponent(float Szx, float Syz, float Szz, float3 v) 
            {
                return float(v.x*Szx + v.y*Syz + v.z*Szz); 
            } 

            // Vertex Shader
            VertexOutput vert (VertexInput v)
            {
                VertexOutput o;

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.normalWorldPos = normalize(mul((float3x3)unity_ObjectToWorld, v.normal));
                o.normal = v.normal;
                o.uv0 = v.uv0;
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                //o.uv = TRANSFORM_TEX(v.uv, _MainTex); //Transforms texture using the tiling

                // Empirical Approximation of Fresnal Term
                float3 I = normalize(o.worldPos - _CameraDirection.xyz);
                o.R = float2(_Bias + _Scale * pow(1.0 + dot(I, o.normalWorldPos), _Power), 1);

                return o;
            }

            // Fragment Shader
            fixed4 frag (VertexOutput o) : SV_Target
            {
                float2 uv = o.uv0;
                float3 normal = normalize(o.normal); //Normalize interpolated normals

                //View Directions
                // To use an actual Camera Perspective, uncomment this code block and comment the next line
                //float3 camPos = _WorldSpaceCameraPos;
                //float3 frag2cam = camPos - o.worldPos;
                //float3 viewDir = normalize(frag2cam); //From frag2cam normalized
                
                // Using an Orthographic Camera with vector given in property
                float3 viewDir = normalize(_CameraDirection.xyz);

                // Ambient Light
                float3 ambientLight = _Ambient.rgb;

                // Lighting (Using only 1 light)
                float3 lightDir = normalize(_WorldSpaceLightPos0.xyz); // Light Direction, from frag2light, normalized
                float3 lightColor = _LightColor0.rgb; // Light Color

                // Direct Diffuse Light (Simple Lambertian)
                float3 lightFallOff = max(0, dot(lightDir, normal)); // The falloff of light
                float3 directDiffuseLight = lightFallOff * lightColor; //Calculate Diffuse effect from Light
                float3 diffuseLight = directDiffuseLight + ambientLight; //Add in the Ambient Light 
                float3 diffuseMaterial = tex2D(_Diffuse, uv); //Get Diffuse Material Color
                float3 finalDiffuse = diffuseLight * diffuseMaterial; //Final Lambertian Shading Component
                
                // Convert Light and View Direction into Object Space
                float3 oLightDir = normalize(mul(unity_WorldToObject, lightDir)); //in object space and not WorldSpace
                float3 oViewDir = normalize(mul(unity_WorldToObject, viewDir)); //in object space and not WorldSpace
                
                // Cause Unity Coordinate System is different from the Ellipsoid Code Coordinate System
                oLightDir = oLightDir.xzy;
                oViewDir = oViewDir.xzy;

                // Get Material Colors from Maps
                float3 glossyMat = tex2D(_Gloss, uv);
                float3 SDiagonalsMat = tex2D(_SDiagonals, uv);
                float3 SOffDiagonalsMat = tex2D(_SOffDiagonals, uv);
                
                // Construct S Matrix Values
                float Sxx = SDiagonalsMat.r;
                float Syy = SDiagonalsMat.g;
                float Szz = SDiagonalsMat.b;
                float Sxy = SOffDiagonalsMat.r;
                float Syz = SOffDiagonalsMat.g;
                float Szx = SOffDiagonalsMat.b;

                // Calculate InvS Matrix Values
                float det = Sxx*(Szz*Syy - Syz*Syz) + Sxy*(Syz*Szx - Szz*Sxy) + Szx*(Syz*Sxy - Syy*Szx);
                float invDet = 1.0/det;
                float invSxx = invDet*(Szz*Syy - Syz*Syz); 
                float invSyy = invDet*(Szz*Sxx - Szx*Szx); 
                float invSzz = invDet*(Syy*Sxx - Sxy*Sxy); 
                float invSxy = invDet*(Syz*Szx - Szz*Sxy);
                float invSyz = invDet*(Sxy*Szx - Syz*Sxx); 
                float invSzx = invDet*(Syz*Sxy - Syy*Szx);

                //BRDF
                float cosViewNormal = oViewDir.z;   
                float cosLightNormal = oLightDir.z; 
                float val = 1 / (4*abs(cosViewNormal)*abs(cosLightNormal)); 

                //Compute D 
                float3 hv;
                hv.x = oViewDir.x + oLightDir.x; 
                hv.y = oViewDir.y + oLightDir.y; 
                hv.z = oViewDir.z + oLightDir.z; 
                float lenH2 = hv.x*hv.x + hv.y*hv.y + hv.z*hv.z;
                float hSh = compute_vSv(Sxx, Syy, Szz, Sxy, Syz, Szx, hv); 
                float D = (lenH2*lenH2) / (hSh*hSh); 

                //Add Ellipsoid NDF
                val *= D;

                // Compute G()
                float nAAn = invSzz;  
                float vAAv = compute_vSv(invSxx, invSyy, invSzz, invSxy, invSyz, invSzx, oViewDir); 
                float lAAl = compute_vSv(invSxx, invSyy, invSzz, invSxy, invSyz, invSzx, oLightDir); 
                float vAAn = compute_vS_zcomponent(invSzx, invSyz, invSzz, oViewDir); 
                float lAAn = compute_vS_zcomponent(invSzx, invSyz, invSzz, oLightDir); 
                float Gv = 2*nAAn*abs(oViewDir.z) / (sqrt(vAAv*nAAn) + vAAn); 
                float Gl = 2*nAAn*abs(oLightDir.z) / (sqrt(lAAl*nAAn) + lAAn); 
                Gv = min(1.0, abs(Gv));
                Gl = min(1.0, abs(Gl));
                float G = Gv * Gl;

                //Add Shadow Masking Term
                val *= G;

                // Apply Fresnal Factor
                float F = o.R.x;
                val *= F;

                // Ellipsoid final Scale
                float3 finalSpecular = val * glossyMat;

                // Composite
                float3 finalSurfaceColor = finalDiffuse + finalSpecular;

                return float4(finalSurfaceColor, 1);
            }
            ENDCG
        }
    }
}
