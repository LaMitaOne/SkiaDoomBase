{*******************************************************************************
  SkiaDoomBase (Raycaster Edition v0.1)
********************************************************************************
  A 2.5D raycasting engine prototype built with Delphi FMX and Skia4Delphi.

  Features:
  - DDA Raycasting: Classic algorithm rendering a 2D grid map into a pseudo-3D
    environment with textured walls and distance-based shading.
  - Sprite Rendering: Enemy sprites are projected into the 3D world using a
    Z-Buffer to handle occlusion correctly behind walls.
  - Near-Clip Fix: Prevents sprites from distorting, filling the screen, or
    causing extreme stutter when the player gets too close.
  - View Modes: Toggle between First-Person (FPS) and Over-The-Shoulder (OTS)
    procedural weapon/avatar models.
  - Threaded Game Loop: Physics and input are handled in a background thread,
    while rendering is synchronized safely to the main UI thread.
  - Procedural Assets: Wall textures and weapon models are generated purely in
    code using Skia canvas primitives.

  Controls:
    W/S     - Move Forward / Backward
    A/D     - Strafe Left / Right
    Mouse   - Turn Left / Right
    LMB     - Shoot
    V       - Toggle FPS / OTS view


  Author:  Lara Miriam Tamy Reschke
  License: MIT
*******************************************************************************}

unit SkiaDoomBase;

interface

uses
  System.SysUtils, System.Types, System.Classes, System.Math,
  System.Generics.Collections, System.UITypes, System.SyncObjs, FMX.Types,
  FMX.Controls, FMX.Forms, FMX.Skia, Winapi.MMSystem, System.Skia,
  Winapi.Windows;

const
  FOV = 60 * (Pi / 180);
  MOVE_SPEED = 3.5;
  ROT_SPEED = 2.2;
  MOUSE_SENS = 0.0025;
  ASPECT_RATIO = 4 / 3;
  // Prevents massive sprites and stuttering when an object is extremely close
  MIN_DRAW_DIST = 0.5;

type
  TGameState = (gsPlaying, gsDead, gsWin);
  TTileType = (ttEmpty, ttWall, ttStone);
  TViewMode = (vmFPS, vmOTS);

  TTile = record
    TileType: TTileType;
    Solid: Boolean;
  end;

  TRaycasterGame = class(TSkCustomControl)
  private
    FThread: TThread;
    FActive: Boolean;
    FLock: TCriticalSection;
    FGameState: TGameState;

    // Player state
    FPlayerX: Single;
    FPlayerY: Single;
    FPlayerAngle: Single;
    FTurnHoldTime: Single;

    // Weapon and Combat state
    FIsFiring: Boolean;
    FShootCooldown: Single;
    FRecoil: Single;
    FEnemyHP: Integer;
    FEnemyAlive: Boolean;
    FVToggled: Boolean;

    // Mouse input state
    FLastMouseX: Single;
    FMouseInit: Boolean;

    // World map data
    FTiles: TArray<TTile>;
    FMapCols: Integer;
    FMapRows: Integer;

    // Graphics assets
    FWallTexture: ISkImage;

    // Z-Buffer and Enemy projection data
    FZBuffer: array of Single;
    FEnemyX: Single;
    FEnemyY: Single;
    FEnemyScreenX: Single;
    FEnemyTransformY: Single;

    FViewMode: TViewMode;

    procedure DoPhysicsUpdate(DeltaSec: Double);
    procedure SafeInvalidate;
    procedure StartThread;
    procedure StopThread;

    procedure GenerateMaze;
    procedure InitProceduralTextures;

    procedure FireWeapon;
    function CheckCollision(X, Y: Single): Boolean;
    function IsKeyDown(Key: Integer): Boolean;

    procedure DrawRaycast(const ACanvas: ISkCanvas; const ADest: TRectF);
    procedure DrawEnemiesAs3DSprites(const ACanvas: ISkCanvas; const ADest: TRectF);
    procedure DrawEnemySprite(const ACanvas: ISkCanvas; const DestRect: TRectF; IsHit: Boolean);
    procedure DrawViewModel(const ACanvas: ISkCanvas; const ADest: TRectF);
    procedure DrawAvatarModel(const ACanvas: ISkCanvas; const ADest: TRectF);
    function IsWall(AX, AY: Integer): Boolean;
  protected
    procedure Draw(const ACanvas: ISkCanvas; const ADest: TRectF; const AOpacity: Single); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

