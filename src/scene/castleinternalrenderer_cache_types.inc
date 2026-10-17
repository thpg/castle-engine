{%MainUnit castleinternalrenderer.pas}
{
  Copyright 2002-2023 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Types used by TRendererContextCache. }

{$ifdef read_interface}
//type
  TTextureImageCache = class
    { Full URL of used texture image. Empty ('') if not known
      (or maybe this texture didn't come from any URL, e.g. it's generated). }
    FullUrl: String;
    FlipVertically: Boolean;
    Filter: TTextureFilter;
    Anisotropy: TGLfloat;
    Wrap: TTextureWrap2D;
    GUITexture: boolean;
    References: Cardinal;
    GLName: TGLTexture;
    { Metadata of the source image, retained with the existing GL cache entry.
      Reusing a live GPU texture must not require decoding its URL again. }
    SourceWidth, SourceHeight: Cardinal;
    SourceAlpha: TAlphaChannel;
  end;
  TTextureImageCacheList = {$ifdef FPC}specialize{$endif} TObjectList<TTextureImageCache>;

  TTextureVideoCache = class
    { Full URL of used texture image. Empty ('') if not known
      (or maybe this texture didn't come from any URL, e.g. it's generated). }
    FullUrl: String;
    FlipVertically: Boolean;
    Filter: TTextureFilter;
    Anisotropy: TGLfloat;
    Wrap: TTextureWrap2D;
    GUITexture: boolean;
    References: Cardinal;
    GLVideo: TGLVideo3D;
  end;
  TTextureVideoCacheList = {$ifdef FPC}specialize{$endif} TObjectList<TTextureVideoCache>;

  TTextureCubeMapCache = class
    { Full URL of used texture image. Empty ('') if not known
      (or maybe this texture didn't come from any URL, e.g. it's generated). }
    FullUrl: String;
    Filter: TTextureFilter;
    Anisotropy: TGLfloat;
    References: Cardinal;
    GLName: TGLTexture;
  end;
  TTextureCubeMapCacheList = {$ifdef FPC}specialize{$endif} TObjectList<TTextureCubeMapCache>;

  TTexture3DCache = class
    { Full URL of used texture image. Empty ('') if not known
      (or maybe this texture didn't come from any URL, e.g. it's generated). }
    FullUrl: String;
    Filter: TTextureFilter;
    Anisotropy: TGLfloat;
    Wrap: TTextureWrap3D;
    References: Cardinal;
    GLName: TGLTexture;
  end;
  TTexture3DCacheList = {$ifdef FPC}specialize{$endif} TObjectList<TTexture3DCache>;

  { Cached depth or float texture.
    For now, depth and float textures require the same fields. }
  TTextureDepthOrFloatCache = class
    { Full URL of used texture image. Empty ('') if not known
      (or maybe this texture didn't come from any URL, e.g. it's generated). }
    FullUrl: String;
    Wrap: TTextureWrap2D;
    References: Cardinal;
    GLName: TGLTexture;
  end;
  TTextureDepthOrFloatCacheList = {$ifdef FPC}specialize{$endif} TObjectList<TTextureDepthOrFloatCache>;

  TX3DRendererShape = class;
  TVboType = (vtCoordinate, vtAttribute, vtIndex);
  TVboTypes = set of TVboType;
  TVboArrays = array [TVboType] of TGLBuffer;

  { Cached shape resources. }
  TShapeCache = class
  private
    RenderOptions: TCastleRenderOptions;
    Geometry: TAbstractGeometryNode;
    State: TX3DGraphTraverseState;
    FogVolumetric: boolean;
    FogVolumetricDirection: TVector3;
    FogVolumetricVisibilityStart: Single;
    References: Cardinal;

    { An instance of TGeometryArrays, decomposing this shape geometry.
      Used to easily render and process this geometry.

      When VBO are supported (all non-ancient GPUs) then TShapeCache
      uses an instance of it only once (in LoadArraysToVbo,
      to load contents to GPU, and then calls Arrays.FreeData).
      But it is later used by outside code multiple times to make draw calls
      (as it is passed by TBaseCoordinateRenderer).
      So storing it in TShapeCache (to be shared when possible) makes sense.

      TShapeCache owns this -- it will be freed when TShapeCache is freed. }
    Arrays: TGeometryArrays;

    { Small CPU hierarchy over unchanged indexed triangle ranges, only
      present on static geometry explicitly marked by its producer. }
    IndexRangeCulling: TStaticMeshIndexRanges;
    SpatialJob: TSpatialMeshJob;
    SpatialStream: TSpatialMeshIndexStream;
    SpatialVbo, SpatialIndirectVbo: TGLBuffer;
    SpatialUploaded: SizeUInt;
    SpatialUploadFrame: Int64;

    { Geometry-only preparation for surface queries. The first normal draw
      replaces the minimal layout through the existing arrays/VBO path. }
    SurfaceQueryOnly: Boolean;

    { Monotonic identity of the final GPU index topology. Unlike a GL name
      or object pointer this cannot alias a destroyed/recreated cache. Pose,
      origin and coordinate-only animation do not invalidate the indices. }
    DeformedTopologyId: QWord;
    DeformedGeometryId: QWord;

    { What VBOs do we need to reload at next LoadArraysToVbo call.
      This also implies that content for this VBOs needs to be created,
      which may mean we need to change Arrays.
      This is extended at each InvalidateVertexData call. }
    VboToReload: TVboTypes;

    Vbo: TVboArrays;
    VboAllocatedUsage: TGLenum;
    VboAllocatedSize: array [TVboType] of Cardinal;
    VboCoordinatePreserveGeometryOrder: Boolean; //< copied from TGeometryArrays.CoordinatePreserveGeometryOrder

    Vao: TVertexArrayObject;

    { GPU-only object-space deformation, shared by colour and shadow draws. }
    PoseVbo: array[0..1] of TGLBuffer;
    PoseFrame: QWord;
    PoseRevision: QWord;
    PoseSize: Cardinal;
    PoseRead: Integer;
    PoseValid, PosePending: Boolean;
    procedure ClearPose;
    procedure ClearSpatial;
    function PrepareSpatial: Boolean;

    { Like TX3DRendererShape.LoadArraysToVbo,
      but takes explicit DynamicGeometry. }
    procedure LoadArraysToVbo(const DynamicGeometry: boolean);
    procedure GLContextClose;
  public
    constructor Create;
    destructor Destroy; override;
    procedure InvalidateVertexData(const Changed: TVboTypes);
    { Debug description of this shape cache. }
    function ToString: String; override;
  end;

  TShapeCacheList = {$ifdef FPC}specialize{$endif} TObjectList<TShapeCache>;

  TX3DGLSLProgram = class;

  TShaderProgramCache = class
  public
    { Hash of TShader code when initializing this shader
      by LinkProgram. Used to decide when shader needs to be regenerated,
      and when it can be shared. }
    Hash: TShaderCodeHash;

    { Actual GLSL program. May be @nil (if it failed to link). }
    ShaderProgram: TX3DGLSLProgram;

    References: Cardinal;

    destructor Destroy; override;
  end;

  TShaderProgramCacheList = {$ifdef FPC}specialize{$endif} TObjectList<TShaderProgramCache>;
{$endif read_interface}

