@echo off
FOR /R "roms" %%i IN (*.*) DO (
7z.exe a -tzip -mx=9 "%%i.zip" "%%i"
del "%%i"
)