function TRaycasterGame.IsKeyDown(Key: Integer): Boolean;
begin
  // Wrapper for Windows API to check real-time keyboard state
  Result := (GetAsyncKeyState(Key) and $8000) <> 0;
end;

{ =============================================================================
  PROCEDURAL TEXTURES
  Generates a 64x64 wall texture using Skia primitives.
============================================================================= }
procedure TRaycasterGame.InitProceduralTextures;
var
  LSurface: ISkSurface;
  LCanvas: ISkCanvas;
  LPaint: ISkPaint;
  X, Y: Integer;
begin
  LSurface := TSkSurface.MakeRaster(64, 64);
  LCanvas := LSurface.Canvas;
  LCanvas.Clear($FF000000);

  LPaint := TSkPaint.Create(TSkPaintStyle.Fill);
  LPaint.AntiAlias := False;

  // Base background color
  LPaint.Color := $FF2A2A2A;
  LCanvas.DrawRect(RectF(0, 0, 64, 64), LPaint);

  // Draw a brick pattern
  LPaint.Color := $FF8B0000;
  for Y := 0 to 3 do
    for X := 0 to 3 do
    begin
      // Offset every other row for a staggered brick look
      var Offset := (Y mod 2) * 16;
      LCanvas.DrawRect(RectF((X * 16) + Offset, Y * 16, (X * 16) + 14 + Offset, Y * 16 + 14), LPaint);
    end;

  // Add random noise/dirt to the texture
  LPaint.Color := $FF5A0000;
  for var I := 0 to 50 do
    LCanvas.DrawPoint(PointF(Random(64), Random(64)), LPaint);

  // Snap the drawn surface to an image for rendering
  FWallTexture := LSurface.MakeImageSnapshot;
end;

{ =============================================================================
  WORLD GEN
  Initializes a 32x32 grid map with borders and random obstacles.
============================================================================= }
procedure TRaycasterGame.GenerateMaze;
begin
  FMapCols := 32;
  FMapRows := 32;
  SetLength(FTiles, FMapCols * FMapRows);

  // Initialize all tiles as empty
  for var R := 0 to FMapRows - 1 do
    for var C := 0 to FMapCols - 1 do
    begin
      FTiles[R * FMapCols + C].TileType := ttEmpty;
      FTiles[R * FMapCols + C].Solid := False;
    end;

  // Generate outer walls (borders)
  for var I := 0 to FMapCols - 1 do
  begin
    FTiles[I].Solid := True;
    FTiles[(FMapRows - 1) * FMapCols + I].Solid := True;
  end;
  for var I := 0 to FMapRows - 1 do
  begin
    FTiles[I * FMapCols].Solid := True;
    FTiles[I * FMapCols + FMapCols - 1].Solid := True;
  end;

  // Scatter random pillars/obstacles inside the map, keeping spawn area clear
  for var I := 0 to 40 do
  begin
    var C := Random(FMapCols - 4) + 2;
    var R := Random(FMapRows - 4) + 2;
    if (Abs(C - 3) > 3) or (Abs(R - 3) > 3) then
    begin
      FTiles[R * FMapCols + C].Solid := True;
    end;
  end;

  // Initialize Player start position
  FPlayerX := 3.5;
  FPlayerY := 3.5;
  FPlayerAngle := 0;

  // Initialize Enemy state and position
  FEnemyAlive := True;
  FEnemyHP := 3;
  FEnemyX := 25.5;
  FEnemyY := 25.5;
end;

function TRaycasterGame.IsWall(AX, AY: Integer): Boolean;
begin
  // Treat out-of-bounds as solid walls to prevent escaping the grid
  if (AX < 0) or (AX >= FMapCols) or (AY < 0) or (AY >= FMapRows) then
    Exit(True);
  Result := FTiles[AY * FMapCols + AX].Solid;
end;

