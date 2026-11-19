@echo off
rem Reachy recruitment clip: sad, then promises to dance.
rem Close the game first; keep Reachy Mini Control running.
cd /d "%~dp0"
"services\controller\.venv\Scripts\python.exe" "dev\recruit_video.py" --play
pause
