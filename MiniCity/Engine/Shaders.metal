//
//  Shaders.metal
//  MiniCity
//
//  Advanced Metal shaders for city rendering with PBR, instancing, and tessellation

#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

// MARK: - Constants and Structures

struct FrameUniforms {
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float4x4 viewProjectionMatrix;
    float4x4 lightViewProjectionMatrix;
    float3 cameraPosition;
    float time;
    float3 sunDirection;
    float3 sunColor;
    float sunIntensity;
};

struct InstanceData {
    float4x4 modelMatrix;
    float3x3 normalMatrix;
    float4 color;
    float metallic;
    float roughness;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texcoord [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float2 texcoord;
    float4 shadowCoord;
    float3 viewDirection;
};

// MARK: - Terrain Shaders

vertex VertexOut terrainVertex(VertexIn in [[stage_in]],
                               constant FrameUniforms& uniforms [[buffer(1)]],
                               texture2d<float> heightMap [[texture(0)]]) {
    VertexOut out;
    
    // Sample height from texture
    constexpr sampler heightSampler(coord::normalized, filter::linear);
    float height = heightMap.sample(heightSampler, in.texcoord).r * 10.0;
    
    float3 position = in.position + float3(0, height, 0);
    float4 worldPos = float4(position, 1.0);
    
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.worldPosition = worldPos.xyz;
    
    // Calculate normal from height map
    float2 texelSize = 1.0 / float2(heightMap.get_width(), heightMap.get_height());
    float heightL = heightMap.sample(heightSampler, in.texcoord - float2(texelSize.x, 0)).r * 10.0;
    float heightR = heightMap.sample(heightSampler, in.texcoord + float2(texelSize.x, 0)).r * 10.0;
    float heightT = heightMap.sample(heightSampler, in.texcoord - float2(0, texelSize.y)).r * 10.0;
    float heightB = heightMap.sample(heightSampler, in.texcoord + float2(0, texelSize.y)).r * 10.0;
    
    float3 normal = normalize(float3(heightL - heightR, 2.0, heightT - heightB));
    out.worldNormal = normal;
    
    out.texcoord = in.texcoord;
    out.shadowCoord = uniforms.lightViewProjectionMatrix * worldPos;
    out.viewDirection = normalize(uniforms.cameraPosition - worldPos.xyz);
    
    return out;
}

fragment float4 terrainFragment(VertexOut in [[stage_in]],
                               constant FrameUniforms& uniforms [[buffer(1)]],
                               texture2d<float> grassTexture [[texture(0)]],
                               texture2d<float> rockTexture [[texture(1)]],
                               depth2d<float> shadowMap [[texture(2)]]) {
    constexpr sampler texSampler(coord::normalized, filter::linear, address::repeat);
    constexpr sampler shadowSampler(coord::normalized, filter::linear, compare_func::less_equal);
    
    // Multi-texture blending based on slope
    float slope = dot(in.worldNormal, float3(0, 1, 0));
    float grassWeight = smoothstep(0.5, 0.8, slope);
    
    // Use default colors when textures aren't bound
    float3 grassColor = float3(0.2, 0.6, 0.2); // Green grass
    float3 rockColor = float3(0.5, 0.45, 0.4); // Grey rock
    float3 baseColor = mix(rockColor, grassColor, grassWeight);
    
    // Calculate lighting (PBR)
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(-uniforms.sunDirection);
    float3 V = normalize(in.viewDirection);
    float3 H = normalize(L + V);
    
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);
    float NdotH = max(dot(N, H), 0.0);
    float VdotH = max(dot(V, H), 0.0);
    
    // Diffuse
    float3 diffuse = baseColor * NdotL;
    
    // Specular (simplified)
    float roughness = 0.8;
    float specular = pow(NdotH, (2.0 / (roughness * roughness + 0.0001) - 2.0));
    
    // Shadow calculation (simplified for now)
    float shadow = 1.0;
    // TODO: Implement proper shadow mapping
    
