//
//  Shaders.metal
//  MiniCity
//
//  Created by Griffin on 8/9/25.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

// Simple test shaders for debugging
vertex float4 simpleGroundVertex(uint vertexID [[vertex_id]],
                                 constant float3 *vertices [[buffer(0)]],
                                 constant Uniforms & uniforms [[buffer(BufferIndexUniforms)]])
{
    float3 position = vertices[vertexID];
    float4 worldPos = float4(position, 1.0);
    return uniforms.projectionMatrix * uniforms.modelViewMatrix * worldPos;
}

fragment float4 simpleGroundFragment()
{
    // Solid green color
    return float4(0.2, 0.6, 0.1, 1.0);
}

// Output structures
typedef struct
{
    float4 position [[position]];
    float2 texCoord;
} ColorInOut;

typedef struct
{
    float4 position [[position]];
    float3 color;
} GridInOut;

// Ground plane shaders  
struct GroundVertex {
    float3 position;
    float2 texCoord;
};

vertex ColorInOut groundVertexShader(uint vertexID [[vertex_id]],
                                     constant GroundVertex *vertices [[buffer(0)]],
                                     constant Uniforms & uniforms [[buffer(BufferIndexUniforms)]])
{
    ColorInOut out;
    
    GroundVertex vert = vertices[vertexID];
    
    float4 worldPosition = float4(vert.position, 1.0);
    float4 viewPosition = uniforms.modelViewMatrix * worldPosition;
    out.position = uniforms.projectionMatrix * viewPosition;
    out.texCoord = vert.texCoord;
    
    return out;
}

fragment float4 groundFragmentShader(ColorInOut in [[stage_in]],
                                     texture2d<float> groundTexture [[texture(0)]])
{
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::repeat);
    
    // Sample the grass texture with tiling
    float4 color = groundTexture.sample(textureSampler, in.texCoord * 10.0); // Tile the texture
    
    // If texture is black/empty, use a default green color
    if (length(color.rgb) < 0.01) {
        color = float4(0.2, 0.5, 0.15, 1.0); // Default grass green
    }
    
    // Fog disabled for now - just return the ground color
    return color;
}

// Grid shaders
vertex GridInOut gridVertexShader(uint vertexID [[vertex_id]],
                                  constant float *vertexData [[buffer(0)]],
                                  constant Uniforms & uniforms [[buffer(BufferIndexUniforms)]])
{
    GridInOut out;
    
    // Each vertex has 6 floats (3 position, 3 color)
    uint dataIndex = vertexID * 6;
    float3 position = float3(vertexData[dataIndex], vertexData[dataIndex + 1], vertexData[dataIndex + 2]);
    float3 color = float3(vertexData[dataIndex + 3], vertexData[dataIndex + 4], vertexData[dataIndex + 5]);
    
    float4 worldPosition = float4(position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * worldPosition;
    out.color = color;
    
    return out;
}

fragment float4 gridFragmentShader(GridInOut in [[stage_in]])
{
    // Add slight transparency to grid lines so they blend better
    return float4(in.color, 0.5);
}

// Checkerboard ground shaders
struct CheckerboardVertex {
    float3 position [[attribute(0)]];
    float3 color [[attribute(1)]];
    float2 gridCoord [[attribute(2)]];
};

struct CheckerboardInOut {
    float4 position [[position]];
    float3 color;
    float2 gridCoord;
    float3 worldPos;
};

vertex CheckerboardInOut checkerboardVertexShader(uint vertexID [[vertex_id]],
                                                  constant float *vertexData [[buffer(0)]],
                                                  constant Uniforms & uniforms [[buffer(BufferIndexUniforms)]])
{
    CheckerboardInOut out;
    
    // Each vertex has 8 floats (3 position, 3 color, 2 grid coords)
    uint dataIndex = vertexID * 8;
    float3 position = float3(vertexData[dataIndex], vertexData[dataIndex + 1], vertexData[dataIndex + 2]);
    float3 color = float3(vertexData[dataIndex + 3], vertexData[dataIndex + 4], vertexData[dataIndex + 5]);
    float2 gridCoord = float2(vertexData[dataIndex + 6], vertexData[dataIndex + 7]);
    
    float4 worldPosition = float4(position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * worldPosition;
    out.color = color;
    out.gridCoord = gridCoord;
    out.worldPos = position;
    
    return out;
}

fragment float4 checkerboardFragmentShader(CheckerboardInOut in [[stage_in]])
{
    // Add subtle variation to the base color
    float noise = fract(sin(dot(in.gridCoord, float2(12.9898, 78.233))) * 43758.5453);
    float3 variedColor = in.color * (0.9 + noise * 0.1);
    
    // Add grid lines at cell boundaries
    float2 grid = fract(in.gridCoord);
    float lineWidth = 0.02;
    float gridLine = 0.0;
    
    if (grid.x < lineWidth || grid.x > (1.0 - lineWidth) ||
        grid.y < lineWidth || grid.y > (1.0 - lineWidth)) {
        gridLine = 0.3; // Darken for grid lines
    }
    
    float3 finalColor = variedColor * (1.0 - gridLine * 0.5);
    
    return float4(finalColor, 1.0);
}

// Original shaders for textured objects (will use later for buildings)
typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float2 texCoord [[attribute(VertexAttributeTexcoord)]];
} Vertex;

vertex ColorInOut vertexShader(Vertex in [[stage_in]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]])
{
    ColorInOut out;

    float4 position = float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * position;
    out.texCoord = in.texCoord;

    return out;
}

fragment float4 fragmentShader(ColorInOut in [[stage_in]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                               texture2d<half> colorMap     [[ texture(TextureIndexColor) ]])
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);

    half4 colorSample   = colorMap.sample(colorSampler, in.texCoord.xy);

    return float4(colorSample);
}