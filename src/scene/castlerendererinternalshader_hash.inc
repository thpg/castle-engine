{%MainUnit castlerendererinternalshader.pas}
{
  Copyright 2010-2024 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Maintain a hash of the shader code. }

{$ifdef read_interface}

//type
  { Hash of the shader code.
    Different hash -> different shader code, must link a new shader program.
    Same hash -> can reuse the shader program with the same hash. }
  TShaderCodeHash = record
  strict private
    Sum, XorValue: UInt32;
  public
    procedure AddString(const S: AnsiString; const Multiplier: UInt32);
    procedure AddInteger(const I: Integer);
    procedure AddFloat(const F: Single; const UniquePrimeNumber: Cardinal);
    procedure AddPointer(Ptr: Pointer);
    procedure AddEffects(Nodes: TX3DNodeList); overload;
    procedure AddEffects(Nodes: TMFNode); overload;

    function ToString: String;
    procedure Clear;

    class operator {$ifdef FPC}={$else}Equal{$endif} (const A, B: TShaderCodeHash): boolean;
  end;

{$endif read_interface}

{$ifdef read_implementation}

{ TShaderCodeHash ------------------------------------------------------------ }

{$include norqcheckbegin.inc}

procedure TShaderCodeHash.AddString(const S: AnsiString; const Multiplier: UInt32);
var
  PS: PUInt32;
  Last: UInt32;
  I: Integer;
begin
  PS := PUInt32(S);

  for I := 1 to Length(S) div 4 do
  begin
    Sum := Sum + PS^ * Multiplier;
    XorValue := XorValue xor PS^;
    Inc(PS);
  end;

  if Length(S) mod 4 <> 0 then
  begin
    Last := 0;
    Move(S[(Length(S) div 4) * 4 + 1], Last, Length(S) mod 4);
    Sum := Sum + Last * Multiplier;
    XorValue := XorValue xor Last;
  end;
end;

procedure TShaderCodeHash.AddPointer(Ptr: Pointer);
begin
  { This will cut the pointer on non-32bit processors.
    But that's not a problem --- we just want it for hash,
    taking the least significant 32 bits from pointer is OK for this. }
  Sum := Sum + UInt32(PtrUInt(Ptr));
  XorValue := XorValue xor UInt32(PtrUInt(Ptr));
end;

procedure TShaderCodeHash.AddInteger(const I: Integer);
begin
  Sum := Sum + I;
end;

procedure TShaderCodeHash.AddFloat(const F: Single; const UniquePrimeNumber: Cardinal);
begin
  Sum := Sum + (Round(F * 1000) + 1) * UniquePrimeNumber;
end;

{$include norqcheckend.inc}

procedure TShaderCodeHash.AddEffects(Nodes: TX3DNodeList);
var
  I: Integer;
begin
  { Opt-in effects refresh uniforms before each draw. Other effects retain
    their node identity because their uniforms are updated on events. }
  for I := 0 to Nodes.Count - 1 do
    if (Nodes[I] is TEffectNode) and
       TEffectNode(Nodes[I]).FdEnabled.Value then
      if TEffectNode(Nodes[I]).InternalSharedCodeKey <> '' then
        AddString(IntToStr(I) + ':' + TEffectNode(Nodes[I]).InternalSharedCodeKey, 104729)
      else
        AddPointer(Nodes[I]);
end;

procedure TShaderCodeHash.AddEffects(Nodes: TMFNode);
begin
  AddEffects(Nodes.InternalItems);
end;

function TShaderCodeHash.ToString: String;
begin
  Result := IntToStr(Sum) + '/' + IntToStr(XorValue);
end;

procedure TShaderCodeHash.Clear;
begin
  Sum := 0;
  XorValue := 0;
end;

class operator TShaderCodeHash.{$ifdef  FPC}={$else}Equal{$endif}(const A, B: TShaderCodeHash): boolean;
begin
  Result := (A.Sum = B.Sum) and (A.XorValue = B.XorValue);
end;

{$endif read_implementation}
