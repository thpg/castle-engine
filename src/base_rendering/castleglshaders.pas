{
  Copyright 2007-2025 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ OpenGL shaders in GLSL language.

  @unorderedList(
    @item(
      GLSL version:

      For maximum portability, provide shader code
      that works with oldest GLSL versions, and do not declare "#version".
      This means targeting ancient GLSL 1.10 version for desktop OpenGL
      (introduced in OpenGL 2.0)
      and targeting GLSL 1.00 for OpenGLES (introduced in OpenGLES 2.0).
      This means using "attribute", "varying" keywords, and querying
      the textures using "texture2D", "textureCube" and so on.

      When compiling the shader on modern OpenGL or OpenGLES,
      we will add a modern #version statement to the shader,
      and define a few macros that make it use modern keywords
      (e.g. "attribute" will be replaced with "in" in vertex shader;
      "texture2D" call will be replaced with "texture").
      The resulting shader will not use any deprecated features,
      so it should be fine for OpenGL "core" profile (without compatibility) too.

      As of now, this means we bump the #version for the desktop OpenGL 3.1
      core profile (if OpenGL >= 3.1) and we bump the #version for
      the mobile OpenGLES 3 (if OpenGLES >= 3.0).

      Note: If you know you want to target only newer OpenGL(ES) versions,
      you can also specify #version in shader code explicitly.
      We will not add another #version then. It is your responsibility
      then to provide proper alternatives for desktop OpenGL and mobile OpenGLES,
      as they use similar but not exactly compatible GLSL versions.

      For geometry shaders, you can assume GLSL >= 1.50 (OpenGL 3.2).
      We do not support geometry shaders with older versions.

      Set InternalUpgradeGlslVersion to @false to test that shaders work also without it.
    )

    @item(
      Precision on OpenGLES:

      We automatically add "precision mediump float;" to fragment shader on OpenGLES,
      if no declaration "precision mediump/lowp/highp float;" is found in the code.
      This is practically universally needed for OpenGLES fragment shader,
      that have no default precision.

      See also WebGL recommendations:
      https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/WebGL_best_practices#be_precise_with_glsl_precision_annotations
    )

    @item(
      Creating/destroying the TGLSLProgram instance immediately creates/destroys
      appropriate program on GPU. So be sure to create/destroy it only
      when you have OpenGL context available (for example,
      create in @link(TCastleUserInterface.GLContextOpen),
      and destroy in @link(TCastleUserInterface.GLContextClose)).)

    @item(
      Upon creation, we check current OpenGL context abilities.

      Currently 2 support levels are possible:
      no support at all (ancient OpenGL) or support built-in (newer OpenGL versions, >= 2.0).
      The support for shaders using ARB extensions has been removed at 2023-01,
      as practically no GPU had it and we didn't really test it.

      Both cases are automatically handled inside, so usually you
      do not have to care about these details.)

  )
}
unit CastleGLShaders;