function TRaycasterGame.CheckCollision(X, Y: Single): Boolean;
begin
  // Check collision with solid map tiles
  if IsWall(Trunc(X), Trunc(Y)) then Exit(True);
  // Check collision with the enemy physical body (radius 0.4)
  if FEnemyAlive and (Hypot(X - FEnemyX, Y - FEnemyY) < 0.4) then Exit(True);
  Result := False;
end;

{ =============================================================================
  LOGIC
  Handles weapon firing, hit detection, and player movement.
============================================================================= }
procedure TRaycasterGame.FireWeapon;
var
  ScreenCenterX: Single;
begin
  if FShootCooldown > 0 then Exit;
  if not FEnemyAlive then Exit;

  // Apply cooldown and recoil visual trigger
  FShootCooldown := 0.35;
  FRecoil := 1.0;

  // Dynamic calculation of screen center for crosshair targeting
  ScreenCenterX := Width / 2;

  // Hitscan logic: Check if enemy is in front and within 40px tolerance of crosshair
  if (FEnemyTransformY > 0) and (Abs(FEnemyScreenX - ScreenCenterX) < 40) then
  begin
    Dec(FEnemyHP);
    if FEnemyHP <= 0 then
      FEnemyAlive := False; // Enemy defeated
  end;
end;

procedure TRaycasterGame.DoPhysicsUpdate(DeltaSec: Double);
var
  MoveFwd, MoveBwd, StrafeL, StrafeR, TurnL, TurnR: Boolean;
  CurrentRotSpeed, NewX, NewY: Single;
begin
  if not FActive or (FGameState <> gsPlaying) then Exit;

  // Update cooldowns and recoil timers
  if FShootCooldown > 0 then FShootCooldown := FShootCooldown - DeltaSec;
  if FRecoil > 0 then FRecoil := FRecoil - (DeltaSec * 4);

  // Map keyboard input to actions
  TurnL := IsKeyDown(VK_LEFT);
  TurnR := IsKeyDown(VK_RIGHT);
  MoveFwd := IsKeyDown(VK_UP) or IsKeyDown(Ord('W')) or IsKeyDown(Ord('w'));
  MoveBwd := IsKeyDown(VK_DOWN) or IsKeyDown(Ord('S')) or IsKeyDown(Ord('s'));
  StrafeL := IsKeyDown(Ord('A')) or IsKeyDown(Ord('a'));
  StrafeR := IsKeyDown(Ord('D')) or IsKeyDown(Ord('d'));

  // Toggle view mode between FPS and OTS (edge-triggered)
  if IsKeyDown(Ord('V')) or IsKeyDown(Ord('v')) then
  begin
    if not FVToggled then
    begin
      if FViewMode = vmFPS then FViewMode := vmOTS else FViewMode := vmFPS;
      FVToggled := True;
    end;
  end
  else
  begin
    FVToggled := False;
  end;

  // Dynamic rotation speed: speeds up if the turn key is held down
  if TurnL or TurnR then
    FTurnHoldTime := FTurnHoldTime + DeltaSec
  else
    FTurnHoldTime := 0;

  CurrentRotSpeed := ROT_SPEED;
  if FTurnHoldTime > 0.1 then
    CurrentRotSpeed := ROT_SPEED * 1.8;

  if TurnL then FPlayerAngle := FPlayerAngle - CurrentRotSpeed * DeltaSec;
  if TurnR then FPlayerAngle := FPlayerAngle + CurrentRotSpeed * DeltaSec;

  NewX := FPlayerX;
  NewY := FPlayerY;

  // Vector math for forward/backward movement
  if MoveFwd then
  begin
    NewX := NewX + Cos(FPlayerAngle) * MOVE_SPEED * DeltaSec;
    NewY := NewY + Sin(FPlayerAngle) * MOVE_SPEED * DeltaSec;
  end;
  if MoveBwd then
  begin
    NewX := NewX - Cos(FPlayerAngle) * MOVE_SPEED * DeltaSec;
    NewY := NewY - Sin(FPlayerAngle) * MOVE_SPEED * DeltaSec;
  end;
  // Vector math for strafing (perpendicular to forward angle)
  if StrafeL then
  begin
    NewX := NewX + Sin(FPlayerAngle) * MOVE_SPEED * DeltaSec;
    NewY := NewY - Cos(FPlayerAngle) * MOVE_SPEED * DeltaSec;
  end;
  if StrafeR then
  begin
    NewX := NewX - Sin(FPlayerAngle) * MOVE_SPEED * DeltaSec;
    NewY := NewY + Cos(FPlayerAngle) * MOVE_SPEED * DeltaSec;
  end;

  // Apply collision detection per-axis to allow sliding along walls
  if not CheckCollision(NewX, FPlayerY) then FPlayerX := NewX;
  if not CheckCollision(FPlayerX, NewY) then FPlayerY := NewY;

  // Keep angle mapped between 0 and 2*Pi
  while FPlayerAngle < 0 do FPlayerAngle := FPlayerAngle + 2 * Pi;
  while FPlayerAngle >= 2 * Pi do FPlayerAngle := FPlayerAngle - 2 * Pi;

  // Process firing input
  if FIsFiring then FireWeapon;
