@echo off
title JARVIS Launcher
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0JARVIS-Legacy.ps1"
if errorlevel 1 pause