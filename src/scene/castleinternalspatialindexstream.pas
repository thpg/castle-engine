{ Spatial raster indices. Original geometry, triangle IDs and RTX/contact data
  are never modified. Draw commands retain original primitive order, including
  coplanar surfaces. Build workers own immutable snapshots, never CGE/GL objects. }
unit CastleInternalSpatialIndexStream;
{$I castleconf.inc}
interface
uses Classes, CastleVectors, CastleBoxes, CastleFrustum, CastleInternalGeometryArrays,
  CastleInternalMeshIndexRanges;
type
  TSpatialPositions=array of TVector3;
  TSpatialIndices=array of TGeometryIndex;
  TSpatialIds=array of Cardinal;
  TSpatialCluster=record Bounds:TBox3D;First,Count:Cardinal end;
  TSpatialDrawCommand=packed record
    Count,InstanceCount,FirstIndex:Cardinal;
    BaseVertex:LongInt;
    BaseInstance:Cardinal;
  end;
  TSpatialSourceRun=record First,Count,Cluster:Cardinal end;
  TSpatialMeshIndexStream=class
  private
    FIndices:TSpatialIndices;
    FOriginalTriangle,FSpatialTriangle,FClusterOfSource:TSpatialIds;
    FClusters:array of TSpatialCluster;
    FVisible:array of Boolean;
    FSourceRuns:array of TSpatialSourceRun;
    FIndexCount:Cardinal;
    FRanges:array of TMeshIndexRange;
    FCounts:array of LongInt;
    FOffsets:array of Pointer;
    FCommands:array of TSpatialDrawCommand;
    FRangeCount:Integer;
    FSelected:Cardinal;
    function GetIndexData:Pointer;
    function GetIndexCount:Cardinal;
    function GetCounts:PLongInt;
    function GetOffsets:Pointer;
    function GetCommands:Pointer;
  public
    constructor Create(const Positions:TSpatialPositions;const Source:TSpatialIndices;
      const Padding:Single;Cancelled:PLongInt=nil);
    { False = use original VBO/single draw, never a reordered whole-mesh draw. }
    function Select(const Frustum:TFrustum;const MaxRanges:Integer=128):Boolean;
    procedure ReleaseUploadedIndices;
    property Indices:TSpatialIndices read FIndices;
    property OriginalTriangle:TSpatialIds read FOriginalTriangle;
    property SpatialTriangle:TSpatialIds read FSpatialTriangle;
    property IndexData:Pointer read GetIndexData;
    property IndexCount:Cardinal read GetIndexCount;
    property SelectedIndexCount:Cardinal read FSelected;
    property RangeCount:Integer read FRangeCount;
    property DrawCounts:PLongInt read GetCounts;
    property DrawOffsets:Pointer read GetOffsets;
    property DrawCommands:Pointer read GetCommands;
  end;
  TSpatialMeshJob=class
  private
    FReferences,FCancelled,FReady:LongInt;
    FPositions:TSpatialPositions;
    FIndices:TSpatialIndices;
    FPadding:Single;
    FResult:TSpatialMeshIndexStream;
    FBytes:SizeUInt;
    procedure Execute;
  public
    destructor Destroy;override;
    procedure Cancel;
    procedure Release;
    function TakeResult:TSpatialMeshIndexStream;
    function Ready:Boolean;
  end;
function QueueSpatialMesh(const Arrays:TGeometryArrays;Padding:Single):TSpatialMeshJob;
function SpatialUploadAllowance(Frame:Int64;Wanted:SizeUInt):SizeUInt;
var
  SpatialRenderAllowed:Boolean=true;
  UseSpatialIndexStreams:Boolean=false;
  UseSpatialIndirect:Boolean=false;
  SpatialQueued,SpatialCompleted,SpatialCancelled,SpatialDeclined:QWord;
  SpatialUploadBytes,SpatialSourceBytes,SpatialPasses,SpatialDraws,SpatialRangeFallbacks:QWord;
  SpatialCandidateIndices,SpatialSubmittedIndices:QWord;
implementation
uses SysUtils, Math, SyncObjs;
const ClusterSize=256;MaxPendingBytes=128*1024*1024;MaxQueued=32;
type
  TPair=record Key,Triangle:Cardinal end;
  TSpatialWorker=class(TThread)
    procedure Execute;override;
  end;
var PendingJobs:TList;QueueLock:TRTLCriticalSection;Wake:TEvent;
  Workers:array[0..1]of TSpatialWorker;
  Stopping:Boolean;PendingBytes:SizeUInt;
  UploadFrame:Int64=-1;UploadRemaining:SizeUInt;