{ Define CASTLE_COLLECT_SHADER_SOURCE to collect in TGLSLProgram shader code as Srting, to

  - show it in case of error
  - show it before linking, if LogShaders.

  Note:

  - The resulting error message can be quite long,
    as it will contain a full GLSL code.
    That's useful if you're a developer familiar with GLSL, and able to modify it.
    But it makes the log very long and hard to read,
    which is a problem if you're not interested in this particular GLSL bug now.

  - Showing it (at linking) requires collecting shader source code,
    which uses a bit of memory and time.
    (But in practice, this is negligible, so this isn't an important argument.)
}
{$ifdef DEBUG}
  {$define CASTLE_COLLECT_SHADER_SOURCE}
{$endif}

{$I castleconf.inc}

interface

uses SysUtils, Classes, Generics.Collections,
  {$ifdef OpenGLES} CastleGLES, {$else} CastleGL, {$endif}
  CastleGLUtils, CastleUtils, CastleVectors, CastleRenderOptions;

type
  { Common class for exceptions related to GLSL programs. }
  EGLSLError = class(Exception);

  EGLSLShaderCompileError = class(EGLSLError);
  EGLSLProgramLinkError = class(EGLSLError);
  EGLSLAttributeNotFound = class(EGLSLError);
  EGLSLTransformFeedbackError = class(EGLSLError);

  TGLSLProgram = class;

  { GLSL uniform provides information to shader that is constant for a given shader execution. }
  TGLSLUniform = record
  public
    Owner: TGLSLProgram;
    Name: string;
    Location: TGLUniformLocation;

    { Calling @link(TGLSLUniform.SetValue) of this is ignored. }
    class function NotExisting: TGLSLUniform; static;

    { Set uniform variable value.
      You should get the uniform information first using the
      @link(TGLSLProgram.Uniform) call. All the documentation for
      @link(TGLSLProgram.SetUniform) applies also here, so the program must be
      linked, and enabled (it will be enabled automatically by calling this).

      This method always ignores a missing uniform.
      Rely on @link(TGLSLProgram.Uniform) to make something else (like make a warning).

      The TGLSLUniform information about a given uniform stays constant while
      the program is linked. Using the @link(TGLSLProgram.Uniform) one time, and then
      repeatedly calling @link(TGLSLUniform.SetValue), is faster than repeatedly
      calling @link(TGLSLProgram.SetUniform). Because the latter will
      effectively call @link(TGLSLProgram.Uniform) every time, which may have non-zero cost.

      Actually, the uniform location (TGLSLUniform.Location) is constant for a given program,
      and you can even predict the location in some cases without calling @link(TGLSLProgram.Uniform)
      method (see GLSL reference). So it can be even faster, as you can prepare
      correct TGLSLUniform instance in your own code, without calling
      @link(TGLSLProgram.Uniform).

      @groupBegin }
    procedure SetValue(const Value: boolean        ); overload;
    procedure SetValue(const Value: TGLint         ); overload;
    procedure SetValue(const Value: TVector2Integer); overload;
    procedure SetValue(const Value: TVector3Integer); overload;
    procedure SetValue(const Value: TVector4Integer); overload;
    procedure SetValue(const Value: TGLfloat       ); overload;
    procedure SetValue(const Value: TVector2       ); overload;
    procedure SetValue(const Value: TVector3       ); overload;
    procedure SetValue(const Value: TVector4       ); overload;
    procedure SetValue(const Value: TMatrix2       ); overload;
    procedure SetValue(const Value: TMatrix3       ); overload;
    procedure SetValue(const Value: TMatrix4       ); overload;

    procedure SetValue(const Value: TBooleanList); overload;
    procedure SetValue(const Value: TInt32List  ); overload;
    procedure SetValue(const Value: TSingleList ); overload;
    procedure SetValue(const Value: TVector2List); overload;
    procedure SetValue(const Value: TVector3List); overload;
    procedure SetValue(const Value: TVector4List); overload;
    procedure SetValue(const Value: TMatrix3List); overload;
    procedure SetValue(const Value: TMatrix4List); overload;
    { @groupEnd }
  end;

  { GLSL attribute provides per-vertex information to the shader. }
  TGLSLAttribute = record
  public
    type
      TLocationOffset = 0..3;
    var
    Owner: TGLSLProgram;
    Name: string;
    Location: TGLAttribLocation;
    LocationOffsetsToDisable: array [TLocationOffset] of boolean;

    { Enable an array of arbitary OpenGL type.
      See the OpenGL documentation of glVertexAttribPointer for meaning of the
      parameters.

      Note that Ptr is usually an offset relative to the currently bound VBO
      (Vertex Buffer Object), not a regular pointer to a memory content.
      That is why is has a type PtrUInt (not Pointer), since usually you calculate
      it as an integer.

      Note that the array size is not specified anywhere. The way you access
      the array (what indexes you use) determines the minimum count of the array
      you should have (and uploaded to VBO).

      You have to provide VertexArrayObject where the array is bound. }
    procedure EnableArray(const Vao: TVertexArrayObject;
      const LocationOffset: TLocationOffset;
      const Size: TGLint; const AType: TGLenum; const Normalized: TGLboolean; const Stride: TGLsizei;
      const Ptr: PtrUInt);
    { Shortcut to enable an array of floats (Single in Pascal). }
    procedure EnableArraySingle(const Vao: TVertexArrayObject;
      const Stride: TGLsizei; const Ptr: PtrUInt);
    { Shortcut to enable an array of TVector2. }
    procedure EnableArrayVector2(const Vao: TVertexArrayObject;
      const Stride: TGLsizei; const Ptr: PtrUInt);
    { Shortcut to enable an array of TVector3. }
    procedure EnableArrayVector3(const Vao: TVertexArrayObject;
      const Stride: TGLsizei; const Ptr: PtrUInt);
    { Shortcut to enable an array of TVector4. }
    procedure EnableArrayVector4(const Vao: TVertexArrayObject;
      const Stride: TGLsizei; const Ptr: PtrUInt);
    { Shortcut to enable an array of TMatrix3. }
    procedure EnableArrayMatrix3(const Vao: TVertexArrayObject;
      const Stride: TGLsizei; const Ptr: PtrUInt);
    { Shortcut to enable an array of TMatrix4. }
    procedure EnableArrayMatrix4(const Vao: TVertexArrayObject;
      const Stride: TGLsizei; const Ptr: PtrUInt);

    procedure DisableArray;

    { Set attribute variable value.
      The used type must match the type of this variable in GLSL program.

      OpenGL forces some constraints on using this, see SetUniform.
      In short: use this only after linking the program.
      The program is automatically enabled (set as @link(TRenderContext.CurrentProgram RenderContext.CurrentProgram)) by this.
      And note that attributes declared but not actually used in shader code
      may be eliminated, use DebugInfo to see which attributes are actually
      used (@italic(active) in OpenGL terminology).

      These should not be often useful. Usually, you should rather load
      attribute arrays, by EnableArray.

      @groupBegin }
    procedure SetValue(const Value: TGLfloat); overload;
    procedure SetValue(const Value: TVector2); overload;
    procedure SetValue(const Value: TVector3); overload;
    procedure SetValue(const Value: TVector4); overload;
    procedure SetValue(const Value: TMatrix3); overload;
    procedure SetValue(const Value: TMatrix4); overload;
    {$ifndef OpenGLES}
    procedure SetValue(const Value: TVector4Integer); overload;
    procedure SetValue(const Value: TVector4Byte); overload;
    procedure SetValue(const Value: TGLdouble); overload;
    // Makes FPC errors: Error: Asm: Duplicate label, see https://bugs.freepascal.org/view.php?id=32188
    // procedure SetValue(const Value: TVector2Double);
    // procedure SetValue(const Value: TVector3Double);
    // procedure SetValue(const Value: TVector4Double);
    {$endif}
    { @groupEnd }
  end;

  TGLSLAttributeList = {$ifdef FPC}specialize{$endif} TList<TGLSLAttribute>;

  TUniformLocationCache = {$ifdef FPC}specialize{$endif} TDictionary<String, TGLUniformLocation>;
  TAttribLocationCache = {$ifdef FPC}specialize{$endif} TDictionary<String, TGLAttribLocation>;

  TGLShaderList = {$ifdef FPC}specialize{$endif} TList<TGLShader>;

  { Manage (build, use) a program in GLSL (OpenGL Shading Language). }
  TGLSLProgram = class
  private
    ProgramId: TGLprogram;
    ShaderIds: TGLShaderList;
    FSaveBinaryRequested: Boolean;
    {$ifndef CASTLE_WEBGL}
    type
      TUniformValueEntry = record
        Location: TGLint;
        Kind, Size: Byte;
        Epoch: QWord;
        Data: array[0..15] of UInt32;
      end;
    var
      FUniformValueEntries: array[0..63] of TUniformValueEntry;
      FUniformValueEpoch: QWord;
    function UploadUniformValue(const Location: TGLint; const Value;
      const Size, Kind: Byte): Boolean;
    {$endif}

  private
    FUniformMissing: TUniformMissing;
    FUniformLocations: TUniformLocationCache;
    FAttributeLocations: TAttribLocationCache;
    FUniformReportedMissing: TStringList;
    FAttributeReportedMissing: TStringList;

    // Given stage was attached and compiled by @link(AttachShader).
    HasStage: array [TShaderType] of Boolean;

    {$ifdef CASTLE_COLLECT_SHADER_SOURCE}
    FSource: array [TShaderType] of TStringList;
    {$endif CASTLE_COLLECT_SHADER_SOURCE}

    class function GetCurrent: TGLSLProgram; static;
    class procedure SetCurrent(const Value: TGLSLProgram); static;

    { Make sure all shaders are detached and deleted, to free all resources.
      This may be called repeatedly, calling it the 2nd time will not free
      any more resources.

      Note that we don't support calling "Link" repeatedly,
      this class assumes that TGLSLProgram is only linked once and then used,
      for now.
      So calling GLContextClose multiple times has really simple semantics:
      2nd call just does nothing. The shader is not useful after the 1st
      GLContextClose call. }
    procedure GLContextClose;
    procedure OnGlContextClose(Sender: TObject);
  public
    { Opt in only for programs whose uniforms are written through SetValue.
      Raw glUniform writes must call InvalidateUniformValues first. }
    CacheUniformValues: Boolean;

    { Shader name is used in log messages. Any String is OK. }
    Name: String;
    {$ifdef CASTLE_CANNOT_CATCH_EXCEPTIONS}
    { Web target doesn't support try..except, so we use this field
      to report that AttachShader or Link caused an error.
      WritelnWarning with details was already generated.
      Non-web targets should not rely on this, exceptions signal errors. }
    ErrorOnCompileLink: Boolean;
    {$endif}

    { Is fragment shader required to link successfully.

      By default this is @false (for now) and you can attempt to link
      a shader with only vertex shader, without fragment shader.
      This makes sense on OpenGL
      ( https://www.khronos.org/opengl/wiki/Fragment_Shader#Optional ).
      Only OpenGLES, or OpenGL on macOS with Core profile,
      strictly requires fragment shader to be present.

      Setting this to @true is useful when you know shader really requires
      fragment shader and you want to get more clear error message.
      CGE then knows to abort linking early, with clear error message,
      when fragment shader is missing. }
    FragmentShaderRequired: Boolean;

    procedure InvalidateUniformValues;
    constructor Create;
    destructor Destroy; override;

    { Create shader from given string, compile it and attach to current program.

      For desktop OpenGL, you can attach more than one shader of given
      type, just make sure that only one main() function is among each type
      (otherwise link error will be raised later).
      For OpenGLES, this is not allowed, so don't use this if you want
      to work with OpenGLES too.

      If you want to explicitly get rid of old shaders, use DetachAllShaders.

      @raises(EGLSLShaderCompileError If the shader source code cannot be compiled,
        exception message contains precise description from OpenGL where
        the error is.)

      @groupBegin }
    procedure AttachVertexShader(const S: string);
    procedure AttachGeometryShader(const S: string);
    procedure AttachFragmentShader(const S: string);
    procedure AttachShader(const ShaderType: TShaderType; S: string); overload;
    { @groupEnd }

    { Attach multiple shader parts for given type.

      For normal OpenGL, we can use GLSL separate compilation units.
      So this is equivalent to just calling
      @code(AttachShader(ShaderType, Parts[I])) for each part.

      For OpenGL ES, this is unfortunately not possible,
      you can only attach a single shader of a given type (see
      http://www.khronos.org/opengles/sdk/docs/man/xhtml/glAttachShader.xml ).
      So we simply concatenate the shaders into one. }
    procedure AttachShader(const ShaderType: TShaderType;
      const Parts: TStrings); overload;

    procedure DetachAllShaders;

    { Specify values to record in transform feedback buffers.
      This must be called before @link(Link) method. }
    procedure SetTransformFeedbackVaryings(const Varyings: array of String;
      const IsSingleBufferMode: Boolean = True);

    { Optional cache for expensive generated programs. The caller's key must
      cover every shader stage and link option. Each load creates an independent
      GL program, so uniforms are never shared between riders/materials. }
    function TryLoadBinaryCache(const Key: String): Boolean;
    procedure SaveBinaryCache(const Key: String);

    { Link the program, this should be done after attaching all shaders
      and before actually using the program.

      @raises(EGLSLProgramLinkError If the program cannot be linked,
        exception message contains precise description from OpenGL where
        the error is.) }
    procedure Link; overload; virtual;
    procedure Link(Ignored: boolean); overload; deprecated 'use parameterless Link method';

    { Enable (use) this program. Shortcut for @code(RenderContext.CurrentProgram := Self). }
    procedure Enable;

    { Disable this program (use the fixed function pipeline).
      Shortcut for @code(RenderContext.CurrentProgram := nil). }
    class procedure Disable;

    { Override this to set uniform values, in particular to
      bind the textures used by this shader, right after each @link(Enable)
      call.

      This is automatically called

      - by our shape rendering
        (when we renders shapes, from TShaderCoordinateRenderer.RenderCoordinateBegin)

      - by our screen effects rendering code
        (from TCastleScreenEffects.RenderOverChildren).

      ... right after the given shader is enabled by
      @code(RenderContext.CurrentProgram := ThisShader),
      which is equivalent to @code(ThisShader.Enable).

      If other cases, it's your responsibility to call this method
      explicitly, if you want shaders using it to work. Do this right after
      @code(RenderContext.CurrentProgram := ThisShader),
      or equivalent @code(ThisShader.Enable).

      You can set any uniform values, and generally do
      anything you want to be done each time this shader is enabled.
      In particular, you can bind textures and set corresponding uniform
      variables of them. Increase BoundTextureUnits appropriately.

      Returns @false is some texture couldn't be bound. }
    function SetupUniforms(var BoundTextureUnits: Cardinal): boolean; virtual;

    { Returns multiline debug info about current program.
      Reports whether shaders are supported,
      names of active uniform and attribute variables etc.

      @raises Exception If any OpenGL error will be detected. }
    function DebugInfo: string;

    { This is program info log, given to you from OpenGL after the program
      is linked. }
    function ProgramInfoLog: string;

    { After the program is linked, you can check this.

      Note that this is necessarily implemented in quite hacky way (by
      looking at ProgramInfoLog), there is no way currently (AFAIK ?)
      to get this information cleanly from OpenGL.
      In case of doubts, we try to "trust" OpenGL to execute shader in hardware.
      Return @false only when we see clear indication in ProgramInfoLog that
      it'll run in software. }
    function RunningInHardware: boolean;

    { What to do when GLSL uniform variable is accessed (by @link(SetUniform)
      or @link(Uniform)) but doesn't exist in the shader.
      Note that OpenGL aggresively removes unused code and variables
      from the shader when compiling/linking, so this also happens for
      "declared but unused" variables.

      This is only the default value, each @link(Uniform) method call
      may explicitly use other TUniformMissing.

      @seealso TUniformMissing }
    property UniformMissing: TUniformMissing
      read FUniformMissing write FUniformMissing
      default umWarning;

    { Get the uniform instance. It can be used to make repeated
      @link(TGLSLUniform.SetValue) calls. You must link the program first.

      If the uniform doesn't exist (or is unused), the action
      we take depends on @link(UniformMissing) property
      (by default -- umWarning).
      The overloaded version with extra @code(AUniformMissing)
      parameter follows this parameter value.

      @groupBegin }
    function Uniform(const AName: string): TGLSLUniform; overload;
    function Uniform(const AName: string; const AUniformMissing: TUniformMissing): TGLSLUniform; overload;
    { @groupEnd }

    { Set appropriate uniform variable value.
      The used type must match the type of this variable in GLSL program.

      OpenGL forces some constraints on using this:

      @unorderedList(
        @item(This should be used only after linking, and re-linking clears
          (sets to zero) all uniform variables values.)

        @item(This GLSL program must be currently enabled for this to work.
          So calling this automatically calls @link(Enable)
          and sets @link(TRenderContext.CurrentProgram RenderContext.CurrentProgram).

          This is required by OpenGL glUniform*
          commands. glGetUniformLocation take program id as parameter, so they
          can operate on any program. But glUniform* operate only on
          active program.)

        @item(Only @italic(active) uniforms variables may be set.
          @italic(Active) means, quoting OpenGL manpages,
          a variable that is determined during the link operation
          that it may be accessed during program execution.
          In other words, when linking GLSL program, unused variables
          may be eliminated, and you cannot set them by SetUniform.

          Call DebugInfo to see what uniform variables are considered
          active for your shader.

          You can change UniformMissing not to silently ignore setting
          of inactive (or not existing) uniform values.)
      )

      This will make warning if the variable is not found within
      the program and UniformMissing = umWarning.
      The overloaded version with explicit AUniformMissing parameter uses that
      to decide whether to show warning.

      @groupBegin }
    procedure SetUniform(const AName: string; const Value: boolean        ; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TGLint         ; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TVector2Integer; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TVector3Integer; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TVector4Integer; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TGLfloat       ; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TVector2 ; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TVector3 ; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TVector4 ; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TMatrix2 ; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TMatrix3 ; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TMatrix4 ; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TBooleanList; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TInt32List  ; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TSingleList ; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TVector2List; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TVector3List; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TVector4List; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TMatrix3List; const AUniformMissing: TUniformMissing); overload;
    procedure SetUniform(const AName: string; const Value: TMatrix4List; const AUniformMissing: TUniformMissing); overload;

    procedure SetUniform(const AName: string; const Value: boolean        ); overload;
    procedure SetUniform(const AName: string; const Value: TGLint         ); overload;
    procedure SetUniform(const AName: string; const Value: TVector2Integer); overload;
    procedure SetUniform(const AName: string; const Value: TVector3Integer); overload;
    procedure SetUniform(const AName: string; const Value: TVector4Integer); overload;
    procedure SetUniform(const AName: string; const Value: TGLfloat       ); overload;
    procedure SetUniform(const AName: string; const Value: TVector2 ); overload;
    procedure SetUniform(const AName: string; const Value: TVector3 ); overload;
    procedure SetUniform(const AName: string; const Value: TVector4 ); overload;
    procedure SetUniform(const AName: string; const Value: TMatrix2 ); overload;
    procedure SetUniform(const AName: string; const Value: TMatrix3 ); overload;
    procedure SetUniform(const AName: string; const Value: TMatrix4 ); overload;
    procedure SetUniform(const AName: string; const Value: TBooleanList); overload;
    procedure SetUniform(const AName: string; const Value: TInt32List  ); overload;
    procedure SetUniform(const AName: string; const Value: TSingleList ); overload;
    procedure SetUniform(const AName: string; const Value: TVector2List); overload;
    procedure SetUniform(const AName: string; const Value: TVector3List); overload;
    procedure SetUniform(const AName: string; const Value: TVector4List); overload;
    procedure SetUniform(const AName: string; const Value: TMatrix3List); overload;
    procedure SetUniform(const AName: string; const Value: TMatrix4List); overload;
    { @groupEnd }

    { Get the attribute instance. It can be used to make repeated
      @link(TGLSLAttribute.SetValue) and @link(TGLSLAttribute.EnableArray).

      @raises(EGLSLAttributeNotFound If the variable is not found within
        the program.

        Note that this is only one of the many things that can
        go wrong. And on most cases we don't raise any error,
        instead OpenGL sets it's error state and you probably want to
        call CheckGLErrors from time to time to catch them.) }
    function Attribute(const AName: string): TGLSLAttribute;

    { Get the attribute instance. It can be used to make repeated
      @link(TGLSLAttribute.SetValue) and @link(TGLSLAttribute.EnableArray).

      Returned attribute has @link(TGLSLAttribute.Location) equal to GLAttribLocationNone.
      All the calls to @link(TGLSLAttribute.SetValue)
      or @link(TGLSLAttribute.EnableArray) or @link(TGLSLAttribute.DisableArray)
      methods are silently ignored. }
    function AttributeOptional(const AName: string): TGLSLAttribute;

    { Report an unused external attribute once per linked program. }
    procedure WarnMissingAttribute(const AName: string);

    { Set attribute variable value.
      The used type must match the type of this variable in GLSL program.

      OpenGL forces some constraints on using this, see SetUniform.
      In short: use this only after linking the program.
      The program is automatically enabled (set as @link(TRenderContext.CurrentProgram RenderContext.CurrentProgram)) by this.
      And note that attributes declared but not actually used in shader code
      may be eliminated, use DebugInfo to see which attributes are actually
      used (@italic(active) in OpenGL terminology).

      These should not be often used. Usually, you should rather load
      attribute arrays, by VertexAttribPointer. You should also get attribute
      by the @link(Attribute) method, as TGLSLAttribute, and then call
      @link(TGLSLAttribute.SetValue) or @link(TGLSLAttribute.EnableArray).

      @raises(EGLSLAttributeNotFound If the variable is not found within
        the program.

        Note that this is only one of the many things that can
        go wrong. And on most cases we don't raise any error,
        instead OpenGL sets it's error state and you probably want to
        call CheckGLErrors from time to time to catch them.)

      @groupBegin }
    procedure SetAttribute(const AName: string; const Value: TGLfloat); overload; deprecated 'use TGLSLAttribute.SetValue';
    procedure SetAttribute(const AName: string; const Value: TVector2); overload; deprecated 'use TGLSLAttribute.SetValue';
    procedure SetAttribute(const AName: string; const Value: TVector3); overload; deprecated 'use TGLSLAttribute.SetValue';
    procedure SetAttribute(const AName: string; const Value: TVector4); overload; deprecated 'use TGLSLAttribute.SetValue';
    procedure SetAttribute(const AName: string; const Value: TMatrix3); overload; deprecated 'use TGLSLAttribute.SetValue';
    procedure SetAttribute(const AName: string; const Value: TMatrix4); overload; deprecated 'use TGLSLAttribute.SetValue';
    {$ifndef OpenGLES}
    procedure SetAttribute(const AName: string; const Value: TVector4Integer); overload; deprecated 'use TGLSLAttribute.SetValue';
    procedure SetAttribute(const AName: string; const Value: TVector4Byte); overload; deprecated 'use TGLSLAttribute.SetValue';
    procedure SetAttribute(const AName: string; const Value: TGLdouble); overload; deprecated 'use TGLSLAttribute.SetValue';
    // Makes FPC errors: Error: Asm: Duplicate label, see https://bugs.freepascal.org/view.php?id=32188
    // procedure SetAttribute(const AName: string; const Value: TVector2Double); deprecated 'use TGLSLAttribute.SetValue';
    // procedure SetAttribute(const AName: string; const Value: TVector3Double); deprecated 'use TGLSLAttribute.SetValue';
    // procedure SetAttribute(const AName: string; const Value: TVector4Double); deprecated 'use TGLSLAttribute.SetValue';
    {$endif}
    { @groupEnd }

    {$ifdef FPC}
    { Currently enabled GLSL program.
      @nil if fixed-function pipeline should be used.
      Setting this property encapsulates the OpenGL glUseProgram
      (or equivalent ARB extension), additionally preventing redundant glUseProgram
      calls. }
    class property Current: TGLSLProgram read GetCurrent write SetCurrent; deprecated 'use RenderContext.CurrentProgram';
    {$endif}
    { REZVIVO: process counters for explicit diagnostics / regression probes.
      No per-frame logging and no shared GL program or uniform state. }
    class var BinaryCacheHits, BinaryCacheMisses, BinaryCacheStores: QWord;
  end;

  TGLSLProgramList = {$ifdef FPC}specialize{$endif} TObjectList<TGLSLProgram>;

var
  LogShaders: boolean;
  { Diagnostic switch. GLSL identifiers and shader fingerprints are compared
    exactly, not with the user's language-dependent collation rules. }
  UseProgramUniformCache: Boolean = True;
  ProgramUniformUploads, ProgramUniformSkips: QWord;
  UseBinaryShaderNames: Boolean = True;

{ Configure internal shader-name lists; changing the diagnostic mode also
  restores the correct sort order before binary search. }
procedure ConfigureShaderNameList(const Names: TStringList);

{$ifdef FPC}
function GetCurrentProgram: TGLSLProgram;
  deprecated 'use RenderContext.CurrentProgram';
procedure SetCurrentProgram(const Value: TGLSLProgram);
  deprecated 'use RenderContext.CurrentProgram';

{ Currently enabled GLSL program.
  @nil if fixed-function pipeline should be used.
  Setting this property encapsulates the OpenGL glUseProgram
  (or equivalent ARB extension), additionally preventing redundant glUseProgram
  calls.

  @deprecated Use RenderContext.CurrentProgram }
property CurrentProgram: TGLSLProgram
  read GetCurrentProgram write SetCurrentProgram;
{$endif FPC}

{ Used by RenderContext.SetCurrentProgram. @exclude }
procedure InternalSetCurrentProgram(const Value: TGLSLProgram);

var
  { By default, TGLSLProgram automatically adds a #version and a few macros
    to make GLSL shader code use a modern version, with only modern (not deprecated)
    GLSL features.

    Set this to @false to disable it -- useful to test
    that shaders also work fine on older OpenGL(ES) versions than what you have.
    Note that resulting shaders may not work in OpenGL "core" profile (only compatibility)
    and some features (like shadow samplers on OpenGLES) may be missing.

    @exclude }
  InternalUpgradeGlslVersion: Boolean = true;

{ Signature of the actual built-in GLSL headers, for binary cache invalidation. }
function GLSLCacheHeaderSignature: String;

implementation

uses CastleStringUtils, CastleLog, CastleGLVersion, CastleRenderContext,
  CastleInternalGLUtils, CastleApplicationProperties
  {$if defined(FPC) and not defined(OpenGLES)}, MD5{$endif};

const
  {$ifdef OpenGLES}
  GLES30CoreHeader: array [TShaderType] of String = (
    // vertex
    '#version 300 es' + NL +
    '#define CASTLE_GLSL_VERSION_UPGRADE' + NL +
    '#define attribute in' + NL +
    '#define varying out' + NL +
    '#define texture2D texture' + NL +
    '#define texture3D texture' + NL +
    '#define textureCube texture' + NL +
    '#define texture2DProj textureProj' + NL +
    '#define texture3DProj textureProj' + NL +
    { Otherwise each sampler2DShadow would have to contain precision specifier.
      EXT_shadow_samplers says that lowp is default, so presumably it is OK:
      https://registry.khronos.org/OpenGL/extensions/EXT/EXT_shadow_samplers.txt }
    'precision lowp sampler2DShadow;' + NL +
    { Otherwise each sampler3D would have to contain precision specifier.
      3D textures are part of OpenGLES 3.0 core, so it's OK to use sampler3D here.
      Testcase that this is needed: castle-model-viewer, compiled with OpenGLES,
      viewing demo-models/water/caustics/Barna29.x3dv . }
    'precision lowp sampler3D;' + NL,

    // geometry - not supported by OpenGLES
    '#define CASTLE_GLSL_VERSION_UPGRADE' + NL,

    // fragment
    '#version 300 es' + NL +
    '#define CASTLE_GLSL_VERSION_UPGRADE' + NL +
    '#define varying in' + NL +
    '#define texture2D texture' + NL +
    '#define texture3D texture' + NL +
    '#define textureCube texture' + NL +
    '#define texture2DProj textureProj' + NL +
    '#define texture3DProj textureProj' + NL +
    '#define gl_FragColor castle_FragColor' + NL +
    'out mediump vec4 castle_FragColor;' + NL +
    { We need to use highp for shadow maps processing on mobile,
      to make the shadows look good,
      see https://github.com/castle-engine/castle-engine/pull/674 }
    '#define shadowsPrecision highp' + NL +
    'precision lowp sampler2DShadow;' + NL +
    'precision lowp sampler3D;' + NL
  );
  {$else}
  GL31CoreHeader: array [TShaderType] of String = (
    // vertex
    '#version 140' + NL +
    '#define CASTLE_GLSL_VERSION_UPGRADE' + NL +
    '#define attribute in' + NL +
    '#define varying out' + NL +
    '#define texture2D texture' + NL +
    '#define texture3D texture' + NL +
    '#define textureCube texture' + NL +
    '#define texture2DProj textureProj' + NL +
    '#define texture3DProj textureProj' + NL,

    // geometry
    '#version 150' + NL +
    '#define CASTLE_GLSL_VERSION_UPGRADE' + NL,

    // fragment
    '#version 140' + NL +
    '#define CASTLE_GLSL_VERSION_UPGRADE' + NL +
    '#define varying in' + NL +
    '#define texture2D texture' + NL +
    '#define texture3D texture' + NL +
    '#define textureCube texture' + NL +
    '#define texture2DProj textureProj' + NL +
    '#define texture3DProj textureProj' + NL +
    '#define gl_FragColor castle_FragColor' + NL +
    'out mediump vec4 castle_FragColor;' + NL +
    '#define shadowsPrecision' + NL
  );
  {$endif}


{$if defined(FPC) and not defined(OpenGLES)}
type
  TProgramBinaryHeader = packed record
    Magic, BinaryFormat, DataLength: UInt32;
    Digest: TMD5Digest;
  end;

function ProgramBinaryFile(const Key: String): String;
var Driver, Directory: String;
begin
  Driver := String(PAnsiChar(glGetString(GL_VENDOR))) + #0 +
    String(PAnsiChar(glGetString(GL_RENDERER))) + #0 +
    String(PAnsiChar(glGetString(GL_VERSION))) + #0 +
    String(PAnsiChar(glGetString(GL_SHADING_LANGUAGE_VERSION)));
  Directory := GetEnvironmentVariable('REZVIVO_TEST_SHADER_CACHE_DIR');
  if Directory = '' then
    Directory := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'shader-cache';
  Result := IncludeTrailingPathDelimiter(Directory) +
    MD5Print(MD5String(Driver + #0 + Key)) + '.gpb';
end;

function ProgramBinarySupported: Boolean;
var Count: GLint;
begin
  Result := (GL_VERSION_4_1 or GL_ARB_get_program_binary) and
    Assigned(glProgramBinary) and Assigned(glGetProgramBinary) and
    Assigned(glProgramParameteri) and (GetEnvironmentVariable('REZVIVO_SHADER_CACHE') <> '0');
  if not Result then Exit;
  Count := 0;
  glGetIntegerv(GL_NUM_PROGRAM_BINARY_FORMATS, @Count);
  Result := Count > 0;
end;

procedure TrimProgramBinaryCache(const Directory: String);
const Budget = 256 * 1024 * 1024;
var Search: TSearchRec; Total: Int64; Oldest: LongInt; OldestFile: String;
begin
  { Only disposable shader binaries in this directory. Bound growth across
    edited shaders and driver upgrades; never touch configuration files. }
  repeat
    Total := 0; Oldest := High(LongInt); OldestFile := '';
    if FindFirst(Directory + '*.gpb', faAnyFile, Search) = 0 then
    begin
      repeat
        if (Search.Attr and faDirectory) <> 0 then Continue;
        Inc(Total, Search.Size);
        if Search.Time <= Oldest then
        begin Oldest := Search.Time; OldestFile := Directory + Search.Name; end;
      until FindNext(Search) <> 0;
      FindClose(Search);
    end;
    if (Total <= Budget) or (OldestFile = '') then Break;
    if not DeleteFile(OldestFile) then Break;
  until False;
end;
{$endif}

function GLSLCacheHeaderSignature: String;
{$if defined(FPC) and not defined(OpenGLES)}
var ShaderType: TShaderType;
{$endif}
begin
  Result := '';
  {$if defined(FPC) and not defined(OpenGLES)}
  for ShaderType := Low(TShaderType) to High(TShaderType) do
    Result := Result + ':' + MD5Print(MD5String(GL31CoreHeader[ShaderType]));
  {$endif}
end;

function TGLSLProgram.TryLoadBinaryCache(const Key: String): Boolean;
{$if defined(FPC) and not defined(OpenGLES)}
var Stream: TFileStream; H: TProgramBinaryHeader; Data: array of Byte;
  Linked, Count, I: GLint; FileName: String; Formats: array of GLint;
  FormatSupported: Boolean;
  Started, ReadStarted, PrepareMs: QWord;
{$endif}
begin
  Result := False;
  {$if defined(FPC) and not defined(OpenGLES)}
  FSaveBinaryRequested := (Key <> '') and ProgramBinarySupported;
  if not FSaveBinaryRequested then Exit;
  Inc(BinaryCacheMisses);
  FileName := ProgramBinaryFile(Key);
  if not FileExists(FileName) then Exit;
  ReadStarted := GetTickCount64;
  try
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if Stream.Size < SizeOf(H) then Exit;
      Stream.ReadBuffer(H, SizeOf(H));
      if (H.Magic <> $31425047) or (H.DataLength = 0) or
         (H.DataLength > 32 * 1024 * 1024) or
         (Stream.Size <> SizeOf(H) + Int64(H.DataLength)) then Exit;
      SetLength(Data, H.DataLength);
      Stream.ReadBuffer(Data[0], H.DataLength);
      if not MD5Match(H.Digest, MD5Buffer(Data[0], H.DataLength)) then Exit;
    finally Stream.Free; end;
    glGetIntegerv(GL_NUM_PROGRAM_BINARY_FORMATS, @Count);
    if (Count < 1) or (Count > 128) then Exit;
    SetLength(Formats, Count);
    glGetIntegerv(GL_PROGRAM_BINARY_FORMATS, @Formats[0]);
    FormatSupported := False;
    for I := 0 to Count - 1 do
      if UInt32(Formats[I]) = H.BinaryFormat then FormatSupported := True;
    if not FormatSupported then Exit;
    PrepareMs := GetTickCount64 - ReadStarted;
    if PrepareMs > 100 then
      WritelnLog('ResourcePrepare', 'stage=program_binary_read ms=%d bytes=%d name="%s"',
        [PrepareMs, H.DataLength, Name]);
    Started := GetTickCount64;
    glProgramParameteri(ProgramId, GL_PROGRAM_BINARY_RETRIEVABLE_HINT, GL_TRUE);
    glProgramBinary(ProgramId, H.BinaryFormat, @Data[0], H.DataLength);
    glGetProgramiv(ProgramId, GL_LINK_STATUS, @Linked);
    Result := Linked = GL_TRUE;
    if Result then begin Inc(BinaryCacheHits); Dec(BinaryCacheMisses); end;
    PrepareMs := GetTickCount64 - Started;
    if PrepareMs > 100 then
      WritelnLog('ResourcePrepare', 'stage=program_binary_load ms=%d bytes=%d format=%d ok=%s name="%s"',
        [PrepareMs, H.DataLength, H.BinaryFormat, BoolToStr(Result, true), Name]);
    if LogShaders and Result then WritelnLog('GLSL binary cache',
      'Loaded %s (%d ms)', [Name, GetTickCount64 - Started]);
  except
    { Cache permissions/corruption cannot prevent a normal source compile. }
    Result := False;
  end;
  {$endif}
end;

procedure TGLSLProgram.SaveBinaryCache(const Key: String);
{$if defined(FPC) and not defined(OpenGLES)}
var Stream: TFileStream; H: TProgramBinaryHeader; Data: array of Byte;
  Size, Actual: GLint; FileName, TempName: String;
{$endif}
begin
  {$if defined(FPC) and not defined(OpenGLES)}
  if (Key = '') or not ProgramBinarySupported then Exit;
  TempName := '';
  try
    glGetProgramiv(ProgramId, GL_PROGRAM_BINARY_LENGTH, @Size);
    if GetEnvironmentVariable('REZVIVO_SHADER_DIAGNOSTICS') = '1' then
      WritelnLog('ShaderBinaryProbe', 'bytes=%d name="%s"', [Size, Name]);
    if (Size <= 0) or (Size > 32 * 1024 * 1024) then Exit;
    SetLength(Data, Size);
    glGetProgramBinary(ProgramId, Size, @Actual, @H.BinaryFormat, @Data[0]);
    if (Actual <= 0) or (Actual > Size) then Exit;
    H.Magic := $31425047; H.DataLength := Actual;
    H.Digest := MD5Buffer(Data[0], Actual);
    FileName := ProgramBinaryFile(Key);
    if not ForceDirectories(ExtractFilePath(FileName)) then Exit;
    TempName := FileName + '.' + IntToStr(GetProcessID) + '.tmp';
    Stream := TFileStream.Create(TempName, fmCreate);
    try
      Stream.WriteBuffer(H, SizeOf(H));
      Stream.WriteBuffer(Data[0], Actual);
    finally Stream.Free; end;
    if FileExists(FileName) then DeleteFile(FileName);
    if RenameFile(TempName, FileName) then Inc(BinaryCacheStores);
    TrimProgramBinaryCache(ExtractFilePath(FileName));
    if LogShaders then WritelnLog('GLSL binary cache', 'Saved ' + Name);
  except
    { Disk cache is optional. }
  end;
  if TempName <> '' then DeleteFile(TempName);
  {$endif}
end;

{ Wrapper around glGetShaderInfoLog. }
function GetShaderInfoLog(const ShaderId: TGLShader): String;
{$ifdef CASTLE_WEBGL}
begin
  Result := glGetShaderInfoLog(ShaderId);
{$else}
{ OpenGL version based on Dean Ellis BasicShader.dpr
  (with some changes, e.g. fixed ? <> 0 not > 1, adjusted to both FPC / Delphi
  and our CastleGL header). }
var
  Len, Len2: TGLint;
{$ifndef FPC}
  AnsiResult: AnsiString;
{$endif}
begin
  glGetShaderiv(ShaderId, GL_INFO_LOG_LENGTH, @Len);

  if Len <> 0 then
  begin
    {$ifdef FPC}
      SetLength(Result, Len);
      glGetShaderInfoLog(ShaderId, Len, @Len2, PChar(Result));
    {$else}
      SetLength(AnsiResult, Len);
      glGetShaderInfoLog(ShaderId, Len, @Len2, PAnsiChar(AnsiResult));
      Result := String(AnsiResult);
    {$endif}
    StringReplaceAllVar(Result, #0, NL);
  end else
    Result := '';
{$endif}
end;

{ Wrapper around glGetProgramInfoLog. }
function GetProgramInfoLog(const ProgramId: TGLProgram): String;
{$ifdef CASTLE_WEBGL}
begin
  Result := glGetProgramInfoLog(ProgramId);
{$else}
var
  Len, Len2: TGLint;
{$ifndef FPC}
  AnsiResult: AnsiString;
{$endif}
begin
  glGetProgramiv(ProgramId, GL_INFO_LOG_LENGTH, @Len);

  if Len <> 0 then
  begin
    {$ifdef FPC}
      SetLength(Result, Len);
      glGetProgramInfoLog(ProgramId, Len, @Len2, PChar(Result));
    {$else}
      SetLength(AnsiResult, Len);
      glGetProgramInfoLog(ProgramId, Len, @Len2, PAnsiChar(AnsiResult));
      Result := String(AnsiResult);
    {$endif}
    StringReplaceAllVar(Result, #0, NL);
  end else
    Result := '';
{$endif}
end;

function GetCurrentProgram: TGLSLProgram;
begin
  Result := RenderContext.CurrentProgram;
end;

procedure SetCurrentProgram(const Value: TGLSLProgram);
begin
  RenderContext.CurrentProgram := Value;
end;

procedure InternalSetCurrentProgram(const Value: TGLSLProgram);
begin
  if Value <> nil then
  begin
    if Value.ProgramId = GLObjectNone then
    begin
      WritelnWarning('Trying to use a GLSL shader after the OpenGL context for which it was prepared closed; you have to create new TGLSLProgram instance');
      glUseProgram(GLObjectNone);
      Exit;
    end;
    if GLFeatures.Shaders then
      glUseProgram(Value.ProgramId);
  end else
  begin
    if GLFeatures.Shaders then
      glUseProgram(GLObjectNone);
  end;
end;

{ TGLSLUniform --------------------------------------------------------------- }

class function TGLSLUniform.NotExisting: TGLSLUniform; {$ifdef FPC} static;{$endif}
const
  R: TGLSLUniform = (Owner: nil; Name: ''; Location: GLUniformLocationNone);
begin
  Result := R;
end;

procedure TGLSLUniform.SetValue(const Value: boolean);
begin
  SetValue(TGLint(Ord(Value)));
end;

procedure TGLSLUniform.SetValue(const Value: TGLint);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.Enable;
  {$ifndef CASTLE_WEBGL}
  if GLFeatures.Shaders and
     not Owner.UploadUniformValue(Location, Value, SizeOf(Value), 1) then Exit;
  {$endif}
  if GLFeatures.Shaders then
    glUniform1i(Location, Value);
end;

procedure TGLSLUniform.SetValue(const Value: TVector2Integer);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.Enable;
  {$ifndef CASTLE_WEBGL}
  if GLFeatures.Shaders and
     not Owner.UploadUniformValue(Location, Value, SizeOf(Value), 1) then Exit;
  {$endif}
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniform2i(Location, Value[0], Value[1]);
    {$else}
    glUniform2iv(Location, 1, @Value);
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TVector3Integer);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.Enable;
  {$ifndef CASTLE_WEBGL}
  if GLFeatures.Shaders and
     not Owner.UploadUniformValue(Location, Value, SizeOf(Value), 1) then Exit;
  {$endif}
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniform3i(Location, Value[0], Value[1], Value[2]);
    {$else}
    glUniform3iv(Location, 1, @Value);
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TVector4Integer);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.Enable;
  {$ifndef CASTLE_WEBGL}
  if GLFeatures.Shaders and
     not Owner.UploadUniformValue(Location, Value, SizeOf(Value), 1) then Exit;
  {$endif}
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniform4i(Location, Value[0], Value[1], Value[2], Value[3]);
    {$else}
    glUniform4iv(Location, 1, @Value);
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TGLfloat);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.Enable;
  {$ifndef CASTLE_WEBGL}
  if GLFeatures.Shaders and
     not Owner.UploadUniformValue(Location, Value, SizeOf(Value), 2) then Exit;
  {$endif}
  if GLFeatures.Shaders then
    glUniform1f(Location, Value);
end;

procedure TGLSLUniform.SetValue(const Value: TVector2);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.Enable;
  {$ifndef CASTLE_WEBGL}
  if GLFeatures.Shaders and
     not Owner.UploadUniformValue(Location, Value, SizeOf(Value), 2) then Exit;
  {$endif}
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniform2f(Location, Value[0], Value[1]);
    {$else}
    glUniform2fv(Location, 1, @Value);
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TVector3);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.Enable;
  {$ifndef CASTLE_WEBGL}
  if GLFeatures.Shaders and
     not Owner.UploadUniformValue(Location, Value, SizeOf(Value), 2) then Exit;
  {$endif}
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniform3f(Location, Value[0], Value[1], Value[2]);
    {$else}
    glUniform3fv(Location, 1, @Value);
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TVector4);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.Enable;
  {$ifndef CASTLE_WEBGL}
  if GLFeatures.Shaders and
     not Owner.UploadUniformValue(Location, Value, SizeOf(Value), 2) then Exit;
  {$endif}
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniform4f(Location, Value[0], Value[1], Value[2], Value[3]);
    {$else}
    glUniform4fv(Location, 1, @Value);
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TMatrix2);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.Enable;
  {$ifndef CASTLE_WEBGL}
  if GLFeatures.Shaders and
     not Owner.UploadUniformValue(Location, Value, SizeOf(Value), 3) then Exit;
  {$endif}
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniformMatrix2fv(Location, GL_FALSE, MatrixToWebGL(Value), 0, 0);
    {$else}
    glUniformMatrix2fv(Location, 1, GL_FALSE, @Value);
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TMatrix3);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.Enable;
  {$ifndef CASTLE_WEBGL}
  if GLFeatures.Shaders and
     not Owner.UploadUniformValue(Location, Value, SizeOf(Value), 3) then Exit;
  {$endif}
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniformMatrix3fv(Location, GL_FALSE, MatrixToWebGL(Value), 0, 0);
    {$else}
    glUniformMatrix3fv(Location, 1, GL_FALSE, @Value);
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TMatrix4);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.Enable;
  {$ifndef CASTLE_WEBGL}
  if GLFeatures.Shaders and
     not Owner.UploadUniformValue(Location, Value, SizeOf(Value), 3) then Exit;
  {$endif}
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniformMatrix4fv(Location, GL_FALSE, MatrixToWebGL(Value), 0, 0);
    {$else}
    glUniformMatrix4fv(Location, 1, GL_FALSE, @Value);
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TBooleanList);
var
  Ints: TInt32List;
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here

  { We cannot pass Value.List, as Pascal booleans do not have 4 bytes
    (well, actually I could change this by compiler directive or
    by using LongBool for TBooleanList --- but for TBooleanList
    this would enlarge it 4 times, not nice).

    Unfortunately, there's no glUniform*ub (unsigned byte) or such function.

    So convert to 32 ints. }
  Ints := Value.ToInt32;
  try
    SetValue(Ints);
  finally FreeAndNil(Ints) end;
end;

procedure TGLSLUniform.SetValue(const Value: TInt32List);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Assert(SizeOf(Int32) = SizeOf(TGLint));
  Owner.InvalidateUniformValues;
  Owner.Enable;
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniform1iv(Location, ListToWebGL(Value), 0, 0);
    {$else}
    glUniform1iv(Location, Value.Count, PGLInt(Value.L));
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TSingleList);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.InvalidateUniformValues;
  Owner.Enable;
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniform1fv(Location, ListToWebGL(Value), 0, 0);
    {$else}
    glUniform1fv(Location, Value.Count, PGLfloat(Value.L));
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TVector2List);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.InvalidateUniformValues;
  Owner.Enable;
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniform2fv(Location, ListToWebGL(Value), 0, 0);
    {$else}
    glUniform2fv(Location, Value.Count, PGLfloat(Value.L));
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TVector3List);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.InvalidateUniformValues;
  Owner.Enable;
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniform3fv(Location, ListToWebGL(Value), 0, 0);
    {$else}
    glUniform3fv(Location, Value.Count, PGLfloat(Value.L));
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TVector4List);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.InvalidateUniformValues;
  Owner.Enable;
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniform4fv(Location, ListToWebGL(Value), 0, 0);
    {$else}
    glUniform4fv(Location, Value.Count, PGLfloat(Value.L));
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TMatrix3List);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.InvalidateUniformValues;
  Owner.Enable;
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniformMatrix3fv(Location, GL_FALSE, ListToWebGL(Value), 0, 0);
    {$else}
    glUniformMatrix3fv(Location, Value.Count, GL_FALSE, PGLfloat(Value.L));
    {$endif}
