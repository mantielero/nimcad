import std/math
import opengl
import staticglfw as glfw
import ../core/sdf_ast
import camera

const FULLSCREEN_VERTEX_SHADER = """
#version 430
out vec2 v_uv;
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  v_uv = p * 0.5;
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
"""

var pendingScroll = 0.0

proc onScroll(window: glfw.Window, xOffset, yOffset: cdouble) {.cdecl.} =
  discard window
  discard xOffset
  pendingScroll += float(yOffset)

proc shaderLog(shader: GLuint): string =
  var length: GLint
  glGetShaderiv(shader, GL_INFO_LOG_LENGTH, addr length)
  if length <= 1:
    return "no compiler log"
  result = newString(int(length))
  var written: GLsizei
  glGetShaderInfoLog(shader, length, addr written,
                     cast[cstring](addr result[0]))
  result.setLen(max(0, int(written)))

proc programLog(program: GLuint): string =
  var length: GLint
  glGetProgramiv(program, GL_INFO_LOG_LENGTH, addr length)
  if length <= 1:
    return "no linker log"
  result = newString(int(length))
  var written: GLsizei
  glGetProgramInfoLog(program, length, addr written,
                      cast[cstring](addr result[0]))
  result.setLen(max(0, int(written)))

proc compileShader(source: string, shaderType: GLenum): GLuint =
  result = glCreateShader(shaderType)
  if result == 0:
    raise newException(IOError, "OpenGL could not create a shader")
  var sourcePointer = source.cstring
  glShaderSource(result, 1, cast[cstringArray](addr sourcePointer), nil)
  glCompileShader(result)
  var status: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, addr status)
  if status == 0:
    let message = shaderLog(result)
    glDeleteShader(result)
    result = 0
    raise newException(IOError, "GLSL shader compilation failed:\n" & message)

proc createProgram(fragmentSource: string): GLuint =
  let vertex = compileShader(FULLSCREEN_VERTEX_SHADER, GL_VERTEX_SHADER)
  var fragment: GLuint
  try:
    fragment = compileShader(fragmentSource, GL_FRAGMENT_SHADER)
  except:
    glDeleteShader(vertex)
    raise
  result = glCreateProgram()
  if result == 0:
    glDeleteShader(vertex)
    glDeleteShader(fragment)
    raise newException(IOError, "OpenGL could not create a shader program")
  glAttachShader(result, vertex)
  glAttachShader(result, fragment)
  glLinkProgram(result)
  glDeleteShader(vertex)
  glDeleteShader(fragment)
  var status: GLint
  glGetProgramiv(result, GL_LINK_STATUS, addr status)
  if status == 0:
    let message = programLog(result)
    glDeleteProgram(result)
    result = 0
    raise newException(IOError, "GLSL program link failed:\n" & message)

proc uniform(program: GLuint, name: string): GLint =
  glGetUniformLocation(program, name.cstring)