end;

{ =============================================================================
  RENDERING: RAYCASTER
  Core DDA (Digital Differential Analyzer) algorithm for drawing the world.
============================================================================= }
procedure TRaycasterGame.DrawRaycast(const ACanvas: ISkCanvas; const ADest: TRectF);
var
  ScreenW, ScreenX: Integer;
  RayAngle, DirX, DirY: Single;
  MapX, MapY: Integer;
  SideDistX, SideDistY: Single;
  DeltaDistX, DeltaDistY: Single;
  StepX, StepY: Integer;
  Hit: Boolean;
  Side: Integer;
  PerpWallDist, LineHeight, DrawStart, DrawEnd, Shade, RatioFactor: Single;
  Paint: ISkPaint;
  TexX: Integer;
begin
  ScreenW := Trunc(ADest.Width);
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := False;

  // Draw floor and ceiling
  Paint.Color := $FF333333;
  ACanvas.DrawRect(RectF(0, ADest.Height / 2, ADest.Width, ADest.Height), Paint);
  Paint.Color := $FF222222;
  ACanvas.DrawRect(RectF(0, 0, ADest.Width, ADest.Height / 2), Paint);

  // Initialize/Resize Z-Buffer if screen size changed
  if Length(FZBuffer) <> ScreenW then
    SetLength(FZBuffer, ScreenW);

  // Maintain correct 4:3 aspect ratio scaling regardless of window size
  RatioFactor := (ADest.Width / ADest.Height) / ASPECT_RATIO;

  // Cast one ray for every vertical screen column
  for ScreenX := 0 to ScreenW - 1 do
  begin
    RayAngle := FPlayerAngle - (FOV / 2) + (ScreenX / ScreenW) * FOV;
    DirX := Cos(RayAngle);
    DirY := Sin(RayAngle);

    MapX := Trunc(FPlayerX);
    MapY := Trunc(FPlayerY);
    DeltaDistX := Abs(1 / DirX);
    DeltaDistY := Abs(1 / DirY);
    Hit := False;

    // Calculate step and initial side distance
    if DirX < 0 then begin StepX := -1; SideDistX := (FPlayerX - MapX) * DeltaDistX; end
    else begin StepX := 1; SideDistX := (MapX + 1.0 - FPlayerX) * DeltaDistX; end;

    if DirY < 0 then begin StepY := -1; SideDistY := (FPlayerY - MapY) * DeltaDistY; end
    else begin StepY := 1; SideDistY := (MapY + 1.0 - FPlayerY) * DeltaDistY; end;

    // DDA Loop: Step through the map grid until a wall is hit
    while not Hit do
    begin
      if SideDistX < SideDistY then begin SideDistX := SideDistX + DeltaDistX; MapX := MapX + StepX; Side := 0; end
      else begin SideDistY := SideDistY + DeltaDistY; MapY := MapY + StepY; Side := 1; end;
      if IsWall(MapX, MapY) then Hit := True;
    end;

    // Calculate perpendicular distance to prevent fisheye effect
    if Side = 0 then PerpWallDist := (SideDistX - DeltaDistX)
    else PerpWallDist := (SideDistY - DeltaDistY);

    // Save distance to Z-Buffer for sprite occlusion
    FZBuffer[ScreenX] := PerpWallDist;

    // Calculate wall slice height and boundaries
    LineHeight := Trunc((ADest.Height / PerpWallDist) * RatioFactor);
    DrawStart := -LineHeight / 2 + ADest.Height / 2;
    DrawEnd := LineHeight / 2 + ADest.Height / 2;

    // Calculate texture X coordinate based on where the ray hit the wall
    if Side = 0 then TexX := Trunc((FPlayerY + PerpWallDist * DirY) * 64) mod 64
    else TexX := Trunc((FPlayerX + PerpWallDist * DirX) * 64) mod 64;
    if TexX < 0 then TexX := TexX + 64;

    // Distance shading: darker further away, and Y-sides are darker than X-sides
    Shade := Max(0, 1 - (PerpWallDist / 15));
    if Side = 1 then Shade := Shade * 0.7;

    // Draw textured slice with shading overlay
    if Assigned(FWallTexture) then
    begin
      ACanvas.Save;
      try
        ACanvas.ClipRect(RectF(ScreenX, DrawStart, ScreenX + 1, DrawEnd));
        ACanvas.DrawImageRect(FWallTexture, RectF(TexX, 0, TexX + 1, 64), RectF(ScreenX, DrawStart, ScreenX + 1, DrawEnd), Paint);
        Paint.Color := TAlphaColorF.Create(0, 0, 0, 1 - Shade).ToAlphaColor;
        ACanvas.DrawRect(RectF(ScreenX, DrawStart, ScreenX + 1, DrawEnd), Paint);
      finally
        ACanvas.Restore;
      end;
    end;
  end;
