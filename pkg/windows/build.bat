set isxpath=C:\Program Files\Inno Setup 5
set isx=%isxpath%\iscc.exe
set iwz=setup.iss
"%isx%" "%iwz%" > build.log