{$ifdef read_implementation}

{ TShapeCache ---------------------------------------------------------------- }

var
  LastDeformedTopologyId: QWord = 0;

function NextDeformedTopologyId: QWord;
begin
  Inc(LastDeformedTopologyId);
  Result := LastDeformedTopologyId;
end;

function SpatialIndexBuffersSupported: Boolean; inline;
begin
  {$ifdef OpenGLES}
  Result := False;
  {$else}
  { Upload uses COPY_WRITE_BUFFER to avoid disturbing VAO / CGE bindings.
    VBO and multidraw alone are insufficient on desktop GL 2.x / 3.0. }
  Result := (GLFeatures <> nil) and GLFeatures.VertexBufferObject and
    (GLFeatures.Version_3_1 or GL_ARB_copy_buffer) and
    Assigned(glMultiDrawElements);
  {$endif}
end;

constructor TShapeCache.Create;
begin
  inherited;
  DeformedTopologyId := NextDeformedTopologyId;
  DeformedGeometryId := NextDeformedTopologyId;
  VboToReload := AllVboTypes;
end;

destructor TShapeCache.Destroy;
begin
  FreeAndNil(IndexRangeCulling);
  FreeAndNil(Arrays);
  GLContextClose;
  inherited;
end;

procedure TShapeCache.GLContextClose;
var
  I: TVboType;
