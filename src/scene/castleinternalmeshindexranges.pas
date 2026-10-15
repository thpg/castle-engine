{ Conservative draw-range culling for explicitly opted-in static meshes.
  Uses the existing index buffer in its original order. No geometry copy,
  remap, GPU readback, or per-frame allocation is needed. }
unit CastleInternalMeshIndexRanges;

{$I castleconf.inc}

interface

uses CastleVectors, CastleBoxes, CastleFrustum, CastleInternalGeometryArrays;

type
  TMeshIndexRange = record
    First, Count: Cardinal;
  end;

  TStaticMeshIndexRanges = class
  private
    type
      TNode = record
        Bounds: TBox3D;
        First, Count: Cardinal;
        Left, Right: Integer;
      end;
    var
      FNodes: array of TNode;
      FRanges: array of TMeshIndexRange;
      FDrawCounts: array of LongInt;
      FDrawOffsets: array of Pointer;
      FNodeCount, FRangeCount: Integer;
      FIndexCount, FSelectedIndexCount, FTestedNodes: Cardinal;
      FMergeGapIndices: Cardinal;
      FFrustum: TFrustum;
      FPositiveCorner: array[TFrustumPlane, 0..2] of Byte;
    procedure AppendRange(const First, Count: Cardinal);
    procedure SelectNode(const Index: Integer; PlaneMask: Byte);
    function GetRange(const Index: Integer): TMeshIndexRange;
    function GetDrawCounts: PLongInt;
    function GetDrawOffsets: Pointer;
  public
    constructor Create(const Arrays: TGeometryArrays; const Padding: Single);
    { Recomputed for each render pass, using that pass's actual matrices.
      Returned ranges are ascending, non-overlapping, and triangle-aligned. }
    procedure Select(const Frustum: TFrustum;
      const MergeGapTriangles: Cardinal = 0; const MaxDrawRanges: Integer = 128);
    property IndexCount: Cardinal read FIndexCount;
    property SelectedIndexCount: Cardinal read FSelectedIndexCount;
    property TestedNodes: Cardinal read FTestedNodes;
    property RangeCount: Integer read FRangeCount;
    property Ranges[const Index: Integer]: TMeshIndexRange read GetRange;
    { OpenGL-compatible arrays. Counts are signed 32-bit, offsets are
      pointer-sized byte offsets into the unchanged element VBO. }
    property DrawCounts: PLongInt read GetDrawCounts;
    property DrawOffsets: Pointer read GetDrawOffsets;
  end;

implementation

uses Math;

const
  LeafTriangles = 512;

constructor TStaticMeshIndexRanges.Create(const Arrays: TGeometryArrays;
  const Padding: Single);
var
  TriangleCount: Cardinal;

  function BuildNode(const FirstTriangle, Count: Cardinal): Integer;
  var
    I, VertexIndex, Half: Cardinal;
    Left, Right: Integer;
    B: TBox3D;
  begin
    Result := FNodeCount;
    Inc(FNodeCount);
    FNodes[Result].First := FirstTriangle * 3;
    FNodes[Result].Count := Count * 3;
    if Count <= LeafTriangles then
    begin
      B := TBox3D.Empty;
      for I := FirstTriangle * 3 to (FirstTriangle + Count) * 3 - 1 do
      begin
        VertexIndex := Arrays.Indexes[I];
        B.Include(Arrays.Position(VertexIndex)^);
      end;
      FNodes[Result].Bounds := B.Grow(Max(0, Padding));
      FNodes[Result].Left := -1;
      FNodes[Result].Right := -1;
    end else
    begin
      Half := Count div 2;
      Left := BuildNode(FirstTriangle, Half);
      Right := BuildNode(FirstTriangle + Half, Count - Half);
      FNodes[Result].Left := Left;
      FNodes[Result].Right := Right;
      B := FNodes[Left].Bounds;
      B.Include(FNodes[Right].Bounds);
      FNodes[Result].Bounds := B;
    end;
  end;

begin
  inherited Create;
  if (Arrays = nil) or Arrays.DataFreed or (Arrays.Indexes = nil) or
     (Arrays.Primitive <> gpTriangles) or (Arrays.Counts <> nil) then Exit;
  FIndexCount := Arrays.Indexes.Count;
  if (FIndexCount = 0) or (FIndexCount mod 3 <> 0) then
  begin
    FIndexCount := 0;
    Exit;
  end;
  TriangleCount := FIndexCount div 3;
  { A balanced split has less than twice the rounded-up leaf count;
    two nodes per leaf fit this conservative reservation. }
  SetLength(FNodes, 4 * ((TriangleCount + LeafTriangles - 1) div LeafTriangles));
  BuildNode(0, TriangleCount);
  SetLength(FNodes, FNodeCount);
  SetLength(FRanges, (FNodeCount + 1) div 2);
  SetLength(FDrawCounts, Length(FRanges));
  SetLength(FDrawOffsets, Length(FRanges));
