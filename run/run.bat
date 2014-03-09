@echo off

masm /Mx a.asm;
if errorlevel 1 goto quit

link /noignorecase a.obj, a.exe,nul,llama.lib;
if errorlevel 1 goto quitwobj

echo ------------------------
a
echo ------------------------

del %1.exe

:quitwobj

del %1.obj

:quit
pause
