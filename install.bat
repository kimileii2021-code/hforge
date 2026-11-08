@echo off
chcp 65001 >nul
title 史鉴工坊 一键安装
powershell -ExecutionPolicy Bypass -File "%~dp0install.ps1"
pause