function Morton(const P:TVector3;const B:TBox3D):Cardinal;
var V:TVector3;Extent:Single;X,Y,Z,I:Cardinal;
begin
  V:=B.Data[1]-B.Data[0];
  { Isotropic cells: a few metres of terrain height must not dominate a
    kilometre-wide tile merely because its Y extent is small. }
  Extent:=Max(0.000001,Max(V.X,Max(V.Y,V.Z)));
  X:=EnsureRange(Trunc((P.X-B.Data[0].X)/Extent*1023),0,1023);
  Y:=EnsureRange(Trunc((P.Y-B.Data[0].Y)/Extent*1023),0,1023);
  Z:=EnsureRange(Trunc((P.Z-B.Data[0].Z)/Extent*1023),0,1023);
  Result:=0;
  for I:=0 to 9 do Result:=Result or (((X shr I)and 1)shl(I*3)) or
    (((Y shr I)and 1)shl(I*3+1)) or (((Z shr I)and 1)shl(I*3+2));
end;
constructor TSpatialMeshIndexStream.Create(const Positions:TSpatialPositions;const Source:TSpatialIndices;
  const Padding:Single;Cancelled:PLongInt);
var Pairs:array of TPair;B:TBox3D;I,J,K,C,N,Start,Finish,T:Integer;Centre:TVector3;
  procedure Sort(L,R:Integer;ById:Boolean);
  var A,Bi:Integer;Pivot,Temp:TPair;
    function Less(const A,B:TPair):Boolean;
    begin
      if ById then Exit(A.Triangle<B.Triangle);
      Result:=(A.Key<B.Key) or ((A.Key=B.Key) and (A.Triangle<B.Triangle));
    end;
  begin
    A:=L;Bi:=R;Pivot:=Pairs[(L+R) div 2];
    repeat
      while Less(Pairs[A],Pivot) do Inc(A);
      while Less(Pivot,Pairs[Bi]) do Dec(Bi);
      if A<=Bi then begin Temp:=Pairs[A];Pairs[A]:=Pairs[Bi];Pairs[Bi]:=Temp;Inc(A);Dec(Bi) end;
    until A>Bi;
    if L<Bi then Sort(L,Bi,ById);if A<R then Sort(A,R,ById);
  end;
  function IsCancelled:Boolean;
  begin Result:=(Cancelled<>nil) and (InterlockedCompareExchange(Cancelled^,0,0)<>0) end;
begin
  inherited Create;
  N:=Length(Source) div 3;
  if (N=0) or (Length(Source) mod 3<>0) then Exit;
  B:=TBox3D.Empty;for I:=0 to High(Positions) do B.Include(Positions[I]);
  SetLength(Pairs,N);
  for I:=0 to N-1 do begin
    if (I mod 4096=0) and IsCancelled then Exit;
    for K:=0 to 2 do if Source[I*3+K]>=Cardinal(Length(Positions)) then Exit;
    Centre:=(Positions[Source[I*3]]+Positions[Source[I*3+1]]+Positions[Source[I*3+2]])/3;
    Pairs[I].Key:=Morton(Centre,B);Pairs[I].Triangle:=I;
  end;
  Sort(0,N-1,False);if IsCancelled then Exit;
  FIndexCount:=Length(Source);
  SetLength(FIndices,Length(Source));SetLength(FOriginalTriangle,N);
  SetLength(FSpatialTriangle,N);SetLength(FClusterOfSource,N);
  SetLength(FClusters,(N+ClusterSize-1) div ClusterSize);SetLength(FVisible,Length(FClusters));
  for C:=0 to High(FClusters) do begin
    if IsCancelled then begin FIndices:=nil;Exit end;
    Start:=C*ClusterSize;Finish:=Min(N,Start+ClusterSize)-1;
    { Source order within a cluster improves vertex-cache locality and lets
      command merging retain coplanar ordering with few ranges. }
    Sort(Start,Finish,True);B:=TBox3D.Empty;
    for J:=Start to Finish do begin
      T:=Pairs[J].Triangle;FOriginalTriangle[J]:=T;FSpatialTriangle[T]:=J;FClusterOfSource[T]:=C;
      for K:=0 to 2 do begin FIndices[J*3+K]:=Source[T*3+K];B.Include(Positions[Source[T*3+K]]) end;
    end;
    FClusters[C].First:=Start*3;FClusters[C].Count:=(Finish-Start+1)*3;
    FClusters[C].Bounds:=B.Grow(Max(0,Padding));
  end;
  SetLength(FSourceRuns,N);J:=0;
  for I:=0 to N-1 do begin
    if (J>0) and (FSourceRuns[J-1].Cluster=FClusterOfSource[I]) and
       (FSourceRuns[J-1].First+FSourceRuns[J-1].Count=FSpatialTriangle[I]*3) then
      Inc(FSourceRuns[J-1].Count,3)
    else begin
      FSourceRuns[J].First:=FSpatialTriangle[I]*3;FSourceRuns[J].Count:=3;
      FSourceRuns[J].Cluster:=FClusterOfSource[I];Inc(J);
    end;
  end;
  SetLength(FSourceRuns,J);FClusterOfSource:=nil;
  { Range capacity is bounded independently of mesh size. Fragmented visibility
    falls back to the untouched original stream, not thousands of submissions. }
  SetLength(FRanges,129);SetLength(FCounts,129);SetLength(FOffsets,129);SetLength(FCommands,129);
