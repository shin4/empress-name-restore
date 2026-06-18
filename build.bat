@echo off
chcp 65001 >nul 2>&1
cd /d "%~dp0"

echo ========================================
echo   女帝篇字幕还原补丁 - 打包工具
echo ========================================
echo.

echo [1/3] 安装 PyInstaller...
pip install pyinstaller 2>nul || uv pip install pyinstaller --system 2>nul
if errorlevel 1 (
    echo [错误] PyInstaller 安装失败，请手动安装: pip install pyinstaller
    pause
    exit /b 1
)
echo      完成
echo.

echo [2/3] 打包 memory_patch.exe...
pyinstaller --onefile --uac-admin --add-data "name_mapping.json;." --name memory_patch --clean --noconfirm memory_patch.py
if errorlevel 1 (
    echo [错误] 打包失败
    pause
    exit /b 1
)
echo      完成
echo.

echo [3/3] 复制到发布目录...
if not exist "release" mkdir release
copy /y "dist\memory_patch.exe" "release\" >nul
copy /y "name_mapping.json" "release\" >nul
echo      完成
echo.

echo ========================================
echo   打包成功！
echo   输出目录: release\
echo     - memory_patch.exe
echo     - name_mapping.json
echo ========================================
pause
