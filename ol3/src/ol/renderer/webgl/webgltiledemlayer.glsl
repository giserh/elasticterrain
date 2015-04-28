//! NAMESPACE=ol.renderer.webgl.tiledemlayer.shader
//! CLASS=ol.renderer.webgl.tiledemlayer.shader.

//! COMMON

// ELASTIC TERRAIN MAP

// Copyright (C) 2015 Jonas Buddeberg <buddebej * mailbox.org>, 
//                    Bernhard Jenny <jennyb * geo.oregonstate.edu>

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// texture with encoded elevation values
uniform sampler2D u_texture;

// texture with overlay map
uniform sampler2D u_overlayTexture;

// flag for active overlay texture
uniform bool u_overlayActive;

// length of one tile in meter at equator
uniform float u_tileSizeM;

// min Elevation in current Extent
uniform float u_minElevation; 

// max Elevation in current Extent
uniform float u_maxElevation;

// temporary variable for coord transfer to fragment shader
varying vec2 v_texCoord;

// current shearing factor
uniform vec2 u_scaleFactor;

// zoom level
uniform float u_zoom;   

// decodes input data elevation value using texture colors from two channels combined
float decodeElevation(in vec2 colorChannels) {
    // use float decoding for higher zoomlevels
    float decimalDecode = 1.0;
    if(u_zoom > 12.0){
        decimalDecode = 0.01;
    }
    float elevationM = ((colorChannels.x*255.0 + (colorChannels.y*255.0)*256.0)-11000.0)*decimalDecode;    
    if(elevationM > 9000.0){
        elevationM = 0.0;
    }
    return elevationM;
}

//! VERTEX

// vertex coordinates for tile mesh
attribute vec2 a_position;

// tile offset in current framebuffer view
uniform vec4 u_tileOffset;

// current depth depends on zoomlevel
uniform float u_z;

void main(void) { 

    // Orientation of coordinate system in vertex shader:
    // y
    // ^ 
    // |
    // |
    // ------>  x

    // pass current vertex coordinates to fragment shader
    v_texCoord = a_position;
    
    // compute y-flipped texture coordinates for further processing in fragment-shader
    v_texCoord.y = 1.0 - v_texCoord.y;

    // read and decode elevation for current vertex
    float absElevation = decodeElevation(vec2(texture2D(u_texture, v_texCoord.xy).xy));
    
    // normalize elevation for current minimum and maximum
    float nElevation = (absElevation-u_minElevation)/(u_maxElevation-u_minElevation); 
    float zOrderElevation = absElevation/100.0;

    if(u_overlayActive){
        // FIXME 
        // sometimes the overlay texture is mistaken for the elevation model
        // we could use different shaders for rendering with and without overlay
        // or we can find a reliable test in the function that serves the overlay textures
        if(texture2D(u_overlayTexture, v_texCoord) != texture2D(u_texture, v_texCoord)){
            gl_Position = vec4((a_position+(nElevation * u_scaleFactor.xy) / u_tileSizeM) * u_tileOffset.xy + u_tileOffset.zw, 
                                u_z-(zOrderElevation/u_tileSizeM), // depth sort rendered tiles depending on their zoomlevel
                                1.0);
        }
    } else {
        // shift vertex positions by given shearing factors
        // z value has to be inverted to get a left handed coordinate system and to make the depth test work
        gl_Position = vec4((a_position+(nElevation * u_scaleFactor.xy) / u_tileSizeM) * u_tileOffset.xy + u_tileOffset.zw, 
                            u_z-(zOrderElevation/u_tileSizeM), // depth sort rendered tiles depending on their zoomlevel
                            1.0);
    }
}

//! FRAGMENT

// color ramp texture to look up hypsometric tints
uniform sampler2D u_hypsoColors;

// color ramp texture to look up bathymetric tints
uniform sampler2D u_bathyColors;

// flag for coloring inland waterbodies
uniform bool u_waterBodies; 

// flag for hillShading
uniform bool u_shading; 

// flag for testing mode
uniform bool u_testing;    

// flag for testing mode
uniform bool u_stackedCardb; 

// scale threshold values to adapt color ramp 
// u_colorScale.x is lower threshold, u_colorScale.y is upper threshold
uniform vec2 u_colorScale;

// direction of light source
uniform vec3 u_light; 

// hillShading Opacity for Blending
uniform float u_shadingOpacity; 

// hillShading Exaggeration
uniform float u_hsExaggeration; 

// intensity of ambient light
uniform float u_ambient_light;    

// cellsize for tile resolution of 256x256 pixel = 1.0/256.0
const highp float CELLSIZE = 0.00390625; 

float rowToCell(in int row) { 
    float v = (float(row)*2.0+1.0)/512.0;
    return v;
}