    // Combine lighting
    float3 color = uniforms.sunColor * uniforms.sunIntensity * shadow * (diffuse + specular * 0.1);
    
    // Add ambient
    color += baseColor * 0.2;
    
    // Fog
    float distance = length(uniforms.cameraPosition - in.worldPosition);
    float fogFactor = exp(-distance * 0.002);
    color = mix(float3(0.7, 0.8, 0.9), color, fogFactor);
    
    return float4(color, 1.0);
}

// MARK: - Building Shaders

// Non-instanced building vertex shader
vertex VertexOut buildingVertex(VertexIn in [[stage_in]],
                                constant FrameUniforms& uniforms [[buffer(1)]],
                                constant InstanceData& instanceData [[buffer(2)]]) {
    VertexOut out;
    
    float4 worldPos = instanceData.modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.worldPosition = worldPos.xyz;
    out.worldNormal = instanceData.normalMatrix * in.normal;
    out.texcoord = in.texcoord;
    out.shadowCoord = uniforms.lightViewProjectionMatrix * worldPos;
    out.viewDirection = normalize(uniforms.cameraPosition - worldPos.xyz);
    
    return out;
}

// Instanced building vertex shader
vertex VertexOut buildingVertexInstanced(VertexIn in [[stage_in]],
                                         constant FrameUniforms& uniforms [[buffer(1)]],
                                         constant InstanceData* instances [[buffer(2)]],
                                         uint instanceID [[instance_id]]) {
    VertexOut out;
    
    InstanceData instance = instances[instanceID];
    
    float4 worldPos = instance.modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.worldPosition = worldPos.xyz;
    out.worldNormal = instance.normalMatrix * in.normal;
    out.texcoord = in.texcoord;
    out.shadowCoord = uniforms.lightViewProjectionMatrix * worldPos;
    out.viewDirection = normalize(uniforms.cameraPosition - worldPos.xyz);
    
    return out;
}

fragment float4 buildingFragmentPBR(VertexOut in [[stage_in]],
                                    constant FrameUniforms& uniforms [[buffer(1)]],
                                    constant InstanceData& instanceData [[buffer(2)]],
                                    texture2d<float> buildingAtlas [[texture(0)]],
                                    texture2d<float> normalMap [[texture(1)]],
                                    depth2d<float> shadowMap [[texture(2)]]) {
    constexpr sampler texSampler(coord::normalized, filter::linear);
    constexpr sampler shadowSampler(coord::normalized, filter::linear, compare_func::less_equal);
    
    // Use instance color if no texture is bound
    float4 albedo = instanceData.color;
    float3 normal = in.worldNormal;
    
    // Transform normal to world space
    float3 N = normalize(in.worldNormal);
    float3 T = normalize(cross(N, float3(0, 0, 1)));
    float3 B = cross(N, T);
    float3x3 TBN = float3x3(T, B, N);
    N = normalize(TBN * normal);
    
    // PBR calculations
    float3 L = normalize(-uniforms.sunDirection);
    float3 V = normalize(in.viewDirection);
    float3 H = normalize(L + V);
    
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);
    float NdotH = max(dot(N, H), 0.0);
    float VdotH = max(dot(V, H), 0.0);
    
    // Material properties
    float metallic = 0.1;
    float roughness = 0.6;
    
    // Fresnel
    float3 F0 = mix(float3(0.04), albedo.rgb, metallic);
    float3 F = F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);
    
    // Distribution
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    float denom = NdotH * NdotH * (alpha2 - 1.0) + 1.0;
    float D = alpha2 / (M_PI_F * denom * denom);
    
    // Geometry
    float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    float G1L = NdotL / (NdotL * (1.0 - k) + k);
    float G1V = NdotV / (NdotV * (1.0 - k) + k);
    float G = G1L * G1V;
    
    // BRDF
    float3 numerator = D * G * F;
    float denominator = 4.0 * NdotV * NdotL + 0.001;
    float3 specular = numerator / denominator;
    
    float3 kS = F;
    float3 kD = float3(1.0) - kS;
    kD *= 1.0 - metallic;
    
    // Shadow (simplified for now)
    float shadow = 1.0;
    // TODO: Implement proper shadow mapping
    
    // Final color
    float3 color = (kD * albedo.rgb / M_PI_F + specular) * uniforms.sunColor * uniforms.sunIntensity * NdotL * shadow;
    
    // Ambient with fake GI
    float3 ambient = albedo.rgb * 0.03 * (1.0 + N.y * 0.5);
    color += ambient;
    
    // Window glow at night
    float nightFactor = max(0.0, -uniforms.sunDirection.y);
    float windowGlow = step(0.7, in.texcoord.y) * step(fract(in.texcoord.x * 10.0), 0.3);
    color += float3(1.0, 0.9, 0.7) * windowGlow * nightFactor * 2.0;
    
    // Ensure minimum brightness so buildings are visible
    color = max(color, albedo.rgb * 0.3);
    
    return float4(color, 1.0);
}