end;
function TSpatialMeshIndexStream.Select(const Frustum:TFrustum;const MaxRanges:Integer):Boolean;
var I,Limit:Integer;Offset:Cardinal;AllVisible:Boolean;
begin
  Result:=False;FRangeCount:=0;FSelected:=0;AllVisible:=True;
  Limit:=EnsureRange(MaxRanges,1,128);
  for I:=0 to High(FClusters) do begin
    FVisible[I]:=Frustum.Box3DCollisionPossibleSimple(FClusters[I].Bounds);
    AllVisible:=AllVisible and FVisible[I];
  end;
  if AllVisible then Exit;
  { Walk SOURCE order. Reordering opaque triangles can change equal-depth
    ownership on arches, coplanar markings and facade trim. Spatial storage
    never grants permission to reorder those primitive submissions. }
  for I:=0 to High(FSourceRuns) do if FVisible[FSourceRuns[I].Cluster] then begin
    Offset:=FSourceRuns[I].First;Inc(FSelected,FSourceRuns[I].Count);
    if (FRangeCount>0) and (FRanges[FRangeCount-1].First+FRanges[FRangeCount-1].Count=Offset) then
      Inc(FRanges[FRangeCount-1].Count,FSourceRuns[I].Count)
    else begin
      if FRangeCount=Limit then begin Inc(SpatialRangeFallbacks);Exit end;
      FRanges[FRangeCount].First:=Offset;FRanges[FRangeCount].Count:=FSourceRuns[I].Count;Inc(FRangeCount);
    end;
  end;
  if QWord(FSelected)*10>=QWord(FIndexCount)*9 then Exit;
  for I:=0 to FRangeCount-1 do begin
    FCounts[I]:=FRanges[I].Count;FOffsets[I]:=Pointer(PtrUInt(FRanges[I].First)*SizeOf(TGeometryIndex));
    FCommands[I].Count:=FRanges[I].Count;FCommands[I].InstanceCount:=1;
    FCommands[I].FirstIndex:=FRanges[I].First;FCommands[I].BaseVertex:=0;FCommands[I].BaseInstance:=0;
  end;
  Result:=True;
end;
function TSpatialMeshIndexStream.GetIndexData:Pointer;
begin if Length(FIndices)=0 then Exit(nil);Result:=@FIndices[0] end;
function TSpatialMeshIndexStream.GetIndexCount:Cardinal;
begin Result:=FIndexCount end;
procedure TSpatialMeshIndexStream.ReleaseUploadedIndices;
begin FIndices:=nil end;
function TSpatialMeshIndexStream.GetCounts:PLongInt;
begin if FRangeCount=0 then Exit(nil);Result:=@FCounts[0] end;
function TSpatialMeshIndexStream.GetOffsets:Pointer;
begin if FRangeCount=0 then Exit(nil);Result:=@FOffsets[0] end;
function TSpatialMeshIndexStream.GetCommands:Pointer;
begin if FRangeCount=0 then Exit(nil);Result:=@FCommands[0] end;
function SpatialUploadAllowance(Frame:Int64;Wanted:SizeUInt):SizeUInt;
begin
  if Frame<>UploadFrame then begin UploadFrame:=Frame;UploadRemaining:=2*1024*1024 end;
  Result:=Min(Wanted,Min(UploadRemaining,SizeUInt(256*1024)));Dec(UploadRemaining,Result);
end;
destructor TSpatialMeshJob.Destroy;
begin FResult.Free;inherited end;
procedure TSpatialMeshJob.Cancel;
begin InterlockedExchange(FCancelled,1) end;
procedure TSpatialMeshJob.Release;
begin if InterlockedDecrement(FReferences)=0 then Free end;
function TSpatialMeshJob.Ready:Boolean;
begin Result:=InterlockedCompareExchange(FReady,0,0)<>0 end;
function TSpatialMeshJob.TakeResult:TSpatialMeshIndexStream;
begin
  Result:=nil;
  if InterlockedCompareExchange(FReady,0,0)=0 then Exit;
  Result:=FResult;FResult:=nil;