proc runViewport*(fragmentSource, title: string, bounds: AABB) =
  if glfw.init() == 0:
    raise newException(IOError, "GLFW could not initialize a display")

  glfw.defaultWindowHints()
  glfw.windowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
  glfw.windowHint(glfw.CONTEXT_VERSION_MINOR, 3)
  glfw.windowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
  glfw.windowHint(glfw.VISIBLE, glfw.TRUE)
  let window = glfw.createWindow(1280, 800, title.cstring, nil, nil)
  if window == nil:
    glfw.terminate()
    raise newException(IOError,
      "could not create an OpenGL 4.3 window; check the display and GPU driver")
  glfw.makeContextCurrent(window)
  loadExtensions()
  glfw.swapInterval(1)

  var program: GLuint
  var vertexArray: GLuint
  try:
    program = createProgram(fragmentSource)
    glGenVertexArrays(1, addr vertexArray)
    glBindVertexArray(vertexArray)
    glUseProgram(program)
    discard glfw.setScrollCallback(window, onScroll)

    var camera = initCamera()
    camera.pivot = ((bounds.lo.x + bounds.hi.x) * 0.5,
                    (bounds.lo.y + bounds.hi.y) * 0.5,
                    (bounds.lo.z + bounds.hi.z) * 0.5)
    let dx = bounds.hi.x - bounds.lo.x
    let dy = bounds.hi.y - bounds.lo.y
    let dz = bounds.hi.z - bounds.lo.z
    camera.distance = max(sqrt(dx * dx + dy * dy + dz * dz) * 1.8, 20.0)

    let resolutionLocation = uniform(program, "u_resolution")
    let cameraPosLocation = uniform(program, "u_cameraPos")
    let cameraTargetLocation = uniform(program, "u_cameraTarget")
    let viewModeLocation = uniform(program, "u_viewMode")
    let stepScaleLocation = uniform(program, "u_stepScale")
    let orthoLocation = uniform(program, "u_ortho")
    let orthoScaleLocation = uniform(program, "u_orthoScale")
    let timeLocation = uniform(program, "u_time")
    var lastX, lastY: cdouble
    glfw.getCursorPos(window, addr lastX, addr lastY)
    let startTime = glfw.getTime()

    while glfw.windowShouldClose(window) == 0:
      glfw.pollEvents()
      if glfw.getKey(window, glfw.KEY_ESCAPE) == glfw.PRESS:
        glfw.setWindowShouldClose(window, 1)

      var cursorX, cursorY: cdouble
      glfw.getCursorPos(window, addr cursorX, addr cursorY)
      if glfw.getMouseButton(window, glfw.MOUSE_BUTTON_MIDDLE) == glfw.PRESS:
        let dxMouse = float(cursorX - lastX)
        let dyMouse = float(cursorY - lastY)
        if glfw.getKey(window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS or
            glfw.getKey(window, glfw.KEY_RIGHT_SHIFT) == glfw.PRESS:
          camera.pan(dxMouse, dyMouse)
        else:
          camera.orbit(dxMouse * 0.006, -dyMouse * 0.006)
      lastX = cursorX
      lastY = cursorY
      if pendingScroll != 0:
        camera.zoom(-pendingScroll * 0.12)
        pendingScroll = 0

      var width, height: cint
      glfw.getFramebufferSize(window, addr width, addr height)
      if width > 0 and height > 0:
        glViewport(0, 0, GLsizei(width), GLsizei(height))
        glClearColor(0.025, 0.030, 0.040, 1.0)
        glClear(GL_COLOR_BUFFER_BIT)

        let cosPitch = cos(camera.pitch)
        let position = (
          camera.pivot.x + camera.distance * cosPitch * sin(camera.yaw),
          camera.pivot.y + camera.distance * sin(camera.pitch),
          camera.pivot.z + camera.distance * cosPitch * cos(camera.yaw))
        glUniform2f(resolutionLocation, GLfloat(width), GLfloat(height))
        glUniform3f(cameraPosLocation, GLfloat(position[0]),
                    GLfloat(position[1]), GLfloat(position[2]))
        glUniform3f(cameraTargetLocation, GLfloat(camera.pivot.x),
                    GLfloat(camera.pivot.y), GLfloat(camera.pivot.z))
        glUniform1i(viewModeLocation, 0)
        glUniform1f(stepScaleLocation, 1.0)
        glUniform1f(orthoLocation, if camera.ortho: 1.0 else: 0.0)
        glUniform1f(orthoScaleLocation, GLfloat(camera.orthoScale))
        glUniform1f(timeLocation, GLfloat(glfw.getTime() - startTime))
        glDrawArrays(GL_TRIANGLES, 0, 3)

      glfw.swapBuffers(window)
  finally:
    if program != 0:
      glDeleteProgram(program)
    if vertexArray != 0:
      glDeleteVertexArrays(1, addr vertexArray)
    glfw.destroyWindow(window)
    glfw.terminate()