// MARK: - Road Shaders

vertex VertexOut roadVertex(VertexIn in [[stage_in]],
                            constant FrameUniforms& uniforms [[buffer(1)]],
                            constant InstanceData& instanceData [[buffer(2)]]) {
    VertexOut out;
    
    float4 worldPos = instanceData.modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.worldPosition = worldPos.xyz;
    out.worldNormal = instanceData.normalMatrix * in.normal;
    out.texcoord = in.texcoord;
    out.shadowCoord = uniforms.lightViewProjectionMatrix * worldPos;
    out.viewDirection = normalize(uniforms.cameraPosition - worldPos.xyz);
    
    return out;
}

fragment float4 roadFragment(VertexOut in [[stage_in]],
                            constant FrameUniforms& uniforms [[buffer(1)]],
                            constant InstanceData& instanceData [[buffer(2)]],
                            texture2d<float> roadTexture [[texture(0)]],
                            texture2d<float> roadNormal [[texture(1)]]) {
    constexpr sampler texSampler(coord::normalized, filter::linear, address::repeat);
    
    // Use dark grey for roads
    float4 albedo = instanceData.color;
    float3 normal = in.worldNormal;
    
    // Yellow dashed center line
    float centerLine = step(0.48, in.texcoord.x) * step(in.texcoord.x, 0.52); // Slightly wider line
    float dashPattern = step(0.5, fract(in.texcoord.y * 8.0)); // More frequent dashes
    float3 yellowLine = float3(1.0, 0.9, 0.0); // Bright yellow
    albedo.rgb = mix(albedo.rgb, yellowLine, centerLine * dashPattern);
    
    // White edge lines
    float leftEdge = step(in.texcoord.x, 0.05);
    float rightEdge = step(0.95, in.texcoord.x);
    float edgeLines = leftEdge + rightEdge;
    albedo.rgb = mix(albedo.rgb, float3(0.9, 0.9, 0.9), edgeLines * 0.8);
    
    // Basic lighting
    float3 N = normalize(in.worldNormal + normal * 0.2);
    float3 L = normalize(-uniforms.sunDirection);
    float NdotL = max(dot(N, L), 0.0);
    
    float3 color = albedo.rgb * uniforms.sunColor * uniforms.sunIntensity * NdotL;
    color += albedo.rgb * 0.3; // Ambient
    
    // Wet road effect
    float wetness = 0.3;
    float3 V = normalize(in.viewDirection);
    float3 H = normalize(L + V);
    float NdotH = max(dot(N, H), 0.0);
    float specular = pow(NdotH, 32.0) * wetness;
    color += uniforms.sunColor * specular;
    
    return float4(color, 1.0);
}

// MARK: - Vegetation Shaders (Instanced with wind)

