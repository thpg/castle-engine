{ Pure decision shared by uniform preparation and transform-feedback drawing. }
unit CastleInternalPoseCache;

{$I castleconf.inc}

interface

type
  TPoseCacheInput = record
    CacheEnabled, ProgramSupportsCache, HasSourceBuffer, UniqueOwner,
      Requested, PoseValid, PoseBuffersReady: Boolean;
    ExpectedBytes, PoseBytes, Frame, PoseFrame, Revision, PoseRevision: QWord;
  end;

  TPoseCacheDecision = record
    Enabled, Allocate, Capture, ReturningAfterGap,
      SkipDeformationUniforms: Boolean;
    Frame, Revision: QWord;
  end;

function DecidePoseCache(const Input: TPoseCacheInput): TPoseCacheDecision;

implementation

function DecidePoseCache(const Input: TPoseCacheInput): TPoseCacheDecision;
begin
  Result := Default(TPoseCacheDecision);
  Result.Frame := Input.Frame;
  Result.Revision := Input.Revision;
  Result.Enabled := Input.CacheEnabled and Input.ProgramSupportsCache and
    Input.HasSourceBuffer and Input.UniqueOwner and Input.Requested;
  if not Result.Enabled then Exit;
  Result.ReturningAfterGap := Input.PoseValid and
    (Input.PoseFrame <> Input.Frame) and (Input.PoseFrame + 1 <> Input.Frame);
  Result.Allocate := not Input.PoseValid or not Input.PoseBuffersReady or
    (Input.PoseBytes <> Input.ExpectedBytes);
  if Input.Revision <> 0 then
    Result.Capture := Result.Allocate or Result.ReturningAfterGap or
      (Input.PoseRevision <> Input.Revision)
  else
    Result.Capture := Result.Allocate or (Input.PoseFrame <> Input.Frame);
  Result.SkipDeformationUniforms := not Result.Capture;
end;

end.