end;

procedure TGLSLUniform.SetValue(const Value: TMatrix4List);
begin
  if Location = GLUniformLocationNone then Exit; // ignore non-existing uniform here
  Owner.InvalidateUniformValues;
  Owner.Enable;
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glUniformMatrix4fv(Location, GL_FALSE, ListToWebGL(Value), 0, 0);
    {$else}
    glUniformMatrix4fv(Location, Value.Count, GL_FALSE, PGLfloat(Value.L));
    {$endif}
end;

{ TGLSLAttribute ------------------------------------------------------------- }

procedure TGLSLAttribute.SetValue(const Value: TGLfloat);
begin
  if Location = GLAttribLocationNone then Exit; // ignore non-existing attribute here
  Owner.Enable;
  if GLFeatures.Shaders then
    glVertexAttrib1f(Location, Value);
end;

procedure TGLSLAttribute.SetValue(const Value: TVector2);
begin
  if Location = GLAttribLocationNone then Exit; // ignore non-existing attribute here
  Owner.Enable;
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glVertexAttrib2f(Location, Value[0], Value[1]);
    {$else}
    glVertexAttrib2fv(Location, @Value);
    {$endif}
end;

procedure TGLSLAttribute.SetValue(const Value: TVector3);
begin
  if Location = GLAttribLocationNone then Exit; // ignore non-existing attribute here
  Owner.Enable;
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glVertexAttrib3f(Location, Value[0], Value[1], Value[2]);
    {$else}
    glVertexAttrib3fv(Location, @Value);
    {$endif}
