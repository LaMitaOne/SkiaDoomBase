unit Unit9;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, SkiaDoomBase;

type
  TForm9 = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    Game: TRaycasterGame;
  public
    { Public-Deklarationen }
  end;

var
  Form9: TForm9;

implementation
{$R *.fmx}

procedure TForm9.FormCreate(Sender: TObject);
begin
  Game := TRaycasterGame.Create(Self);
  Game.Parent := Self;
  Game.Align := TAlignLayout.Client;
  Game.HitTest := True;
end;


procedure TForm9.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if Assigned(Game) then
  begin
    Game.Free;
    Game := nil;
  end;
  CanClose := True;
end;


end.