vertex VertexOut vegetationVertexInstanced(VertexIn in [[stage_in]],
                                           constant FrameUniforms& uniforms [[buffer(1)]],
                                           constant InstanceData* instances [[buffer(2)]],
                                           uint instanceID [[instance_id]]) {
    VertexOut out;
    
    InstanceData instance = instances[instanceID];
    
    // Add wind animation
    float windStrength = 0.3;
    float3 windOffset = float3(
        sin(uniforms.time + instance.modelMatrix[3][0] * 0.1) * windStrength * in.position.y,
        0,
        cos(uniforms.time * 1.2 + instance.modelMatrix[3][2] * 0.1) * windStrength * in.position.y
    );
    
    float4 worldPos = instance.modelMatrix * float4(in.position + windOffset, 1.0);
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.worldPosition = worldPos.xyz;
    out.worldNormal = instance.normalMatrix * in.normal;
    out.texcoord = in.texcoord;
    out.shadowCoord = uniforms.lightViewProjectionMatrix * worldPos;
    out.viewDirection = normalize(uniforms.cameraPosition - worldPos.xyz);
    
    return out;
}

fragment float4 vegetationFragment(VertexOut in [[stage_in]],
                                  constant FrameUniforms& uniforms [[buffer(1)]],
                                  texture2d<float> foliageTexture [[texture(0)]]) {
    constexpr sampler texSampler(coord::normalized, filter::linear);
    
    float4 albedo = foliageTexture.sample(texSampler, in.texcoord);
    
    // Alpha test for leaves
    if (albedo.a < 0.5) {
        discard_fragment();
    }
    
    // Simple subsurface scattering approximation
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(-uniforms.sunDirection);
    float3 V = normalize(in.viewDirection);
    
    float NdotL = dot(N, L);
    float subsurface = max(0.0, -NdotL) * 0.3;
    float diffuse = max(0.0, NdotL);
    
    float3 color = albedo.rgb * uniforms.sunColor * uniforms.sunIntensity * (diffuse + subsurface);
    color += albedo.rgb * 0.4; // Ambient
    
    return float4(color, albedo.a);
}

// MARK: - Water Shaders

vertex VertexOut waterVertex(VertexIn in [[stage_in]],
                             constant FrameUniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    
    // Animated water waves
    float waveHeight = sin(in.position.x * 0.5 + uniforms.time) * 0.1;
    waveHeight += sin(in.position.z * 0.3 + uniforms.time * 1.3) * 0.1;
    
    float3 position = in.position + float3(0, waveHeight, 0);
    float4 worldPos = float4(position, 1.0);
    
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.worldPosition = worldPos.xyz;
    
    // Calculate wave normal
    float3 normal = normalize(float3(
        cos(in.position.x * 0.5 + uniforms.time) * 0.5,
        1.0,
        cos(in.position.z * 0.3 + uniforms.time * 1.3) * 0.3
    ));
    out.worldNormal = normal;
    
    out.texcoord = in.texcoord;
    out.viewDirection = normalize(uniforms.cameraPosition - worldPos.xyz);
    
    return out;
}

fragment float4 waterFragment(VertexOut in [[stage_in]],
                             constant FrameUniforms& uniforms [[buffer(1)]],
                             texturecube<float> skybox [[texture(0)]]) {
    float3 N = normalize(in.worldNormal);
    float3 V = normalize(in.viewDirection);
    
    // Reflection
    float3 R = reflect(-V, N);
    constexpr sampler cubeSampler(filter::linear);
    float3 reflection = skybox.sample(cubeSampler, R).rgb;
    
    // Refraction (fake)
    float3 waterColor = float3(0.0, 0.3, 0.5);
    
    // Fresnel
    float fresnel = pow(1.0 - max(dot(N, V), 0.0), 2.0);
    
    float3 color = mix(waterColor, reflection, fresnel);
    
    // Specular highlights
    float3 L = normalize(-uniforms.sunDirection);
    float3 H = normalize(L + V);
    float NdotH = max(dot(N, H), 0.0);
    float specular = pow(NdotH, 128.0);
    color += uniforms.sunColor * specular * uniforms.sunIntensity;
    
    return float4(color, 0.8);
}