end;

procedure TGLSLAttribute.SetValue(const Value: TVector4);
begin
  if Location = GLAttribLocationNone then Exit; // ignore non-existing attribute here
  Owner.Enable;
  if GLFeatures.Shaders then
    {$ifdef CASTLE_WEBGL}
    glVertexAttrib4f(Location, Value[0], Value[1], Value[2], Value[3]);
    {$else}
    glVertexAttrib4fv(Location, @Value);
    {$endif}
end;

procedure TGLSLAttribute.SetValue(const Value: TMatrix3);

  procedure SetColumn(const Column: Integer; const Value: TMatrix3.TIndexArray);
  begin
    {$ifdef CASTLE_WEBGL}
    glVertexAttrib3f(Location + Column, Value[0], Value[1], Value[2]);
    {$else}
    glVertexAttrib3fv(Location + Column, @Value);
    {$endif}
  end;

begin
  if Location = GLAttribLocationNone then Exit; // ignore non-existing attribute here
  Owner.Enable;
  if GLFeatures.Shaders then
  begin
    SetColumn(0, Value.Data[0]);
    SetColumn(1, Value.Data[1]);
    SetColumn(2, Value.Data[2]);
  end;
end;

procedure TGLSLAttribute.SetValue(const Value: TMatrix4);

  procedure SetColumn(const Column: Integer; const Value: TMatrix4.TIndexArray);
  begin
    {$ifdef CASTLE_WEBGL}
    glVertexAttrib4f(Location + Column, Value[0], Value[1], Value[2], Value[3]);
    {$else}
    glVertexAttrib4fv(Location + Column, @Value);
    {$endif}
  end;

