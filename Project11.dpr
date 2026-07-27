program Project11;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  Unit9 in 'Unit9.pas' {Form9},
  SkiaDoomBase in 'SkiaDoomBase.pas';

{$R *.res}

begin
  GlobalUseSkia := True;
  Application.Initialize;
  Application.CreateForm(TForm9, Form9);
  Application.Run;
end.
