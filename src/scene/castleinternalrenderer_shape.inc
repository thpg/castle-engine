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

{ Shape class necessary by TRenderer. }

{$ifdef read_interface}
//type
  { Shape that can be rendered. }
  TX3DRendererShape = class(TShape)
  private
    { Generate VBO if needed, and reload VBO contents.
      Assumes GLVertexBufferObject is true.

      Arrays data @italic(must not) be freed (by TGeometryArrays.FreeData)
      before calling this method. Also, this method will always call
      Arrays.FreeData. So do not load the same TGeometryArrays instance
      twice to the Vbo.

      We always keep assertion that Vbo is loaded <=> Arrays data is freed. }
    procedure LoadArraysToVbo;
  public
    { Non-nil means that we have obtained TShaderProgramCache instance,
      with valid Hash and ShaderProgram. Note that ShaderProgram may still
      be @nil, if it failed to link.

      Separate values for each rendering pass, since different rendering
      passes probably have different GlobalLights and so will require different
      shaders. This makes multi-pass rendering, like for shadow volumes,
      play nicely with shaders. Otherwise we could recreate shaders at each
      rendering pass. }
    ProgramCache: array [TTotalRenderingPass] of TShaderProgramCache;

    Cache: TShapeCache;

    { Read-only access for GPU surface queries. Borrowed GL names remain owned
      by the renderer and must be refreshed after a context/cache rebuild. }
    function SurfaceQueryBuffers(out Coordinates, Indices: TGLBuffer;
      out Stride, VertexCount, IndexCount: Cardinal): Boolean;
    { Exact vertices selected by the last draw, including cached GPU skinning.
      Query immediately after rendering; buffers remain owned by the shape. }
    function DeformedQueryBuffers(out Coordinates, Indices: TGLBuffer;
      out Stride, VertexCount, IndexCount: Cardinal; out Posed: Boolean): Boolean;
    { Prepare only static indexed geometry in the native cache, without
      textures, shaders or drawing. Call on the GL thread on a query miss. }
    function PrepareSurfaceQueryBuffers(const RenderOptions: TCastleRenderOptions): Boolean;
  public

    { Assign this each time before passing this shape to RenderShape. }
    Fog: TFogFunctionality;

    { For implementing TextureCoordinateGenerator.mode = "MIRROR-PLANE". }
    MirrorPlaneUniforms: TMirrorPlaneUniforms;

    { Is bump mapping allowed by the current shape.
      Fully calculated only after InitMeshRenderer, as determining GeneratorClass
      is needed to set this. }
    BumpMappingAllowed: Boolean;

    { Is bump mapping used for current shape.
      Fully calculated only during render, after BumpMappingAllowed is calculated
      and after textures are applied.
      This is determined by BumpMappingAllowed,
      global BumpMapping, and by the texture information for current
      shape (whether user provided normal map, height map etc.) }
    BumpMappingUsed: Boolean;

    { Along with Shape.BumpMappingUsed, this is calculated (use only if Shape.BumpMappingUsed). }
    BumpMappingTextureCoordinatesId: Cardinal;

    destructor Destroy; override;
  end;
{$endif read_interface}

{$ifdef read_implementation}

type
  { Access the existing owner lifecycle without preparing scene materials. }
  TSurfaceQueryTransformAccess = class(TCastleTransform);

function TX3DRendererShape.SurfaceQueryBuffers(out Coordinates, Indices: TGLBuffer;
  out Stride, VertexCount, IndexCount: Cardinal): Boolean;
begin
  Coordinates := 0; Indices := 0; Stride := 0; VertexCount := 0; IndexCount := 0;
  Result := (Cache <> nil) and (Cache.Arrays <> nil);
  if not Result then Exit;
  Result := Cache.VboCoordinatePreserveGeometryOrder and
    (Cache.Arrays.Primitive = gpTriangles) and Cache.Arrays.HasIndexes and
    (Cache.Vbo[vtCoordinate] <> 0) and (Cache.Vbo[vtIndex] <> 0) and
    (Cache.VboToReload = []);
  if not Result then Exit;
  Coordinates := Cache.Vbo[vtCoordinate]; Indices := Cache.Vbo[vtIndex];
  Stride := Cache.Arrays.CoordinateSize;
  VertexCount := Cache.Arrays.Count; IndexCount := Cache.Arrays.IndexesCount;
end;

function TX3DRendererShape.DeformedQueryBuffers(out Coordinates, Indices: TGLBuffer;
  out Stride, VertexCount, IndexCount: Cardinal; out Posed: Boolean): Boolean;