begin
  if Location = GLAttribLocationNone then Exit; // ignore non-existing attribute here
  Owner.Enable;
  if GLFeatures.Shaders then
  begin
    SetColumn(0, Value.Data[0]);
    SetColumn(1, Value.Data[1]);
    SetColumn(2, Value.Data[2]);
    SetColumn(3, Value.Data[3]);
  end;
end;

{$ifndef OpenGLES}
procedure TGLSLAttribute.SetValue(const Value: TVector4Integer);
begin
  if Location = GLAttribLocationNone then Exit; // ignore non-existing attribute here
  Owner.Enable;
  if GLFeatures.Shaders then
    glVertexAttrib4iv(Location, @Value);
end;

procedure TGLSLAttribute.SetValue(const Value: TVector4Byte);
begin
  if Location = GLAttribLocationNone then Exit; // ignore non-existing attribute here
  Owner.Enable;
  if GLFeatures.Shaders then
    glVertexAttrib4ubv(Location, @Value);
end;

procedure TGLSLAttribute.SetValue(const Value: TGLdouble);
begin
  if Location = GLAttribLocationNone then Exit; // ignore non-existing attribute here
  Owner.Enable;
  if GLFeatures.Shaders then
    glVertexAttrib1d(Location, Value);
end;

// Makes FPC errors: Error: Asm: Duplicate label, see https://bugs.freepascal.org/view.php?id=32188
{
procedure TGLSLAttribute.SetValue(const Value: TVector2Double);
begin
  if Location = GLAttribLocationNone then Exit; // ignore non-existing attribute here
  Owner.Enable;
  if GLFeatures.Shaders then
    glVertexAttrib2dv(Location, @Value);
end;

procedure TGLSLAttribute.SetValue(const Value: TVector3Double);
begin
  if Location = GLAttribLocationNone then Exit; // ignore non-existing attribute here
  Owner.Enable;
  if GLFeatures.Shaders then
    glVertexAttrib3dv(Location, @Value);
end;

procedure TGLSLAttribute.SetValue(const Value: TVector4Double);
begin
  if Location = GLAttribLocationNone then Exit; // ignore non-existing attribute here
  Owner.Enable;
  if GLFeatures.Shaders then
    glVertexAttrib4dv(Location, @Value);
end;
}
{$endif}

procedure TGLSLAttribute.EnableArray(const Vao: TVertexArrayObject;
  const LocationOffset: TLocationOffset;
  const Size: TGLint; const AType: TGLenum; const Normalized: TGLboolean; const Stride: TGLsizei;
  const Ptr: PtrUInt);
begin
  if Location = GLAttribLocationNone then Exit; // ignore non-existing attribute here
  if GLFeatures.Shaders then
  begin
    RenderContext.CurrentVao := Vao;
    RenderContext.CurrentProgram := Owner;

    LocationOffsetsToDisable[LocationOffset] := true;
    glEnableVertexAttribArray(Location + LocationOffset);
    glVertexAttribPointer    (Location + LocationOffset, Size, AType,
      Normalized, Stride, {$ifndef CASTLE_WEBGL} Pointer {$endif} (Ptr));
  end;
end;

procedure TGLSLAttribute.EnableArraySingle(const Vao: TVertexArrayObject;
  const Stride: TGLsizei; const Ptr: PtrUInt);
begin
  EnableArray(Vao, 0, 1, GL_FLOAT, GL_FALSE, Stride, Ptr);
end;

procedure TGLSLAttribute.EnableArrayVector2(const Vao: TVertexArrayObject;
  const Stride: TGLsizei; const Ptr: PtrUInt);
begin
  EnableArray(Vao, 0, 2, GL_FLOAT, GL_FALSE, Stride, Ptr);
end;

procedure TGLSLAttribute.EnableArrayVector3(const Vao: TVertexArrayObject;
  const Stride: TGLsizei; const Ptr: PtrUInt);
begin
  EnableArray(Vao, 0, 3, GL_FLOAT, GL_FALSE, Stride, Ptr);
end;

procedure TGLSLAttribute.EnableArrayVector4(const Vao: TVertexArrayObject;
  const Stride: TGLsizei; const Ptr: PtrUInt);
begin
  EnableArray(Vao, 0, 4, GL_FLOAT, GL_FALSE, Stride, Ptr);
end;

procedure TGLSLAttribute.EnableArrayMatrix3(const Vao: TVertexArrayObject;
  const Stride: TGLsizei; const Ptr: PtrUInt);
begin
  EnableArray(Vao, 0, 3, GL_FLOAT, GL_FALSE, Stride, Ptr);
  EnableArray(Vao, 1, 3, GL_FLOAT, GL_FALSE, Stride, Ptr + SizeOf(TVector3));
  EnableArray(Vao, 2, 3, GL_FLOAT, GL_FALSE, Stride, Ptr + SizeOf(TVector3) * 2);
end;

procedure TGLSLAttribute.EnableArrayMatrix4(const Vao: TVertexArrayObject;
  const Stride: TGLsizei; const Ptr: PtrUInt);
begin
  EnableArray(Vao, 0, 4, GL_FLOAT, GL_FALSE, Stride, Ptr);
  EnableArray(Vao, 1, 4, GL_FLOAT, GL_FALSE, Stride, Ptr + SizeOf(TVector4));
  EnableArray(Vao, 2, 4, GL_FLOAT, GL_FALSE, Stride, Ptr + SizeOf(TVector4) * 2);
  EnableArray(Vao, 3, 4, GL_FLOAT, GL_FALSE, Stride, Ptr + SizeOf(TVector4) * 3);
end;

procedure TGLSLAttribute.DisableArray;
var
  Offset: TLocationOffset;
begin
  if Location = GLAttribLocationNone then Exit; // ignore non-existing attribute here

  if GLFeatures.Shaders then
    for Offset := Low(TLocationOffset) to High(TLocationOffset) do
      if LocationOffsetsToDisable[Offset] then
        glDisableVertexAttribArray(Location + Offset);
end;

{ TGLSLProgram --------------------------------------------------------------- }

procedure TGLSLProgram.InvalidateUniformValues;
begin
  {$ifndef CASTLE_WEBGL}
  { Constant time; array uploads can overlap scalar/element uniform handles. }
  if FUniformValueEpoch = High(QWord) then
  begin
    FillChar(FUniformValueEntries, SizeOf(FUniformValueEntries), 0);
    FUniformValueEpoch := 1;
  end else
    Inc(FUniformValueEpoch);
  {$endif}
end;

{$ifndef CASTLE_WEBGL}
function TGLSLProgram.UploadUniformValue(const Location: TGLint;
  const Value; const Size, Kind: Byte): Boolean;
var
  Index: Cardinal;
begin
  Result := True;
  if not CacheUniformValues then
  begin
    { A caller may temporarily opt out, then opt back in. Writes made while
      disabled must not leave the previous cached value valid. }
    InvalidateUniformValues;
    Exit;
  end;
  if not UseProgramUniformCache then
  begin
    InvalidateUniformValues;
    Inc(ProgramUniformUploads);
    Exit;
  end;
  { Bounded storage even for sparse explicit locations. Hash collisions are
    misses, never false hits. Compare exact bytes, with no tolerance. }
  Index := Cardinal(Location) and High(FUniformValueEntries);
  if (FUniformValueEntries[Index].Epoch = FUniformValueEpoch) and
     (FUniformValueEntries[Index].Size = Size) and
     (FUniformValueEntries[Index].Kind = Kind) and
     (FUniformValueEntries[Index].Location = Location) and
     CompareMem(@FUniformValueEntries[Index].Data, @Value, Size) then
  begin
    Inc(ProgramUniformSkips);
    Exit(False);
  end;
  FUniformValueEntries[Index].Epoch := FUniformValueEpoch;
  FUniformValueEntries[Index].Location := Location;
  FUniformValueEntries[Index].Size := Size;
  FUniformValueEntries[Index].Kind := Kind;
  Move(Value, FUniformValueEntries[Index].Data, Size);
  Inc(ProgramUniformUploads);
end;
{$endif}

constructor TGLSLProgram.Create;
{$ifdef CASTLE_COLLECT_SHADER_SOURCE}
var
  ShaderType: TShaderType;
{$endif CASTLE_COLLECT_SHADER_SOURCE}
begin
  inherited;

  if GLFeatures.Shaders then
    ProgramId := glCreateProgram();

  { Program id = 0 means that an error occurred. glCreateProgram docs say

      "This function returns 0 if an error occurs creating the program object."

    Looking at glGetError, I don't see any error code there.
    So I just have to raise enigmatic error that creating GLSL program failed.
  }

  if ProgramId = GLObjectNone then
    raise EGLSLError.Create('Cannot create GLSL shader program');

  ApplicationProperties.OnGLContextCloseObject.Add({$ifdef FPC}@{$endif}OnGlContextClose);

  ShaderIds := TGLShaderList.Create;

  FUniformMissing := umWarning;

  FUniformLocations := TUniformLocationCache.Create;
  FAttributeLocations := TAttribLocationCache.Create;

  {$ifdef CASTLE_COLLECT_SHADER_SOURCE}
  for ShaderType := Low(TShaderType) to High(TShaderType) do
    FSource[ShaderType] := TStringList.Create;
  {$endif CASTLE_COLLECT_SHADER_SOURCE}
end;