end;

{ =============================================================================
  RENDERING: SPRITES (With Near-Clip & Z-Buffer)
  Projects enemy sprites into the world correctly occluded by walls.
============================================================================= }
procedure TRaycasterGame.DrawEnemiesAs3DSprites(const ACanvas: ISkCanvas; const ADest: TRectF);
var
  SpriteX, SpriteY: Single;
  DirX, DirY, PlaneX, PlaneY: Single;
  InverseDet, TransformX, TransformY: Single;
  SpriteScreenX, SpriteHeight, SpriteWidth: Single;
  DrawStartX, DrawEndX, DrawStartY, DrawEndY: Single;
  Stripe: Integer;
  IsHit: Boolean;
  DestRect: TRectF;
begin
  if not FEnemyAlive then Exit;

  // Vector from player to enemy
  SpriteX := FEnemyX - FPlayerX;
  SpriteY := FEnemyY - FPlayerY;

  // Calculate camera direction and projection plane
  DirX := Cos(FPlayerAngle);
  DirY := Sin(FPlayerAngle);
  PlaneX := -DirY * Tan(FOV / 2);
  PlaneY := DirX * Tan(FOV / 2);

  // Matrix transformation to project sprite into camera space
  InverseDet := 1.0 / (PlaneX * DirY - DirX * PlaneY);
  TransformX := InverseDet * (DirY * SpriteX - DirX * SpriteY);
  TransformY := InverseDet * (-PlaneY * SpriteX + PlaneX * SpriteY);

  // CRITICAL: Near Clip Plane. Skip rendering if too close to prevent
  // screen filling, stuttering, and division-by-zero issues.
  if TransformY <= MIN_DRAW_DIST then Exit;

  // Calculate screen X position and dimensions
  SpriteScreenX := (ADest.Width / 2) * (1.0 + TransformX / TransformY);
  SpriteHeight := Abs((ADest.Height / TransformY) * 1.2); // 1.2x tile size
  SpriteWidth := Abs((ADest.Height / TransformY) * 1.2);

  // Save projection data for hit-scan calculations
  FEnemyScreenX := SpriteScreenX;
  FEnemyTransformY := TransformY;

  // Calculate bounding box for sprite
  DrawStartX := SpriteScreenX - SpriteWidth / 2;
  DrawEndX := SpriteScreenX + SpriteWidth / 2;
  DrawStartY := -SpriteHeight / 2 + ADest.Height / 2;
  DrawEndY := SpriteHeight / 2 + ADest.Height / 2;

  // Determine flash state when recently hit
  IsHit := (FRecoil > 0.7);

  // Render sprite stripe-by-stripe to respect the Z-Buffer
  for Stripe := Trunc(DrawStartX) to Trunc(DrawEndX) do
  begin
    if (Stripe >= 0) and (Stripe < Trunc(ADest.Width)) then
    begin
      // Only draw if the sprite is closer than the wall at this X coordinate
      if (TransformY < FZBuffer[Stripe]) or (FZBuffer[Stripe] <= 0) then
      begin
        ACanvas.Save;
        try
          ACanvas.ClipRect(RectF(Stripe, DrawStartY, Stripe + 1, DrawEndY));
          DestRect := RectF(DrawStartX, DrawStartY, DrawEndX, DrawEndY);
          DrawEnemySprite(ACanvas, DestRect, IsHit);
        finally
          ACanvas.Restore;
        end;
      end;
    end;
  end;