begin
  Coordinates:=0;Indices:=0;Stride:=0;VertexCount:=0;IndexCount:=0;Posed:=false;
  Result:=(Cache<>nil) and (Cache.Arrays<>nil) and (Cache.Vbo[vtCoordinate]<>0) and
    (Cache.Arrays.Primitive=gpTriangles) and (Cache.VboToReload=[]);
  if not Result then Exit;
  Posed:=Cache.PoseValid;
  { A rigid attachment (e.g. the helmet) can inherit a Skin traversal node
    without belonging to its animated shapes. Its ordinary vertex buffer is
    already the rendered geometry; waiting for a posed buffer would omit it
    from ray queries. Only GPU-skinned geometry needs a deformation cache. }
  if State.SkinnedAnimatedShape and Cache.Arrays.HasSkinWeights0 and
     Cache.Arrays.HasSkinJoints0 and (State.Skin.InternalMeshCalculation<>mcCpu) and
     not Posed then Exit(false);
  Coordinates:=Cache.Vbo[vtCoordinate];Stride:=Cache.Arrays.CoordinateSize;
  VertexCount:=Cache.Arrays.Count;
  if Posed then begin Coordinates:=Cache.PoseVbo[Cache.PoseRead];Stride:=10*SizeOf(Single);end;
  if Cache.Arrays.HasIndexes then begin Indices:=Cache.Vbo[vtIndex];IndexCount:=Cache.Arrays.IndexesCount;end
  else IndexCount:=VertexCount;
end;

function TX3DRendererShape.PrepareSurfaceQueryBuffers(
  const RenderOptions: TCastleRenderOptions): Boolean;
var
  Coordinates, Indices: TGLBuffer;
  Stride, VertexCount, IndexCount: Cardinal;
  GeneratorClass: TArraysGeneratorClass;
  Generator: TArraysGenerator;
  OldArray, OldIndex: GLint;
begin
  if SurfaceQueryBuffers(Coordinates, Indices, Stride, VertexCount, IndexCount) then
    Exit(true);
  Result := false;
  if not ApplicationProperties.IsGLContextOpen or not GLFeatures.VertexBufferObject or
     not (Geometry is TIndexedFaceSetNode) or (State.Skin <> nil) or
     (ParentScene = nil) then Exit;
  GeneratorClass := GetArraysGenerator(Geometry);
  if GeneratorClass = nil then Exit;
  { A tile first requested in Focus may never have called scene PrepareResources.
    Register its normal GLContextClose before acquiring any cached resources. }
  TSurfaceQueryTransformAccess(ParentScene).RegisterGLContextClose;
  if Cache = nil then Cache := RendererCache.Shape_IncReference(Self, RenderOptions);
  { IncReference may have returned a cache already prepared by another shape. }
  if SurfaceQueryBuffers(Coordinates, Indices, Stride, VertexCount, IndexCount) then
    Exit(true);
  { The same cache owns both preparations. Never change a valid warm cache,
    and force all VBO data to reload when a later draw completes the layout. }
  Cache.SurfaceQueryOnly := true;
  Cache.InvalidateVertexData(AllVboTypes);
  FreeAndNil(Cache.Arrays);
  Generator := GeneratorClass.Create(Self);
  try Cache.Arrays := Generator.GenerateArrays;
  finally Generator.Free end;
  glGetIntegerv(GL_ARRAY_BUFFER_BINDING, @OldArray);
  glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, @OldIndex);
  try LoadArraysToVbo;
  finally
    RenderContext.BindBuffer[btArray] := OldArray;
    RenderContext.BindBuffer[btElementArray] := OldIndex;
  end;
  Result := SurfaceQueryBuffers(Coordinates, Indices, Stride, VertexCount, IndexCount);
end;

{ Sometimes the updates indicated by Shape.Cache.VboToReload can be performed without
  actually recreating the Shape.Cache.Arrays (so no need to create TArraysGenerator
  and call TArraysGenerator.GenerateArrays).
  Detect and perform such optimized case.

  This is crucial for skinned animation, that only requires updating coords/normals/tangents
  each frame, no need for updating other attributes. }
