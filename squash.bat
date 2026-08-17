@echo off

REM setup: git worktree add --orphan -b dist dist

for /f %%i in ('git rev-parse --short master') do set commit=%%i
echo Detected master commit: %commit%

call inline everything.red dist\spaces.red
cd dist
call git add spaces.red
call git commit -m "squashed @ %commit%"
call git push --force origin dist
cd ..
echo New squashed version pushed successfully.