end;

procedure TRaycasterGame.DrawEnemySprite(const ACanvas: ISkCanvas; const DestRect: TRectF; IsHit: Boolean);
var
  Paint: ISkPaint;
begin
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;

  // Draw outer body. Flash white if recently hit, otherwise bright red.
  // No glow is used to prevent ugly gray halos during anti-aliasing.
  if IsHit then
    Paint.Color := $FFFFFFFF
  else
    Paint.Color := $FFFF0000;

  ACanvas.DrawOval(DestRect, Paint);

  // Draw dark red inner body
  Paint.Color := $FF880000;
  var Inset := DestRect.Width * 0.1;
  ACanvas.DrawOval(RectF(DestRect.Left + Inset, DestRect.Top + Inset, DestRect.Right - Inset, DestRect.Bottom - Inset), Paint);

  // Draw yellow eyes
  Paint.Color := TAlphaColors.Yellow;
  var EyeY := DestRect.Top + (DestRect.Height * 0.3);
  var EyeSize := DestRect.Width * 0.08;
  ACanvas.DrawCircle(PointF(DestRect.CenterPoint.X - DestRect.Width * 0.2, EyeY), EyeSize, Paint);
  ACanvas.DrawCircle(PointF(DestRect.CenterPoint.X + DestRect.Width * 0.2, EyeY), EyeSize, Paint);
end;

{ =============================================================================
  RENDERING: VIEW MODELS
  Draws the first-person weapon or the over-the-shoulder avatar.
============================================================================= }
procedure TRaycasterGame.DrawViewModel(const ACanvas: ISkCanvas; const ADest: TRectF);
var
  Paint: ISkPaint;
  BaseY, OffsetY: Single;
begin
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;

  // Draw semi-transparent crosshair
  Paint.Color := TAlphaColors.White;
  Paint.Alpha := 150;
  ACanvas.DrawRect(RectF(ADest.Width/2 - 1, ADest.Height/2 - 5, ADest.Width/2 + 1, ADest.Height/2 + 5), Paint);
  ACanvas.DrawRect(RectF(ADest.Width/2 - 5, ADest.Height/2 - 1, ADest.Width/2 + 5, ADest.Height/2 + 1), Paint);

  Paint.Alpha := 255;
  BaseY := ADest.Height - 80;
  // Apply recoil offset to the weapon model
  OffsetY := FRecoil * 20;

  // Draw muzzle flash if recently fired
  if FRecoil > 0.5 then
  begin
    Paint.Color := $FFFFFF00;
    Paint.Alpha := Trunc(FRecoil * 255);
    ACanvas.DrawCircle(PointF(ADest.Width/2 + 20, BaseY + OffsetY + 20), 15, Paint);
    Paint.Color := $FFFF0000;
    ACanvas.DrawCircle(PointF(ADest.Width/2 + 20, BaseY + OffsetY + 20), 8, Paint);
    Paint.Alpha := 255;
  end;

  // Draw weapon body and grip
  Paint.Color := $FF222222;
  ACanvas.DrawRect(RectF(ADest.Width/2 - 30, BaseY + OffsetY, ADest.Width/2 + 30, BaseY + 80), Paint);
  Paint.Color := $FF5A3A1A;
  ACanvas.DrawRect(RectF(ADest.Width/2 - 15, BaseY + OffsetY + 30, ADest.Width/2 + 15, BaseY + 80), Paint);