// MARK: - Shadow Mapping

struct ShadowVertexIn {
    float3 position [[attribute(0)]];
};

vertex float4 shadowVertex(ShadowVertexIn in [[stage_in]],
                          constant float4x4& mvpMatrix [[buffer(1)]]) {
    return mvpMatrix * float4(in.position, 1.0);
}

// MARK: - Compute Shaders

struct VehicleData {
    float3 position;
    float3 velocity;
    float3 destination;
    uint type;
    float speed;
    float4 color;
};

struct SimulationParams {
    float deltaTime;
    float time;
    uint vehicleCount;
    float avoidanceRadius;
    float maxSpeed;
};

// Traffic simulation with collision avoidance
kernel void updateTraffic(device VehicleData* vehicles [[buffer(0)]],
                         constant SimulationParams& params [[buffer(1)]],
                         uint id [[thread_position_in_grid]]) {
    if (id >= params.vehicleCount) return;
    
    VehicleData vehicle = vehicles[id];
    
    // Calculate direction to destination
    float3 toDestination = vehicle.destination - vehicle.position;
    float distToDestination = length(toDestination);
    
    // Check if reached destination
    if (distToDestination < 2.0) {
        // Generate new destination (simplified - would use road network in full implementation)
        float angle = params.time * 0.1 + float(id) * 0.5;
        vehicle.destination = float3(
            cos(angle) * 100.0,
            0.5,
            sin(angle) * 100.0
        );
        toDestination = vehicle.destination - vehicle.position;
        distToDestination = length(toDestination);
    }
    
    // Desired velocity
    float3 desiredVelocity = normalize(toDestination) * vehicle.speed;
    
    // Collision avoidance
    float3 avoidance = float3(0, 0, 0);
    int neighborCount = 0;
    
    for (uint i = 0; i < params.vehicleCount; i++) {
        if (i == id) continue;
        
        VehicleData other = vehicles[i];
        float3 separation = vehicle.position - other.position;
        float distance = length(separation);
        
        if (distance < params.avoidanceRadius && distance > 0.001) {
            // Calculate avoidance force
            float strength = (params.avoidanceRadius - distance) / params.avoidanceRadius;
            avoidance += normalize(separation) * strength;
            neighborCount++;
        }
    }
    
    // Apply avoidance
    if (neighborCount > 0) {
        avoidance = avoidance / float(neighborCount) * vehicle.speed * 0.5;
        desiredVelocity += avoidance;
    }
    
    // Smooth velocity change
    vehicle.velocity = mix(vehicle.velocity, desiredVelocity, params.deltaTime * 2.0);
    
    // Limit speed
    float currentSpeed = length(vehicle.velocity);
    if (currentSpeed > vehicle.speed) {
        vehicle.velocity = normalize(vehicle.velocity) * vehicle.speed;
    }
    
    // Update position
    vehicle.position += vehicle.velocity * params.deltaTime;
    vehicle.position.y = 0.5; // Keep at road level
    
    // Write back
    vehicles[id] = vehicle;
}

// Pathfinding kernel
kernel void calculatePath(device float3* waypoints [[buffer(0)]],
                         device uint* pathIndices [[buffer(1)]],
                         device VehicleData* vehicles [[buffer(2)]],
                         constant uint& waypointCount [[buffer(3)]],
                         uint id [[thread_position_in_grid]]) {
    VehicleData vehicle = vehicles[id];
    
    // Find nearest waypoint
    float minDistance = INFINITY;
    uint nearestIndex = 0;
    
    for (uint i = 0; i < waypointCount; i++) {
        float dist = distance(vehicle.position, waypoints[i]);
        if (dist < minDistance) {
            minDistance = dist;
            nearestIndex = i;
        }
    }
    
    pathIndices[id] = nearestIndex;
}

