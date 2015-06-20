@echo off

set arg1=%1
set arg2=%2

cd /d %arg1%
perl check.pl %arg2% -dump

pause