function FastUpdateArrays(const Shape: TX3DRendererShape): Boolean;

  { If possible, update the coordinate/normal/tangent data in VBO fast.

    This is carefully implemented to do a specific case of TShapeCache.LoadArraysToVbo.
    It optimizes the case of animating coordinates/normals/tangents using CoordinateInterpolator,
    which is very important to optimize, since that's how glTF skinned animations
    are done.

    Pass non-nil Tangents if VBO should have tangent data,
    pass nil Tangents if VBO should not have it. }
  function FastCoordinateNormalUpdate(const Cache: TShapeCache;
    const Coords, Normals: TVector3List;
    const Tangents: TVector4List): Boolean;
  var
    NewCoordinates, NewCoord: Pointer;
    Count, Size, ItemSize: Cardinal;
    I: Integer;
  begin
    Result := false;

    if Cache.VboCoordinatePreserveGeometryOrder and
       (Normals.Count = Coords.Count) and
       ( (Tangents = nil) or
         (Tangents.Count = Coords.Count) ) then
    begin
      Count := Coords.Count;

      ItemSize := SizeOf(TVector3) * 2;
      if Tangents <> nil then
        ItemSize := ItemSize + SizeOf(TVector4);
      Size := Count * ItemSize;

      if (Cache.VboAllocatedUsage = GL_STREAM_DRAW) and
         { Comparing the byte sizes also makes sure that previous and new coordinates
           count stayed the same.
           (Well, assuming we didn't change the Count, and simultaneously changed
           the Tangent existence, which in theory could cause Size to match
           for different structures.)
         }
         (Cache.VboAllocatedSize[vtCoordinate] = Size) then
      begin
        Result := true;
        Cache.VboToReload := Cache.VboToReload - [vtCoordinate]; // vtCoordinate are done
        if Count <> 0 then
        begin
          // calculate NewCoordinates
          NewCoordinates := GetMem(Size);
          try
            NewCoord := NewCoordinates;

            if Tangents <> nil then
            begin
              for I := 0 to Count - 1 do
              begin
                PVector3(NewCoord)^ := Coords.L[I];
                PtrUInt(NewCoord) := PtrUInt(NewCoord) + SizeOf(TVector3);

                PVector3(NewCoord)^ := Normals.L[I];
                PtrUInt(NewCoord) := PtrUInt(NewCoord) + SizeOf(TVector3);

                PVector4(NewCoord)^ := Tangents.L[I];
                PtrUInt(NewCoord) := PtrUInt(NewCoord) + SizeOf(TVector4);
              end;
            end else
            begin
              for I := 0 to Count - 1 do
              begin
                PVector3(NewCoord)^ := Coords.L[I];
                PtrUInt(NewCoord) := PtrUInt(NewCoord) + SizeOf(TVector3);

                PVector3(NewCoord)^ := Normals.L[I];
                PtrUInt(NewCoord) := PtrUInt(NewCoord) + SizeOf(TVector3);
              end;
            end;

            // load NewCoordinates to GPU
            RenderContext.BindBuffer[btArray] := Cache.Vbo[vtCoordinate];
            glBufferSubData(GL_ARRAY_BUFFER, 0, Size, NewCoordinates);
          finally FreeMemNiling(NewCoordinates) end;
        end;
      end;
    end;
  end;

var
  Cache: TShapeCache;
  Coords, Normals: TVector3List;
  Tangents: TVector4List;
begin
  Result := false;

  Cache := Shape.Cache;

  // this only optimizes the specific case of VboToReload = [vtCoordinate] now
  if Cache.VboToReload <> [vtCoordinate] then
    Exit;

  { When VBO of coordinates is 0 then
    - VBOs not supported (ancient GPU) -> we need to really update Arrays contents each time
    - or VBO of coordinates was not initialized yet }
  if Cache.Vbo[vtCoordinate] = GLObjectNone then
    Exit;
  if Cache.Arrays = nil then // not initialized yet
    Exit;

  if // Shape has coordinates expressed in simple way
     (Shape.Geometry.CoordField <> nil) and
     (Shape.Geometry.CoordField.Value is TCoordinateNode) then // checks also Value <> nil
  begin
    Coords := TCoordinateNode(Shape.Geometry.CoordField.Value).FdPoint.Items;

    if // Shape has normals expressed in simple way
       (Shape.Geometry.NormalField <> nil) and
       (Shape.Geometry.NormalField.Value is TNormalNode) then // checks also Value <> nil
    begin
      Normals := TNormalNode(Shape.Geometry.NormalField.Value).FdVector.Items;

      // Shape has normals expressed in tangents way, or doesn't use tangents (when no bump mapping used)
      if ( (not Cache.Arrays.HasTangent) or
           ( (Shape.Geometry.TangentField <> nil) and
             (Shape.Geometry.TangentField.Value is TTangentNode) ) ) then // checks also Value <> nil
      begin
        if Cache.Arrays.HasTangent then
          Tangents := TTangentNode(Shape.Geometry.TangentField.Value).FdVector.Items
        else
          Tangents := nil;

        Result := FastCoordinateNormalUpdate(Cache, Coords, Normals, Tangents);
      end;
    end;
  end;
end;

{ TX3DRendererShape --------------------------------------------------------- }

destructor TX3DRendererShape.Destroy;
begin
  FreeAndNil(MirrorPlaneUniforms);
  inherited;
end;

procedure TX3DRendererShape.LoadArraysToVbo;
begin
  Assert(Cache <> nil);
  Cache.LoadArraysToVbo(DynamicGeometry);
end;

{$endif}