procedure TGLSLProgram.GLContextClose;
begin
  InvalidateUniformValues;
  { This is called from destructor,
    which may be called if exception is raised from constructor,
    so be careful to check here things -- e.g. check that
    ShaderIds was created.

    Note that, if resources have already been freed, we try to not assume
    that GLFeatures is <> nil. So you can free TGLSLProgram even after
    context is closed.
  }

  if ShaderIds <> nil then
    DetachAllShaders;

  { Deleting by glDeleteProgram the shader that is currently used
    (by glUseProgram) is allowed in OpenGL, and it implicitly sets
    the used program to 0. Which is absolutely reasonable.

    We need to make sure that RenderContext knowledge corresponds to the
    OpenGL state. So RenderContext.CurrentProgram must become nil.

    Moreover, RenderContext.CurrentProgram cannot point to non-existing
    object. Again, this means that RenderContext.CurrentProgram must become nil.

    If we would ignore 2 reasons above, we could have error:

    - RenderContext.CurrentProgram containing a dangling pointer,
    - and this pointer could be reused for new TGLSLProgram instance,
    - and then "RenderContext.CurrentProgram := ..."
      would do nothing (because FCurrenProgram = Value in the setter)
    - and the new shader would not become active.
    - Causing OpenGL errors when not setting uniforms, because shader program
      would be unset before callling glSetUniform*.
    - See https://github.com/castle-engine/castle-engine/issues/664
      for 3 testcases that show this problem, compounded with overly
      eager recreation of shaders.

    Note: checking RenderContext <> nil to make sure we do nothing when
    we're doing TGLSLProgram.Destroy after FreeAndNil(RenderContext). }
  if (RenderContext <> nil) and
     (RenderContext.CurrentProgram = Self) then
    RenderContext.CurrentProgram := nil;

  if ProgramId <> GLObjectNone then
  begin
    { ProgramId can be non-zero only if GLFeatures.Shaders,
      and right now GLFeatures must be <> nil because we must free while
      GL context is available. }
    Assert(GLFeatures.Shaders);
    glDeleteProgram(ProgramId);
    ProgramId := GLObjectNone;
  end;

  if FUniformLocations <> nil then
    FUniformLocations.Clear;
  if FAttributeLocations <> nil then
    FAttributeLocations.Clear;

  {$ifdef CASTLE_CANNOT_CATCH_EXCEPTIONS}
  ErrorOnCompileLink := false;
  {$endif}
end;

procedure TGLSLProgram.OnGlContextClose(Sender: TObject);
begin
  GLContextClose;
end;

destructor TGLSLProgram.Destroy;
{$ifdef CASTLE_COLLECT_SHADER_SOURCE}
var
  ShaderType: TShaderType;
{$endif CASTLE_COLLECT_SHADER_SOURCE}
begin
  ApplicationProperties.OnGLContextCloseObject.Remove({$ifdef FPC}@{$endif}OnGlContextClose);
  GLContextClose;

  {$ifdef CASTLE_COLLECT_SHADER_SOURCE}
  for ShaderType := Low(TShaderType) to High(TShaderType) do
    FreeAndNil(FSource[ShaderType]);
  {$endif}

  FreeAndNil(ShaderIds);
  FreeAndNil(FUniformLocations);
  FreeAndNil(FAttributeLocations);
  FreeAndNil(FUniformReportedMissing);
  FreeAndNil(FAttributeReportedMissing);

  inherited;
end;

function TGLSLProgram.ProgramInfoLog: string;
begin
  if GLFeatures.Shaders then
    Result := GetProgramInfoLog(ProgramId)
  else
    Result := '';
end;

function TGLSLProgram.DebugInfo: string;
{$ifdef CASTLE_WEBGL}
begin
  Result := 'GLSL program support: ' + BoolToStr(GLFeatures.Shaders, true);

  // TODO: web: Restore full DebugInfo functionality with WebGL
{$else}

  function GLShaderVariableTypeName(AType: TGLenum): string;
  begin
    case AType of
      GL_FLOAT: Result := 'FLOAT';
      GL_FLOAT_VEC2: Result := 'FLOAT_VEC2';
      GL_FLOAT_VEC3: Result := 'FLOAT_VEC3';
      GL_FLOAT_VEC4: Result := 'FLOAT_VEC4';
      GL_INT: Result := 'INT';
      GL_INT_VEC2: Result := 'INT_VEC2';
      GL_INT_VEC3: Result := 'INT_VEC3';
      GL_INT_VEC4: Result := 'INT_VEC4';
      GL_BOOL: Result := 'BOOL';
      GL_BOOL_VEC2: Result := 'BOOL_VEC2';
      GL_BOOL_VEC3: Result := 'BOOL_VEC3';
      GL_BOOL_VEC4: Result := 'BOOL_VEC4';
      GL_FLOAT_MAT2: Result := 'FLOAT_MAT2';
      GL_FLOAT_MAT3: Result := 'FLOAT_MAT3';
      GL_FLOAT_MAT4: Result := 'FLOAT_MAT4';
      {$ifndef OpenGLES}
      GL_FLOAT_MAT2x3: Result := 'FLOAT_MAT2x3';
      GL_FLOAT_MAT2x4: Result := 'FLOAT_MAT2x4';
      GL_FLOAT_MAT3x2: Result := 'FLOAT_MAT3x2';
      GL_FLOAT_MAT3x4: Result := 'FLOAT_MAT3x4';
      GL_FLOAT_MAT4x2: Result := 'FLOAT_MAT4x2';
      GL_FLOAT_MAT4x3: Result := 'FLOAT_MAT4x3';
      GL_SAMPLER_1D: Result := 'SAMPLER_1D';
      {$endif}
      GL_SAMPLER_2D: Result := 'SAMPLER_2D';
      {$ifndef OpenGLES} GL_SAMPLER_3D: Result := 'SAMPLER_3D'; {$endif}
      GL_SAMPLER_CUBE: Result := 'SAMPLER_CUBE';
      {$ifndef OpenGLES} GL_SAMPLER_1D_SHADOW: Result := 'SAMPLER_1D_SHADOW'; {$endif}
      GL_SAMPLER_2D_SHADOW: Result := 'SAMPLER_2D_SHADOW';
      {$ifndef OpenGLES}
      GL_SAMPLER_2D_RECT: Result := 'SAMPLER_2D_RECT';
      GL_SAMPLER_2D_RECT_SHADOW: Result := 'SAMPLER_2D_RECT_SHADOW';
      GL_INT_SAMPLER_2D_RECT: Result := 'INT_SAMPLER_2D_RECT';
      GL_UNSIGNED_INT_SAMPLER_2D_RECT: Result := 'UNSIGNED_INT_SAMPLER_2D_RECT';
      GL_SAMPLER_2D_MULTISAMPLE: Result := 'SAMPLER_2D_MULTISAMPLE';
      {$endif}
      else Result := Format('Unrecognized uniform type "%d"', [AType]);
    end;
  end;

  const
    SCannotGetCount = '  Cannot get variables count (probably buggy fglrx ('+
      'Radeon closed-source drivers) or Mesa)';

  { Fills the UniformNames with the names (and properties)
    of all active uniform variables available by the program.
    The program must be previously linked to use this.

    Quoting OpenGL manpage about what is @italic(active) uniform variable:
    A uniform variable (either built-in or user-defined) is
    considered active if it is determined during the link operation
    that it may be accessed during program execution.

    You may want to clear UniformNames before calling this, as this doesn't
    clear them automatically, it only appends new names.

    GetActiveUniforms was planned once to be public, but actually
    I think it fits better in DebugInfo }
  procedure GetActiveUniforms(UniformNames: TStringList);
  var
    I: Integer;
    UniformsCount, UniformMaxLength: TGLuint;
    ReturnedLength: TGLsizei;
    Size: TGLint;
    AType: TGLEnum;
    Name: AnsiString;
    ErrorCode: TGLenum;
  begin
    if GLFeatures.Shaders then
    begin
      {$ifdef CASTLE_WEBGL}
      UniformsCount := glGetProgramParameter(ProgramId, GL_ACTIVE_UNIFORMS);
      {$else}
      glGetProgramiv(ProgramId, GL_ACTIVE_UNIFORMS, @UniformsCount);
      {$endif}

      { fglrx (Radeon closed-source OpenGL drivers) are buggy (that's not
        news, I know...) and they report GL_INVALID_ENUM on some queries
        here. We detect this, and still produce nice debug message, without
        raising any exception (after all, we have to workaround fglrx bugs,
        and try to run our program anyway...).
        For this we have to check first whether there are any OpenGL errors
        pending, and raise exceptions on them. }
      ErrorCode := glGetError();
      if ErrorCode = GL_INVALID_ENUM then
      begin
        UniformNames.Append(SCannotGetCount);
        Exit;
      end else
      if ErrorCode <> GL_NO_ERROR then
        raise EOpenGLError.Create(ErrorCode, 'GetActiveUniforms');

      glGetProgramiv(ProgramId, GL_ACTIVE_UNIFORM_MAX_LENGTH, @UniformMaxLength);

      for I := 0 to UniformsCount - 1 do
      begin
        SetLength(Name, UniformMaxLength);
        glGetActiveUniform(ProgramId, I, UniformMaxLength,
          {$ifndef USE_DGL}@{$endif} ReturnedLength,
          {$ifndef USE_DGL}@{$endif} Size,
          {$ifndef USE_DGL}@{$endif} AType,
          PAnsiCharOrNil(Name));
        SetLength(Name, ReturnedLength);
        UniformNames.Append(Format('  %d: Name: %s, type: %s, size: %d',
          [I, Name, GLShaderVariableTypeName(AType), Size]));
      end;
    end;
  end;

  procedure GetActiveAttribs(AttribNames: TStringList);
  var
    I: Integer;
    AttribsCount, AttribMaxLength: TGLuint;
    ReturnedLength: TGLsizei;
    Size: TGLint;
    AType: TGLEnum;
    Name: AnsiString;
    ErrorCode: TGLenum;
  begin
    if GLFeatures.Shaders then
    begin
      glGetProgramiv(ProgramId, GL_ACTIVE_ATTRIBUTES, @AttribsCount);

      ErrorCode := glGetError();
      if ErrorCode = GL_INVALID_ENUM then
      begin
        AttribNames.Append(SCannotGetCount);
        Exit;
      end else
      if ErrorCode <> GL_NO_ERROR then
        raise EOpenGLError.Create(ErrorCode, 'GetActiveAttribs');

      glGetProgramiv(ProgramId, GL_ACTIVE_ATTRIBUTE_MAX_LENGTH, @AttribMaxLength);

      for I := 0 to AttribsCount - 1 do
      begin
        SetLength(Name, AttribMaxLength);
        glGetActiveAttrib(ProgramId, I, AttribMaxLength,
          {$ifndef USE_DGL}@{$endif} ReturnedLength,
          {$ifndef USE_DGL}@{$endif} Size,
          {$ifndef USE_DGL}@{$endif} AType,
          PAnsiCharOrNil(Name));
        SetLength(Name, ReturnedLength);
        AttribNames.Append(Format('  %d: Name: %s, type: %s, size: %d',
          [I, Name, GLShaderVariableTypeName(AType), Size]));
      end;
    end;
  end;

  function ShaderInfoLog(ShaderId: TGLShader): string;
  begin
    if GLFeatures.Shaders then
      Result := GetShaderInfoLog(ShaderId);
  end;

var
  S: TStringList;
  I: Integer;
begin
  Result := 'GLSL program support: ' + BoolToStr(GLFeatures.Shaders, true);

  CheckGLErrors('Check at the beginning of TGLSLProgram.DebugInfo');

  S := TStringList.Create;
  try
    GetActiveUniforms(S);
    Result := Result + NL + 'Active uniforms:' + NL + S.Text;

    S.Clear;
    GetActiveAttribs(S);
    Result := Result +  NL + 'Active attribs:' + NL + S.Text ;
  finally FreeAndNil(S) end;

  for I := 0 to ShaderIds.Count - 1 do
  begin
    Result := Result +  NL + Format('Shader number %d (OpenGL id %d) log:',
      [I, ShaderIds[I]]) + NL +
      ShaderInfoLog(ShaderIds[I]) ;
  end;

  Result := Result +  NL + 'Program info log:' + NL + ProgramInfoLog;

  Result := Result + NL + 'Program detected as running in hardware: ' +
    BoolToStr(RunningInHardware, true);
{$endif CASTLE_WEBGL}
end;

procedure TGLSLProgram.AttachShader(const ShaderType: TShaderType; S: string);
var
  AType: TGLenum;

  { Some Nvidia drivers on Linux (like version 295.49
    in Debian testing on 2012-06-02) segfault when calling glCompileShader[ARB]
    with code like "const in gl_MaterialParameters material".
    Googling, at least Nvidia happens to sefault also on other pieces of GLSL.

    Although our internal GLSL code avoids using such known buggy constructs,
    but user can always supply his own shader code.
    So we surround glCompileShader[ARB] in a safeguard, to raise nice
    EGLSLShaderCompileError (that will result in simple warning and fallback
    on fixed-function pipeline) instead of crash. }
  procedure ReportCompileAccessViolation;
  var
    Message: String;
  begin
    Message := Format('%s shader not compiled, segmentation fault in glCompileShader call. Buggy OpenGL GLSL compiler.',
      [ShaderTypeName[ShaderType]]);

    {$ifdef CASTLE_CANNOT_CATCH_EXCEPTIONS}
    WritelnWarning('GLSL', Message);
    ErrorOnCompileLink := true;
    {$else}
    raise EGLSLShaderCompileError.Create(Message);
    {$endif}
  end;

  procedure ReportCompileError(const CompileErrorMessage: String);
  var
    Message: String;
  begin
    Message := Format('%s shader not compiled:' + NL +
      '%s',
      [ShaderTypeName[ShaderType], CompileErrorMessage]);

    Message := Message + NL +
      NL +
      'The shader source code is below:' + NL +
      '-------------------------------------------------------' + NL +
      S + NL +
      '-------------------------------------------------------';

    {$ifdef CASTLE_CANNOT_CATCH_EXCEPTIONS}
    WritelnWarning('GLSL', Message);
    ErrorOnCompileLink := true;
    {$else}
    raise EGLSLShaderCompileError.Create(Message);
    {$endif}
  end;

  { Create a shader, adding sources and compiling it.

    Based on OpenGL code by Dean Ellis BasicShader.dpr,
    many adjustments later - to work with OpenGL / OpenGL ES / WebGL,
    using our CastleGL unit, FPC / Delphi compatibility. }
  function CreateShader(const S: string): TGLshader;
  var
    {$ifndef CASTLE_WEBGL}
    SrcPtr: PGLChar;
    SrcLength: Cardinal;
    {$ifndef FPC}
    AnsiS: AnsiString;
    {$endif}
    CompiledInt: TGLint;
    {$endif not CASTLE_WEBGL}
    Compiled: Boolean;
    PrepareTick, PrepareMs: QWord;
    {$ifdef REZVIVO_STARTUP_TIMING}
    TimingStart: QWord;
    {$endif}
  begin
    Result := glCreateShader(AType);

    { Call glShaderSource to pass source code S to shader.
      This is trivial in WebGL, but requires some work for OpenGL / OpenGLES
      to express string data as needed (and for Delphi, extra work needed
      to convert UnicodeString to 8-bit AnsiString). }
    {$ifdef CASTLE_WEBGL}
    glShaderSource(Result, S);
    {$else}
    {$ifdef FPC}
    SrcPtr := PGLChar(S);
    SrcLength := Length(S);
    {$else}
    AnsiS := AnsiString(S);
    SrcPtr := PGLChar(AnsiS);
    SrcLength := Length(AnsiS);
    {$endif}
    glShaderSource(Result, 1, @SrcPtr, @SrcLength);
    {$endif}

    {$ifdef REZVIVO_STARTUP_TIMING}
    WritelnLog('StartupTiming', Format('compile begin shader=%d stage=%s bytes=%d name=%s',
      [Result, ShaderTypeName[ShaderType], Length(S), Name]));
    TimingStart := GetTickCount64;
    {$endif}
    PrepareTick := GetTickCount64;
    try
      glCompileShader(Result);
    except
      on E: EAccessViolation do ReportCompileAccessViolation;
    end;

    {$ifdef CASTLE_WEBGL}
    Compiled := glGetShaderParameter(Result, GL_COMPILE_STATUS);
    {$else}
    glGetShaderiv(Result, GL_COMPILE_STATUS, @CompiledInt);
    Compiled := CompiledInt = Ord(GL_TRUE);
    {$endif}
    PrepareMs := GetTickCount64 - PrepareTick;
    if PrepareMs > 100 then
      WritelnLog('ResourcePrepare', 'stage=shader_compile ms=%d shader=%d type=%s bytes=%d name="%s"',
        [PrepareMs, Result, ShaderTypeName[ShaderType], Length(S), Name]);
    {$ifdef REZVIVO_STARTUP_TIMING}
    WritelnLog('StartupTiming', Format('compile end shader=%d ms=%d',
      [Result, GetTickCount64 - TimingStart]));
    {$endif}

    { Although we generally avoid creating multiline exception messages,
      ShaderGetInfoLog naturally comes out multiline (it contains a
      couple of error messages) and it's best presented with line breaks.
      So a line break right before ShaderGetInfoLog contents looks good. }
    if not Compiled then
      ReportCompileError(GetShaderInfoLog(Result));
  end;


  { Does shader code Text has a line starting with LinePrefix. }
  function HasLine(const LinePrefix: String; const Text: String): Boolean;
  begin
    Result :=
      (Pos(#13 + LinePrefix, S) <> 0) or
      (Pos(#10 + LinePrefix, S) <> 0) or
      IsPrefix(LinePrefix, S, false);
  end;

  { Workaround bug of old ANGLE version in Firefox,
    that requires main() to be after all "varying" declarations.
    See
    https://bugzilla.mozilla.org/show_bug.cgi?id=2039887
    https://github.com/michaliskambi/firefox-webgl-angle-varying-bug

    Shaders where this is necessary (only vertex shaders
    are affected by this bug, and only if we'll generate
    there code using our "plugs" system) should have markers
    "/* CASTLE-MAIN-BEGIN */" and "/* CASTLE-MAIN-END */.
    Example: src/scene/glsl/source/main_shading_phong.vs .

    Not doing this would break many features of our engine shaders
    using "varying" variables, like
    - clip planes (to implement X3D ClipPlane node) (testcase: pope call in Unholy)
    - bump mapping
    - fog
    - water in examples/terrain/
    - time to shader (in castle-model-viewer-mobile demo)
  }
  procedure WebGLMoveMainBlockToEnd;
  {$ifdef CASTLE_WEBGL}
  const
    SMarkerBegin = '/* CASTLE-MAIN-BEGIN */';
    SMarkerEnd = '/* CASTLE-MAIN-END */';
  var
    MarkerBegin, MarkerEnd: Integer;
    Main: String;
  begin
    MarkerBegin := Pos(SMarkerBegin, S);
    if MarkerBegin = 0 then Exit;
    MarkerEnd := Pos(SMarkerEnd, S);
    if MarkerEnd = 0 then Exit;
    Main := CopyPos(S, MarkerBegin, MarkerEnd + Length(SMarkerEnd) - 1);
    Delete(S, MarkerBegin, MarkerEnd + Length(SMarkerEnd) - MarkerBegin);
    S := S + NL + Main;
  {$else}
  begin
  {$endif}
  end;

const
  { FPC < 2.4.4 doesn't have it defined }
  GL_GEOMETRY_SHADER = $8DD9;
var
  ShaderId: TGLShader;
begin
  { When shaders not supported, TGLSLProgram does nothing, silently. }
  if not GLFeatures.Shaders then
    Exit;

  { calculate AType }
  case ShaderType of
    stVertex:
      AType := GL_VERTEX_SHADER;
    stGeometry:
      begin
        AType := GL_GEOMETRY_SHADER;
        if not GLVersion.AtLeast(3, 2) then
          { raise an error if Shaders supported but not geometry shaders. }
          raise EGLSLShaderCompileError.Create('Geometry shaders not supported by your OpenGL version');
      end;
    stFragment:
      begin
        AType := GL_FRAGMENT_SHADER;
        {$ifdef OpenGLES}
        if (not HasLine('precision mediump float;', S)) and
           (not HasLine('precision lowp float;', S)) and
           (not HasLine('precision highp float;', S)) then
        begin
          { GLES 3 materials use shared camera/world uniforms in both stages.
            Match the vertex default (highp), also keeping world-space noise
            stable on mobile GPUs with actual 16-bit mediump arithmetic. }
          if GLVersion.AtLeast(3, 0) then
            S := 'precision highp float;' + NL + S
          else
            S := 'precision mediump float;' + NL + S;
        end;
        if GLVersion.AtLeast(3, 0) and
           (not HasLine('precision mediump int;', S)) and
           (not HasLine('precision lowp int;', S)) and
           (not HasLine('precision highp int;', S)) then
          S := 'precision highp int;' + NL + S;
        {$endif}
      end;
    {$ifndef COMPILER_CASE_ANALYSIS}
    else raise EInternalError.Create('TGLSLProgram.AttachShader ShaderType?');
    {$endif}
  end;

  { Add #version.
    Done after adding "precision ..." for OpenGLES fragment shader,
    as #version must be earlier. }
  if InternalUpgradeGlslVersion and
     GLFeatures.
       {$if defined(CASTLE_WEBGL)} VersionWebGL_2
       {$elseif defined(OpenGLES)} VersionES_3_0
       {$else} Version_3_1
       {$endif} and
     (not HasLine('#version ', S)) then
    S := {$ifdef OpenGLES} GLES30CoreHeader {$else} GL31CoreHeader {$endif}
      [ShaderType] + S;

  WebGLMoveMainBlockToEnd;

  ShaderId := CreateShader(S);

  {$ifdef CASTLE_CANNOT_CATCH_EXCEPTIONS}
  if ErrorOnCompileLink then Exit;
  {$endif}

  glAttachShader(ProgramId, ShaderId);
  ShaderIds.Add(ShaderId);

  {$ifdef CASTLE_COLLECT_SHADER_SOURCE}
  FSource[ShaderType].Add(S);
  {$endif CASTLE_COLLECT_SHADER_SOURCE}
  HasStage[ShaderType] := true;
end;

procedure TGLSLProgram.AttachShader(const ShaderType: TShaderType;
  const Parts: TStrings);
var
  I: Integer;
  {$ifdef OpenGLES}
  Concatenated: string;
  {$endif}
begin
  {$ifdef OpenGLES}
  Concatenated := '';
  for I := 0 to Parts.Count - 1 do
    Concatenated := Concatenated +  Parts[I] + NL ;
  if Trim(Concatenated) <> '' then
    AttachShader(ShaderType, Concatenated);
  {$else}
  for I := 0 to Parts.Count - 1 do
    AttachShader(ShaderType, Parts[I]);
  {$endif}
end;

procedure TGLSLProgram.AttachVertexShader(const S: string);
begin
  AttachShader(stVertex, S);
end;

procedure TGLSLProgram.AttachFragmentShader(const S: string);
begin
  AttachShader(stFragment, S);
end;

procedure TGLSLProgram.AttachGeometryShader(const S: string);
begin
  AttachShader(stGeometry, S);
end;

procedure TGLSLProgram.SetTransformFeedbackVaryings(
  const Varyings: array of String; const IsSingleBufferMode: Boolean);
var
  TransformFeedbackBufferMode, ErrorCode: TGLuint;
  VaryingLength: Cardinal;
  {$ifndef CASTLE_WEBGL}
  I: Integer;
  VaryingsAnsi: array of AnsiString;
  VaryingsAnsiPtr: array of PAnsiChar;
  {$endif}
begin;
  VaryingLength := Length(Varyings);
  if VaryingLength > 0 then
  begin
    if not GLFeatures.TransformFeedbackVaryings then
      raise EGLSLTransformFeedbackError.Create('Transform Feedback not supported by this context (too low OpenGL / OpenGLES / WebGL version)');
    if IsSingleBufferMode then
      TransformFeedbackBufferMode := GL_INTERLEAVED_ATTRIBS
    else
      TransformFeedbackBufferMode := GL_SEPARATE_ATTRIBS;

    // call transformFeedbackVaryings
    {$ifdef CASTLE_WEBGL}
    GL2.transformFeedbackVaryings(ProgramId, ListToWebGL(Varyings), TransformFeedbackBufferMode);
    {$else}
    SetLength(VaryingsAnsi, VaryingLength);
    SetLength(VaryingsAnsiPtr, VaryingLength);
    for I := 0 to VaryingLength - 1 do
    begin
      VaryingsAnsi[I] := Varyings[I];
      VaryingsAnsiPtr[I] := PAnsiChar(VaryingsAnsi[I]);
    end;
    glTransformFeedbackVaryings(ProgramId, VaryingLength, @VaryingsAnsiPtr[0], TransformFeedbackBufferMode);
    {$endif}

    ErrorCode := glGetError();
    if ErrorCode = GL_INVALID_VALUE then
    begin
      raise EGLSLTransformFeedbackError.Create('Error occured after setting transform feedback varyings');
    end;
  end;
end;

procedure TGLSLProgram.DetachAllShaders;
var
  I: Integer;
  ShaderType: TShaderType;
begin
  for I := 0 to ShaderIds.Count - 1 do
  begin
    { ShaderIds can be non-empty only if GLFeatures.Shaders,
      and right now GLFeatures must be <> nil because we must free while
      GL context is available. }
    Assert(GLFeatures.Shaders);
    glDetachShader(ProgramId, ShaderIds[I]);
    glDeleteShader(ShaderIds[I]);
  end;

  ShaderIds.Count := 0;

  for ShaderType := Low(TShaderType) to High(TShaderType) do
  begin
    {$ifdef CASTLE_COLLECT_SHADER_SOURCE}
    FSource[ShaderType].Clear;
    {$endif CASTLE_COLLECT_SHADER_SOURCE}
    HasStage[ShaderType] := false;
  end;
end;

procedure TGLSLProgram.Link;

  { Outputs shader source code, if collected.
    Returns empty string if not collected.
    If collected, this is multiline string that *starts* with newline,
    and does not end with newline. }
  function LogShaderCode: String;
  {$ifdef CASTLE_COLLECT_SHADER_SOURCE}
  var
    ShaderType: TShaderType;
    I: Integer;
  begin
    Result := NL + Format('Shader "%s" source code:', [Name]) + NL;
    for ShaderType := Low(TShaderType) to High(TShaderType) do
      for I := 0 to FSource[ShaderType].Count - 1 do
        Result := Result + Format(
          '%s [%d] -------------------------------------------------------' + NL +
          '%s' + NL,
          [ ShaderTypeName[ShaderType], I, FSource[ShaderType][I] ] );
    Result := Result +
      'End of shader source code -------------------------------------------------------';
  {$else}
  begin
    Result := '';
  {$endif CASTLE_COLLECT_SHADER_SOURCE}
  end;

  procedure ReportLinkError(const LinkErrorMessage: String);
  var
    Message: String;
  begin
    Message := Format('Shader "%s" not linked:', [Name]) + NL +
      LinkErrorMessage +
      LogShaderCode;

    {$ifdef CASTLE_CANNOT_CATCH_EXCEPTIONS}
    WritelnWarning('GLSL', Message);
    ErrorOnCompileLink := true;
    {$else}
    raise EGLSLProgramLinkError.Create(Message);
    {$endif}
  end;

var
  {$ifndef CASTLE_WEBGL}
  LinkedInt: TGLuint;
  {$endif}
  Linked: Boolean;
  PrepareTick, PrepareMs: QWord;
  {$ifdef REZVIVO_STARTUP_TIMING}
  TimingStart: QWord;
  {$endif}
begin
  InvalidateUniformValues;
  if GLFeatures.Shaders then
  begin
    {$if defined(FPC) and not defined(OpenGLES)}
    { A binary already linked this program. Still run the virtual Link chain:
      descendants resolve their uniform and attribute locations after inherited. }
    if FSaveBinaryRequested and (ShaderIds.Count = 0) then
    begin
      glGetProgramiv(ProgramId, GL_LINK_STATUS, @LinkedInt);
      if LinkedInt = GL_TRUE then Exit;
    end;
    {$endif}
    { Produce clear error messages, without waiting for OpenGL errors,
      if required shaders are not attached. }
    if not HasStage[stVertex] then
      raise EGLSLProgramLinkError.Create('Vertex shader not attached');
    if FragmentShaderRequired and (not HasStage[stFragment]) then
      raise EGLSLProgramLinkError.Create('Fragment shader not attached');

    {$ifdef REZVIVO_STARTUP_TIMING}
    WritelnLog('StartupTiming', Format('link begin program=%d name=%s', [ProgramId, Name]));
    TimingStart := GetTickCount64;
    {$endif}
    {$if defined(FPC) and not defined(OpenGLES)}
    if FSaveBinaryRequested then
      glProgramParameteri(ProgramId, GL_PROGRAM_BINARY_RETRIEVABLE_HINT, GL_TRUE);
    {$endif}
    PrepareTick := GetTickCount64;
    glLinkProgram(ProgramId);

    {$ifdef CASTLE_WEBGL}
    Linked := glGetProgramParameter(ProgramId, GL_LINK_STATUS);
    {$else}
    glGetProgramiv(ProgramId, GL_LINK_STATUS, @LinkedInt);
    Linked := LinkedInt = Ord(GL_TRUE);
    {$endif}
    PrepareMs := GetTickCount64 - PrepareTick;
    if PrepareMs > 100 then
      WritelnLog('ResourcePrepare', 'stage=shader_link ms=%d program=%d name="%s"',
        [PrepareMs, ProgramId, Name]);
    {$ifdef REZVIVO_STARTUP_TIMING}
    WritelnLog('StartupTiming', Format('link end program=%d ms=%d name=%s',
      [ProgramId, GetTickCount64 - TimingStart, Name]));
    {$endif}

    if not Linked then
      // raises exception
      ReportLinkError(GetProgramInfoLog(ProgramId));

    {$ifdef CASTLE_CANNOT_CATCH_EXCEPTIONS}
    if ErrorOnCompileLink then Exit;
    {$endif}

    if LogShaders then
      WritelnLogMultiline('GLSL',
        Format('Shader "%s" successfully linked:', [Name]) + NL +
        'Information:' + NL +
        DebugInfo +
        LogShaderCode);
  end;
end;

procedure TGLSLProgram.Link(Ignored: boolean);
begin
  Link;
end;

function TGLSLProgram.RunningInHardware: boolean;
begin
  { This is good at least for capturing shaders running in software on
      Radeon X300/X550/X1050 Series (crypto on ii.324), Linux fglrx. }

  Result := Pos('shader will run in software due to the', ProgramInfoLog) = 0;
end;

procedure TGLSLProgram.Enable;
begin
  RenderContext.CurrentProgram := Self;
end;

procedure ConfigureShaderNameList(const Names: TStringList);
{$ifdef FPC}
var WasSorted: Boolean;
{$endif}
begin
  {$ifdef FPC}
  if Names.UseLocale = UseBinaryShaderNames then
  begin
    WasSorted := Names.Sorted;
    Names.Sorted := False;
    Names.UseLocale := not UseBinaryShaderNames;
    Names.Sorted := WasSorted;
  end;
  {$endif}
end;

class procedure TGLSLProgram.Disable;
begin
  RenderContext.CurrentProgram := nil;
end;

function TGLSLProgram.SetupUniforms(var BoundTextureUnits: Cardinal): boolean;
begin
  Result := true;
end;

function TGLSLProgram.Uniform(const AName: string): TGLSLUniform;
begin
  Result := Uniform(AName, UniformMissing);
end;

function TGLSLProgram.Uniform(const AName: string; const AUniformMissing: TUniformMissing): TGLSLUniform;

  procedure ReportUniformMissing;

    function ErrMessage: string;
    begin
      Result := Format('Uniform variable "%s" not found (or not used) in the shader source code', [AName]);
    end;

  begin
    if FUniformReportedMissing = nil then
    begin
      FUniformReportedMissing := TStringList.Create;
      FUniformReportedMissing.CaseSensitive := true; // GLSL uniform names are case-sensitive
    end;
    ConfigureShaderNameList(FUniformReportedMissing);
    FUniformReportedMissing.Sorted := UseBinaryShaderNames;
    // don't spam the log with warning "Uniform variable "%s" not found (or not used)"... every frame
    if FUniformReportedMissing.IndexOf(AName) <> -1 then
      Exit;
    FUniformReportedMissing.Add(AName);

    case AUniformMissing of
      umWarning  : WritelnWarning('GLSL', ErrMessage);
      // This was implemented in the past, but was not useful - we converted it to warnings anyway
      //uaException: raise EGLSLUniformMissing.Create(ErrMessage);
      umIgnore   : ;
      {$ifndef COMPILER_CASE_ANALYSIS}
      else raise EInternalError.Create('AUniformMissing? in TGLSLProgram.UniformMissing');
      {$endif}
    end;
  end;

begin
  Result.Owner := Self;
  Result.Name := AName;

  if not FUniformLocations.TryGetValue(AName, Result.Location) then
  begin
    if GLFeatures.Shaders then
      Result.Location := glGetUniformLocation(ProgramId, PAnsiCharOrNil(AName))
    else
      Result.Location := GLUniformLocationNone;

    {$ifdef CASTLE_LOG_GET_LOCATIONS}
    WritelnLog('Doing (potentially expensive) glGetUniformLocation: ' + AName);
    {$endif}
    FUniformLocations.Add(AName, Result.Location);
  end;

  if Result.Location = GLUniformLocationNone then
    ReportUniformMissing;
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: boolean; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TGLint; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector2Integer; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector3Integer; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector4Integer; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TGLfloat; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector2; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector3; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector4; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TMatrix2; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TMatrix3; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TMatrix4; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TBooleanList; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TInt32List; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TSingleList; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector2List; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector3List; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector4List; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TMatrix3List; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TMatrix4List; const AUniformMissing: TUniformMissing);
begin
  Uniform(AName, AUniformMissing).SetValue(Value);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: boolean);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TGLint);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector2Integer);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector3Integer);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector4Integer);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TGLfloat);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector2);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector3);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector4);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TMatrix2);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TMatrix3);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TMatrix4);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TBooleanList);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TInt32List);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TSingleList);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector2List);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector3List);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TVector4List);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TMatrix3List);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.SetUniform(const AName: string; const Value: TMatrix4List);
