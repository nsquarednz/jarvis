; Script generated by the Inno Setup Script Wizard.
; SEE THE DOCUMENTATION FOR DETAILS ON CREATING INNO SETUP SCRIPT FILES!

[Setup]
; NOTE: The value of AppId uniquely identifies this application.
; Do not use the same AppId value in installers for other applications.
; (To generate a new GUID, click Tools | Generate GUID inside the IDE.)
AppId={{8B0C6409-2D65-44D7-9A37-EFF99F4BD1D0}
AppName=Jarvis
AppVerName={code:GetAppVersion|Jarvis}
AppPublisher=N Squared Software
DefaultDirName=c:\opt\jarvis
DefaultGroupName=jarvis
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=jarvis_setup
Compression=lzma
SolidCompression=yes
UsePreviousAppDir=no

[Languages]
Name: english; MessagesFile: compiler:Default.isl


[Files]
Source: ..\..\cgi-bin\jarvis.pl; DestDir: {app}\cgi-bin; Flags: ignoreversion; AfterInstall: SetJarvisLocations
Source: ..\..\demo\*; DestDir: {app}\demo; Flags: ignoreversion recursesubdirs createallsubdirs
Source: ..\..\docs\*; DestDir: {app}\docs; Flags: ignoreversion recursesubdirs createallsubdirs
Source: ..\..\etc\*; DestDir: {app}\etc; Flags: ignoreversion recursesubdirs createallsubdirs
Source: ..\..\htdocs\*; DestDir: {app}\htdocs; Flags: ignoreversion recursesubdirs createallsubdirs
Source: ..\..\lib\*; DestDir: {app}\lib; Flags: ignoreversion recursesubdirs createallsubdirs
Source: ..\..\build-version.txt; DestDir: {app}; Flags: ignoreversion
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Code]
const
	defaultPerlLoc='\strawberry\perl\bin\perl';

var
	wpPerlLocation: TInputQueryWizardPage;

//Custom initializer so we can add custom pages
procedure InitializeWizard();
begin

	//This page will set where we look for the Perl installation
	wpPerlLocation := CreateInputQueryPage(wpSelectDir,
		'Perl Location',
		'Where is Perl located?',
		'Enter the location of this system Perl installation (i.e. the path to the ''perl'' executable) and then click Next');

	wpPerlLocation.Add('Perl Path:', False);
	wpPerlLocation.Values[0] := defaultPerlLoc;

end;

//Fetches application version decription from version file
function GetAppVersion(default: String): String;
var
  AppVersion: String;
begin
  ExtractTemporaryFile('build-version.txt');
  LoadStringFromFile(ExpandConstant('{tmp}/build-version.txt'), AppVersion);
  if AppVersion = '' then
    AppVersion := default;
  Result := AppVersion;
end;

function ConvertBackSlashes(inString: String) : String;
var
	outString: String;
begin
	outString := inString;
	StringChange(outString, '\', '/');
	Result := outString;
end;

//Set Jarvis locations:
// - location of Perl installation
// - locatin of Jarvis etc and lib directories
procedure SetJarvisLocations();
var
	jarvisScript: String;
begin
	if wpPerlLocation.Values[0] = '' then
		wpPerlLocation.Values[0] := defaultPerlLoc;

	LoadStringFromFile(ExpandConstant('{app}/cgi-bin/jarvis.pl'), jarvisScript);

	//Change Perl location
	StringChange(jarvisScript,'#!/usr/bin/perl', '#!' + ConvertBackSlashes(wpPerlLocation.Values[0]));

	//Change Jarvis lib and etc locations
	StringChange(jarvisScript,'use lib "/opt/jarvis/lib";', ConvertBackSlashes(ExpandConstant('use lib "{app}/lib";')));
	StringChange(jarvisScript,'my $default_jarvis_etc = "/opt/jarvis/etc";', ConvertBackSlashes(ExpandConstant('my $default_jarvis_etc = "{app}/etc";')));

	//Replace original jarvis.pl
	SaveStringToFile(ExpandConstant('{app}/cgi-bin/jarvis.pl'), jarvisScript, false);

end;