void main(void) {

        // Orientation of coordinate system in fragment shader:
        //  NORTH
        // ------>  x
        // |
        // | 
        // y    

        vec2 m_texCoord = v_texCoord;
        m_texCoord = vec2(m_texCoord.x,m_texCoord.y);

        bool atNorthBorder = m_texCoord.y <= CELLSIZE;
        bool atSouthBorder = m_texCoord.y >= 1.0-CELLSIZE;
        bool atWestBorder = m_texCoord.x <= CELLSIZE;
        bool atEastBorder = m_texCoord.x >= 1.0 - CELLSIZE;

        // use different tile border decoding for zoomlevel 12 data
        // to fix this, tiles for zoomlevel 12 have to be recomputed (a long and boring process)
        if(u_zoom == 12.0){
            if(atEastBorder){ // eastern border of tile                
                m_texCoord.x = m_texCoord.x - CELLSIZE;
            }

            if(atWestBorder){ // western border of tile                
                m_texCoord.x = m_texCoord.x + CELLSIZE;
            }

            if(atNorthBorder){ // northern border of tile                
                m_texCoord.y = m_texCoord.y + CELLSIZE;
            }

            if(atSouthBorder){ // southern border of tile                
                m_texCoord.y = m_texCoord.y - CELLSIZE;
            }
        }

        vec2 nRight = vec2(m_texCoord.x+CELLSIZE, m_texCoord.y);
        vec2 nLeft = vec2(m_texCoord.x-CELLSIZE, m_texCoord.y);
        vec2 nAbove = vec2(m_texCoord.x, m_texCoord.y+CELLSIZE);
        vec2 nBelow = vec2(m_texCoord.x, m_texCoord.y-CELLSIZE);
        // read and decode elevation values from tile texture
        float absElevation = decodeElevation(vec2(texture2D(u_texture, m_texCoord.xy).xy));

        // read neighboring values
        float neighborRight = decodeElevation(vec2(texture2D(u_texture, nRight).xy));
        float neighborLeft  = decodeElevation(vec2(texture2D(u_texture, nLeft).xy));
        float neighborAbove = decodeElevation(vec2(texture2D(u_texture, nAbove).xy));
        float neighborBelow = decodeElevation(vec2(texture2D(u_texture, nBelow).xy));    

        // use different tile border decoding for zoomlevel 12 data
        // to fix this, tiles for zoomlevel 12 have to be recomputed (a long and boring process) 
        if(u_zoom != 12.0){
            // display tile borders properly: use alternative decoding
            // last eight rows of blue channel contain neighbor values
            if(atNorthBorder){ 
                float valA = texture2D(u_texture, vec2(m_texCoord.x, rowToCell(256))).b; // row 256          
                float valB = texture2D(u_texture, vec2(m_texCoord.x, rowToCell(251))).b; // row 251
                neighborBelow = decodeElevation(vec2(valB, valA));
            }

            if(atSouthBorder){  
                float valA = texture2D(u_texture, vec2(m_texCoord.x, rowToCell(254))).b; // row 254        
                float valB = texture2D(u_texture, vec2(m_texCoord.x, rowToCell(250))).b; // row 250
                neighborAbove = decodeElevation(vec2(valB, valA));            
            }

            if(atEastBorder){ 
                float valA = texture2D(u_texture, vec2(m_texCoord.y, rowToCell(253))).b; // row 253         
                float valB = texture2D(u_texture, vec2(m_texCoord.y, rowToCell(249))).b; // row 249 
                neighborRight = decodeElevation(vec2(valB, valA));            
            }

            if(atWestBorder){  
                float valA = texture2D(u_texture, vec2(m_texCoord.y, rowToCell(252))).b; // row 252         
                float valB = texture2D(u_texture, vec2(m_texCoord.y, rowToCell(248))).b; // row 248 
                neighborLeft = decodeElevation(vec2(valB, valA));            
            }      
        }   

        // cardboard stack
        if(u_stackedCardb && !u_overlayActive && absElevation<0.0){
            // neighborRight = decodeElevation(vec2(0.0, texture2D(u_texture, nRight).g));
            // neighborLeft  = decodeElevation(vec2(0.0, texture2D(u_texture, nLeft).g));
            neighborAbove = decodeElevation(vec2(0.0, texture2D(u_texture, nAbove).g));            
            // neighborBelow = decodeElevation(vec2(0.0, texture2D(u_texture, nBelow).g));
        }               

    // texture
        vec4 fragColor;

        if(u_overlayActive){
             // use overlay texture color
             fragColor = texture2D(u_overlayTexture, m_texCoord);
        } else {
            // lookup a hypsometric color   

                // scaling of color ramp
                float colorMin = 1.0-u_colorScale.x*1.0;
                float colorMax = u_colorScale.y*1.0;   

                float relativeElevation = 0.0;

                if(absElevation > 0.1){
                    relativeElevation = absElevation/u_maxElevation;
                    fragColor = abs(texture2D(u_hypsoColors,vec2(0.5,relativeElevation)));
                } else {
                    relativeElevation = abs(absElevation/u_minElevation);
                    fragColor = abs(texture2D(u_bathyColors,vec2(0.5,relativeElevation)));
                }
                                  
                // color for water surfaces in flat terrain
                if(u_waterBodies) {
                    vec4 waterBlue = vec4(0.4058823529,0.6725490196,0.8970588235,1.0);

                    // compute other neighbors for water surface test
                    float n01 = decodeElevation(vec2(texture2D(u_texture, vec2(m_texCoord.x+CELLSIZE, m_texCoord.y+CELLSIZE)).xy));
                    float n02 = decodeElevation(vec2(texture2D(u_texture, vec2(m_texCoord.x-CELLSIZE, m_texCoord.y+CELLSIZE)).xy));
                    float n03 = decodeElevation(vec2(texture2D(u_texture, vec2(m_texCoord.x+CELLSIZE, m_texCoord.y-CELLSIZE)).xy));
                    float n04 = decodeElevation(vec2(texture2D(u_texture, vec2(m_texCoord.x-CELLSIZE, m_texCoord.y+CELLSIZE)).xy));         

                    if(absElevation>0.0 && 
                       n01 == absElevation && 
                       n02 == absElevation && 
                       n03 == absElevation && 
                       n04 == absElevation && 
                       neighborRight == absElevation && 
                       neighborLeft == absElevation && 
                       neighborAbove == absElevation && 
                       neighborBelow == absElevation) 
                    {
                        fragColor = waterBlue; 
                    }
                
                } 
        }

    // computation of shading
        if(u_shading){

            // apply exaggeration
            float exaggerationFactor = max(u_hsExaggeration*10.0,1.0);

            // compute normal with values from four neighbors
            vec3 normal = vec3(  neighborLeft - neighborRight,
                                 neighborAbove - neighborBelow,
                                 CELLSIZE * u_tileSizeM / exaggerationFactor);
           
            // compute the dot product of the normal and the light vector. This
            // gives a value between -1 (surface faces directly away from
            // light) and 1 (surface faces directly toward light)
            float hillShade = dot(normal,normalize(u_light)) / length(normal);

            // apply ambient light and adjust value to be between 0.0 and 1.0
            hillShade = clamp(u_ambient_light * 1.0 + (hillShade + 1.0) * 0.5, 0.0, 1.0);

            // remap image tonality
            hillShade = pow(hillShade, 1.0 / (1.0 + u_shadingOpacity * 2.0));

            // avoid black shadows
            hillShade = max(hillShade, 0.25);

            // mix with hypsometric color
            gl_FragColor = vec4(hillShade,hillShade,hillShade,1.0)*fragColor;


        } else {
            // apply hypsometric color without hillshading
            gl_FragColor = fragColor;
        }

    // testing mode
        if(u_testing){

            vec4 red = vec4(0.98,0.18,0.15,1.0);
            vec4 green = vec4(0.0,1.0,0.0,1.0);
            vec4 blue = vec4(0.0,0.0,1.0,1.0);
            vec4 black = vec4(0.0,0.0,0.0,1.0);
            vec4 lighten = vec4(1.2,1.2,1.2,1.0);

            // highlight maxima and minima 
            // float criticalEl = u_minElevation + (u_maxElevation - u_minElevation) * u_critElThreshold;
           
            // display minima in gray
            // if(absElevation < criticalEl){
            //     float gray = dot(gl_FragColor.rgb, vec3(0.299, 0.587, 0.114));
            //     gl_FragColor = vec4(gray, gray, gray, 1.0);
            // }   

            // if(absElevation > criticalEl){
            //     float gray = dot(gl_FragColor.rgb, vec3(0.299, 0.587, 0.114));
            //     gl_FragColor = vec4(red.xyz, gray);
            // }           

            // mark tile borders and draw a grid            
            if(atWestBorder){
                gl_FragColor = green;
            }
            if(atEastBorder){
                gl_FragColor = black;
            }
            if(atNorthBorder){
                gl_FragColor = red;
            }
            if(atSouthBorder){
                gl_FragColor = blue;
            } 
            if(mod(m_texCoord.x,65.0*CELLSIZE) < CELLSIZE){
               gl_FragColor = gl_FragColor*lighten;
            }
            if(mod(m_texCoord.y,65.0*CELLSIZE) < CELLSIZE){
               gl_FragColor = gl_FragColor*lighten;
            }
          
        }
}