begin
  SetUniform(AName, Value, UniformMissing);
end;

procedure TGLSLProgram.WarnMissingAttribute(const AName: string);
begin
  if FAttributeReportedMissing = nil then
  begin
    FAttributeReportedMissing := TStringList.Create;
    FAttributeReportedMissing.CaseSensitive := True;
  end;
  if FAttributeReportedMissing.IndexOf(AName) <> -1 then Exit;
  FAttributeReportedMissing.Add(AName);
  WritelnWarning('VRML/X3D', 'Shader attribute "' + AName +
    '" not found (or not used) in ' + Name);
end;

function TGLSLProgram.AttributeOptional(const AName: string): TGLSLAttribute;
begin
  Result.Owner := Self;
  Result.Name := AName;

  if not FAttributeLocations.TryGetValue(AName, Result.Location) then
  begin
    if GLFeatures.Shaders then
      Result.Location := glGetAttribLocation(ProgramId, PAnsiCharOrNil(AName))
    else
      Result.Location := GLAttribLocationNone;

    {$ifdef CASTLE_LOG_GET_LOCATIONS}
    WritelnLog('Doing (potentially expensive) glGetAttribLocation: ' + AName);
    {$endif}
    FAttributeLocations.Add(AName, Result.Location);
  end;
end;