begin
  DeformedTopologyId := NextDeformedTopologyId;
  DeformedGeometryId := NextDeformedTopologyId;
  FreeAndNil(IndexRangeCulling);
  ClearSpatial;
  ClearPose;
  if Vbo[vtCoordinate] <> GLObjectNone then
  begin
    for I := Low(I) to High(I) do
    begin
      { All Vbo must be zero, or none. }
      Assert(Vbo[I] <> GLObjectNone);
      FreeBuffer(Vbo[I]);
    end;
  end;

  FreeAndNil(Vao);
end;

procedure TShapeCache.ClearPose;
begin
  FreeBuffer(PoseVbo[0]);
  FreeBuffer(PoseVbo[1]);
  PoseSize := 0;
  PoseFrame := 0;
  PoseRead := 0;
  PoseValid := false;
  PosePending := false;
end;

procedure TShapeCache.InvalidateVertexData(const Changed: TVboTypes);
begin
  ClearSpatial;
  FreeAndNil(IndexRangeCulling);
  { The old pose cannot be replayed after geometry or weights change. }
  PoseValid := false;
  VboToReload := VboToReload + Changed;
end;

procedure TShapeCache.ClearSpatial;
begin
  if SpatialJob<>nil then begin SpatialJob.Cancel;SpatialJob.Release;SpatialJob:=nil end;
  FreeAndNil(SpatialStream);
  FreeBuffer(SpatialVbo);FreeBuffer(SpatialIndirectVbo);
  SpatialUploaded:=0;SpatialUploadFrame:=-1;
end;
function TShapeCache.PrepareSpatial:Boolean;
{$ifndef OpenGLES}
var Bytes,Amount:SizeUInt;OldBuffer:GLint;
{$endif}
begin
  Result:=False;
  {$ifndef OpenGLES}
  if not UseSpatialIndexStreams or not SpatialRenderAllowed or
     not SpatialIndexBuffersSupported then Exit;
  if (SpatialJob<>nil) and SpatialJob.Ready then begin
    SpatialStream:=SpatialJob.TakeResult;SpatialJob.Release;SpatialJob:=nil;
  end;
  if SpatialStream=nil then Exit;
  Bytes:=SizeUInt(SpatialStream.IndexCount)*SizeOf(TGeometryIndex);
  if Bytes=0 then Exit;
  if SpatialUploaded<Bytes then begin
    if SpatialUploadFrame=TFramesPerSecond.RenderFrameId then Exit;
    SpatialUploadFrame:=TFramesPerSecond.RenderFrameId;
    Amount:=SpatialUploadAllowance(SpatialUploadFrame,Bytes-SpatialUploaded);
    if Amount=0 then Exit;
    glGetIntegerv(GL_COPY_WRITE_BUFFER_BINDING,@OldBuffer);
    try
      if SpatialVbo=0 then begin
        glGenBuffers(1,@SpatialVbo);glBindBuffer(GL_COPY_WRITE_BUFFER,SpatialVbo);
        glBufferData(GL_COPY_WRITE_BUFFER,Bytes,nil,GL_STATIC_DRAW);
      end else glBindBuffer(GL_COPY_WRITE_BUFFER,SpatialVbo);
      glBufferSubData(GL_COPY_WRITE_BUFFER,SpatialUploaded,Amount,
        Pointer(PtrUInt(SpatialStream.IndexData)+SpatialUploaded));
      Inc(SpatialUploaded,Amount);Inc(SpatialUploadBytes,Amount);
      if SpatialUploaded=Bytes then SpatialStream.ReleaseUploadedIndices;
    finally glBindBuffer(GL_COPY_WRITE_BUFFER,OldBuffer) end;
  end;
  Result:=SpatialUploaded=Bytes;
  {$endif}