end;

procedure TRaycasterGame.DrawAvatarModel(const ACanvas: ISkCanvas; const ADest: TRectF);
var
  Paint, GlowPaint: ISkPaint;
  BaseY, OffsetY: Single;
begin
  Paint := TSkPaint.Create;
  Paint.Style := TSkPaintStyle.Stroke;
  Paint.StrokeWidth := 6.0;
  Paint.StrokeCap := TSkStrokeCap.Round;
  Paint.AntiAlias := True;
  Paint.Color := $FF202020;

  // Create a glowing paint for cybernetic lines
  GlowPaint := TSkPaint.Create(Paint);
  GlowPaint.MaskFilter := TSkMaskFilter.MakeBlur(TSkBlurStyle.Solid, 12.0);
  GlowPaint.Color := $FF00FFFF;

  BaseY := ADest.Height - 150;
  OffsetY := FRecoil * 15;

  // Draw muzzle flash at the hands
  if FRecoil > 0.5 then
  begin
    Paint.Style := TSkPaintStyle.Fill;
    Paint.Color := $FFFFFF00;
    Paint.Alpha := Trunc(FRecoil * 255);
    ACanvas.DrawCircle(PointF(ADest.Width/2 + 60, BaseY + 80 + OffsetY), 20, Paint);
    Paint.Color := $FFFF0000;
    ACanvas.DrawCircle(PointF(ADest.Width/2 + 60, BaseY + 80 + OffsetY), 10, Paint);
    Paint.Alpha := 255;
    Paint.Style := TSkPaintStyle.Stroke;
  end;

  // Draw legs
  ACanvas.DrawLine(PointF(ADest.Width/2 - 25, BaseY + 150), PointF(ADest.Width/2 - 25, BaseY + 100 + OffsetY), GlowPaint);
  ACanvas.DrawLine(PointF(ADest.Width/2 - 25, BaseY + 150), PointF(ADest.Width/2 - 25, BaseY + 100 + OffsetY), Paint);
  ACanvas.DrawLine(PointF(ADest.Width/2 + 25, BaseY + 150), PointF(ADest.Width/2 + 25, BaseY + 100 + OffsetY), GlowPaint);
  ACanvas.DrawLine(PointF(ADest.Width/2 + 25, BaseY + 150), PointF(ADest.Width/2 + 25, BaseY + 100 + OffsetY), Paint);

  // Draw torso
  ACanvas.DrawRect(RectF(ADest.Width/2 - 35, BaseY + 20 + OffsetY, ADest.Width/2 + 35, BaseY + 110 + OffsetY), GlowPaint);
  ACanvas.DrawRect(RectF(ADest.Width/2 - 35, BaseY + 20 + OffsetY, ADest.Width/2 + 35, BaseY + 110 + OffsetY), Paint);

  // Draw arms pointing to weapon
  ACanvas.DrawLine(PointF(ADest.Width/2 - 35, BaseY + 40 + OffsetY), PointF(ADest.Width/2 + 60, BaseY + 80 + OffsetY), GlowPaint);
  ACanvas.DrawLine(PointF(ADest.Width/2 - 35, BaseY + 40 + OffsetY), PointF(ADest.Width/2 + 60, BaseY + 80 + OffsetY), Paint);
  ACanvas.DrawLine(PointF(ADest.Width/2 + 35, BaseY + 40 + OffsetY), PointF(ADest.Width/2 + 60, BaseY + 80 + OffsetY), GlowPaint);
  ACanvas.DrawLine(PointF(ADest.Width/2 + 35, BaseY + 40 + OffsetY), PointF(ADest.Width/2 + 60, BaseY + 80 + OffsetY), Paint);

  // Draw head
  Paint.Style := TSkPaintStyle.Fill;
  ACanvas.DrawCircle(PointF(ADest.Width/2, BaseY + OffsetY), 25, GlowPaint);
  ACanvas.DrawCircle(PointF(ADest.Width/2, BaseY + OffsetY), 25, Paint);

  // Draw visor
  Paint.Color := TAlphaColors.Red;
  ACanvas.DrawRect(RectF(ADest.Width/2 - 15, BaseY - 5 + OffsetY, ADest.Width/2 + 15, BaseY + 5 + OffsetY), Paint);
