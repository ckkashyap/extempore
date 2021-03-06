#version 400

layout(location = 0) in vec2 vertex_position;
layout(location = 1) in vec3 vertex_colour;

out vec3 colour;

void main () {
  colour = vertex_colour;
  gl_PointSize = 100.0;
  gl_Position = vec4(vertex_position,1.0,1.0);
}
