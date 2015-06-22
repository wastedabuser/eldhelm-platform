@echo off

set arg1=%1
set arg2=%2

cd /d %arg1%
echo perl check.pl %arg2% -dump -syntax -static -unittest
echo .
perl check.pl %arg2% -dump -syntax -static -unittest

pause