end;

procedure TRaycasterGame.Draw(const ACanvas: ISkCanvas; const ADest: TRectF; const AOpacity: Single);
begin
  // Thread-safe rendering block
  FLock.Acquire;
  try
    DrawRaycast(ACanvas, ADest);
    DrawEnemiesAs3DSprites(ACanvas, ADest);

    // Render the correct view model based on the active view mode
    if FViewMode = vmFPS then
      DrawViewModel(ACanvas, ADest)
    else
      DrawAvatarModel(ACanvas, ADest);

  finally
    FLock.Release;
  end;
end;

{ =============================================================================
  INPUT (Mouse Events)
============================================================================= }
procedure TRaycasterGame.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  // Start firing when Left Mouse Button is pressed
  if Button = TMouseButton.mbLeft then
    FIsFiring := True;
end;

procedure TRaycasterGame.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  // Stop firing when Left Mouse Button is released
  if Button = TMouseButton.mbLeft then
    FIsFiring := False;
end;

procedure TRaycasterGame.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited;
  // Initialize mouse tracking on first movement to prevent snapping
  if not FMouseInit then
  begin
    FLastMouseX := X;
    FMouseInit := True;
    Exit;
  end;
  // Apply horizontal mouse delta to player angle
  FPlayerAngle := FPlayerAngle + (X - FLastMouseX) * MOUSE_SENS;
  FLastMouseX := X;
end;

{ =============================================================================
  LIFECYCLE & THREADING
  Manages the background physics loop and main-thread synchronization.
============================================================================= }
procedure TRaycasterGame.SafeInvalidate;
begin
  if csDestroying in ComponentState then Exit;
  // Queue redraw safely to the main FMX thread
  TThread.Queue(nil, procedure begin
    if not (csDestroying in ComponentState) and Assigned(Self) then
    begin
      Redraw; Repaint;
    end;
  end);
end;

procedure TRaycasterGame.StartThread;
begin
  if Assigned(FThread) then Exit;
  FThread := TThread.CreateAnonymousThread(procedure
  var LastTime, NowTime, DeltaMS: Cardinal;
  begin
    LastTime := TThread.GetTickCount;
    // Main game loop
    while not TThread.CheckTerminated do
    begin
      NowTime := TThread.GetTickCount;
      DeltaMS := NowTime - LastTime;
      if DeltaMS = 0 then DeltaMS := 1; // Prevent division by zero
      LastTime := NowTime;

      if FActive then
      begin
        // Process game logic using delta time
        DoPhysicsUpdate(DeltaMS / 1000);
        // Trigger rendering
        SafeInvalidate;
      end;
      // Yield execution roughly targeting ~80 FPS logic updates
      Sleep(12);
    end;
  end);
  FThread.FreeOnTerminate := True;
  FThread.Start;
end;

procedure TRaycasterGame.StopThread;
begin
  FActive := False;
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    Sleep(50); // Allow thread to finish safely
  end;
end;

constructor TRaycasterGame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Initialize thread synchronization lock
  FLock := TCriticalSection.Create;

  // Setup control properties for capturing input
  Align := TAlignLayout.Client;
  HitTest := True;
  CanFocus := True;
  TabStop := True;

  // Initial game state
  FActive := True;
  FGameState := gsPlaying;
  FTurnHoldTime := 0;
  FMouseInit := False;
  FViewMode := vmFPS;
  FVToggled := False;

  // Generate world and assets
  InitProceduralTextures;
  GenerateMaze;

  // Kick off the game loop
  StartThread;
end;

destructor TRaycasterGame.Destroy;
begin
  // Cleanly stop the thread before destroying the lock
  StopThread;
  FreeAndNil(FLock);
  inherited;
end;

end.