end;
procedure TSpatialMeshJob.Execute;
begin
  try
    if InterlockedCompareExchange(FCancelled,0,0)=0 then begin
      FResult:=TSpatialMeshIndexStream.Create(FPositions,FIndices,FPadding,@FCancelled);
      if (FResult.IndexCount<>Cardinal(Length(FIndices))) or (InterlockedCompareExchange(FCancelled,0,0)<>0) then
        FreeAndNil(FResult);
    end;
  except FreeAndNil(FResult) end;
  FPositions:=nil;FIndices:=nil;
  EnterCriticalSection(QueueLock);
  try
    Dec(PendingBytes,FBytes);if FResult<>nil then Inc(SpatialCompleted) else Inc(SpatialCancelled);
  finally LeaveCriticalSection(QueueLock) end;
  InterlockedExchange(FReady,1); // publishes immutable result after input release
end;
procedure TSpatialWorker.Execute;
var Job:TSpatialMeshJob;
begin
  while True do begin
    Job:=nil;EnterCriticalSection(QueueLock);
    try
      if PendingJobs.Count>0 then begin Job:=TSpatialMeshJob(PendingJobs[0]);PendingJobs.Delete(0) end
      else if Stopping then Exit
      else Wake.ResetEvent;
    finally LeaveCriticalSection(QueueLock) end;
    if Job=nil then Wake.WaitFor(1000)
    else begin Job.Execute;Job.Release end;
  end;
end;
function QueueSpatialMesh(const Arrays:TGeometryArrays;Padding:Single):TSpatialMeshJob;
var Size:SizeUInt;I:Integer;
begin
  Result:=nil;
  if (Arrays=nil) or Arrays.DataFreed or (Arrays.Indexes=nil) or
     (Arrays.Primitive<>gpTriangles) or (Arrays.Counts<>nil) or (Arrays.Indexes.Count mod 3<>0) then Exit;
  Size:=SizeUInt(Arrays.Count)*SizeOf(TVector3)+SizeUInt(Arrays.Indexes.Count)*SizeOf(TGeometryIndex);
  EnterCriticalSection(QueueLock);
  try
    if (PendingJobs.Count>=MaxQueued) or (PendingBytes+Size>MaxPendingBytes) or Stopping then begin Inc(SpatialDeclined);Exit end;
    Inc(PendingBytes,Size);
  finally LeaveCriticalSection(QueueLock) end;
  try
    Result:=TSpatialMeshJob.Create;Result.FBytes:=Size;Result.FPadding:=Padding;
    Result.FReferences:=2;
    SetLength(Result.FPositions,Arrays.Count);SetLength(Result.FIndices,Arrays.Indexes.Count);
    for I:=0 to Arrays.Count-1 do Result.FPositions[I]:=Arrays.Position(I)^;
    for I:=0 to Arrays.Indexes.Count-1 do Result.FIndices[I]:=Arrays.Indexes[I];
    EnterCriticalSection(QueueLock);
    try
      for I:=0 to High(Workers) do if Workers[I]=nil then begin
        Workers[I]:=TSpatialWorker.Create(True);Workers[I].FreeOnTerminate:=False;Workers[I].Start;
      end;
      PendingJobs.Add(Result);Inc(SpatialQueued);Inc(SpatialSourceBytes,Size);
      Wake.SetEvent;
    finally LeaveCriticalSection(QueueLock) end;
  except
    Result.Free;Result:=nil;
    EnterCriticalSection(QueueLock);try Dec(PendingBytes,Size);finally LeaveCriticalSection(QueueLock) end;
  end;
end;
procedure StopWorkers;
var I:Integer;
begin
  EnterCriticalSection(QueueLock);
  try
    Stopping:=True;
    for I:=0 to PendingJobs.Count-1 do TSpatialMeshJob(PendingJobs[I]).Cancel;
    Wake.SetEvent;
  finally LeaveCriticalSection(QueueLock) end;
  for I:=0 to High(Workers) do if Workers[I]<>nil then begin Workers[I].WaitFor;Workers[I].Free end;
end;
initialization
  InitCriticalSection(QueueLock);PendingJobs:=TList.Create;Wake:=TEvent.Create(nil,True,False,'');
  UseSpatialIndexStreams:=GetEnvironmentVariable('REZVIVO_SPATIAL_INDICES')='1';
  UseSpatialIndirect:=GetEnvironmentVariable('REZVIVO_SPATIAL_INDIRECT')='1';
finalization
  StopWorkers;Wake.Free;PendingJobs.Free;DoneCriticalSection(QueueLock);
end.
