@echo off
setlocal
python "%~dp0visual_compare.py" compare --config "%~dp0config.pura90.json" %*
exit /b %errorlevel%