// City growth and economic simulation
kernel void cityGrowthSimulation(texture2d<float, access::read_write> populationDensity [[texture(0)]],
                                texture2d<float, access::read_write> commercialDensity [[texture(1)]],
                                texture2d<float, access::read_write> industrialDensity [[texture(2)]],
                                constant float& growthRate [[buffer(0)]],
                                constant float& time [[buffer(1)]],
                                uint2 gid [[thread_position_in_grid]]) {
    float residential = populationDensity.read(gid).r;
    float commercial = commercialDensity.read(gid).r;
    float industrial = industrialDensity.read(gid).r;
    
    // Sample neighbors for growth calculation
    float residentialNeighbors = 0.0;
    float commercialNeighbors = 0.0;
    float industrialNeighbors = 0.0;
    
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            if (x == 0 && y == 0) continue;
            uint2 neighborCoord = uint2(int2(gid) + int2(x, y));
            residentialNeighbors += populationDensity.read(neighborCoord).r;
            commercialNeighbors += commercialDensity.read(neighborCoord).r;
            industrialNeighbors += industrialDensity.read(neighborCoord).r;
        }
    }
    
    // Growth dynamics
    // Residential grows near commercial
    float residentialGrowth = growthRate * commercialNeighbors / 8.0 * (1.0 - residential);
    residentialGrowth -= industrial * 0.1; // Industrial reduces residential desirability
    
    // Commercial grows near residential
    float commercialGrowth = growthRate * residentialNeighbors / 8.0 * (1.0 - commercial);
    
    // Industrial grows away from residential
    float industrialGrowth = growthRate * (1.0 - residentialNeighbors / 8.0) * (1.0 - industrial);
    
    // Apply growth with time-based variation
    float timeModulation = 0.5 + 0.5 * sin(time * 0.1);
    residential = clamp(residential + residentialGrowth * timeModulation, 0.0, 1.0);
    commercial = clamp(commercial + commercialGrowth * timeModulation, 0.0, 1.0);
    industrial = clamp(industrial + industrialGrowth, 0.0, 1.0);
    
    // Write back
    populationDensity.write(float4(residential), gid);
    commercialDensity.write(float4(commercial), gid);
    industrialDensity.write(float4(industrial), gid);
}

// Particle system for smoke/effects
struct Particle {
    float3 position;
    float3 velocity;
    float4 color;
    float life;
    float size;
};

kernel void updateParticles(device Particle* particles [[buffer(0)]],
                           constant SimulationParams& params [[buffer(1)]],
                           uint id [[thread_position_in_grid]]) {
    Particle particle = particles[id];
    
    // Update physics
    particle.velocity.y += -9.8 * params.deltaTime * 0.1; // Gentle gravity
    particle.velocity *= 0.98; // Air resistance
    particle.position += particle.velocity * params.deltaTime;
    
    // Update life
    particle.life -= params.deltaTime;
    
    // Fade out
    particle.color.a = particle.life;
    particle.size = particle.life * 2.0;
    
    // Reset dead particles
    if (particle.life <= 0.0) {
        // Respawn at random building position
        float angle = float(id) * 0.618033988749895; // Golden ratio
        particle.position = float3(
            cos(angle * 6.28) * 50.0,
            10.0,
            sin(angle * 6.28) * 50.0
        );
        particle.velocity = float3(
            (fract(sin(float(id) * 12.9898) * 43758.5453) - 0.5) * 2.0,
            2.0 + fract(sin(float(id) * 78.233) * 43758.5453) * 3.0,
            (fract(sin(float(id) * 93.123) * 43758.5453) - 0.5) * 2.0
        );
        particle.color = float4(0.5, 0.5, 0.5, 1.0);
        particle.life = 3.0 + fract(sin(float(id) * 45.123) * 43758.5453) * 2.0;
        particle.size = 1.0;
    }
    
    particles[id] = particle;
}