end;

procedure TStaticMeshIndexRanges.AppendRange(const First, Count: Cardinal);
var Gap: Cardinal;
begin
  if FRangeCount > 0 then
  begin
    Gap := First - (FRanges[FRangeCount - 1].First + FRanges[FRangeCount - 1].Count);
    if Gap <= FMergeGapIndices then
    begin
      Inc(FRanges[FRangeCount - 1].Count, Gap + Count);
      Inc(FSelectedIndexCount, Gap + Count);
      Exit;
    end;
  end;
  FRanges[FRangeCount].First := First;
  FRanges[FRangeCount].Count := Count;
  Inc(FRangeCount);
  Inc(FSelectedIndexCount, Count);
end;

procedure TStaticMeshIndexRanges.SelectNode(const Index: Integer; PlaneMask: Byte);
var Plane: TFrustumPlane; Bit: Byte; P: PVector4; B: ^TBox3D;
  X, Y, Z: Byte;
begin
  Inc(FTestedNodes);
  B := @FNodes[Index].Bounds;
  for Plane := Low(Plane) to High(Plane) do
  begin
    Bit := 1 shl Ord(Plane);
    if PlaneMask and Bit = 0 then Continue;
    P := @FFrustum.Planes[Plane];
    X := FPositiveCorner[Plane, 0];
    Y := FPositiveCorner[Plane, 1];
    Z := FPositiveCorner[Plane, 2];
    if P^.X * B^.Data[X].X + P^.Y * B^.Data[Y].Y +
       P^.Z * B^.Data[Z].Z + P^.W < 0 then Exit;
    { Children cannot cross a plane which contains their complete parent.
      Passing the reduced mask avoids repeating those tests at every level. }
    if P^.X * B^.Data[1-X].X + P^.Y * B^.Data[1-Y].Y +
       P^.Z * B^.Data[1-Z].Z + P^.W > 0 then
      PlaneMask := PlaneMask and not Bit;
  end;
  if (PlaneMask = 0) or (FNodes[Index].Left < 0) then
    AppendRange(FNodes[Index].First, FNodes[Index].Count)
  else
  begin
    SelectNode(FNodes[Index].Left, PlaneMask);
    SelectNode(FNodes[Index].Right, PlaneMask);
  end;
end;

procedure TStaticMeshIndexRanges.Select(const Frustum: TFrustum;
  const MergeGapTriangles: Cardinal; const MaxDrawRanges: Integer);
var Plane: TFrustumPlane; Mask: Byte; I: Integer;
begin
  FFrustum := Frustum;
  FMergeGapIndices := Min(MergeGapTriangles, Cardinal(65536)) * 3;
  FRangeCount := 0;
  FSelectedIndexCount := 0;
  FTestedNodes := 0;
  for Plane := Low(Plane) to High(Plane) do
  begin
    FPositiveCorner[Plane, 0] := Ord(Frustum.Planes[Plane].X >= 0);
    FPositiveCorner[Plane, 1] := Ord(Frustum.Planes[Plane].Y >= 0);
    FPositiveCorner[Plane, 2] := Ord(Frustum.Planes[Plane].Z >= 0);
  end;
  Mask := $3f;
  if Frustum.FarInfinity then Mask := Mask and not (1 shl Ord(fpFar));
  if FNodeCount <> 0 then SelectNode(0, Mask);
  { A fragmented or almost completely visible mesh is cheaper as its
    original single draw. This fallback only adds invisible triangles. }
  if (FRangeCount > Max(1, MaxDrawRanges)) or
     ((FRangeCount > 1) and (QWord(FSelectedIndexCount) * 10 >= QWord(FIndexCount) * 9)) then
  begin
    FRangeCount := 0;
    FSelectedIndexCount := 0;
    AppendRange(0, FIndexCount);
  end;
  for I := 0 to FRangeCount - 1 do
  begin
    FDrawCounts[I] := FRanges[I].Count;
    FDrawOffsets[I] := Pointer(PtrUInt(FRanges[I].First) * SizeOf(TGeometryIndex));
  end;
end;

function TStaticMeshIndexRanges.GetRange(const Index: Integer): TMeshIndexRange;
begin
  Result := FRanges[Index];
end;

function TStaticMeshIndexRanges.GetDrawCounts: PLongInt;
begin
  if FRangeCount = 0 then Exit(nil);
  Result := @FDrawCounts[0];
end;

function TStaticMeshIndexRanges.GetDrawOffsets: Pointer;
begin
  if FRangeCount = 0 then Exit(nil);
  Result := @FDrawOffsets[0];
end;

end.