function TGLSLProgram.Attribute(const AName: string): TGLSLAttribute;
begin
  Result := AttributeOptional(AName);
  if Result.Location = GLAttribLocationNone then
    raise EGLSLAttributeNotFound.CreateFmt('Attribute variable "%s" not found', [AName]);
end;

procedure TGLSLProgram.SetAttribute(const AName: string; const Value: TGLfloat);
begin
  Attribute(AName).SetValue(Value);
end;

procedure TGLSLProgram.SetAttribute(const AName: string; const Value: TVector2);
begin
  Attribute(AName).SetValue(Value);
end;

procedure TGLSLProgram.SetAttribute(const AName: string; const Value: TVector3);
begin
  Attribute(AName).SetValue(Value);
end;

procedure TGLSLProgram.SetAttribute(const AName: string; const Value: TVector4);
begin
  Attribute(AName).SetValue(Value);
end;

procedure TGLSLProgram.SetAttribute(const AName: string; const Value: TMatrix3);
begin
  Attribute(AName).SetValue(Value);
end;

procedure TGLSLProgram.SetAttribute(const AName: string; const Value: TMatrix4);
begin
  Attribute(AName).SetValue(Value);
end;

{$ifndef OpenGLES}
procedure TGLSLProgram.SetAttribute(const AName: string; const Value: TVector4Integer);
begin
  Attribute(AName).SetValue(Value);
end;

procedure TGLSLProgram.SetAttribute(const AName: string; const Value: TVector4Byte);
begin
  Attribute(AName).SetValue(Value);
end;

procedure TGLSLProgram.SetAttribute(const AName: string; const Value: TGLdouble);
begin
  Attribute(AName).SetValue(Value);
end;

// Makes FPC errors: Error: Asm: Duplicate label, see https://bugs.freepascal.org/view.php?id=32188
{
procedure TGLSLProgram.SetAttribute(const AName: string; const Value: TVector2Double);
begin
  Attribute(AName).SetValue(Value);
end;

procedure TGLSLProgram.SetAttribute(const AName: string; const Value: TVector3Double);
begin
  Attribute(AName).SetValue(Value);
end;

procedure TGLSLProgram.SetAttribute(const AName: string; const Value: TVector4Double);
begin
  Attribute(AName).SetValue(Value);
end;
}
{$endif}

class function TGLSLProgram.GetCurrent: TGLSLProgram;
begin
  Result := RenderContext.CurrentProgram;
end;

class procedure TGLSLProgram.SetCurrent(const Value: TGLSLProgram);
begin
  RenderContext.CurrentProgram := Value;
end;

end.