end;

procedure TShapeCache.LoadArraysToVbo(const DynamicGeometry: boolean);
var
  DataUsage: TGLenum;
  NewVbos: boolean;

  { Bind Vbo buffer and load data. Updates AllocatedSize.

    Uses glBufferSubData if possible, as it may be faster than glBufferData
    (not confirmed by tests, but OpenGL docs suggest it:
    https://registry.khronos.org/OpenGL-Refpages/gl4/html/glBufferSubData.xhtml
    "When replacing the entire data store, consider using glBufferSubData
    rather than completely recreating the data store with glBufferData.
    This avoids the cost of reallocating the data store. " ). }
  procedure BufferData(const VboType: TVboType;
    const Target: TBufferTarget; const Size: Cardinal; const Data: Pointer);
  var
    TargetGL: TGLenum;
  begin
    { It may happen that Data = nil, because Arrays.AttributeSize may be 0
      (some shapes just don't need extra per-vertex attributes).

      We should not proceed then.
      Passing Data = nil to glBufferSubData can make actual bugs:
      see the testcase from
      https://github.com/castle-engine/castle-engine/issues/389 :
      open dragon.json, turn on "Dynamic Batching", run some animation
      -- it will update VBOs each frame, and on at least some systems
      (confirmed on 3 systems with NVidia on Windows) it will cause
      weird problems (like unrelated buffers are trashed with garbage).
      Strangely glBufferData doesn't have a problem with Data = nil,
      but we also avoid it. }
    if Data = nil then
    begin
      Assert(Size = 0);
      Exit;
    end;

    if NewVbos or
       (VboType in VboToReload) or
       { In normal circumstances, when vbo is already loaded,
         it should have already the appropriate size. But through VRML/X3D
         events, user may be able to actually incorrectly change
         coordinates, such that new ones have different size than the old ones
         --- in this case, VboToReload optimization fails, and we have
         to reload data (or we'll get terrible OpenGL segfaults later,
         as it tries to access non-existent data from vertex arrays). }
       (VboAllocatedSize[VboType] <> Size) then
    begin
      if VboType = vtIndex then
        DeformedTopologyId := NextDeformedTopologyId;
      if VboType = vtCoordinate then
        DeformedGeometryId := NextDeformedTopologyId;
      RenderContext.BindBuffer[Target] := Vbo[VboType];
      TargetGL := BufferTargetGL[Target];
      if NewVbos or
        (VboAllocatedUsage <> DataUsage) or
        (VboAllocatedSize[VboType] <> Size) then
      begin
        glBufferData(TargetGL, Size, Data, DataUsage);
        VboAllocatedSize[VboType] := Size;
      end else
        glBufferSubData(TargetGL, 0, Size, Data);
    end;
  end;

  function VboTypesToStr(const VboTypes: TVboTypes): string;
  const
    Names: array [TVboType] of string =
    ( 'Coordinate', 'Attribute', 'Index' );
  var
    I: TVboType;
  begin
    Result := '';
    for I := Low(I) to High(I) do
      if I in VboTypes then
      begin
        if Result <> '' then Result := Result + ',';
        Result := Result + Names[I];
      end;
    Result := '[' + Result + ']';
  end;

  procedure CreateVbo;
  var
    VboType: TVboType;
  begin
    for VboType := Low(VboType) to High(VboType) do
      Vbo[VboType] := glCreateBuffer();
  end;

begin
  { Build from the final arrays, not the source IndexedFaceSet: the arrays
    generator may duplicate/remap vertices for normals or UV seams. Keep
    triangle/index order intact for surface queries. Opted-in shaders must
    not use gl_PrimitiveID (each separate draw restarts that counter).
    Bounds are also created while the A/B switch is off, so switching on
    never requires VBO regeneration or synchronous readback. }
  ClearSpatial;
  {$ifndef OpenGLES}
  if UseSpatialIndexStreams and SpatialRenderAllowed and SpatialIndexBuffersSupported and
     not DynamicGeometry and (Geometry<>nil) and
     Geometry.MetadataBoolean['castle.spatialIndexStream'] and
     (Arrays<>nil) and not Arrays.DataFreed and (Arrays.Indexes<>nil) and
     (Arrays.Indexes.Count>=4096*3) then
    SpatialJob:=QueueSpatialMesh(Arrays,Geometry.MetadataDouble['castle.staticIndexRangePadding']);
  {$endif}
  FreeAndNil(IndexRangeCulling);
  { The individual-draw fallback was slower in measurements. GLES and
    desktop drivers without multi-draw keep the original single draw and
    do not pay the hierarchy's construction or memory cost. }
  {$ifndef OpenGLES}
  if GLFeatures.VertexBufferObject and Assigned(glMultiDrawElements) and
     (not DynamicGeometry) and (Geometry <> nil) and
     Geometry.MetadataBoolean['castle.staticIndexRangeCulling'] and
     (Arrays <> nil) and (not Arrays.DataFreed) and
     (Arrays.Primitive = gpTriangles) and (Arrays.Counts = nil) and
     (Arrays.Indexes <> nil) and (Arrays.Indexes.Count >= 4096 * 3) then
    IndexRangeCulling := TStaticMeshIndexRanges.Create(Arrays,
      Geometry.MetadataDouble['castle.staticIndexRangePadding']);
  {$endif}

  if GLFeatures.VertexBufferObject then
  begin
    { In case of VBO not supported (ancient GPUs), we do not free data in Arrays,
      it will be used to provide data at each draw call. }
    Assert(not Arrays.DataFreed);

    NewVbos := Vbo[vtCoordinate] = GLObjectNone;
    if NewVbos then
    begin
      CreateVbo;
      if LogRenderer then
        WritelnLog('Renderer', Format('Creating and loading data to VBOs (%d,%d,%d)',
          [Vbo[vtCoordinate], Vbo[vtAttribute], Vbo[vtIndex]]));
    end else
    begin
      if LogRenderer then
        WritelnLog('Renderer', Format('Loading data to existing VBOs (%d,%d,%d), reloading %s',
          [Vbo[vtCoordinate], Vbo[vtAttribute], Vbo[vtIndex],
           VboTypesToStr(VboToReload)]));
    end;

    if DynamicGeometry then
      { GL_STREAM_DRAW is most suitable if we will modify this every frame,
        according to
        https://www.khronos.org/opengl/wiki/Buffer_Object
        https://computergraphics.stackexchange.com/questions/5712/gl-static-draw-vs-gl-dynamic-draw-vs-gl-stream-draw-does-it-matter
      }
      DataUsage := GL_STREAM_DRAW
    else
      DataUsage := GL_STATIC_DRAW;

    VboCoordinatePreserveGeometryOrder := Arrays.CoordinatePreserveGeometryOrder;

    BufferData(vtCoordinate, btArray,
      Arrays.Count * Arrays.CoordinateSize, Arrays.CoordinateArray);

    BufferData(vtAttribute, btArray,
      Arrays.Count * Arrays.AttributeSize, Arrays.AttributeArray);

    if Arrays.Indexes <> nil then
      BufferData(vtIndex, btElementArray,
        Arrays.Indexes.Count * SizeOf(TGeometryIndex), Arrays.Indexes.L);

    VboAllocatedUsage := DataUsage;

    Arrays.FreeData;

    if GLFeatures.VertexArrayObject and (Vao = nil) then
      Vao := TVertexArrayObject.Create(nil);
  end;

  VboToReload := [];
end;

function TShapeCache.ToString: String;
var
  ShapeNodeName: String;
begin
  if State.ShapeNode <> nil then
    ShapeNodeName := ' ' + State.ShapeNode.X3DName
  else
    ShapeNodeName := '';
  Result := Format('Shape%s %s (%s): %d', [
    ShapeNodeName,
    PointerToStr(Self),
    Geometry.X3DType,
    References
  ]);
end;

{ TShaderProgramCache -------------------------------------------------------- }

destructor TShaderProgramCache.Destroy;
begin
  FreeAndNil(ShaderProgram);
  inherited;
end;

{$endif}
